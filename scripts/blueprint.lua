-- =============================================================================
-- Quick Mall — scripts/blueprint.lua
-- =============================================================================
-- Blueprint construction, placement, cursor handling, and researched-item
-- filters. Depends on: prototypes (resolve_item_prototype,
-- resolve_entity_prototype) and recipes (is_recipe_compatible_with_surface).
-- =============================================================================

local prototypes = require("scripts.prototypes")
local recipes = require("scripts.recipes")

-- Local aliases to cross-module helpers so the moved function bodies stay
-- byte-identical to their control.lua originals.
local resolve_item_prototype = prototypes.resolve_item_prototype
local resolve_entity_prototype = prototypes.resolve_entity_prototype
local is_recipe_compatible_with_surface = recipes.is_recipe_compatible_with_surface

-- Builds the input-chest logistic request list for a recipe: one full stack of
-- each solid ingredient at the given quality. Each entry is
-- { index, name, count, quality, comparator = "=" }.
local function get_item_requests(player, recipe, quality)
  local requests = {}
  local index = 1
  local quality_name = quality or "normal"
  for _, ingredient in pairs(recipe.ingredients or {}) do
    local name = ingredient.name or ingredient[1]
    local ingredient_type = ingredient.type or "item"
    if ingredient_type == "item" and name then
      local prototype = resolve_item_prototype(name)
      local stack_size = (prototype and prototype.stack_size) or 1
      -- Request 1 full stack of each input
      local count = stack_size
      table.insert(requests, { index = index, name = name, count = count, quality = quality_name, comparator = "=" })
      index = index + 1
    end
  end

  return requests
end

-- Returns (true, nil) if every placement can be placed on the surface, else
-- (false, name) of the first placement that cannot be placed. Each placement is
-- { name, position, direction? }.
local function can_place_all(surface, force, placements)
  for _, placement in ipairs(placements) do
    local ok, can_place = pcall(function()
      return surface.can_place_entity({
        name = placement.name,
        position = placement.position,
        force = force,
        direction = placement.direction or defines.direction.north,
      })
    end)
    if not ok then
      return false, placement.name
    end
    if not can_place then
      return false, placement.name
    end
  end

  return true, nil
end

-- Constructs the list of blueprint-entity tables for the mall layout, relative to
-- base_position:
--   - the crafting building (with recipe, recipe_quality, and quick_mall_* tags;
--     when module_selections are given it also gets a logistic request for those
--     modules and a pre-filled module inventory via the blueprint `items` field),
--   - an input chest with logistic request_filters + a feeding inserter (only when
--     request_list is non-empty and an input chest is chosen),
--   - an output chest (with an optional `bar` = stack_limit) + an extracting
--     inserter (only when an output chest / inserter is chosen).
-- chest_offset / inserter_offset are horizontal offsets to the west of the
-- building. module_selections is a nil-safe slot-indexed array of module item
-- names. Each entity gets a sequential entity_number. Returns the entity list.
local function build_blueprint_entities(
  base_position,
  building_name,
  recipe_name,
  input_chest,
  output_chest,
  inserter_name,
  chest_offset,
  inserter_offset,
  request_list,
  quality,
  stack_limit,
  module_selections
)
  local entities = {}
  local next_id = 1
  local quality_name = quality or "normal"
  local bar_value = (stack_limit and stack_limit > 0) and stack_limit or nil

  -- Module support (workitem-14): module_selections is a slot-indexed array of
  -- module item names (nils allowed for empty slots). Collapse it into
  --   module_counts[name] = number of slots assigned to that module
  -- and a compact slot list (in original order) so we can (a) build a logistic
  -- request on the building so bots deliver the modules, and (b) pre-fill the
  -- building's module inventory in the blueprint entity `items` field.
  local module_counts = {}
  local module_slot_names = {}
  if module_selections then
    for _, module_name in ipairs(module_selections) do
      if module_name and module_name ~= "" then
        module_counts[module_name] = (module_counts[module_name] or 0) + 1
        table.insert(module_slot_names, module_name)
      end
    end
  end
  local has_modules = next(module_counts) ~= nil

  local request_filters = nil
  if request_list then
    request_filters = {}
    for index, request in ipairs(request_list) do
      request_filters[index] = {
        index = index,
        name = request.name,
        count = request.count,
        quality = request.quality,
        comparator = request.comparator,
      }
    end
  end

  local function add_entity(def)
    def.entity_number = next_id
    next_id = next_id + 1
    table.insert(entities, def)
  end

  local building_def = {
    name = building_name,
    position = { x = base_position.x, y = base_position.y },
    direction = defines.direction.north,
    recipe = recipe_name,
    recipe_quality = quality_name,
    tags = {
      quick_mall_recipe = recipe_name,
      quick_mall_recipe_quality = quality_name
    },
  }

  if has_modules then
    -- (a) Logistic request on the BUILDING so bots deliver the modules from the
    -- network (this is the primary requirement). Same request_filters shape used
    -- for the input chest below.
    local module_filters = {}
    local module_index = 1
    for module_name, count in pairs(module_counts) do
      module_filters[module_index] = {
        index = module_index,
        name = module_name,
        count = count,
        quality = "normal",
        comparator = "=",
      }
      module_index = module_index + 1
    end
    building_def.request_filters = {
      sections = {
        {
          index = 1,
          filters = module_filters,
        },
      },
    }

    -- Record the modules in tags too (informational; not relied on for delivery).
    building_def.tags.quick_mall_modules = table.concat(module_slot_names, ",")

    -- (b) Complementary: pre-fill the building's module inventory in the blueprint
    -- `items` field so the ghost visually shows which modules belong in which
    -- slots. Wrapped in pcall + guarded on the inventory constant so a wrong or
    -- absent constant can never abort blueprint creation (delivery still works via
    -- the request above).
    pcall(function()
      local module_inventory = defines
        and defines.inventory
        and defines.inventory.assembling_machine_modules
      if module_inventory then
        local items = {}
        -- Group the InventoryPositions per module name (stacks are 0-based).
        local positions_by_name = {}
        for slot_index, module_name in ipairs(module_slot_names) do
          local list = positions_by_name[module_name]
          if not list then
            list = {}
            positions_by_name[module_name] = list
          end
          table.insert(list, {
            inventory = module_inventory,
            stack = slot_index - 1,
            count = 1,
          })
        end
        for module_name, positions in pairs(positions_by_name) do
          table.insert(items, {
            id = { name = module_name, quality = "normal" },
            items = { in_inventory = positions },
          })
        end
        if #items > 0 then
          building_def.items = items
        end
      end
    end)
  end

  add_entity(building_def)

  if #request_list > 0 and input_chest then
    add_entity({
      name = input_chest,
      position = { x = base_position.x - chest_offset, y = base_position.y },
      request_filters = {
        sections = {
            {
                index = 1,
                filters = request_filters
            }
        }
    },
    })

    add_entity({
      name = inserter_name,
      position = { x = base_position.x - inserter_offset, y = base_position.y },
      direction = defines.direction.west,
    })
  end

  if output_chest then
    add_entity({
      name = output_chest,
      position = { x = base_position.x - chest_offset, y = base_position.y + 1 },
      bar = bar_value,
    })
  end

  if output_chest and inserter_name then
    add_entity({
      name = inserter_name,
      position = { x = base_position.x - inserter_offset, y = base_position.y + 1 },
      direction = defines.direction.east,
    })
  end

  return entities
end

-- Returns the list of names from `names` that do not resolve to an entity
-- prototype (empty list means all valid).
local function validate_entity_names(names)
  local missing = {}
  for _, name in ipairs(names) do
    if not resolve_entity_prototype(name) then
      table.insert(missing, name)
    end
  end
  return missing
end

-- Places a blueprint holding `entities` into the player's cursor. Clears a
-- non-empty cursor first, sets a temporary blueprint stack, validates all entity
-- names resolve, then writes the entities. Returns true on success, false if the
-- cursor could not be prepared or any entity name is missing.
local function give_blueprint_cursor(player, entities, request_list)
  local function cursor_is_empty(stack)
    if not (stack and stack.valid) then
      return true
    end
    return not stack.valid_for_read
  end

  local function set_blueprint_on_stack(stack)
    if not (stack and stack.valid) then
      return false
    end
    if not cursor_is_empty(stack) then
      player.clear_cursor()
    end
    if not cursor_is_empty(stack) then
      return false
    end
    stack.set_stack({ name = "blueprint" })
    player.cursor_stack_temporary = true
    if not stack.valid_for_read or not stack.is_blueprint then
      return false
    end
    local entity_names = {}
    for _, entity in ipairs(entities) do
      table.insert(entity_names, entity.name)
    end

    local missing = validate_entity_names(entity_names)
    if #missing > 0 then
      return false
    end

    stack.set_blueprint_entities(entities)
    return true
  end

  if set_blueprint_on_stack(player.cursor_stack) then
    return true
  end

  return false
end

-- If the player holds a Quick Mall blueprint (buildings tagged quick_mall_recipe)
-- whose recipe is not compatible with the current surface, strips the recipe,
-- quality, and tags from those buildings and clears all logistic request filters
-- in the layout, then rewrites the blueprint and notifies the player. Used when
-- the player changes surface while holding a mall blueprint.
local function check_and_clear_incompatible_cursor_recipe(player)
  local stack = player.cursor_stack
  if not (stack and stack.valid and stack.valid_for_read and stack.is_blueprint) then
    return
  end

  local entities = stack.get_blueprint_entities()
  if not entities then return end

  local changed = false
  for _, entity in ipairs(entities) do
    -- Only clear if it's one of OUR recipes (building has the quick_mall_recipe tag)
    if entity.recipe and entity.tags and entity.tags.quick_mall_recipe then
      local recipe = player.force.recipes[entity.recipe]
      if recipe and not is_recipe_compatible_with_surface(recipe, player.surface) then
        entity.recipe = nil
        entity.recipe_quality = nil
        -- Also clear tags to be consistent
        entity.tags.quick_mall_recipe = nil
        entity.tags.quick_mall_recipe_quality = nil
        changed = true

        -- If we found an incompatible building, also clear any requester filters in this layout
        for _, other_e in ipairs(entities) do
          if other_e.request_filters or other_e.logistic_sections then
            other_e.request_filters = nil
            other_e.logistic_sections = nil
          end
        end
      end
    end
  end

  if changed then
    stack.set_blueprint_entities(entities)
    player.print("Quick Mall: cleared surface-incompatible recipe from blueprint.")
  end
end

-- Builds elem_filters for the item chooser: one { filter = "name", name } per
-- item/fluid produced by any enabled recipe, so the picker only offers craftable
-- outputs.
local function get_researched_item_filters(force)
  local item_names = {}
  for _, recipe in pairs(force.recipes) do
    if recipe.enabled then
      for _, product in pairs(recipe.products) do
        if product.type == "item" or product.type == "fluid" then
          item_names[product.name] = true
        end
      end
    end
  end

  local filters = {}
  for name, _ in pairs(item_names) do
    table.insert(filters, { filter = "name", name = name })
  end
  return filters
end

return {
  get_item_requests = get_item_requests,
  can_place_all = can_place_all,
  build_blueprint_entities = build_blueprint_entities,
  validate_entity_names = validate_entity_names,
  give_blueprint_cursor = give_blueprint_cursor,
  check_and_clear_incompatible_cursor_recipe = check_and_clear_incompatible_cursor_recipe,
  get_researched_item_filters = get_researched_item_filters,
}

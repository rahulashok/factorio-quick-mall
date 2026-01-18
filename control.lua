local GUI_ROOT = "quick-mall-window"
local GUI_ITEM = "quick-mall-item"
local GUI_RECIPE_FLOW = "quick-mall-recipe-flow"
local GUI_RECIPE_PREFIX = "quick-mall-recipe-"
local GUI_INPUT_CHEST = "quick-mall-input-chest"
local GUI_OUTPUT_CHEST = "quick-mall-output-chest"
local GUI_INSERTER = "quick-mall-inserter"
local GUI_BUILDING_FLOW = "quick-mall-building-flow"
local GUI_BUILDING_PREFIX = "quick-mall-building-"
local GUI_INSERTER_FLOW = "quick-mall-inserter-flow"
local GUI_INSERTER_PREFIX = "quick-mall-inserter-"
local GUI_INPUT_FLOW = "quick-mall-input-flow"
local GUI_INPUT_PREFIX = "quick-mall-input-"
local GUI_OUTPUT_FLOW = "quick-mall-output-flow"
local GUI_OUTPUT_PREFIX = "quick-mall-output-"
local GUI_CREATE = "quick-mall-create"
local GUI_CLOSE = "quick-mall-close"

local STATIC_BUILDING_CANDIDATES = {
  { name = "assembling-machine-1", label = "Assembler 1" },
  { name = "assembling-machine-2", label = "Assembler 2" },
  { name = "assembling-machine-3", label = "Assembler 3" },
  { name = "chemical-plant", label = "Chemical Plant" },
  { name = "oil-refinery", label = "Oil Refinery" },
  { name = "foundry", label = "Foundry" },
  { name = "em-plant", label = "EM Plant" },
}

local INPUT_CHEST_CANDIDATES = {
  { name = "wooden-chest", label = "Wooden Chest" },
  { name = "iron-chest", label = "Iron Chest" },
  { name = "steel-chest", label = "Steel Chest" },
  {
    name = "logistic-chest-buffer",
    label = "Buffer Chest",
    aliases = { "buffer-chest", "logistic-buffer-chest" },
  },
  {
    name = "logistic-chest-requester",
    label = "Requester Chest",
    aliases = { "requester-chest", "logistic-requester-chest" },
  },
}

local OUTPUT_CHEST_CANDIDATES = {
  { name = "wooden-chest", label = "Wooden Chest" },
  { name = "iron-chest", label = "Iron Chest" },
  { name = "steel-chest", label = "Steel Chest" },
  {
    name = "logistic-chest-passive-provider",
    label = "Passive Provider Chest",
    aliases = { "passive-provider-chest", "logistic-passive-provider-chest" },
  },
  {
    name = "logistic-chest-active-provider",
    label = "Active Provider Chest",
    aliases = { "active-provider-chest", "logistic-active-provider-chest" },
  },
  {
    name = "logistic-chest-storage",
    label = "Storage Chest",
    aliases = { "storage-chest", "logistic-storage-chest" },
  },
  {
    name = "logistic-chest-buffer",
    label = "Buffer Chest",
    aliases = { "buffer-chest", "logistic-buffer-chest" },
  },
  {
    name = "logistic-chest-requester",
    label = "Requester Chest",
    aliases = { "requester-chest", "logistic-requester-chest" },
  },
}

local INSERTER_CANDIDATES = {
  { name = "burner-inserter", label = "Burner Inserter" },
  { name = "inserter", label = "Inserter (Yellow)" },
  { name = "fast-inserter", label = "Fast Inserter (Blue)" },
  { name = "bulk-inserter", label = "Bulk Inserter (Green)" },
  { name = "stack-inserter", label = "Stack Inserter" },
}

local function get_entity_prototypes()
  -- Factorio 1.1/2.0 Standard API
  local ok, res = pcall(function()
    return game.entity_prototypes
  end)
  if ok and res then
    return res
  end

  -- Fallback to Factorio 2.0+ global if available
  if prototypes and prototypes.entity then
    return prototypes.entity
  end

  ok, res = pcall(function()
    if game.get_filtered_entity_prototypes then
      return game.get_filtered_entity_prototypes({})
    end
    return nil
  end)
  if ok and res then
    return res
  end

  return {}
end

local function resolve_entity_prototype(entity_name)
  if not entity_name then return nil end

  -- Factorio 1.1/2.0 Standard API
  local ok, proto = pcall(function()
    if game.get_entity_prototype then
      return game.get_entity_prototype(entity_name)
    end
    return nil
  end)
  if ok and proto then
    return proto
  end

  -- Fallback to Factorio 2.0+ global if available
  if prototypes and prototypes.entity then
    return prototypes.entity[entity_name]
  end

  local prototypes_list = get_entity_prototypes()
  if prototypes_list then
    return prototypes_list[entity_name]
  end

  return nil
end

local function get_item_prototypes()
  -- Factorio 1.1/2.0 Standard API
  local ok, res = pcall(function()
    return game.item_prototypes
  end)
  if ok and res then
    return res
  end

  -- Fallback to Factorio 2.0+ global if available
  if prototypes and prototypes.item then
    return prototypes.item
  end

  return {}
end

local function resolve_item_prototype(item_name)
  if not item_name then return nil end

  -- Factorio 1.1/2.0 Standard API
  local ok, proto = pcall(function()
    if game.get_item_prototype then
      return game.get_item_prototype(item_name)
    end
    return nil
  end)
  if ok and proto then
    return proto
  end

  -- Fallback to Factorio 2.0+ global if available
  if prototypes and prototypes.item then
    return prototypes.item[item_name]
  end

  local prototypes_list = get_item_prototypes()
  if prototypes_list then
    return prototypes_list[item_name]
  end

  return nil
end

local function can_resolve_prototypes()
  return resolve_entity_prototype("inserter") ~= nil
end

local function resolve_candidate_name(candidate)
  if resolve_entity_prototype(candidate.name) then
    return candidate.name
  end
  if candidate.aliases then
    for _, alias in ipairs(candidate.aliases) do
      if resolve_entity_prototype(alias) then
        return alias
      end
    end
  end
  return nil
end

local function build_option_list(candidates)
  local names = {}
  local labels = {}
  local can_resolve = can_resolve_prototypes()
  local uncertain = false

  if not can_resolve then
    for _, option in ipairs(candidates) do
      table.insert(names, option.name)
      table.insert(labels, option.label)
    end
    uncertain = true
  else
    for _, option in ipairs(candidates) do
      local resolved = resolve_candidate_name(option)
      if resolved then
        table.insert(names, resolved)
        table.insert(labels, option.label)
      end
    end
  end

  if #names == 0 then
    for _, option in ipairs(candidates) do
      table.insert(names, option.name)
      table.insert(labels, option.label)
    end
    uncertain = true
  end

  if #names == 0 then
    return { names = { nil }, labels = { "Unavailable" }, uncertain = true }
  end

  return { names = names, labels = labels, uncertain = uncertain }
end

local function get_localised_entity_name(entity_name)
  local prototype = resolve_entity_prototype(entity_name)
  return prototype and prototype.localised_name or entity_name
end

local function find_child_by_name(element, name)
  if not (element and element.valid) then
    return nil
  end

  if element.name == name then
    return element
  end

  for _, child in pairs(element.children) do
    local found = find_child_by_name(child, name)
    if found then
      return found
    end
  end

  return nil
end

local function has_solid_inputs(recipe)
  if not recipe then return false end
  for _, ingredient in pairs(recipe.ingredients or {}) do
    local name = ingredient.name or ingredient[1]
    local ingredient_type = ingredient.type or "item"
    if ingredient_type == "item" and name then
      return true
    end
  end
  return false
end

local function has_solid_outputs(recipe)
  if not recipe then return false end
  local products = recipe.products or {}
  for _, product in pairs(products) do
    if product.type == "item" then
      return true
    end
  end
  return false
end

local function has_solid_outputs(recipe)
  if not recipe then return false end
  local products = recipe.products or {}
  for _, product in pairs(products) do
    if product.type == "item" then
      return true
    end
  end
  return false
end

local function render_building_buttons(frame, options)
  local building_icons = frame and find_child_by_name(frame, GUI_BUILDING_FLOW)
  if not building_icons then
    return
  end

  building_icons.clear()

  if #options.buildings.names == 0 then
    building_icons.add({ type = "label", caption = "No options found for this surface" })
    return
  end

  for _, building_name in ipairs(options.buildings.names) do
    local button = building_icons.add({
      type = "sprite-button",
      name = GUI_BUILDING_PREFIX .. building_name,
      sprite = "entity/" .. building_name,
      style = "slot_button",
      tooltip = get_localised_entity_name(building_name),
    })
    button.toggled = (options.building_selection == building_name)
  end
end

local function render_input_chest_buttons(frame, options, force)
  local input_icons = frame and find_child_by_name(frame, GUI_INPUT_FLOW)
  if not input_icons then
    return
  end

  input_icons.clear()

  local recipe_name = options.recipes.names[options.recipe_selection_index]
  local recipe = recipe_name and force.recipes[recipe_name]
  
  if recipe and not has_solid_inputs(recipe) then
    input_icons.add({ type = "label", caption = "No solid input items" })
    return
  end

  for _, chest_name in ipairs(options.input_chests.names) do
    local button = input_icons.add({
      type = "sprite-button",
      name = GUI_INPUT_PREFIX .. chest_name,
      sprite = "entity/" .. chest_name,
      style = "slot_button",
      tooltip = get_localised_entity_name(chest_name),
    })
    button.toggled = (options.input_chest_selection == chest_name)
  end
end

local function render_output_chest_buttons(frame, options, force)
  local output_icons = frame and find_child_by_name(frame, GUI_OUTPUT_FLOW)
  if not output_icons then
    return
  end

  output_icons.clear()

  local recipe_name = options.recipes.names[options.recipe_selection_index]
  local recipe = recipe_name and force.recipes[recipe_name]
  
  if recipe and not has_solid_outputs(recipe) then
    output_icons.add({ type = "label", caption = "No solid output items" })
    return
  end

  for _, chest_name in ipairs(options.output_chests.names) do
    local button = output_icons.add({
      type = "sprite-button",
      name = GUI_OUTPUT_PREFIX .. chest_name,
      sprite = "entity/" .. chest_name,
      style = "slot_button",
      tooltip = get_localised_entity_name(chest_name),
    })
    button.toggled = (options.output_chest_selection == chest_name)
  end
end

local function is_recipe_compatible_with_surface(recipe, surface)
  if not (recipe and surface) then return true end
  
  local proto = recipe.prototype
  if not proto then return true end

  local conditions = proto.surface_conditions
  if not conditions or #conditions == 0 then return true end

  for _, condition in ipairs(conditions) do
    local property_value = surface.get_property(condition.property)
    
    if property_value == nil then
      -- If the surface doesn't define the property, we treat it as 0
      -- but only if that's valid for the condition.
      property_value = 0
    end
    
    if condition.min and property_value < condition.min then
      return false
    end
    if condition.max and property_value > condition.max then
      return false
    end
  end
  
  return true
end

local function get_recipes_for_item(force, item_name, surface)
  local name_to_check = item_name
  if type(item_name) == "table" then
    name_to_check = item_name.name
  end
  if not name_to_check then return {} end

  local results = {}
  for _, recipe in pairs(force.recipes) do
    if recipe.enabled and is_recipe_compatible_with_surface(recipe, surface) then
      for _, product in pairs(recipe.products or {}) do
        if product.name == name_to_check then
          table.insert(results, recipe)
          break
        end
      end
    end
  end
  return results
end

local function find_recipe_for_item(force, item_name, building_prototype, surface)
  local valid_recipes = get_recipes_for_item(force, item_name, surface)
  if #valid_recipes == 0 then return nil end
  
  if not building_prototype then return valid_recipes[1] end
  
  local categories = building_prototype.crafting_categories or {}
  for _, recipe in ipairs(valid_recipes) do
    if categories[recipe.category] then
      return recipe
    end
  end

  return nil
end

local function render_recipe_buttons(frame, options)
  local recipe_icons = frame and find_child_by_name(frame, GUI_RECIPE_FLOW)
  if not recipe_icons then
    return
  end

  recipe_icons.clear()

  if #options.recipes.names == 0 or (options.recipes.names[1] == nil) then
    recipe_icons.add({ type = "label", caption = "No options found for this surface" })
    return
  end

  for i, recipe_name in ipairs(options.recipes.names) do
    local button = recipe_icons.add({
      type = "sprite-button",
      name = GUI_RECIPE_PREFIX .. i,
      sprite = "recipe/" .. recipe_name,
      style = "slot_button",
      tooltip = options.recipes.labels[i],
    })
    button.toggled = (options.recipe_selection_index == i)
  end
end

local function build_building_options(player, force, item_name, surface)
  local name_to_check = item_name
  if type(item_name) == "table" then
    name_to_check = item_name.name
  end

  -- OPTIMIZATION: Find valid recipes for this item FIRST
  local valid_recipes = {}
  if name_to_check then
    valid_recipes = get_recipes_for_item(force, name_to_check, surface)
    if #valid_recipes == 0 then
      return { names = { nil }, labels = { "No options found for this surface" } }
    end
  end

  local prototypes = get_entity_prototypes()
  local entries = {}
  local found_names = {}

  if prototypes then
    for name, prototype in pairs(prototypes) do
      local is_valid = false
      pcall(function()
        local placeable = prototype.items_to_place_this and #prototype.items_to_place_this > 0
        local has_categories = prototype.crafting_categories and next(prototype.crafting_categories) ~= nil
        
        local is_hidden = false
        pcall(function()
          if prototype.has_flag("hidden") then
            is_hidden = true
          end
        end)
        
        if placeable and has_categories and not is_hidden then
          is_valid = true
        end
      end)

      if is_valid then
        -- Exclude recyclers and other non-production buildings
        if name:find("recycler", 1, true) then
          is_valid = false
        end
      end

      if is_valid then
        local building_can_craft = false
        if not name_to_check then
          building_can_craft = true
        else
          -- EXTREMELY FAST CHECK: Does this building support ANY of the pre-filtered recipes?
          local building_categories = prototype.crafting_categories or {}
          for _, recipe in ipairs(valid_recipes) do
            if building_categories[recipe.category] then
              building_can_craft = true
              break
            end
          end
        end

        if building_can_craft then
          table.insert(entries, {
            name = name,
            label = prototype.localised_name or name,
            order = prototype.order or "z"
          })
          found_names[name] = true
        end
      end
    end
  end

  if #entries == 0 then
    for _, option in ipairs(STATIC_BUILDING_CANDIDATES) do
      if not found_names[option.name] then
        local prototype = resolve_entity_prototype(option.name)
        if prototype then
          local building_can_craft = false
          if not name_to_check then
            building_can_craft = true
          else
            local building_categories = prototype.crafting_categories or {}
            for _, recipe in ipairs(valid_recipes) do
              if building_categories[recipe.category] then
                building_can_craft = true
                break
              end
            end
          end

          if building_can_craft then
            table.insert(entries, {
              name = option.name,
              label = prototype.localised_name or option.name,
              order = prototype.order or "z"
            })
            found_names[option.name] = true
          end
        end
      end
    end
  end

  table.sort(entries, function(a, b)
    return a.order < b.order
  end)

  local names = {}
  local labels = {}
  for _, entry in ipairs(entries) do
    table.insert(names, entry.name)
    table.insert(labels, entry.label)
  end

  if #names == 0 then
    return { names = { nil }, labels = { "No options found for this surface" } }
  end

  return { names = names, labels = labels }
end

local function recipe_outputs_item(recipe, item_name)
  if not recipe or not recipe.enabled then
    return false
  end

  for _, product in pairs(recipe.products or {}) do
    if product.name == item_name then
      return true
    end
  end

  return false
end

local function recipe_usable_in_building(recipe, building_prototype)
  if not (recipe and building_prototype) then
    return false
  end

  local categories = building_prototype.crafting_categories or {}
  return categories[recipe.category] == true
end

local function build_recipe_options(force, item_name, building_name, surface)
  local name_to_check = item_name
  if type(item_name) == "table" then
    name_to_check = item_name.name
  end

  if not (name_to_check and building_name) then
    return { names = { nil }, labels = { "No options found for this surface" } }
  end

  local building_prototype = resolve_entity_prototype(building_name)
  if not building_prototype then
    return { names = { nil }, labels = { "No options found for this surface" } }
  end

  local names = {}
  for recipe_name, recipe in pairs(force.recipes) do
    if recipe_outputs_item(recipe, name_to_check) and recipe_usable_in_building(recipe, building_prototype) then
      local compatible = is_recipe_compatible_with_surface(recipe, surface)
      if compatible then
        table.insert(names, recipe_name)
      end
    end
  end

  table.sort(names)

  if #names == 0 then
    return { names = { nil }, labels = { "No options found for this surface" } }
  end

  local labels = {}
  for _, recipe_name in ipairs(names) do
    local recipe = force.recipes[recipe_name]
    local localized = recipe
      and (recipe.localised_name or (recipe.prototype and recipe.prototype.localised_name) or recipe.name)
    table.insert(labels, localized or recipe_name)
  end

  return { names = names, labels = labels }
end

local function get_storage_root()
  -- Factorio 2.0 uses 'storage', 1.1 uses 'global'
  local root = nil
  if storage then
    root = storage
  elseif global then
    root = global
  end
  
  if not root then
    return nil
  end

  root.quick_mall = root.quick_mall or {}
  root.quick_mall.options = root.quick_mall.options or {}
  return root.quick_mall
end

local function ensure_global()
  get_storage_root()
end

local function destroy_gui(player)
  if player.gui.screen[GUI_ROOT] then
    player.gui.screen[GUI_ROOT].destroy()
  end
end

local function get_entity_tile_size(prototype)
  if prototype.tile_width and prototype.tile_height then
    return prototype.tile_width, prototype.tile_height
  end

  local box = prototype.selection_box or prototype.collision_box
  if not box then
    return 1, 1
  end

  local width = box.right_bottom.x - box.left_top.x
  local height = box.right_bottom.y - box.left_top.y
  return math.ceil(width), math.ceil(height)
end

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
  quality
)
  local entities = {}
  local next_id = 1
  local quality_name = quality or "normal"

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

  add_entity({
    name = building_name,
    position = { x = base_position.x, y = base_position.y },
    direction = defines.direction.north,
    recipe = recipe_name,
    recipe_quality = quality_name,
    tags = { 
      quick_mall_recipe = recipe_name,
      quick_mall_recipe_quality = quality_name
    },
  })

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

  add_entity({
    name = output_chest,
    position = { x = base_position.x - chest_offset, y = base_position.y + 1 },
  })

  add_entity({
    name = inserter_name,
    position = { x = base_position.x - inserter_offset, y = base_position.y + 1 },
    direction = defines.direction.east,
  })

  return entities
end

local function validate_entity_names(names)
  local missing = {}
  for _, name in ipairs(names) do
    if not resolve_entity_prototype(name) then
      table.insert(missing, name)
    end
  end
  return missing
end

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

local function is_valid_selection(selection, list)
  if not selection then return false end
  for _, name in ipairs(list) do
    if name == selection then return true end
  end
  return false
end

local function check_and_clear_incompatible_cursor_recipe(player)
  local stack = player.cursor_stack
  if not (stack and stack.valid and stack.valid_for_read and stack.is_blueprint) then
    return
  end

  local entities = stack.get_blueprint_entities()
  if not entities then return end

  local changed = false
  for _, entity in ipairs(entities) do
    -- Only clear if it's one of OUR recipes (building or input chest with requests)
    if entity.recipe and entity.tags and (entity.tags.quick_mall_recipe or entity.tags.quick_mall_requests) then
      local recipe = player.force.recipes[entity.recipe]
      if recipe and not is_recipe_compatible_with_surface(recipe, player.surface) then
        entity.recipe = nil
        entity.recipe_quality = nil
        -- Also clear tags to be consistent
        if entity.tags.quick_mall_recipe then
          entity.tags.quick_mall_recipe = nil
          entity.tags.quick_mall_recipe_quality = nil
        end
        changed = true
      end
    end
  end

  if changed then
    stack.set_blueprint_entities(entities)
    player.print("Quick Mall: cleared surface-incompatible recipe from blueprint.")
  end
end

local function build_gui(player)
  ensure_global()
  destroy_gui(player)

  local storage = get_storage_root()
  local existing_options = storage and storage.options[player.index]

  local options = {
    buildings = build_building_options(player, player.force, existing_options and existing_options.item_selection, player.surface),
    recipes = { names = { nil }, labels = { "No options found for this surface" } },
    input_chests = build_option_list(INPUT_CHEST_CANDIDATES),
    output_chests = build_option_list(OUTPUT_CHEST_CANDIDATES),
    inserters = build_option_list(INSERTER_CANDIDATES),
    item_selection = existing_options and existing_options.item_selection,
    building_selection = existing_options and existing_options.building_selection,
    recipe_selection_index = existing_options and existing_options.recipe_selection_index or 1,
    input_chest_selection = existing_options and existing_options.input_chest_selection,
    output_chest_selection = existing_options and existing_options.output_chest_selection,
    inserter_selection = existing_options and existing_options.inserter_selection,
    prototype_resolution_uncertain = false,
    is_initializing = true,
  }

  if not is_valid_selection(options.building_selection, options.buildings.names) then
    options.building_selection = options.buildings.names[1]
  end

  if options.item_selection and options.building_selection then
    options.recipes = build_recipe_options(player.force, options.item_selection, options.building_selection, player.surface)
  end

  if options.recipe_selection_index > #options.recipes.names then
    options.recipe_selection_index = 1
  end

  options.prototype_resolution_uncertain = options.input_chests.uncertain
    or options.output_chests.uncertain
    or options.inserters.uncertain
  if storage then
    storage.options[player.index] = options
  end

  local item_filters = get_researched_item_filters(player.force)

  local frame = player.gui.screen.add({
    type = "frame",
    name = GUI_ROOT,
    direction = "vertical",
    caption = "",
  })
  frame.auto_center = true

  local titlebar = frame.add({ type = "flow", direction = "horizontal" })
  titlebar.drag_target = frame
  titlebar.add({ type = "label", caption = "Quick Mall", style = "frame_title" })
  local drag = titlebar.add({ type = "empty-widget", style = "draggable_space_header" })
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = frame
  titlebar.add({
    type = "sprite-button",
    name = GUI_CLOSE,
    style = "frame_action_button",
    sprite = "utility/close",
  })

  local content = frame.add({ type = "flow", direction = "vertical" })
  content.style.padding = 12
  content.style.vertical_spacing = 8

  local item_flow = content.add({ type = "flow", direction = "horizontal" })
  item_flow.add({ type = "label", caption = "Item: " })
  local item_picker = item_flow.add({
    type = "choose-elem-button",
    name = GUI_ITEM,
    elem_type = "signal",
    elem_filters = item_filters,
    tooltip = "Choose the item to craft.",
  })
  
  if options.item_selection then
    item_picker.elem_value = options.item_selection
  end

  options.is_initializing = false

  local building_flow = content.add({ type = "flow", direction = "horizontal" })
  building_flow.add({ type = "label", caption = "Building: " })
  local building_icons = building_flow.add({
    type = "flow",
    name = GUI_BUILDING_FLOW,
    direction = "horizontal",
  })
  building_icons.style.horizontal_spacing = 4

  local recipe_flow = content.add({ type = "flow", direction = "horizontal" })
  recipe_flow.add({ type = "label", caption = "Recipe: " })
  local recipe_icons = recipe_flow.add({
    type = "flow",
    name = GUI_RECIPE_FLOW,
    direction = "horizontal",
  })
  recipe_icons.style.horizontal_spacing = 4

  local input_flow = content.add({ type = "flow", direction = "horizontal" })
  input_flow.add({ type = "label", caption = "Input chest: " })
  local input_icons = input_flow.add({
    type = "flow",
    name = GUI_INPUT_FLOW,
    direction = "horizontal",
  })
  input_icons.style.horizontal_spacing = 4

  local output_flow = content.add({ type = "flow", direction = "horizontal" })
  output_flow.add({ type = "label", caption = "Output chest: " })
  local output_icons = output_flow.add({
    type = "flow",
    name = GUI_OUTPUT_FLOW,
    direction = "horizontal",
  })
  output_icons.style.horizontal_spacing = 4

  local inserter_flow = content.add({ type = "flow", direction = "horizontal" })
  inserter_flow.add({ type = "label", caption = "Inserter: " })
  local inserter_icons = inserter_flow.add({
    type = "flow",
    name = GUI_INSERTER_FLOW,
    direction = "horizontal",
  })
  inserter_icons.style.horizontal_spacing = 4

  for _, inserter_name in ipairs(options.inserters.names) do
    local button = inserter_icons.add({
      type = "sprite-button",
      name = GUI_INSERTER_PREFIX .. inserter_name,
      sprite = "entity/" .. inserter_name,
      style = "slot_button",
      tooltip = get_localised_entity_name(inserter_name),
    })
    button.toggled = (options.inserter_selection == inserter_name)
  end

  local button_flow = content.add({ type = "flow", direction = "horizontal" })
  button_flow.style.horizontal_align = "right"
  button_flow.add({
    type = "button",
    name = GUI_CREATE,
    caption = "Build Quick Mall",
  })

  player.opened = frame

  render_building_buttons(frame, options)
  render_recipe_buttons(frame, options)

  if not is_valid_selection(options.input_chest_selection, options.input_chests.names) then
    options.input_chest_selection = options.input_chests.names[1]
  end
  render_input_chest_buttons(frame, options, player.force)

  if not is_valid_selection(options.output_chest_selection, options.output_chests.names) then
    options.output_chest_selection = options.output_chests.names[1]
  end
  render_output_chest_buttons(frame, options, player.force)

  if not is_valid_selection(options.inserter_selection, options.inserters.names) then
    options.inserter_selection = options.inserters.names[1]
  end
  -- Update inserter buttons state
  local inserter_icons = find_child_by_name(frame, GUI_INSERTER_FLOW)
  if inserter_icons then
    for _, child in pairs(inserter_icons.children) do
      if child and child.valid and child.name:find(GUI_INSERTER_PREFIX, 1, true) == 1 then
        local inserter_name = child.name:sub(#GUI_INSERTER_PREFIX + 1)
        child.toggled = (options.inserter_selection == inserter_name)
      end
    end
  end
end

local function refresh_building_dropdown(player, item_name)
  ensure_global()
  local storage = get_storage_root()
  local options = storage and storage.options[player.index]
  if not options then
    return
  end

  local frame = player.gui.screen[GUI_ROOT]
  if not frame then
    return
  end

  local old_selection = options.building_selection
  options.buildings = build_building_options(player, player.force, item_name, player.surface)
  
  if not is_valid_selection(old_selection, options.buildings.names) then
    options.building_selection = options.buildings.names[1]
  else
    options.building_selection = old_selection
  end
  
  render_building_buttons(frame, options)
end

local function refresh_recipe_buttons(player, item_name)
  ensure_global()
  local storage = get_storage_root()
  local options = storage and storage.options[player.index]
  if not options then
    return
  end

  local frame = player.gui.screen[GUI_ROOT]
  if not frame then
    return
  end

  local building_name = options.building_selection
  local old_recipe_name = options.recipes.names[options.recipe_selection_index]
  
  options.recipes = build_recipe_options(player.force, item_name, building_name, player.surface)

  -- Try to maintain the previous recipe by name instead of index
  local new_index = 1
  if old_recipe_name then
    for i, name in ipairs(options.recipes.names) do
      if name == old_recipe_name then
        new_index = i
        break
      end
    end
  end
  
  options.recipe_selection_index = new_index
  render_recipe_buttons(frame, options)
  render_input_chest_buttons(frame, options, player.force)
  render_output_chest_buttons(frame, options, player.force)
end

local function handle_create_click(player)
  ensure_global()
  local storage = get_storage_root()
  local options = storage and storage.options[player.index]

  if not options then
    player.print("Quick Mall: please reopen the menu.")
    return
  end

  local frame = player.gui.screen[GUI_ROOT]
  if not frame then
    return
  end

  local item_elem = find_child_by_name(frame, GUI_ITEM)

  local item_value = item_elem and item_elem.elem_value
  if not item_value then
    player.print("Quick Mall: choose an item first.")
    return
  end

  local item_name = item_value
  local quality_name = "normal"
  if type(item_value) == "table" then
    item_name = item_value.name
    quality_name = item_value.quality or "normal"
  end

  local building_name = options.building_selection
  local recipe_name = options.recipes.names[options.recipe_selection_index]
  local input_chest = options.input_chest_selection
  local output_chest = options.output_chest_selection
  local inserter_name = options.inserter_selection

  local building_prototype = resolve_entity_prototype(building_name)
  if not building_prototype then
    player.print("Quick Mall: selected building is not available.")
    return
  end

  local recipe = nil
  if recipe_name then
    local selected = player.force.recipes[recipe_name]
    if selected and recipe_outputs_item(selected, item_name) and recipe_usable_in_building(selected, building_prototype) then
      if is_recipe_compatible_with_surface(selected, player.surface) then
        recipe = selected
      end
    end
  end
  if not recipe then
    recipe = find_recipe_for_item(player.force, item_name, building_prototype, player.surface)
  end
  if not recipe then
    player.print("Quick Mall: no enabled recipe for that item using the selected building.")
    return
  end

  local request_list = get_item_requests(player, recipe, quality_name)
  local needs_input_chest = #request_list > 0

  if not (building_name and output_chest and inserter_name) or (needs_input_chest and not input_chest) then
    player.print("Quick Mall: some selected entities are not available.")
    return
  end

  local entities_to_validate = {
    building_name,
    output_chest,
    inserter_name,
  }
  if needs_input_chest then
    table.insert(entities_to_validate, input_chest)
  end

  local missing = validate_entity_names(entities_to_validate)
  if #missing > 0 then
    player.print("Quick Mall: selected entities are not available: " .. table.concat(missing, ", "))
    return
  end

  local tile_width = select(1, get_entity_tile_size(building_prototype))
  local half_width = math.floor(tile_width / 2)
  local inserter_offset = half_width + 1
  local chest_offset = half_width + 2

  local entities = build_blueprint_entities(
    { x = 0, y = 0 },
    building_name,
    recipe.name,
    input_chest,
    output_chest,
    inserter_name,
    chest_offset,
    inserter_offset,
    request_list,
    quality_name
  )
  if not give_blueprint_cursor(player, entities, request_list) then
    player.print("Quick Mall: unable to create blueprint. Clear your cursor and try again.")
    return
  end

  destroy_gui(player)
end

local function apply_ghost_tags(entity, tags)
  if not (entity and entity.valid and tags) then
    return
  end

  if tags.quick_mall_recipe then
    -- Check if it's an assembling-machine or something that actually uses recipes
    -- Furnaces do not use set_recipe() in the API, they are configured differently.
    local actual_entity = entity
    if entity.type == "entity-ghost" then
      -- If it's a ghost, we can only set the recipe if the ghost type supports it
      if entity.ghost_type == "assembling-machine" then
        local quality = tags.quick_mall_recipe_quality or "normal"
        entity.set_recipe(tags.quick_mall_recipe, quality)
      end
    elseif entity.type == "assembling-machine" then
      local quality = tags.quick_mall_recipe_quality or "normal"
      entity.set_recipe(tags.quick_mall_recipe, quality)
    end
  end

  if tags.quick_mall_requests then
    local ok, setter = pcall(function()
      return entity.set_request_slot
    end)
    if ok and setter then
      for index, request in ipairs(tags.quick_mall_requests) do
        local success = pcall(function()
          setter(entity, request, index)
        end)
        if not success then
          break
        end
      end
    end
  end
end

script.on_init(function()
  ensure_global()
end)

script.on_event("quick-mall-open", function(event)
  local player = game.get_player(event.player_index)
  if player then
    build_gui(player)
  end
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= "quick-mall-open" then
    return
  end

  local player = game.get_player(event.player_index)
  if player then
    build_gui(player)
  end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  if event.element and event.element.valid then
    if event.element.name == GUI_CREATE then
      handle_create_click(player)
    elseif event.element.name == GUI_CLOSE then
      destroy_gui(player)
    elseif event.element.name:find(GUI_BUILDING_PREFIX, 1, true) == 1 then
      local storage = get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local building_name = event.element.name:sub(#GUI_BUILDING_PREFIX + 1)
      options.building_selection = building_name

      local frame = player.gui.screen[GUI_ROOT]
      local building_icons = frame and find_child_by_name(frame, GUI_BUILDING_FLOW)
      if building_icons then
        for _, child in pairs(building_icons.children) do
          if child and child.valid and child.name:find(GUI_BUILDING_PREFIX, 1, true) == 1 then
            child.toggled = (child.name == event.element.name)
          end
        end
      end

      local item_elem = find_child_by_name(frame, GUI_ITEM)
      local item_name = item_elem and item_elem.elem_value
      refresh_recipe_buttons(player, item_name)
    elseif event.element.name:find(GUI_RECIPE_PREFIX, 1, true) == 1 then
      local storage = get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local index = tonumber(event.element.name:sub(#GUI_RECIPE_PREFIX + 1))
      options.recipe_selection_index = index

      local frame = player.gui.screen[GUI_ROOT]
      render_recipe_buttons(frame, options)
      render_input_chest_buttons(frame, options, player.force)
      render_output_chest_buttons(frame, options, player.force)
    elseif event.element.name:find(GUI_INPUT_PREFIX, 1, true) == 1 then
      local storage = get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local chest_name = event.element.name:sub(#GUI_INPUT_PREFIX + 1)
      options.input_chest_selection = chest_name

      local frame = player.gui.screen[GUI_ROOT]
      render_input_chest_buttons(frame, options)
    elseif event.element.name:find(GUI_OUTPUT_PREFIX, 1, true) == 1 then
      local storage = get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local chest_name = event.element.name:sub(#GUI_OUTPUT_PREFIX + 1)
      options.output_chest_selection = chest_name

      local frame = player.gui.screen[GUI_ROOT]
      render_output_chest_buttons(frame, options)
    elseif event.element.name:find(GUI_INSERTER_PREFIX, 1, true) == 1 then
      local storage = get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local inserter_name = event.element.name:sub(#GUI_INSERTER_PREFIX + 1)
      options.inserter_selection = inserter_name

      local frame = player.gui.screen[GUI_ROOT]
      local inserter_icons = frame and find_child_by_name(frame, GUI_INSERTER_FLOW)
      if inserter_icons then
        for _, child in pairs(inserter_icons.children) do
          if child and child.valid and child.name:find(GUI_INSERTER_PREFIX, 1, true) == 1 then
            child.toggled = (child.name == event.element.name)
          end
        end
      end
    end
  end
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  if event.element and event.element.valid and event.element.name == GUI_ITEM then
    local storage = get_storage_root()
    local options = storage and storage.options[player.index]
    
    if options and options.is_initializing then
      return
    end
    if options then
      options.item_selection = event.element.elem_value
      options.recipe_selection_index = 1
    end
    
    local item_name = event.element.elem_value
    local name_to_refresh = item_name
    if type(item_name) == "table" then
      name_to_refresh = item_name.name
    end

    refresh_building_dropdown(player, name_to_refresh)
    refresh_recipe_buttons(player, name_to_refresh)
  end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  if event.element and event.element.valid and event.element.name == GUI_ROOT then
    event.element.destroy()
  end
end)

script.on_event(defines.events.on_player_changed_surface, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  -- 1. Check if player is holding an incompatible mall layout in their cursor
  check_and_clear_incompatible_cursor_recipe(player)

  -- 2. Refresh GUI if open
  local frame = player.gui.screen[GUI_ROOT]
  if not frame then
    return
  end

  local storage = get_storage_root()
  local options = storage and storage.options[player.index]
  if options then
    local item_selection = options.item_selection
    local name_to_refresh = item_selection
    if type(item_selection) == "table" then
      name_to_refresh = item_selection.name
    end
    refresh_building_dropdown(player, name_to_refresh)
    refresh_recipe_buttons(player, name_to_refresh)
  end
end)

local function handle_built_entity(event)
  local entity = event.created_entity or event.entity
  if not entity or not entity.valid then
    return
  end

  local tags = event.tags
  if not tags and entity.tags then
    local ok, entity_tags = pcall(function()
      return entity.tags
    end)
    if ok then
      tags = entity_tags
    end
  end

  apply_ghost_tags(entity, tags)
end

script.on_event(defines.events.on_built_entity, handle_built_entity)
script.on_event(defines.events.on_robot_built_entity, handle_built_entity)

-- =============================================================================
-- Quick Mall — control.lua
-- =============================================================================
--
-- WHAT THIS MOD DOES
--   Quick Mall provides a one-click "mall" blueprint builder. The player opens a
--   small GUI (via the shortcut / custom input "quick-mall-open"), picks an item
--   to craft, a crafting building, a recipe, input/output logistic chests, and an
--   inserter type. Pressing "Build Quick Mall" constructs a blueprint in the
--   player's cursor containing:
--     - the chosen crafting building (with the recipe/quality preset),
--     - an input logistic chest requesting one stack of each solid ingredient,
--       plus an inserter feeding the building,
--     - an output logistic chest (with an optional stack/bar limit) plus an
--       inserter pulling finished products out.
--   Chests/inserters are only added when the recipe actually has solid
--   inputs/outputs.
--
-- OVERALL FLOW
--   1. build_gui(player) creates the window and seeds per-player `options` from
--      saved state, computing the available building/recipe/chest/inserter lists.
--   2. GUI events (on_gui_click / on_gui_elem_changed / on_gui_text_changed)
--      update `options` and re-render the affected icon rows via the render_*
--      and refresh_* helpers.
--   3. handle_create_click(player) validates the current selection, computes
--      blueprint geometry, builds the blueprint entities, and places the
--      blueprint in the cursor. The crafting building carries both a `recipe`
--      field and `quick_mall_recipe` / `quick_mall_recipe_quality` tags.
--   4. When a ghost or entity from that blueprint is built (on_built_entity /
--      on_robot_built_entity), apply_ghost_tags re-applies the recipe + quality
--      to assembling-machines from the tags (belt-and-suspenders for cases where
--      the blueprint `recipe` field alone is not honored).
--
-- FACTORIO 1.1 / 2.0 COMPATIBILITY STRATEGY
--   The file is written to run under both Factorio 1.1 and 2.0:
--     - Saved state: 2.0 uses the `storage` global, 1.1 used `global`.
--       get_storage_root() picks whichever exists.
--     - Prototype access: 1.1/2.0 offer game.entity_prototypes /
--       game.item_prototypes / game.get_entity_prototype etc.; 2.0 also exposes
--       the read-only `prototypes` global (prototypes.entity / prototypes.item).
--       The get_*_prototypes / resolve_*_prototype helpers try each API in turn
--       (wrapped in pcall) so a missing API on either version degrades gracefully.
--     - Logistic-chest names differ across versions/mods, so chest candidates
--       carry `aliases` that resolve_candidate_name falls back to.
--
-- NOTE: `building_candidates_cache` is a derived, module-local memo (NOT part of
-- the save file); it is invalidated on init / configuration / research events.
-- =============================================================================

local GUI_ROOT = "quick-mall-window"
local GUI_ITEM = "quick-mall-item"
local GUI_RECIPE_FLOW = "quick-mall-recipe-flow"
local GUI_RECIPE_PREFIX = "quick-mall-recipe-"
local GUI_INPUT_CHEST = "quick-mall-input-chest"
local GUI_OUTPUT_CHEST = "quick-mall-output-chest"
local GUI_STACK_LIMIT = "quick-mall-stack-limit"
local GUI_STACK_LIMIT_FLOW = "quick-mall-stack-limit-flow"
local GUI_INSERTER = "quick-mall-inserter"
local GUI_BUILDING_FLOW = "quick-mall-building-flow"
local GUI_BUILDING_PREFIX = "quick-mall-building-"
local GUI_INSERTER_FLOW = "quick-mall-inserter-flow"
local GUI_INSERTER_PREFIX = "quick-mall-inserter-"
local GUI_INPUT_FLOW = "quick-mall-input-flow"
local GUI_INPUT_PREFIX = "quick-mall-input-"
local GUI_OUTPUT_FLOW = "quick-mall-output-flow"
local GUI_OUTPUT_PREFIX = "quick-mall-output-"
local GUI_QUALITY_WARNING = "quick-mall-quality-warning"
local GUI_CREATE = "quick-mall-create"
local GUI_CLOSE = "quick-mall-close"

-- Optional test module; exposed later via the "quick_mall" remote interface.
local tests = require("tests")

-- Read-only derived cache of candidate crafting buildings (placeable + has
-- crafting_categories + not hidden + not recycler). This depends only on the
-- entity prototypes, NOT on the selected item, so it is computed once and
-- memoized here. It must NEVER be stored in `storage`/`global` (not part of the
-- save file). It is invalidated on init/configuration changes.
local building_candidates_cache = nil

-- === Candidate option tables ===
-- Fallback/ordering hints. Each entry is { name, label, aliases? }. `name` is the
-- preferred prototype name; `aliases` list alternate prototype names to try when
-- `name` is not present (handles 1.1 vs 2.0 vs modded logistic-chest naming).

-- Fallback crafting buildings used only if the dynamic candidate scan finds none.
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

-- === Prototype resolution helpers (1.1 / 2.0 compatible) ===

-- Returns the table of all entity prototypes (keyed by name), trying the
-- standard game API, then the 2.0 `prototypes.entity` global, then a filtered
-- query. Returns {} if none is available.
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

-- Resolves a single entity prototype by name, or nil if unknown/unavailable.
-- Tries the direct getter, then the 2.0 global, then the full-table lookup.
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

-- Returns the table of all item prototypes (keyed by name), or {} if none is
-- available. Same version-fallback approach as get_entity_prototypes.
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

-- Resolves a single item prototype by name, or nil if unknown/unavailable.
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

-- True when prototype lookups appear to be working (probes the vanilla
-- "inserter"). Used to decide whether option lists can be filtered confidently.
local function can_resolve_prototypes()
  return resolve_entity_prototype("inserter") ~= nil
end

-- Returns the first resolvable prototype name for a candidate: its `name`, else
-- one of its `aliases`, else nil. Lets a candidate map to whichever naming the
-- current game/mods use.
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

-- === Option-list builders ===

-- Turns a candidate table into a { names, labels, uncertain } option list for
-- the GUI. When prototypes resolve, keeps only candidates that actually exist
-- (mapped through aliases); otherwise falls back to listing all candidates and
-- flags `uncertain = true`. Guarantees at least one entry.
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

-- === Misc GUI / recipe helpers ===

-- Returns an entity's localised_name (for tooltips), falling back to the raw
-- name when the prototype cannot be resolved.
local function get_localised_entity_name(entity_name)
  local prototype = resolve_entity_prototype(entity_name)
  return prototype and prototype.localised_name or entity_name
end

-- Recursively searches a GUI element subtree for a descendant with the given
-- name (matching the element itself too). Returns the element or nil.
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

-- True if the recipe has at least one solid (item, not fluid) ingredient.
-- Handles both the named-field and positional ingredient shapes.
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

-- True if the recipe produces at least one solid (item) product.
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

-- === GUI render / refresh helpers ===

-- Shows or hides the quality-warning label based on the current selection:
-- fluids and fluid-only-input recipes cannot produce above-normal quality, so a
-- note is shown when a non-normal quality is chosen for such a recipe.
local function update_quality_warning(player, frame, options)
  local warning_label = frame and find_child_by_name(frame, GUI_QUALITY_WARNING)
  if not warning_label then return end

  local item_value = options.item_selection
  local quality_name = "normal"
  local is_fluid = false
  if type(item_value) == "table" then
    quality_name = item_value.quality or "normal"
    is_fluid = (item_value.type == "fluid")
  end

  if quality_name == "normal" and not is_fluid then
    warning_label.visible = false
    return
  end

  local recipe_name = options.recipes.names[options.recipe_selection_index]
  local recipe = recipe_name and player.force.recipes[recipe_name]
  
  if recipe then
    if is_fluid and quality_name ~= "normal" then
      warning_label.visible = true
      warning_label.caption = "Note: Fluids do not possess quality. Output fluid will be of normal quality."
    elseif not has_solid_inputs(recipe) and quality_name ~= "normal" then
      warning_label.visible = true
      warning_label.caption = "Note: Recipes with only fluid inputs cannot produce outputs of higher than normal quality. Output will be of normal quality."
    else
      warning_label.visible = false
    end
  else
    warning_label.visible = false
  end
end

-- Rebuilds the building icon row from options.buildings, marking the selected
-- one toggled. Shows a placeholder label when there are no options.
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

-- Rebuilds the input-chest icon row. If the selected recipe has no solid inputs,
-- shows a "No solid input items" label instead (no chest is needed).
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

-- Rebuilds the output-chest icon row. If the selected recipe has no solid
-- outputs, shows a "No solid output items" label instead.
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

-- Rebuilds the "Output Stacks Limit" row: a numeric textfield (seeded from
-- options.stack_limit) that sets the output chest's bar. Hidden as a label when
-- the recipe has no solid outputs.
local function render_stack_limit_ui(frame, options, force)
  local flow = frame and find_child_by_name(frame, GUI_STACK_LIMIT_FLOW)
  if not flow then return end

  flow.clear()

  local recipe_name = options.recipes.names[options.recipe_selection_index]
  local recipe = recipe_name and force.recipes[recipe_name]
  
  flow.add({ type = "label", caption = "Output Stacks Limit: ", style = "heading_2_label" })
  if recipe and not has_solid_outputs(recipe) then
    flow.add({ type = "label", caption = "No solid output items" })
    return
  end

  local stack_limit = flow.add({
    type = "textfield",
    name = GUI_STACK_LIMIT,
    text = tostring(options.stack_limit or 1),
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
  })
  stack_limit.style.width = 50
end

-- === Recipe filtering & surface compatibility ===

-- True if the recipe can be crafted on the given surface. Checks the recipe
-- prototype's surface_conditions (2.0 planet properties) against the surface's
-- properties; treats a missing property as 0. Recipes with no conditions (or
-- when recipe/surface is nil) are considered compatible.
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

-- Returns a list of recipe objects that are enabled for the force, compatible
-- with the surface, and produce the given item. `item_name` may be a plain name
-- or a signal/table with a `.name` field.
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

-- Picks a single recipe producing the item. With no building prototype, returns
-- the first valid recipe; otherwise returns the first whose category the building
-- can craft. Returns nil if none qualify.
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

-- Rebuilds the recipe icon row from options.recipes (buttons named by 1-based
-- index), marking options.recipe_selection_index toggled. Shows a placeholder
-- when there are no options.
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

-- === Candidate building / recipe option builders ===

-- Build (once) and memoize the set of "candidate crafting buildings". This scan
-- (placeable + has crafting_categories + not hidden + not recycler) does NOT
-- depend on the selected item, so it is safe to compute a single time and reuse
-- across item changes. Only the per-item recipe-category filter varies.
-- The cache is invalidated on init/configuration changes.
local function get_candidate_buildings()
  if building_candidates_cache then
    return building_candidates_cache
  end

  local candidates = {}
  local entity_prototypes = get_entity_prototypes()

  if entity_prototypes then
    for name, prototype in pairs(entity_prototypes) do
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
        table.insert(candidates, {
          name = name,
          label = prototype.localised_name or name,
          order = prototype.order or "z",
          -- Reference to the prototype's crafting_categories table (used as a
          -- set: categories[recipe.category]) so the per-item filter can test
          -- categories without re-reading the prototype.
          crafting_categories = prototype.crafting_categories or {},
        })
      end
    end
  end

  building_candidates_cache = candidates
  return candidates
end

-- Builds the { names, labels } list of buildings that can craft `item_name` on
-- the surface. Pre-filters the item's recipes once, then keeps candidate
-- buildings whose crafting_categories cover any of those recipes; falls back to
-- STATIC_BUILDING_CANDIDATES if nothing matched. Result is sorted by prototype
-- order. Returns a single {nil} entry when there are no options.
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

  local candidates = get_candidate_buildings()
  local entries = {}
  local found_names = {}

  for _, candidate in ipairs(candidates) do
    local building_can_craft = false
    if not name_to_check then
      building_can_craft = true
    else
      -- EXTREMELY FAST CHECK: Does this building support ANY of the pre-filtered recipes?
      local building_categories = candidate.crafting_categories or {}
      for _, recipe in ipairs(valid_recipes) do
        if building_categories[recipe.category] then
          building_can_craft = true
          break
        end
      end
    end

    if building_can_craft then
      table.insert(entries, {
        name = candidate.name,
        label = candidate.label,
        order = candidate.order
      })
      found_names[candidate.name] = true
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

-- True if the recipe is enabled and lists item_name among its products.
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

-- True if the building's crafting_categories include the recipe's category.
local function recipe_usable_in_building(recipe, building_prototype)
  if not (recipe and building_prototype) then
    return false
  end

  local categories = building_prototype.crafting_categories or {}
  return categories[recipe.category] == true
end

-- Builds the { names, labels } list of recipes producing `item_name` that the
-- named building can craft on the surface (names sorted, labels localised).
-- Returns a single {nil} entry when the item/building is missing or nothing
-- matches.
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

  -- OPTIMIZATION: reuse get_recipes_for_item (enabled + surface-compatible +
  -- outputs item) instead of re-scanning force.recipes from scratch. The set
  -- build_recipe_options needs is exactly that result further filtered by the
  -- building's crafting categories, so we only apply recipe_usable_in_building
  -- here. This removes one full force.recipes walk per GUI build/refresh.
  local names = {}
  for _, recipe in ipairs(get_recipes_for_item(force, name_to_check, surface)) do
    if recipe_usable_in_building(recipe, building_prototype) then
      table.insert(names, recipe.name)
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

-- === Storage / global state ===

-- Returns the mod's persistent root table, creating its `quick_mall.options`
-- substructure (per-player options keyed by player index). Uses `storage` on
-- 2.0 and `global` on 1.1; returns nil if neither exists.
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

-- Ensures the storage root/substructure exists (side-effect of get_storage_root).
local function ensure_global()
  get_storage_root()
end

-- === GUI lifecycle & blueprint construction ===

-- Destroys the Quick Mall window for the player if it is open.
local function destroy_gui(player)
  if player.gui.screen[GUI_ROOT] then
    player.gui.screen[GUI_ROOT].destroy()
  end
end

-- Returns the building's footprint as (tile_width, tile_height), using the
-- prototype's tile size when present, else deriving it from the selection or
-- collision box; defaults to 1x1. Used to place chests/inserters clear of the
-- building.
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
--   - the crafting building (with recipe, recipe_quality, and quick_mall_* tags),
--   - an input chest with logistic request_filters + a feeding inserter (only when
--     request_list is non-empty and an input chest is chosen),
--   - an output chest (with an optional `bar` = stack_limit) + an extracting
--     inserter (only when an output chest / inserter is chosen).
-- chest_offset / inserter_offset are horizontal offsets to the west of the
-- building. Each entity gets a sequential entity_number. Returns the entity list.
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
  stack_limit
)
  local entities = {}
  local next_id = 1
  local quality_name = quality or "normal"
  local bar_value = (stack_limit and stack_limit > 0) and stack_limit or nil

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

-- True if `selection` is present in `list` (used to keep a saved selection only
-- when it still exists in the freshly built option list).
local function is_valid_selection(selection, list)
  if not selection then return false end
  for _, name in ipairs(list) do
    if name == selection then return true end
  end
  return false
end

-- === GUI construction ===

-- Builds (or rebuilds) the Quick Mall window for the player. Seeds the per-player
-- `options` table from saved state, computes the building/recipe/chest/inserter
-- option lists, validates/normalizes saved selections, persists options, then
-- creates the frame: titlebar, a scroll-pane holding the item picker and the
-- building/recipe/input/output/stack-limit/inserter rows plus a quality warning,
-- and a Build button pinned below the scroll-pane. Finally renders each icon row.
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
    stack_limit = existing_options and existing_options.stack_limit or 1,
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

  -- Wrap the selection rows in a scroll-pane so a heavily-modded game (with
  -- dozens of building/recipe/chest icons) cannot grow the window taller than
  -- the screen. The titlebar (above) and the Build button (below) stay outside
  -- this scroll-pane so the Build button is always visible/reachable.
  local scroll_pane = frame.add({
    type = "scroll-pane",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto",
  })
  scroll_pane.style.maximum_height = 500

  local content = scroll_pane.add({ type = "flow", direction = "vertical" })
  content.style.padding = 12
  content.style.vertical_spacing = 8

  local item_flow = content.add({ type = "flow", direction = "horizontal" })
  item_flow.style.vertical_align = "center"
  item_flow.add({ type = "label", caption = "Item: ", style = "heading_2_label" })
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
  building_flow.style.vertical_align = "center"
  building_flow.add({ type = "label", caption = "Building: ", style = "heading_2_label" })
  local building_icons = building_flow.add({
    type = "table",
    name = GUI_BUILDING_FLOW,
    column_count = 10,
  })
  building_icons.style.horizontal_spacing = 4
  building_icons.style.vertical_spacing = 4

  local recipe_flow = content.add({ type = "flow", direction = "horizontal" })
  recipe_flow.style.vertical_align = "center"
  recipe_flow.add({ type = "label", caption = "Recipe: ", style = "heading_2_label" })
  local recipe_icons = recipe_flow.add({
    type = "flow",
    name = GUI_RECIPE_FLOW,
    direction = "horizontal",
  })
  recipe_icons.style.horizontal_spacing = 4

  local input_flow = content.add({ type = "flow", direction = "horizontal" })
  input_flow.style.vertical_align = "center"
  input_flow.add({ type = "label", caption = "Input chest: ", style = "heading_2_label" })
  local input_icons = input_flow.add({
    type = "flow",
    name = GUI_INPUT_FLOW,
    direction = "horizontal",
  })
  input_icons.style.horizontal_spacing = 4

  local output_flow = content.add({ type = "flow", direction = "horizontal" })
  output_flow.style.vertical_align = "center"
  output_flow.add({ type = "label", caption = "Output chest: ", style = "heading_2_label" })
  local output_icons = output_flow.add({
    type = "flow",
    name = GUI_OUTPUT_FLOW,
    direction = "horizontal",
  })
  output_icons.style.horizontal_spacing = 4

  local stack_limit_flow = content.add({ 
    type = "flow", 
    name = GUI_STACK_LIMIT_FLOW,
    direction = "horizontal" 
  })
  stack_limit_flow.style.vertical_align = "center"

  local inserter_flow = content.add({ type = "flow", direction = "horizontal" })
  inserter_flow.style.vertical_align = "center"
  inserter_flow.add({ type = "label", caption = "Inserter: ", style = "heading_2_label" })
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

  local warning_label = content.add({
    type = "label",
    name = GUI_QUALITY_WARNING,
    caption = "",
  })
  warning_label.style.font_color = {r = 1, g = 0.5, b = 0}
  warning_label.style.single_line = false
  warning_label.visible = false

  -- Add the Build button directly to the frame (outside the scroll-pane) so it
  -- is always visible below the scrollable content, regardless of icon count.
  local button_flow = frame.add({ type = "flow", direction = "horizontal" })
  button_flow.style.horizontal_align = "right"
  button_flow.style.horizontally_stretchable = true
  button_flow.style.padding = 12
  button_flow.add({
    type = "button",
    name = GUI_CREATE,
    caption = "Build Quick Mall",
  })

  player.opened = frame

  update_quality_warning(player, frame, options)
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
  render_stack_limit_ui(frame, options, player.force)

  if not is_valid_selection(options.inserter_selection, options.inserters.names) then
    options.inserter_selection = options.inserters.names[1]
  end
  -- Update inserter buttons state
  inserter_icons = find_child_by_name(frame, GUI_INSERTER_FLOW)
  if inserter_icons then
    for _, child in pairs(inserter_icons.children) do
      if child and child.valid and child.name:find(GUI_INSERTER_PREFIX, 1, true) == 1 then
        local inserter_name = child.name:sub(#GUI_INSERTER_PREFIX + 1)
        child.toggled = (options.inserter_selection == inserter_name)
      end
    end
  end
end

-- Recomputes the building options for the (possibly new) item, keeping the prior
-- building selection when still valid (else the first option), and re-renders the
-- building icon row.
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

-- Recomputes recipe options for the current item + selected building, preserving
-- the previously selected recipe by name (falling back to the first), and
-- re-renders the recipe row plus the dependent chest/stack-limit rows and the
-- quality warning.
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
  update_quality_warning(player, frame, options)
  render_recipe_buttons(frame, options)
  render_input_chest_buttons(frame, options, player.force)
  render_output_chest_buttons(frame, options, player.force)
  render_stack_limit_ui(frame, options, player.force)
end

-- Handles the "Build Quick Mall" button. Reads the chosen item/quality and the
-- saved building/recipe/chest/inserter selections, resolves and validates a
-- usable recipe (resetting quality to normal for fluids / fluid-only-input
-- recipes), verifies all needed entities exist, computes the layout offsets from
-- the building footprint, builds the blueprint entities, and hands the blueprint
-- to the cursor. Prints an explanatory message and aborts on any failure; closes
-- the GUI on success.
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
  local is_fluid = false
  if type(item_value) == "table" then
    item_name = item_value.name
    quality_name = item_value.quality or "normal"
    is_fluid = item_value.type == "fluid"
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

  if quality_name ~= "normal" and not has_solid_inputs(recipe) then
    -- Quick Mall: Recipes with only fluid inputs cannot produce higher than normal quality. Output quality has been reset to normal.
    quality_name = "normal"
  end

  if is_fluid and quality_name ~= "normal" then
    -- Quick Mall: Fluids do not possess quality. Output quality has been reset to normal.
    quality_name = "normal"
  end

  local request_list = get_item_requests(player, recipe, quality_name)
  local needs_input_chest = #request_list > 0
  local needs_output_chest = has_solid_outputs(recipe)
  local needs_inserter = needs_input_chest or needs_output_chest

  if needs_output_chest == false then
    output_chest = nil
  end

  if not building_name
    or (needs_output_chest and not output_chest)
    or (needs_inserter and not inserter_name)
    or (needs_input_chest and not input_chest)
  then
    player.print("Quick Mall: some selected entities are not available.")
    return
  end

  local entities_to_validate = { building_name }
  if needs_output_chest then
    table.insert(entities_to_validate, output_chest)
  end
  if needs_inserter then
    table.insert(entities_to_validate, inserter_name)
  end
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
    quality_name,
    options.stack_limit
  )
  if not give_blueprint_cursor(player, entities, request_list) then
    player.print("Quick Mall: unable to create blueprint. Clear your cursor and try again.")
    return
  end

  destroy_gui(player)
end

-- === Ghost-tag application ===

-- Re-applies a Quick Mall recipe/quality to a freshly built entity (or ghost)
-- from its quick_mall_recipe / quick_mall_recipe_quality tags. Only acts on
-- assembling-machines (real or ghost), which support set_recipe; no-op otherwise.
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
end

-- === Event handlers ===

-- On new game / mod first load: clear the derived cache and init storage.
script.on_init(function()
  -- Reset the derived candidate-building cache (module local, never saved).
  building_candidates_cache = nil
  ensure_global()
end)

script.on_configuration_changed(function(event)
  -- Mod/version changes can add, remove, or alter entity prototypes, so the
  -- memoized candidate-building set must be rebuilt on next use.
  building_candidates_cache = nil
  ensure_global()
end)

script.on_event(defines.events.on_research_finished, function(event)
  -- Research does NOT change the candidate BUILDING set (placeable/categories/
  -- hidden are prototype properties), only recipe availability, which is handled
  -- by the per-item recipe filter. Reset defensively to stay robust to any
  -- prototype-affecting mod interactions.
  building_candidates_cache = nil
end)

-- Custom input "quick-mall-open" (keybind): open the GUI for the player.
script.on_event("quick-mall-open", function(event)
  local player = game.get_player(event.player_index)
  if player then
    build_gui(player)
  end
end)

-- Toolbar shortcut: open the GUI when the "quick-mall-open" shortcut is clicked.
script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= "quick-mall-open" then
    return
  end

  local player = game.get_player(event.player_index)
  if player then
    build_gui(player)
  end
end)

-- Dispatches GUI clicks by element name: Build, Close, or a building/recipe/
-- input-chest/output-chest/inserter icon. Icon clicks update the corresponding
-- selection in `options` and re-render the affected rows (recipe row rebuilds
-- cascade to the chest/stack-limit rows).
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
      update_quality_warning(player, frame, options)
      render_recipe_buttons(frame, options)
      render_input_chest_buttons(frame, options, player.force)
      render_output_chest_buttons(frame, options, player.force)
      render_stack_limit_ui(frame, options, player.force)
    elseif event.element.name:find(GUI_INPUT_PREFIX, 1, true) == 1 then
      local storage = get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local chest_name = event.element.name:sub(#GUI_INPUT_PREFIX + 1)
      options.input_chest_selection = chest_name

      local frame = player.gui.screen[GUI_ROOT]
      render_input_chest_buttons(frame, options, player.force)
    elseif event.element.name:find(GUI_OUTPUT_PREFIX, 1, true) == 1 then
      local storage = get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local chest_name = event.element.name:sub(#GUI_OUTPUT_PREFIX + 1)
      options.output_chest_selection = chest_name

      local frame = player.gui.screen[GUI_ROOT]
      render_output_chest_buttons(frame, options, player.force)
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

-- Stack-limit textfield changes: store the parsed value in options.stack_limit
-- (empty or 0 = "no limit"); ignores negatives.
script.on_event(defines.events.on_gui_text_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  if event.element and event.element.valid and event.element.name == GUI_STACK_LIMIT then
    local storage = get_storage_root()
    local options = storage and storage.options[player.index]
    if options then
      local val = tonumber(event.element.text)
      if val == nil then
        -- Empty field means "no limit"; store 0 so state tracks the field.
        options.stack_limit = 0
      elseif val >= 0 then
        -- 0 = "no limit" (build_blueprint_entities treats 0 as no bar).
        options.stack_limit = val
      end
      -- Negative values are ignored (textfield also disallows them).
    end
  end
end)

-- Item-picker changes: record the new item, reset the recipe index, and refresh
-- the building and recipe rows. Ignored during initial GUI setup
-- (options.is_initializing) so seeding the picker does not trigger a refresh.
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

-- Reserved: no dropdowns currently use selection-state changes (kept as a no-op).
script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
end)

-- Closes the window when the game dispatches on_gui_closed for our root frame
-- (e.g. the player presses Esc).
script.on_event(defines.events.on_gui_closed, function(event)
  if event.element and event.element.valid and event.element.name == GUI_ROOT then
    event.element.destroy()
  end
end)

-- On surface change: strip surface-incompatible recipes from any Quick Mall
-- blueprint in the cursor, then refresh the open GUI's building/recipe rows for
-- the new surface.
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

-- Shared handler for on_built_entity / on_robot_built_entity: resolves the built
-- entity and its tags (from the event, or the entity itself) and applies any
-- Quick Mall recipe/quality via apply_ghost_tags.
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

-- Remote interface for testing
remote.add_interface("quick_mall", {
  run_tests = function()
    if tests then
      tests.run_all()
    else
      game.print("Quick Mall: tests module not loaded.")
    end
  end
})

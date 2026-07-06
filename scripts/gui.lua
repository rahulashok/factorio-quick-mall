-- =============================================================================
-- Quick Mall — scripts/gui.lua
-- =============================================================================
-- GUI construction, render/refresh helpers, and the build-click handler.
-- Depends on: constants, prototypes, recipes, blueprint, storage.
-- =============================================================================

local constants = require("scripts.constants")
local prototypes = require("scripts.prototypes")
local recipes = require("scripts.recipes")
local blueprint = require("scripts.blueprint")
local storage_mod = require("scripts.storage")

-- Local aliases to cross-module helpers/constants so the moved function bodies
-- stay byte-identical to their control.lua originals.
local GUI_ROOT = constants.GUI_ROOT
local GUI_ITEM = constants.GUI_ITEM
local GUI_RECIPE_FLOW = constants.GUI_RECIPE_FLOW
local GUI_RECIPE_PREFIX = constants.GUI_RECIPE_PREFIX
local GUI_STACK_LIMIT = constants.GUI_STACK_LIMIT
local GUI_STACK_LIMIT_FLOW = constants.GUI_STACK_LIMIT_FLOW
local GUI_BUILDING_FLOW = constants.GUI_BUILDING_FLOW
local GUI_BUILDING_PREFIX = constants.GUI_BUILDING_PREFIX
local GUI_INSERTER_FLOW = constants.GUI_INSERTER_FLOW
local GUI_INSERTER_PREFIX = constants.GUI_INSERTER_PREFIX
local GUI_INPUT_FLOW = constants.GUI_INPUT_FLOW
local GUI_INPUT_PREFIX = constants.GUI_INPUT_PREFIX
local GUI_OUTPUT_FLOW = constants.GUI_OUTPUT_FLOW
local GUI_OUTPUT_PREFIX = constants.GUI_OUTPUT_PREFIX
local GUI_QUALITY_WARNING = constants.GUI_QUALITY_WARNING
local GUI_CREATE = constants.GUI_CREATE
local GUI_CLOSE = constants.GUI_CLOSE
local INPUT_CHEST_CANDIDATES = constants.INPUT_CHEST_CANDIDATES
local OUTPUT_CHEST_CANDIDATES = constants.OUTPUT_CHEST_CANDIDATES
local INSERTER_CANDIDATES = constants.INSERTER_CANDIDATES

local build_option_list = prototypes.build_option_list
local get_localised_entity_name = prototypes.get_localised_entity_name
local resolve_entity_prototype = prototypes.resolve_entity_prototype
local get_entity_tile_size = prototypes.get_entity_tile_size

local has_solid_inputs = recipes.has_solid_inputs
local has_solid_outputs = recipes.has_solid_outputs
local build_building_options = recipes.build_building_options
local build_recipe_options = recipes.build_recipe_options
local recipe_outputs_item = recipes.recipe_outputs_item
local recipe_usable_in_building = recipes.recipe_usable_in_building
local is_recipe_compatible_with_surface = recipes.is_recipe_compatible_with_surface
local find_recipe_for_item = recipes.find_recipe_for_item

local get_researched_item_filters = blueprint.get_researched_item_filters
local get_item_requests = blueprint.get_item_requests
local validate_entity_names = blueprint.validate_entity_names
local build_blueprint_entities = blueprint.build_blueprint_entities
local give_blueprint_cursor = blueprint.give_blueprint_cursor

local ensure_global = storage_mod.ensure_global
local get_storage_root = storage_mod.get_storage_root

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

-- True if `selection` is present in `list` (used to keep a saved selection only
-- when it still exists in the freshly built option list).
local function is_valid_selection(selection, list)
  if not selection then return false end
  for _, name in ipairs(list) do
    if name == selection then return true end
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

-- === GUI lifecycle ===

-- Destroys the Quick Mall window for the player if it is open.
local function destroy_gui(player)
  if player.gui.screen[GUI_ROOT] then
    player.gui.screen[GUI_ROOT].destroy()
  end
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

return {
  find_child_by_name = find_child_by_name,
  is_valid_selection = is_valid_selection,
  update_quality_warning = update_quality_warning,
  render_building_buttons = render_building_buttons,
  render_input_chest_buttons = render_input_chest_buttons,
  render_output_chest_buttons = render_output_chest_buttons,
  render_stack_limit_ui = render_stack_limit_ui,
  render_recipe_buttons = render_recipe_buttons,
  destroy_gui = destroy_gui,
  build_gui = build_gui,
  refresh_building_dropdown = refresh_building_dropdown,
  refresh_recipe_buttons = refresh_recipe_buttons,
  handle_create_click = handle_create_click,
}

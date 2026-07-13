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
local GUI_MODULE_FLOW = constants.GUI_MODULE_FLOW
local GUI_MODULE_PREFIX = constants.GUI_MODULE_PREFIX
local GUI_ICON_COLUMNS = constants.GUI_ICON_COLUMNS
local GUI_MAX_INLINE_ROWS = constants.GUI_MAX_INLINE_ROWS
local GUI_OVERFLOW_SCROLL_HEIGHT = constants.GUI_OVERFLOW_SCROLL_HEIGHT
local INPUT_CHEST_CANDIDATES = constants.INPUT_CHEST_CANDIDATES
local OUTPUT_CHEST_CANDIDATES = constants.OUTPUT_CHEST_CANDIDATES
local INSERTER_CANDIDATES = constants.INSERTER_CANDIDATES

local build_option_list = prototypes.build_option_list
local get_localised_entity_name = prototypes.get_localised_entity_name
local resolve_entity_prototype = prototypes.resolve_entity_prototype
local get_entity_tile_size = prototypes.get_entity_tile_size

local has_solid_inputs = recipes.has_solid_inputs
local has_solid_outputs = recipes.has_solid_outputs
local get_module_slot_count = recipes.get_module_slot_count
local get_allowed_modules = recipes.get_allowed_modules
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

-- Adds one icon row to `parent`: a heading label plus a wrapping `table`
-- (column_count = GUI_ICON_COLUMNS) named `table_name`, so its sprite-buttons
-- wrap into multiple rows instead of a single horizontal line (workitem-10 fix
-- for horizontal overflow). The table is nested inside a `scroll-pane` whose
-- `maximal_height` caps the visible height at ~GUI_MAX_INLINE_ROWS rows: short
-- lists render at their natural size, and only a very long list (past the inline
-- limit) triggers a vertical scrollbar so the row cannot grow the window
-- unbounded. The returned table is looked up later by `find_child_by_name`
-- (recursive) exactly as before — only its `type` changed from "flow" to
-- "table", so `.clear()`/`.add()` in the render_* helpers behave identically.
local function add_icon_row(parent, label_caption, table_name)
  local row = parent.add({ type = "flow", direction = "horizontal" })
  row.style.vertical_align = "center"
  row.add({ type = "label", caption = label_caption, style = "heading_2_label" })

  local scroll = row.add({
    type = "scroll-pane",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto",
  })
  scroll.style.maximal_height = GUI_OVERFLOW_SCROLL_HEIGHT

  local icons = scroll.add({
    type = "table",
    name = table_name,
    column_count = GUI_ICON_COLUMNS,
  })
  icons.style.horizontal_spacing = 4
  icons.style.vertical_spacing = 4
  return icons
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

-- Rebuilds the module icon row (workitem-14). Resolves the selected building's
-- module slot count and the list of modules allowed for the current
-- building+recipe combo, then renders one `choose-elem-button` (elem_type =
-- "item") per slot, seeded from options.module_selections and constrained via
-- `elem_filters` to the allowed module names. Shows a "No module slots" label
-- when the building has none. Also prunes now-invalid saved selections.
local function render_module_buttons(frame, options, force)
  local module_icons = frame and find_child_by_name(frame, GUI_MODULE_FLOW)
  if not module_icons then
    return
  end

  module_icons.clear()

  local building_prototype = resolve_entity_prototype(options.building_selection)
  local slot_count = get_module_slot_count(building_prototype)

  if slot_count <= 0 then
    module_icons.add({ type = "label", caption = "No module slots" })
    -- Clear any stale selections so they aren't carried into the blueprint.
    options.module_selections = {}
    return
  end

  local recipe_name = options.recipes.names[options.recipe_selection_index]
  local recipe = recipe_name and force.recipes[recipe_name]

  local allowed = get_allowed_modules(force, building_prototype, recipe)
  -- Build elem_filters restricting the picker to the allowed module names.
  local elem_filters = {}
  local allowed_set = {}
  for _, name in ipairs(allowed) do
    table.insert(elem_filters, { filter = "name", name = name })
    allowed_set[name] = true
  end

  options.module_selections = options.module_selections or {}
  for slot = 1, slot_count do
    local saved = options.module_selections[slot]
    -- Normalize the saved value's module NAME (backward compat: it may be a legacy
    -- bare string OR the new { name, quality } table from workitem-15).
    local saved_name
    if type(saved) == "table" then
      saved_name = saved.name
    elseif type(saved) == "string" then
      saved_name = saved
    end
    -- Drop a saved selection whose module is no longer allowed for this combo.
    -- allowed_set is keyed by module NAME (quality does not affect allow-ness).
    if saved and (not saved_name or not allowed_set[saved_name]) then
      saved = nil
      options.module_selections[slot] = nil
    end

    local button = module_icons.add({
      type = "choose-elem-button",
      name = GUI_MODULE_PREFIX .. slot,
      -- Quality-aware picker (workitem-15): elem_value is a PrototypeWithQuality
      -- table { name, quality }. The name allow-list below still applies (quality
      -- is orthogonal to the item filter).
      elem_type = "item-with-quality",
      elem_filters = elem_filters,
      tooltip = "Choose a module for slot " .. slot .. ".",
    })
    if saved then
      if type(saved) == "table" then
        button.elem_value = { name = saved.name, quality = saved.quality or "normal" }
      else
        -- Legacy bare string: seed name only (quality defaults to normal in-game).
        button.elem_value = { name = saved }
      end
    end
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
    module_selections = (existing_options and existing_options.module_selections) or {},
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
  scroll_pane.style.maximal_height = 500

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

  -- workitem-16 (BUG 2): a previously-chosen item can vanish when the mod that
  -- added it is disabled. Assigning a stale signal directly to elem_value makes
  -- Factorio throw a non-recoverable "Unknown item name" error on GUI open. Drop
  -- the stale selection silently (no chat message) so the picker opens empty, and
  -- wrap the assignment in pcall as defense-in-depth against any future gap.
  if options.item_selection and not prototypes.is_valid_signal(options.item_selection) then
    options.item_selection = nil
  end
  if options.item_selection then
    pcall(function()
      item_picker.elem_value = options.item_selection
    end)
  end

  options.is_initializing = false

  -- Each icon row is a wrapping `table` inside a bounded scroll-pane so many
  -- candidates wrap into rows and, past ~GUI_MAX_INLINE_ROWS rows, scroll in
  -- place rather than overflowing the window (workitem-10).
  add_icon_row(content, "Building: ", GUI_BUILDING_FLOW)
  add_icon_row(content, "Recipe: ", GUI_RECIPE_FLOW)
  add_icon_row(content, "Input chest: ", GUI_INPUT_FLOW)
  add_icon_row(content, "Output chest: ", GUI_OUTPUT_FLOW)

  local stack_limit_flow = content.add({
    type = "flow",
    name = GUI_STACK_LIMIT_FLOW,
    direction = "horizontal"
  })
  stack_limit_flow.style.vertical_align = "center"

  local inserter_icons = add_icon_row(content, "Inserter: ", GUI_INSERTER_FLOW)

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

  -- Module row (workitem-14): one choose-elem-button per module slot of the
  -- selected building, rendered by render_module_buttons after the frame exists.
  add_icon_row(content, "Modules: ", GUI_MODULE_FLOW)

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

  render_module_buttons(frame, options, player.force)
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
  render_module_buttons(frame, options, player.force)
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

  -- Module support (workitem-14/16): gather the per-slot module selections, capped
  -- at the building's real slot count and filtered to those still allowed for the
  -- final recipe (so a stale selection from a different recipe/building is dropped).
  -- Each selection is normalized to a { name, quality } table (workitem-15).
  -- allowed_set is name-keyed (quality is orthogonal to allow-ness).
  --
  -- workitem-16 (BUG 1): build a DENSE list (no index gaps) carrying each entry's
  -- REAL physical slot in `.slot`. Previously this was indexed by slot number, so
  -- an empty earlier slot left a nil hole and build_blueprint_entities' ipairs()
  -- stopped at the first nil, silently dropping every later module. A dense list
  -- is ipairs-safe regardless of which slots are filled.
  local module_selections = {}
  local slot_count = get_module_slot_count(building_prototype)
  if slot_count > 0 and options.module_selections then
    local allowed_set = {}
    for _, name in ipairs(get_allowed_modules(player.force, building_prototype, recipe)) do
      allowed_set[name] = true
    end
    for slot = 1, slot_count do
      local saved = options.module_selections[slot]
      -- Backward compat: tolerate a legacy bare string OR the new table.
      local sel
      if type(saved) == "table" and saved.name then
        sel = { name = saved.name, quality = saved.quality or "normal" }
      elseif type(saved) == "string" then
        sel = { name = saved, quality = "normal" }
      end
      if sel and allowed_set[sel.name] then
        -- Append densely; carry the real slot index so the blueprint can place
        -- the module into its correct physical inventory stack.
        module_selections[#module_selections + 1] = {
          slot = slot,
          name = sel.name,
          quality = sel.quality,
        }
      end
    end
  end

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
    options.stack_limit,
    module_selections
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
  render_module_buttons = render_module_buttons,
  destroy_gui = destroy_gui,
  build_gui = build_gui,
  refresh_building_dropdown = refresh_building_dropdown,
  refresh_recipe_buttons = refresh_recipe_buttons,
  handle_create_click = handle_create_click,
}

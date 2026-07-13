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
--   inputs/outputs. The player can also pick modules per module slot of the
--   crafting building (workitem-14); the built building requests those modules
--   from the logistics network.
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
-- MODULE LAYOUT
--   The implementation is split into scripts/ modules; control.lua is the
--   Factorio runtime entry point that requires them and registers all
--   script.on_* event handlers and the remote interface. See
--   docs/workitems/12-split-control-into-modules.md.
--
-- NOTE: `building_candidates_cache` is a derived, module-local memo (NOT part of
-- the save file); it is invalidated on init / configuration / research events
-- via prototypes.invalidate_candidate_cache().
-- =============================================================================

local constants = require("scripts.constants")
local prototypes = require("scripts.prototypes")
local recipes = require("scripts.recipes")
local storage_mod = require("scripts.storage")
local blueprint = require("scripts.blueprint")
local gui = require("scripts.gui")

-- Optional test module; exposed later via the "quick_mall" remote interface.
local tests = require("tests")

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
  prototypes.invalidate_candidate_cache()
  recipes.invalidate_module_cache()
  storage_mod.ensure_global()
end)

script.on_configuration_changed(function(event)
  -- Mod/version changes can add, remove, or alter entity prototypes, so the
  -- memoized candidate-building set (and module-item set) must be rebuilt on next
  -- use.
  prototypes.invalidate_candidate_cache()
  recipes.invalidate_module_cache()
  storage_mod.ensure_global()
end)

script.on_event(defines.events.on_research_finished, function(event)
  -- Research does NOT change the candidate BUILDING set (placeable/categories/
  -- hidden are prototype properties), only recipe availability, which is handled
  -- by the per-item recipe filter. Reset defensively to stay robust to any
  -- prototype-affecting mod interactions.
  prototypes.invalidate_candidate_cache()
end)

-- Custom input "quick-mall-open" (keybind): open the GUI for the player.
script.on_event("quick-mall-open", function(event)
  local player = game.get_player(event.player_index)
  if player then
    gui.build_gui(player)
  end
end)

-- Toolbar shortcut: open the GUI when the "quick-mall-open" shortcut is clicked.
script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= "quick-mall-open" then
    return
  end

  local player = game.get_player(event.player_index)
  if player then
    gui.build_gui(player)
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
    if event.element.name == constants.GUI_CREATE then
      gui.handle_create_click(player)
    elseif event.element.name == constants.GUI_CLOSE then
      gui.destroy_gui(player)
    elseif event.element.name:find(constants.GUI_BUILDING_PREFIX, 1, true) == 1 then
      local storage = storage_mod.get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local building_name = event.element.name:sub(#constants.GUI_BUILDING_PREFIX + 1)
      options.building_selection = building_name

      local frame = player.gui.screen[constants.GUI_ROOT]
      local building_icons = frame and gui.find_child_by_name(frame, constants.GUI_BUILDING_FLOW)
      if building_icons then
        for _, child in pairs(building_icons.children) do
          if child and child.valid and child.name:find(constants.GUI_BUILDING_PREFIX, 1, true) == 1 then
            child.toggled = (child.name == event.element.name)
          end
        end
      end

      local item_elem = gui.find_child_by_name(frame, constants.GUI_ITEM)
      local item_name = item_elem and item_elem.elem_value
      gui.refresh_recipe_buttons(player, item_name)
    elseif event.element.name:find(constants.GUI_RECIPE_PREFIX, 1, true) == 1 then
      local storage = storage_mod.get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local index = tonumber(event.element.name:sub(#constants.GUI_RECIPE_PREFIX + 1))
      options.recipe_selection_index = index

      local frame = player.gui.screen[constants.GUI_ROOT]
      gui.update_quality_warning(player, frame, options)
      gui.render_recipe_buttons(frame, options)
      gui.render_input_chest_buttons(frame, options, player.force)
      gui.render_output_chest_buttons(frame, options, player.force)
      gui.render_stack_limit_ui(frame, options, player.force)
    elseif event.element.name:find(constants.GUI_INPUT_PREFIX, 1, true) == 1 then
      local storage = storage_mod.get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local chest_name = event.element.name:sub(#constants.GUI_INPUT_PREFIX + 1)
      options.input_chest_selection = chest_name

      local frame = player.gui.screen[constants.GUI_ROOT]
      gui.render_input_chest_buttons(frame, options, player.force)
    elseif event.element.name:find(constants.GUI_OUTPUT_PREFIX, 1, true) == 1 then
      local storage = storage_mod.get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local chest_name = event.element.name:sub(#constants.GUI_OUTPUT_PREFIX + 1)
      options.output_chest_selection = chest_name

      local frame = player.gui.screen[constants.GUI_ROOT]
      gui.render_output_chest_buttons(frame, options, player.force)
    elseif event.element.name:find(constants.GUI_INSERTER_PREFIX, 1, true) == 1 then
      local storage = storage_mod.get_storage_root()
      local options = storage and storage.options[player.index]
      if not options then
        return
      end

      local inserter_name = event.element.name:sub(#constants.GUI_INSERTER_PREFIX + 1)
      options.inserter_selection = inserter_name

      local frame = player.gui.screen[constants.GUI_ROOT]
      local inserter_icons = frame and gui.find_child_by_name(frame, constants.GUI_INSERTER_FLOW)
      if inserter_icons then
        for _, child in pairs(inserter_icons.children) do
          if child and child.valid and child.name:find(constants.GUI_INSERTER_PREFIX, 1, true) == 1 then
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

  if event.element and event.element.valid and event.element.name == constants.GUI_STACK_LIMIT then
    local storage = storage_mod.get_storage_root()
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

  if event.element and event.element.valid and event.element.name == constants.GUI_ITEM then
    local storage = storage_mod.get_storage_root()
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

    gui.refresh_building_dropdown(player, name_to_refresh)
    gui.refresh_recipe_buttons(player, name_to_refresh)
  elseif event.element and event.element.valid
    and event.element.name:find(constants.GUI_MODULE_PREFIX, 1, true) == 1 then
    -- Module choose-elem-button changed (workitem-14): record the per-slot module
    -- name (nil when cleared) in options.module_selections. No re-render is needed
    -- (the button already shows the new icon); it is read at build time.
    local storage = storage_mod.get_storage_root()
    local options = storage and storage.options[player.index]
    if not options then
      return
    end

    local slot = tonumber(event.element.name:sub(#constants.GUI_MODULE_PREFIX + 1))
    if slot then
      options.module_selections = options.module_selections or {}
      local value = event.element.elem_value
      -- choose-elem-button elem_value for elem_type "item" is the item name
      -- string (or a table with .name for quality-aware pickers); normalize.
      if type(value) == "table" then
        value = value.name
      end
      options.module_selections[slot] = value
    end
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
  if event.element and event.element.valid and event.element.name == constants.GUI_ROOT then
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
  blueprint.check_and_clear_incompatible_cursor_recipe(player)

  -- 2. Refresh GUI if open
  local frame = player.gui.screen[constants.GUI_ROOT]
  if not frame then
    return
  end

  local storage = storage_mod.get_storage_root()
  local options = storage and storage.options[player.index]
  if options then
    local item_selection = options.item_selection
    local name_to_refresh = item_selection
    if type(item_selection) == "table" then
      name_to_refresh = item_selection.name
    end
    gui.refresh_building_dropdown(player, name_to_refresh)
    gui.refresh_recipe_buttons(player, name_to_refresh)
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

-- === Automated in-game tests (FactorioTest) ===
--
-- When the optional `factorio-test` mod is active (dev / CI only — see the
-- "? factorio-test" dependency in info.json), register the FactorioTest runner
-- and load our spec files. This is inert in normal play: the block is skipped
-- unless the player/CI has installed factorio-test. The CLI
-- (`scripts/run_tests.sh`) launches Factorio headless with factorio-test enabled,
-- which auto-runs these specs and reports pass/fail. The specs exercise the REAL
-- scripts/* modules (unlike the legacy `tests` remote above, which runs a
-- mock-only harness). See docs/workitems/13-automated-test-schedule.md.
if script.active_mods["factorio-test"] then
  -- load_luassert = true swaps the global `assert` for luassert, giving the spec
  -- rich matchers (assert.is_true / assert.equals / assert.is_nil / ...).
  require("__factorio-test__/init")({ "tests.qm-blueprint-tests" }, { load_luassert = true })
end

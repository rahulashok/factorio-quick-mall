# Workitem 12 — Split control.lua into scripts/ modules

**Status:** Done
**Type:** Optimization / maintainability (Medium)
**Files changed:** control.lua (rewritten as entry point), scripts/constants.lua, scripts/prototypes.lua, scripts/storage.lua, scripts/recipes.lua, scripts/blueprint.lua, scripts/gui.lua (all new)

## Motivation
`control.lua` had grown to ~1959 lines holding every constant, prototype helper,
recipe filter, blueprint builder, GUI routine, and all event handlers as
file-local values calling each other via lexical scope. That made the file hard
to navigate and impossible to work on in isolation. Splitting it into focused
`require`d modules under `scripts/` gives clear separation of concerns and lets
future (sub)agents work on one small file (e.g. `gui.lua` or `recipes.lua`)
without loading the whole runtime. `control.lua` stays the thin entry point that
wires modules together and owns all `script.on_*` registrations + the remote
interface.

## New module layout

| Module | Responsibilities | Depends on |
| --- | --- | --- |
| `scripts/constants.lua` | GUI_* name/prefix strings; STATIC_BUILDING / INPUT_CHEST / OUTPUT_CHEST / INSERTER candidate tables | (none) |
| `scripts/prototypes.lua` | 1.1/2.0 prototype resolution; option-list builder; candidate-building scan + memo cache; `invalidate_candidate_cache()` | constants (not required — no candidate-table refs needed here) |
| `scripts/storage.lua` | `get_storage_root` / `ensure_global` (2.0 `storage` vs 1.1 `global`) | (none) |
| `scripts/recipes.lua` | recipe filtering, surface compatibility, building/recipe option builders, solid input/output checks | constants, prototypes |
| `scripts/blueprint.lua` | item requests, placement checks, blueprint entity construction, cursor handling, incompatible-recipe clearing, researched-item filters | prototypes, recipes |
| `scripts/gui.lua` | all GUI render/refresh/build helpers + `handle_create_click` | constants, prototypes, recipes, blueprint, storage |
| `control.lua` | entry point: requires modules; keeps `apply_ghost_tags`, `handle_built_entity`; registers all `script.on_*` handlers and `remote.add_interface` | all of the above + tests |

Dependency graph is acyclic: `constants <- prototypes <- recipes <- blueprint <- gui`; `storage` standalone; `control` at the top.

## What moved where

- **constants.lua:** `GUI_ROOT`…`GUI_CLOSE`; `STATIC_BUILDING_CANDIDATES`,
  `INPUT_CHEST_CANDIDATES`, `OUTPUT_CHEST_CANDIDATES`, `INSERTER_CANDIDATES`.
- **prototypes.lua:** `building_candidates_cache` (module-local), `get_entity_prototypes`,
  `resolve_entity_prototype`, `get_item_prototypes`, `resolve_item_prototype`,
  `can_resolve_prototypes`, `resolve_candidate_name`, `build_option_list`,
  `get_localised_entity_name`, `get_candidate_buildings`, `get_entity_tile_size`,
  and new `invalidate_candidate_cache()`.
- **storage.lua:** `get_storage_root`, `ensure_global`.
- **recipes.lua:** `has_solid_inputs`, `has_solid_outputs`,
  `is_recipe_compatible_with_surface`, `get_recipes_for_item`,
  `find_recipe_for_item`, `build_building_options`, `recipe_outputs_item`,
  `recipe_usable_in_building`, `build_recipe_options`.
- **blueprint.lua:** `get_item_requests`, `can_place_all`,
  `build_blueprint_entities`, `validate_entity_names`, `give_blueprint_cursor`,
  `check_and_clear_incompatible_cursor_recipe`, `get_researched_item_filters`.
- **gui.lua:** `find_child_by_name`, `is_valid_selection`,
  `update_quality_warning`, `render_building_buttons`,
  `render_input_chest_buttons`, `render_output_chest_buttons`,
  `render_stack_limit_ui`, `render_recipe_buttons`, `destroy_gui`, `build_gui`,
  `refresh_building_dropdown`, `refresh_recipe_buttons`, `handle_create_click`.
- **control.lua (kept):** `apply_ghost_tags`, `handle_built_entity`, and all
  event-handler / remote-interface registrations. The three inline
  `building_candidates_cache = nil` resets became
  `prototypes.invalidate_candidate_cache()`.

## Behavior preservation
This is a mechanical move: function bodies, user-facing strings,
`player.print(...)` messages, GUI element names, blueprint-entity shapes, and
event logic are byte-for-byte identical. Cross-module calls are wired through
each module's returned table; within a module, functions still call each other
via `local` aliases so the bodies were not edited. `luac -p` passes on all seven
files. Every `script.on_*` handler and `remote.add_interface("quick_mall", …)`
is registered exactly once, in `control.lua`.

## NEEDS IN-GAME VERIFICATION
This refactor changes module loading. `luac -p` validates syntax but NOT
`require` resolution or runtime cross-module calls. Must be loaded in Factorio to
confirm no load errors and the GUI / build flow works.

## How to undo just this workitem
Committed as a single commit tagged `workitem-12`.
```bash
git revert $(git log --grep="workitem-12" -1 --format=%H)
```

# Workitem 14 — Add support for modules

**Status:** 🔵 Needs In-Game Verification
**Type:** New feature (Medium)
**Files changed:** `scripts/constants.lua`, `scripts/recipes.lua`, `scripts/blueprint.lua`, `scripts/gui.lua`, `control.lua`

## Requirements
Enable users to select which modules need to be in the entity. This should take into account the recipe, the entity, the number of module slots for that entity, what modules are allowed for that recipe, entity combo.
Once the entity has been built it should request those module from the logistics network.

## What was wrong / needed

Quick Mall built a crafting building with a preset recipe/quality, input/output
chests, and inserters, but had **no way to specify modules**. There was no module
UI, no module-compatibility logic, and the built building did not request any
modules from the logistics network. The feature needed to:

- Know how many module slots the selected building has.
- Offer only modules **allowed** for that building + recipe combination (respecting
  recipe limitations and the building's allowed effects / module categories).
- Let the player pick a module per slot.
- On build, make the placed building **request those modules from logistics** so
  bots deliver them, and pre-fill the ghost's module inventory so it visually shows
  the intended modules.

## What work I did

### 1. Module-compatibility logic — `scripts/recipes.lua`
Added (and exported) four functions plus a module-local memo `module_item_cache`:

- `get_module_slot_count(building_prototype)` → `building_prototype.module_inventory_size or 0`, pcall-guarded.
- `is_module_allowed(module_item_prototype, building_prototype, recipe)` — returns
  true unless a rule rejects it:
  1. **Recipe limitations (strict):** if the module's `.limitations` recipe
     allow-list is non-empty, `recipe.name` must be in it.
  2. **Module category:** if the building exposes `allowed_module_categories`, the
     module's `.category` must be permitted.
  3. **Effects:** if the building exposes `allowed_effects`, at least one of the
     module's `.module_effects` must be permitted.

  All prototype fields are read via `pcall`; the default is permissive-but-safe
  except the non-empty limitations list, which is respected strictly.
- `get_module_item_prototypes()` — discovers (once) and memoizes every module-type
  item prototype (`prototype.type == "module"`, or a present `.category` /
  `.module_effects`).
- `get_allowed_modules(force, building_prototype, recipe)` — returns the sorted
  list of allowed module names (empty when the building has 0 slots).
- `invalidate_module_cache()` — clears the memo; wired from `control.lua`'s
  init/configuration handlers next to `prototypes.invalidate_candidate_cache()`.

### 2. GUI — `scripts/gui.lua` + `scripts/constants.lua`
- New constants `GUI_MODULE_FLOW = "quick-mall-module-flow"` and
  `GUI_MODULE_PREFIX = "quick-mall-module-"` (exported).
- New `render_module_buttons(frame, options, force)` that resolves the building's
  slot count and the allowed-module list, then renders **one `choose-elem-button`
  (`elem_type = "item"`) per slot**, constrained by `elem_filters` built from the
  allowed names (`{ filter = "name", name = <allowed> }`), seeded from
  `options.module_selections`. Shows a **"No module slots"** label (mirroring the
  "No solid input items" pattern) when the building has none, and prunes
  now-invalid saved selections.
- A "Modules: " row is added in `build_gui` via the existing workitem-10
  `add_icon_row` helper (so the pickers wrap into a grid + bounded scroll-pane),
  and rendered at the end of `build_gui` and again inside `refresh_recipe_buttons`
  so it updates whenever building/recipe change.
- `options.module_selections` (slot → module name) is seeded from saved state.

Before (`build_gui`, end):
```lua
  inserter_icons = find_child_by_name(frame, GUI_INSERTER_FLOW)
  ...
end
```
After:
```lua
  inserter_icons = find_child_by_name(frame, GUI_INSERTER_FLOW)
  ...
  render_module_buttons(frame, options, player.force)
end
```

### 3. Wiring selection changes — `control.lua`
`on_gui_elem_changed` gained an `elseif` for `GUI_MODULE_PREFIX` buttons that
records the per-slot module name (nil when cleared) in `options.module_selections`.
The existing `GUI_ITEM` handling is untouched. `scripts.recipes` is now required so
`recipes.invalidate_module_cache()` runs in `on_init` / `on_configuration_changed`.

### 4. Blueprint — `scripts/blueprint.lua`
`build_blueprint_entities` gained a nil-safe `module_selections` (slot-indexed
array) parameter. When any module is selected, the **crafting building** entity
gets:

- **(a) a logistic request** (the primary requirement) via the same
  `request_filters = { sections = { { index = 1, filters = {...} } } }` shape used
  by the input chest — one filter per distinct module with `count` = number of
  slots using it, `quality = "normal"`, `comparator = "="` — so bots deliver the
  modules from the network.
- **(b) a pre-filled module inventory** via the blueprint entity `items` field
  (`{ id = { name, quality = "normal" }, items = { in_inventory = { { inventory =
  defines.inventory.assembling_machine_modules, stack = <0-based>, count = 1 } } } }`).
  This whole block is wrapped in `pcall` and guarded on the existence of
  `defines.inventory.assembling_machine_modules`, so a wrong/absent inventory
  constant can never abort blueprint creation — delivery still works via (a).
- An informational `tags.quick_mall_modules` string (comma-joined names).

`handle_create_click` in `scripts/gui.lua` gathers `options.module_selections`,
caps it to the building's real slot count, drops any selection no longer allowed
for the final recipe, and passes the array to `build_blueprint_entities`.

## How it was solved + alternatives considered

- **Per-slot `choose-elem-button`** was chosen over a single multi-select control
  because it maps 1:1 to slots and lets us seed/read each slot independently, and
  because `elem_filters` on an item picker supports a `name` allow-list (unlike
  `RecipePrototypeFilter`, which is why workitem-10 used sprite-buttons for
  recipes).
- **Logistic request on the building** is the mechanism that satisfies "request
  those modules from the logistics network." The `items` module-inventory plan is
  complementary (ghost visualization) and deliberately defensive.
- **Permissive-but-safe compatibility**, strict only on the recipe `limitations`
  list, avoids over-filtering in modded games where a building may not expose
  `allowed_effects` / `allowed_module_categories`.

## Uncertain / must be verified in-game (cannot run Factorio here)

`luac -p` passed on all five files but only catches syntax errors. In-game checks:

1. Module row appears with the **correct number of slots** for the selected
   building (e.g. assembling-machine-2/3, EM plant, beacon), and shows
   **"No module slots"** for buildings with none.
2. The pickers only offer **allowed** modules for the current building+recipe
   (e.g. productivity modules restricted by `limitations`; effect restrictions).
3. Building the blueprint places the building **with the chosen modules**, and
   **bots deliver** the modules (the building's logistic request is populated).
4. The `items`/module-inventory pre-fill shows the modules in the ghost (or, if the
   2.0 `items` shape differs, that the defensive `pcall` simply skips it without
   breaking the blueprint — delivery via the request must still work).
5. `request_filters` on a **crafting-machine** blueprint entity is accepted by the
   game (this shape is confirmed for chests; assembling-machine logistic requests
   need confirmation).
6. Buildings with 0 slots, and recipe/building combos with **no allowed modules**,
   behave gracefully (empty picker, no error).
7. `defines.inventory.assembling_machine_modules` is the correct constant on the
   target version; if not, the guard should skip (b) silently.

## How to undo just this workitem
```bash
git revert $(git log --grep="workitem-14" -1 --format=%H)
```
No manual steps required. The change is additive (new constants, functions, one GUI
row, one blueprint parameter); reverting removes the module row and the module
request/inventory from new blueprints. Existing blueprints already in save games are
unaffected (the module request lives in the blueprint entity data, not in code).

## Follow-up fix (2026-07-13): recipe-level module restrictions

**What was wrong (found in-game):** The module picker offered modules that the
selected *recipe* forbids — most visibly **productivity modules on end-product
recipes** like `inserter` / `transport-belt`. Factorio 2.0 blocks productivity
modules on non-intermediate recipes, but Quick Mall's UI still listed them, so the
selection was silently invalid at build time.

**Root cause:** `is_module_allowed(module, building, recipe)` in `scripts/recipes.lua`
checked (1) the module's own `.limitations`, (2) the building's
`allowed_module_categories`, and (3) the building's `allowed_effects`, but **never
consulted the recipe's own effect restrictions**. In 2.0 the "productivity only on
intermediates" rule is per-recipe, exposed on the recipe prototype via
`allowed_effects` (dictionary `[effect]→boolean`) and `allowed_module_categories`.
Base productivity modules carry no `.limitations` in 2.0, so check (1) never caught
them.

**What changed:** Added two recipe-level checks to `is_module_allowed` (no signature
change), read from `recipe.prototype.allowed_effects` /
`recipe.prototype.allowed_module_categories` with a fallback to `recipe.allowed_effects`
/ `recipe.allowed_module_categories`, all pcall-guarded and permissive when
absent/empty:
- **(4) recipe `allowed_effects`:** when present and non-empty, *every* effect the
  module produces must be permitted (`== true`). A module that introduces any
  disallowed effect is rejected. This is stricter than the building rule (3)
  ("at least one allowed") on purpose — a productivity module on a recipe whose
  `allowed_effects.productivity ~= true` is now rejected, while a speed/efficiency
  module on that same recipe stays allowed if those effects are permitted.
- **(5) recipe `allowed_module_categories`:** when present and non-empty, the module's
  `.category` must be permitted — same shape as the existing building-category check.

Both GUI call sites (`scripts/gui.lua:341` picker, `scripts/gui.lua:771` create-time
validation) already pass the `LuaRecipe`, so both benefit with no call-site change.

**New test:** Added a `"module restrictions (real source)"` group to
`tests/qm-blueprint-tests.lua`. It discovers, at runtime from the live prototypes, a
real productivity module, an assembler with module slots, an end-product recipe that
forbids productivity, and an intermediate recipe that permits it (verifying which is
which via the recipe prototype's `allowed_effects` rather than assuming), then asserts
`is_module_allowed(...) == false` for the forbidding recipe and `== true` for the
permitting one. Each discovery step skips gracefully (logs + passes) if a prototype is
absent, so a modded base without productivity modules will not fail the suite.

**Still needs in-game re-verification:** `luac -p` passed, but the suite could not be
run in this environment (the downloaded `factorio-test` mod requires Factorio 2.1 while
the installed binary is 2.0.77, so Factorio aborts at save creation before any test
runs — this blocks all specs, not just the new one). In-game, confirm the picker no
longer offers productivity modules for `inserter`/`transport-belt` recipes but still
offers them for `electronic-circuit`/`iron-gear-wheel`, and that speed/efficiency
modules remain available where permitted.

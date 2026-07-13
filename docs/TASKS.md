# Quick Mall — Task Tracker

Tracks bugs, optimizations, and cleanups found during code review.
Update the **Status** column as work progresses.

**Status legend:** 🔴 Todo · 🟡 In Progress · 🟢 Done · ⚪ Won't Do · 🔵 Needs In-Game Verification

_Last updated: 2026-07-13_

## Summary

| #   | Item                                                                                                                                                                                                                         | Type                 | Severity | Status                        |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------- | -------- | ----------------------------- |
| 1   | `is_fluid` undefined in `handle_create_click`                                                                                                                                                                                | Bug                  | High     | 🟢 Done                       |
| 2   | Inserter directions appear swapped                                                                                                                                                                                           | Not a bug            | —        | ⚪ Won't Do (verified correct) |
| 3   | Duplicate function definitions shadow correct version                                                                                                                                                                        | Bug                  | Medium   | 🟢 Done                       |
| 4   | Dead `quick_mall_requests` tag-application path                                                                                                                                                                              | Bug (dead code)      | Low      | 🟢 Done                       |
| 5   | `build_building_options` re-scans all prototypes per item change                                                                                                                                                             | Optimization         | Medium   | 🟢 Done                       |
| 6   | Redundant recipe scans in `build_gui`                                                                                                                                                                                        | Optimization         | Low      | 🟢 Done                       |
| 7   | Stack-limit field silently ignores empty/`0` input                                                                                                                                                                           | UX                   | Low      | 🟢 Done                       |
| 8   | `inserter_icons` local shadowing                                                                                                                                                                                             | Minor                | Low      | 🟢 Done                       |
| 9   | `local prototypes` shadows Factorio global                                                                                                                                                                                   | Minor                | Low      | 🟢 Done                       |
| 10  | Fix entity overflow error reported here: https://mods.factorio.com/mod/quick-mall/discussion/6a3c1ca62e6b3d3dc9466764 <br>Reopened: horizontal overflow. Fixed by wrapping icon rows into a grid + bounded per-row scroll-pane. | UX                   | Low      | 🟢 Done                       |
| 11  | Document the code                                                                                                                                                                                                            | Optimization         | Low      | 🟢 Done                       |
| 12  | Break the control.lua file into smaller separate files. This enables future subagents to work indeprendently. Separation of concerns, etc                                                                                    | Optimization         | Medium   | 🟢 Done                       |
| 13  | Run automated tests (including unit tests, integration tests, system tests, simulation tests, etc) every 6 hours and report on the results as a part of this doc. Include test coverage rate (lines, methods, files covered) | Platform Improvement | Medium   | 🟢 Done                       |
| 14  | Add support for modules.                                                                                                                                                                                                     | New Feature          | Medium   | 🟢 Done                       |
| 15  | Module picker: allow selecting module quality (higher-quality modules)                                                                                                                                                       | New Feature          | Medium   | 🟢 Done                       |

---

## Bugs

### 1. `is_fluid` is an undefined variable in `handle_create_click`
- **Status:** 🟢 Done
- **Location:** `control.lua:1386`
- **Problem:** `if is_fluid and quality_name ~= "normal"` references a variable that is never declared in this function — it is always `nil`, so the "fluids can't have quality → reset to normal" guard never runs. The GUI warning path computes `is_fluid` correctly, but the create path does not.
- **Fix:** Derive it locally, e.g. `local is_fluid = (type(item_value) == "table" and item_value.type == "fluid")`.

### 2. Inserter directions appear swapped
- **Status:** ⚪ Won't Do — **verified correct in-game (2026-07-06).** Do not "fix" this.
- **Location:** `control.lua` (input inserter `direction.west`, output inserter `direction.east` in `build_blueprint_entities`)
- **Original concern:** Under the Factorio 1.1 convention (inserter `direction` = the side it *drops* on), with chests placed west of the building the directions looked reversed.
- **Resolution:** In Factorio **2.0** the inserter direction convention is inverted vs 1.1 — a 2.0 inserter's `direction` points toward its **pickup** side, not its drop side. The current values are therefore correct: the input inserter (dir `west`) picks up from the west chest and drops east into the building; the output inserter (dir `east`) picks up from the building and drops west into the chest. Confirmed working in-game by the author. **No change made.**

### 3. Duplicate function definitions shadow the correct version
- **Status:** 🟢 Done
- **Location:** `control.lua:936 & 994` (`get_researched_item_filters`), `control.lua:955 & 1021` (`check_and_clear_incompatible_cursor_recipe`)
- **Problem:** Each function is defined twice; the second silently shadows the first. The surviving `check_and_clear_incompatible_cursor_recipe` no longer strips `request_filters`/`logistic_sections`, so after moving to an incompatible surface the recipe clears but the requester chest keeps requesting ingredients.
- **Fix:** Delete the dead first copies; keep the intended behavior for cursor-clearing (decide whether request filters should also be cleared).

### 4. Dead `quick_mall_requests` tag-application path
- **Status:** 🟢 Done
- **Location:** `control.lua:1473`
- **Problem:** `apply_ghost_tags` handles `tags.quick_mall_requests`, but nothing ever writes that tag — requests live in the chest's `request_filters`. The `set_request_slot` block never executes. The ghost `set_recipe` re-application is also redundant since the blueprint entity already carries `recipe`.
- **Fix:** Remove the dead branch (and redundant re-set) for clarity.

---

## Optimizations

### 5. `build_building_options` re-scans all entity prototypes per item change
- **Status:** 🟢 Done
- **Location:** `control.lua:522`
- **Problem:** Runs on every item change, iterating all entity prototypes and allocating nested `pcall` closures per prototype. Hot path with large modpacks.
- **Fix:** Cache the "placeable + has crafting_categories + not hidden + not recycler" building set once (invalidate on research/config change); re-filter by recipe category per item.

### 6. Redundant recipe scans in `build_gui`
- **Status:** 🟢 Done
- **Location:** `control.lua:1054` (calls `build_building_options` then `build_recipe_options`)
- **Problem:** Both re-iterate `force.recipes` (via `get_recipes_for_item`).
- **Fix:** Compute the valid-recipe list once and thread it through.

### 11. Document the code
- **Status:** 🟢 Done
- **Location:** `control.lua` (comments only)
- **Problem:** The ~1470-line `control.lua` had helpful comments in a few hot
  spots but no file-level overview and no per-function documentation, making the
  architecture hard to grasp quickly.
- **Fix:** Added a file-level header block (mod purpose, GUI → blueprint → ghost-tag
  flow, and the Factorio 1.1/2.0 compatibility strategy for `storage`/`global` and
  `prototypes.*` vs `game.*_prototypes`), a concise doc-comment above every local
  function and event handler, and section banners for navigation. Comments only —
  no executable code changed; verified with `luac -p control.lua` (PARSE_OK). See
  `docs/workitems/11-code-documentation.md`.

### 12. Break `control.lua` into smaller separate files
- **Status:** 🟢 Done — 🔵 **Needs in-game verification** (module loading / `require`
  resolution and runtime cross-module calls cannot be checked by `luac -p`).
- **Location:** `control.lua` (was ~1959 lines) → `control.lua` entry point + new
  `scripts/` modules.
- **Problem:** Everything lived in one file as file-local values calling each other
  via lexical scope, making the file hard to navigate and impossible to work on in
  isolation.
- **Fix:** Extracted the implementation into six `require`d modules, each returning
  a table: `scripts/constants.lua`, `scripts/prototypes.lua`, `scripts/storage.lua`,
  `scripts/recipes.lua`, `scripts/blueprint.lua`, `scripts/gui.lua`. `control.lua`
  remains the runtime entry point: it requires the modules, keeps `apply_ghost_tags`
  and `handle_built_entity`, and registers every `script.on_*` handler and the
  `quick_mall` remote interface exactly once. Purely mechanical move — no logic,
  string, element-name, or blueprint-shape changes. Acyclic dependency graph
  (`constants <- prototypes <- recipes <- blueprint <- gui`; `storage` standalone).
  `luac -p` passes on all seven files. See
  `docs/workitems/12-split-control-into-modules.md`.

---

## UX / Minor

### 7. Stack-limit field silently ignores empty/`0` input
- **Status:** 🟢 Done
- **Location:** `control.lua:1619`
- **Problem:** Clearing the field or typing `0` keeps the old value with no user feedback.

### 8. `inserter_icons` local shadowing
- **Status:** 🟢 Done
- **Location:** `control.lua:1249` shadows `control.lua:1193` in the same function.

### 9. `local prototypes` shadows the Factorio 2.0 global
- **Status:** 🟢 Done
- **Location:** `control.lua:537`
- **Problem:** Safe today but fragile; rename the local.

### 10. GUI window overflow (vertical, then horizontal)
- **Status:** 🟢 Done — verified in-game 2026-07-13 (icon rows wrap into a grid and scroll in place; no horizontal overflow; Build button stays visible).
- **Location:** `scripts/gui.lua` `build_gui` (+ new constants in `scripts/constants.lua`)
- **Problem:** The task title ("entity overflow error") is misleading. The linked mod-portal discussion is a GUI sizing issue: in a heavily-modded game the building/recipe/chest/inserter icon lists make the window grow beyond the screen. The first pass fixed **vertical** growth (outer `scroll-pane`), but the in-game retest revealed **horizontal** overflow: the Recipe/Input/Output/Inserter rows were horizontal `flow`s (which never wrap), so many icons extended past the right window edge.
- **Fix (vertical, prior):** Wrapped the middle selection rows in a `scroll-pane` with `maximal_height = 500` and moved the Build button onto `frame` after the scroll-pane so it stays visible.
- **Runtime fix (2026-07-06):** Initial version used `maximum_height`, an invalid LuaStyle key that crashed on GUI open. Corrected to `maximal_height`.
- **Fix (horizontal, 2026-07-13):** Every icon container (`GUI_BUILDING_FLOW`, `GUI_RECIPE_FLOW`, `GUI_INPUT_FLOW`, `GUI_OUTPUT_FLOW`, `GUI_INSERTER_FLOW`) is now a `table` with `column_count = 10` so icons wrap into a grid, and each table is nested inside a bounded per-row `scroll-pane` (`maximal_height` ≈ 3 rows) so a very long list scrolls in place instead of overflowing. Element names are unchanged (only the type flipped from `flow` to `table`), so all `find_child_by_name` lookups and the `on_gui_click` handlers resolve unchanged — no `control.lua` edits needed. Chose the nested-scroll approach over a native `choose-elem-button` picker because `RecipePrototypeFilter` has no recipe-name allow-list (so a native recipe chooser couldn't be constrained to the valid recipes). See `docs/workitems/10-gui-overflow-scrollpane.md`.

---

## Platform Improvements

### 13. Automated tests every 6 hours + coverage reporting
- **Status:** 🟢 Done — 🔵 **first scheduled fire should be observed once** (the on-demand run passes; the recurring launch depends on the machine being awake with the REPL idle at the fire time).
- **Location:** `info.json`, `control.lua` (FactorioTest init hook), new `tests/qm-blueprint-tests.lua`, `factorio-test.json`, `scripts/run_tests.sh`, `docs/test-results/latest.md`.
- **Problem:** The repo's only tests lived in `tests.lua`, a mock-only harness whose
  cases **re-implement the logic inline** ("we define the logic here as it was
  implemented") and never `require` `control.lua`/`scripts/*.lua`. They therefore
  exercised none of the shipped code, ran only manually in-game via
  `remote.call("quick_mall","run_tests")`, and produced no scheduled run and no
  coverage figures.
- **Fix:** Adopted **FactorioTest** (GlassBricks; the maintained successor to
  Testorio) as an optional dependency (`? factorio-test`). `control.lua` registers
  it — guarded by `script.active_mods["factorio-test"]` so it is inert in normal
  play — and loads a new spec `tests/qm-blueprint-tests.lua` that drives the **real**
  `scripts/recipes.lua` and `scripts/blueprint.lua` inside a live headless Factorio.
  `scripts/run_tests.sh` launches Factorio headless through the `factorio-test-cli`
  (`npx`), writes `docs/test-results/latest.md`, and exits non-zero on failure. A
  **Claude Code scheduled job** (durable, in `.claude/scheduled_tasks.json`, every 6
  hours) runs it — deliberately **not** the system crontab. Current run: **8/8 pass**.
  See `docs/workitems/13-automated-test-schedule.md` and the results section below.

---

## New Features

### 14. Add support for modules
- **Status:** 🟢 Done — verified in-game 2026-07-13 (module picker shows correct slots, allowed-module filtering works incl. recipe restrictions, and modules are requested/delivered).
- **Location:** `scripts/constants.lua`, `scripts/recipes.lua`, `scripts/blueprint.lua`, `scripts/gui.lua`, `control.lua`.
- **Need:** Let the player choose modules for the crafting building, respecting the
  building's module-slot count and which modules are allowed for the building+recipe
  combo, and have the built building **request those modules from the logistics
  network**.
- **Fix:** Added module-compatibility logic to `scripts/recipes.lua`
  (`get_module_slot_count`, `is_module_allowed`, `get_module_item_prototypes`,
  `get_allowed_modules`, `invalidate_module_cache` — strict on a module's recipe
  `limitations`, otherwise permissive-but-safe on `allowed_module_categories` /
  `allowed_effects`, all pcall-guarded, with a cached module-item scan). Added a
  "Modules" row to `scripts/gui.lua` `build_gui` using the workitem-10 `add_icon_row`
  pattern: one `choose-elem-button` (`elem_type = "item"`, `elem_filters` limited to
  the allowed module names) per slot, seeded from `options.module_selections`; shows
  "No module slots" when the building has none; re-rendered on building/recipe change.
  `control.lua`'s `on_gui_elem_changed` records per-slot selections. On build,
  `build_blueprint_entities` puts a **logistic request** for the selected modules on
  the building (same `request_filters` sections shape as the input chest) so bots
  deliver them, plus a defensive (`pcall`-guarded) module-inventory pre-fill via the
  blueprint `items` field. **Needs in-game verification** — see
  `docs/workitems/14-add-support-for-modules.md` for the exact checklist (slot count,
  allowed-module filtering, bot delivery, 2.0 blueprint `request_filters`/`items`
  shapes on a crafting machine, and the `defines.inventory.assembling_machine_modules`
  constant).
- **Follow-up fix (2026-07-13):** `is_module_allowed` did not check the *recipe's* own
  effect restrictions, so the picker offered productivity modules for end-product
  recipes (e.g. `inserter`/`transport-belt`) that Factorio forbids. Added two
  recipe-level checks (recipe `allowed_effects` — a module may not introduce any
  disallowed effect; recipe `allowed_module_categories`) read from
  `recipe.prototype.*` (pcall-guarded, permissive when absent). Added a
  "module restrictions (real source)" test in `tests/qm-blueprint-tests.lua`. `luac -p`
  passes; still needs in-game re-verification. See
  `docs/workitems/14-add-support-for-modules.md`.

### 15. Module picker: allow selecting module quality
- **Status:** 🟢 Done — verified in-game 2026-07-13 (per-slot quality selection flows into the module request and inventory).
- **Location:** `scripts/gui.lua` (`render_module_buttons`, `handle_create_click`),
  `control.lua` (`on_gui_elem_changed` module branch), `scripts/blueprint.lua`
  (`build_blueprint_entities`), `tests/qm-blueprint-tests.lua`.
- **Need:** Workitem 14 added a per-slot module picker but only at **normal** quality.
  Users could not request an uncommon/rare/etc. module. Add per-slot quality selection
  and thread the chosen quality through to the blueprint's logistic request and the
  module-inventory insert-plan.
- **Fix:** Switched the per-slot `choose-elem-button` from `elem_type = "item"` (bare
  string value) to `elem_type = "item-with-quality"` (value is a `PrototypeWithQuality`
  table `{ name, quality }`), keeping the existing name allow-list `elem_filters`
  unchanged. `on_gui_elem_changed` now stores `{ name, quality }` per slot instead of
  discarding quality. `build_blueprint_entities` collapses selections by a composite
  `name@quality` key so it emits **one logistic request filter per distinct
  (name, quality) pair with the real quality**, and groups the module-inventory
  `InventoryPosition`s by (name, quality) so each slot's `items` insert-plan `id`
  carries its own quality. The `quick_mall_modules` tag now joins `name:quality` per
  slot. All reads of `module_selections[slot]` tolerate BOTH a legacy bare string and
  the new table (backward compat with any persisted state). Added a blueprint test that
  discovers a non-normal quality prototype at runtime (skips gracefully if none) and
  asserts the chosen quality appears in both `request_filters` and the `items` id.
  `luac -p` passes on all edited files. **Needs in-game verification** — see
  `docs/workitems/15-module-quality-selection.md`. The main open question is whether
  the `{ filter = "name", ... }` allow-list is accepted on an `item-with-quality`
  picker at runtime (documented as the item filter, but only confirmable in-game).

---

## Automated Test Results

_Latest run: 2026-07-11 · refreshed every 6 hours by the Claude Code scheduled job
"Quick Mall automated test run" (durable, `.claude/scheduled_tasks.json`), which
executes `scripts/run_tests.sh`. The full/raw report is regenerated at
`docs/test-results/latest.md` each run._

- **Runner:** FactorioTest CLI (`npx factorio-test-cli run`), headless Factorio 2.0.77 (Steam), factorio-test mod 3.0.1.
- **Result:** ✅ **8 passed, 0 failed** (8 total).
- **Spec:** `tests/qm-blueprint-tests.lua` — exercises the real source modules (no mocks).

### Coverage rate

Factorio runs mods in its own VM and there is **no in-VM line-coverage tool**
(luacov cannot instrument the running game), so a line-percentage cannot be
measured honestly. Reported instead is **functional coverage** — which real files
and functions the suite actually drives:

| Metric | Covered | Notes |
| --- | --- | --- |
| **Files** | 2 of 6 `scripts/*` modules (`recipes.lua`, `blueprint.lua`) directly exercised; `constants.lua` + `prototypes.lua` loaded transitively | `gui.lua` / `storage.lua` need a player/GUI harness — future work. |
| **Methods** | 5 real functions asserted: `recipes.has_solid_inputs`, `recipes.has_solid_outputs`, `recipes.get_recipes_for_item`, `blueprint.build_blueprint_entities`, `blueprint.get_item_requests` | Called against real base-game recipes on a live surface. |
| **Lines** | Not measurable in the Factorio VM | Stated honestly rather than fabricated; would require a luacov-capable harness outside the game. |

> Note: the previous `tests.lua` harness reported "3/3 passed" but covered **0** of
> the real source lines/functions (it tested inline copies of the logic). The figures
> above are the first that reflect the shipped code.

---

## Notes — areas of lower confidence

The blueprint geometry and 2.0 blueprint-entity schema need in-game validation:
- Inserter `direction` (pickup vs drop) convention — see #2.
- Whether `recipe_quality` on the assembler blueprint entity (`control.lua:838`) is honored.
- Whether `request_filters = { sections = { { index, filters } } }` (`control.lua:846`) is the exact 2.0 shape for blueprint logistic requests.

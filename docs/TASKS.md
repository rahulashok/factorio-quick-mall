# Quick Mall — Task Tracker

Tracks bugs, optimizations, and cleanups found during code review.
Update the **Status** column as work progresses.

**Status legend:** 🔴 Todo · 🟡 In Progress · 🟢 Done · ⚪ Won't Do · 🔵 Needs In-Game Verification

_Last updated: 2026-07-06_

## Summary

| #   | Item                                                                                                                  | Type            | Severity | Status                        |
| --- | --------------------------------------------------------------------------------------------------------------------- | --------------- | -------- | ----------------------------- |
| 1   | `is_fluid` undefined in `handle_create_click`                                                                         | Bug             | High     | 🟢 Done                       |
| 2   | Inserter directions appear swapped                                                                                    | Bug             | High     | 🔵 Needs In-Game Verification |
| 3   | Duplicate function definitions shadow correct version                                                                 | Bug             | Medium   | 🟢 Done                       |
| 4   | Dead `quick_mall_requests` tag-application path                                                                       | Bug (dead code) | Low      | 🟢 Done                       |
| 5   | `build_building_options` re-scans all prototypes per item change                                                      | Optimization    | Medium   | 🟢 Done                       |
| 6   | Redundant recipe scans in `build_gui`                                                                                 | Optimization    | Low      | 🟢 Done                       |
| 7   | Stack-limit field silently ignores empty/`0` input                                                                    | UX              | Low      | 🟢 Done                       |
| 8   | `inserter_icons` local shadowing                                                                                      | Minor           | Low      | 🟢 Done                       |
| 9   | `local prototypes` shadows Factorio global                                                                            | Minor           | Low      | 🟢 Done                       |
| 10  | Fix entity overflow error reported here: https://mods.factorio.com/mod/quick-mall/discussion/6a3c1ca62e6b3d3dc9466764 | UX              | Low      | 🔴 Todo                       |

---

## Bugs

### 1. `is_fluid` is an undefined variable in `handle_create_click`
- **Status:** 🟢 Done
- **Location:** `control.lua:1386`
- **Problem:** `if is_fluid and quality_name ~= "normal"` references a variable that is never declared in this function — it is always `nil`, so the "fluids can't have quality → reset to normal" guard never runs. The GUI warning path computes `is_fluid` correctly, but the create path does not.
- **Fix:** Derive it locally, e.g. `local is_fluid = (type(item_value) == "table" and item_value.type == "fluid")`.

### 2. Inserter directions appear swapped
- **Status:** 🔵 Needs In-Game Verification
- **Location:** `control.lua:856-877`
- **Problem:** Chests are placed west of the building. An inserter's `direction` is its **drop** direction. Input inserter (should grab from west chest, drop east into building) is set to `west`; output inserter (should grab from building, drop west into chest) is set to `east`. Both look reversed, which would push items the wrong way.
- **Fix:** Likely swap to input=`east`, output=`west` — **confirm in-game before changing.**

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

---

## Notes — areas of lower confidence

The blueprint geometry and 2.0 blueprint-entity schema need in-game validation:
- Inserter `direction` (pickup vs drop) convention — see #2.
- Whether `recipe_quality` on the assembler blueprint entity (`control.lua:838`) is honored.
- Whether `request_filters = { sections = { { index, filters } } }` (`control.lua:846`) is the exact 2.0 shape for blueprint logistic requests.

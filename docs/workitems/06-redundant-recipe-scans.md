# Workitem 6 — Reduce redundant force.recipes scans

**Status:** Done
**Type:** Optimization (Low)
**Files changed:** control.lua

## What was wrong
On a single GUI build/refresh with an item selected, `force.recipes` was walked
multiple times:

1. `build_building_options` calls `get_recipes_for_item(force, name, surface)`,
   which iterates ALL of `force.recipes` to find enabled, surface-compatible
   recipes that output the item.
2. `build_recipe_options` then independently iterated ALL of `force.recipes`
   again (`for recipe_name, recipe in pairs(force.recipes)`) to find recipes
   that output the item, are usable in the chosen building, and are
   surface-compatible.

Both walks recomputed the same "enabled + outputs-item + surface-compatible"
predicate. `build_recipe_options` only added one extra filter
(`recipe_usable_in_building`), so its result set is a strict SUBSET of what
`get_recipes_for_item` already computes.

## What I changed
`build_recipe_options` now reuses `get_recipes_for_item` and applies only the
building-category filter, removing one full `force.recipes` scan.

Before:
```lua
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
```

After:
```lua
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
```

Everything after this loop (`table.sort(names)`, the empty-result early return,
label construction, and the final return shape) is unchanged.

This does not touch Workitem 5's `get_candidate_buildings` cache; it only
changes how `build_recipe_options` sources its candidate recipes.

## Behavior-preservation notes
- **Output-matching equivalence:** `get_recipes_for_item` matches
  `product.name == name_to_check` over `recipe.products` and requires
  `recipe.enabled`. `recipe_outputs_item` matches `product.name == item_name`
  over `recipe.products` and requires `recipe.enabled`. These predicates are
  identical, so the item/enabled filter is preserved.
- **Surface filter:** `get_recipes_for_item` already applies
  `is_recipe_compatible_with_surface(recipe, surface)`, the same check the old
  code applied. Preserved.
- **Building filter:** The only additional condition in the old loop was
  `recipe_usable_in_building(recipe, building_prototype)`, which is still
  applied. Preserved.
- **Recipe names:** The old code inserted the `force.recipes` key
  (`recipe_name`). In Factorio, `recipe.name` equals its key in `force.recipes`,
  so inserting `recipe.name` yields identical strings.
- **Sorting:** `table.sort(names)` (alphabetical) is unchanged, so the final
  ordering is identical regardless of iteration order.
- **Labels:** Label construction is untouched —
  `recipe.localised_name or (recipe.prototype and recipe.prototype.localised_name) or recipe.name`
  keyed off `force.recipes[recipe_name]`.
- **Return shapes:** All `{ names = { nil }, labels = { "No options found for this surface" } }`
  early returns and the `if not (name_to_check and building_name)` guard are
  unchanged.

## How to undo just this workitem
Committed as a single commit tagged `workitem-6`.
```bash
git revert $(git log --grep="workitem-6" -1 --format=%H)
```

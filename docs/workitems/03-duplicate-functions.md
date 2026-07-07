# Workitem 3 — Remove duplicate function definitions

**Status:** Done
**Type:** Bug (Medium)
**Files changed:** control.lua

## What was wrong
`control.lua` contained two pairs of duplicate top-level function definitions. In
Lua the second definition wins (shadows the first), so the earlier copies were dead
code and the later copies were the ones actually used.

1. **`get_researched_item_filters`** was defined twice (~line 936 and ~line 994).
   The two definitions were byte-for-byte identical, so this was harmless but
   redundant dead code.

2. **`check_and_clear_incompatible_cursor_recipe`** was defined twice (~line 955 and
   ~line 1021), and the two versions were **not** identical:
   - The **first** version gated on `entity.tags.quick_mall_recipe` and, when it
     cleared an incompatible recipe, ALSO looped over all entities and stripped
     `request_filters` / `logistic_sections`.
   - The **second** version (the one that actually won due to shadowing) gated on
     `entity.tags.quick_mall_recipe or entity.tags.quick_mall_requests` and did NOT
     strip `request_filters` / `logistic_sections`.

   Because the second (shadowing) version won, the request filters were never
   stripped. That meant after clearing a surface-incompatible recipe, the requester
   chest kept requesting ingredients for a recipe that no longer existed. The
   `quick_mall_requests` tag in the guard is never written anywhere in the codebase
   (only `quick_mall_recipe` is written by `build_blueprint_entities`), so that extra
   guard condition was also dead.

## What I changed
- Removed the **first** copy of `get_researched_item_filters` (the earlier ~936
  block), keeping the identical later definition so the function is defined exactly
  once.
- Removed the **second** copy of `check_and_clear_incompatible_cursor_recipe` (the
  later ~1021 block that lacked the stripping and used the wrong guard), keeping the
  first version, which already has the desired behavior: it gates on
  `entity.tags.quick_mall_recipe` and strips `request_filters` / `logistic_sections`
  when it clears an incompatible recipe.

The surviving merged function:

```lua
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
```

The removed (before) second version, for reference:

```lua
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
```

## How to undo just this workitem
Committed as a single commit tagged `workitem-3`.
```bash
git revert $(git log --grep="workitem-3" -1 --format=%H)
```

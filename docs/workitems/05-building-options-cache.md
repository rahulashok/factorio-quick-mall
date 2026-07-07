# Workitem 5 — Cache candidate buildings in build_building_options

**Status:** Done
**Type:** Optimization (Medium)
**Files changed:** control.lua

## What was wrong

`build_building_options` runs on every item change in the GUI. On each call it
iterated over **all** entity prototypes (`get_entity_prototypes()`) and, per
prototype, allocated nested `pcall` closures to test:

- placeable (`items_to_place_this` non-empty),
- has `crafting_categories`,
- not hidden (`has_flag("hidden")`),
- name does not contain `"recycler"`.

Only after that did it apply the per-item filter (does the building support any
valid recipe category for the selected item). The expensive prototype scan does
**not** depend on the selected item, yet it was repeated for every item change —
a hot path that gets worse with large modpacks.

## What I changed

Added a module-level Lua local (near the other top-of-file locals, not in
`storage`/`global`) to memoize the derived candidate set:

```lua
local building_candidates_cache = nil
```

Added `get_candidate_buildings()` that performs the placeable/categories/hidden/
recycler scan exactly once and caches the result. Each cached entry carries
`name`, `label` (localised_name or name), `order`, and a reference to the
prototype's `crafting_categories` table so the per-item filter can test
categories without re-reading the prototype:

```lua
local function get_candidate_buildings()
  if building_candidates_cache then
    return building_candidates_cache
  end
  local candidates = {}
  local prototypes = get_entity_prototypes()
  if prototypes then
    for name, prototype in pairs(prototypes) do
      -- ... placeable + has_categories + not hidden + not recycler scan ...
      if is_valid then
        table.insert(candidates, {
          name = name,
          label = prototype.localised_name or name,
          order = prototype.order or "z",
          crafting_categories = prototype.crafting_categories or {},
        })
      end
    end
  end
  building_candidates_cache = candidates
  return candidates
end
```

`build_building_options` now iterates the cached candidate list and applies
**only** the per-item recipe-category filter. The `crafting_categories` set is
accessed with the same `categories[recipe.category]` pattern as before, just
against the cached reference:

**Before:**

```lua
local prototypes = get_entity_prototypes()
for name, prototype in pairs(prototypes) do
  -- placeable/categories/hidden/recycler scan (per item!) ...
  local building_categories = prototype.crafting_categories or {}
  for _, recipe in ipairs(valid_recipes) do
    if building_categories[recipe.category] then ... end
  end
end
```

**After:**

```lua
local candidates = get_candidate_buildings()
for _, candidate in ipairs(candidates) do
  local building_can_craft = false
  if not name_to_check then
    building_can_craft = true
  else
    local building_categories = candidate.crafting_categories or {}
    for _, recipe in ipairs(valid_recipes) do
      if building_categories[recipe.category] then
        building_can_craft = true
        break
      end
    end
  end
  if building_can_craft then
    table.insert(entries, { name = candidate.name, label = candidate.label, order = candidate.order })
    found_names[candidate.name] = true
  end
end
```

All existing code paths are preserved: the `name_to_check == nil` case (all
candidates craftable), the `STATIC_BUILDING_CANDIDATES` fallback when no entries
match, the sort by `order`, and both `{ names = { nil }, labels = {...} }`
"No options found" returns.

Cache invalidation: `building_candidates_cache = nil` is set on
`script.on_init` and `script.on_configuration_changed` (the important case —
mod/version changes can add/remove/alter entity prototypes). A defensive reset
was also added on `defines.events.on_research_finished`; note that research does
not change the candidate BUILDING set (placeable/categories/hidden are prototype
properties) — only recipe availability, which is already handled by the per-item
recipe filter. The existing `on_init` behavior (`ensure_global()`) is preserved;
`on_configuration_changed` also calls `ensure_global()`.

## Determinism / safety notes

- The cache is a plain module-level Lua local. It is **never** written to
  `storage`/`global`, so it is not part of the save file and cannot desync a
  multiplayer game or bloat the save.
- It is rebuilt deterministically from the prototype set on first use after each
  invalidation; every peer computes the identical list from the same prototypes,
  so no nondeterminism is introduced.
- It is invalidated on `on_init` and `on_configuration_changed` (mod/version
  changes), and defensively on `on_research_finished`, guaranteeing it never
  serves a stale prototype set.

## How to undo just this workitem

Committed as a single commit tagged `workitem-5`.

```bash
git revert $(git log --grep="workitem-5" -1 --format=%H)
```

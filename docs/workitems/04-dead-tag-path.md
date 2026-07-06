# Workitem 4 — Remove dead quick_mall_requests tag path

**Status:** Done
**Type:** Bug / dead code (Low)
**Files changed:** control.lua

## What was wrong
`apply_ghost_tags` contained a branch guarded by `if tags.quick_mall_requests then ... end`
that attempted to apply ingredient requests to the entity via `entity.set_request_slot`.

However, nothing anywhere in the mod ever writes a `quick_mall_requests` tag.
`build_blueprint_entities` only writes the `quick_mall_recipe` and
`quick_mall_recipe_quality` tags onto the assembler entity, and puts ingredient
requests in the input chest's `request_filters` field — never in any tag.
As a result the `quick_mall_requests` branch was unreachable dead code; the
`set_request_slot` calls inside it never executed.

## What I changed
Removed the entire dead branch from `apply_ghost_tags`:

```lua
if tags.quick_mall_requests then
  local ok, setter = pcall(function()
    return entity.set_request_slot
  end)
  if ok and setter then
    for index, request in ipairs(tags.quick_mall_requests) do
      local success = pcall(function()
        setter(entity, request, index)
      end)
      if not success then
        break
      end
    end
  end
end
```

Kept intact: the `quick_mall_recipe` handling block (which applies the
recipe/quality from tags when a ghost or assembling-machine entity is built)
and the ghost / assembling-machine type handling.

## How to undo just this workitem
Committed as a single commit tagged `workitem-4`.
```bash
git revert $(git log --grep="workitem-4" -1 --format=%H)
```

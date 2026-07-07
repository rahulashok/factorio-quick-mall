# Workitem 7 — Stack-limit field empty/0 handling

**Status:** Done
**Type:** UX (Low)
**Files changed:** control.lua

## What was wrong
The `on_gui_text_changed` handler for the `GUI_STACK_LIMIT` textfield only wrote
`options.stack_limit` when the parsed value was `> 0`. When the user cleared the
field (text parses to `nil`) or typed `0`, the branch was skipped and
`options.stack_limit` silently retained its previous value. The visible field
and the stored state diverged with no feedback — the field showed empty/`0`
while the mod still applied the old limit.

Empty/`0` is actually a meaningful value, not an error: `build_blueprint_entities`
computes `bar_value = (stack_limit and stack_limit > 0) and stack_limit or nil`,
so a `stack_limit` of `0`/`nil` means "no bar / no output limit" on the chest.

## What I changed
`control.lua`, in the `on_gui_text_changed` handler:

Before:
```lua
local val = tonumber(event.element.text)
if val and val > 0 then
  options.stack_limit = val
end
```

After:
```lua
local val = tonumber(event.element.text)
if val == nil then
  -- Empty field means "no limit"; store 0 so state tracks the field.
  options.stack_limit = 0
elseif val >= 0 then
  -- 0 = "no limit" (build_blueprint_entities treats 0 as no bar).
  options.stack_limit = val
end
-- Negative values are ignored (textfield also disallows them).
```

Now an empty field or `0` stores `options.stack_limit = 0`, which round-trips as
"no limit" through `build_blueprint_entities` (`bar_value` becomes `nil`). The
stored state always tracks the visible field. This is consistent with the
textfield config (`numeric = true, allow_decimal = false, allow_negative = false`)
and its initial text `tostring(options.stack_limit or 1)` — `0` is a valid
displayable value. Negative values are still ignored as a defensive guard, since
the textfield itself disallows them.

## How to undo just this workitem
Committed as a single commit tagged `workitem-7`.
```bash
git revert $(git log --grep="workitem-7" -1 --format=%H)
```

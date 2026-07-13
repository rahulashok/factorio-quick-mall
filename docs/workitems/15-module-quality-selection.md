# Workitem 15 — Module picker: per-slot quality selection

**Status:** 🔵 Needs In-Game Verification
**Type:** New feature (Medium)
**Files changed:** `scripts/gui.lua`, `control.lua`, `scripts/blueprint.lua`, `tests/qm-blueprint-tests.lua`

## What was wrong / needed

Workitem 14 added a per-slot module picker, but each slot's `choose-elem-button` used
`elem_type = "item"`, whose `elem_value` is a bare item-name **string** — so there was
no way to request a **higher-quality** module (uncommon/rare/epic/legendary). The
blueprint therefore always requested and inserted modules at `quality = "normal"`.

The feature needed to:
- Let the player pick both the module ITEM and its QUALITY per slot.
- Thread the chosen quality end-to-end: GUI selection → stored options → the built
  building's logistic **request filter** (so bots deliver the right quality) and the
  module-inventory **insert-plan** (so the ghost shows the right quality per slot).
- Preserve backward compatibility with any persisted `module_selections` that still
  hold legacy bare-string values.

## What work I did

The whole data path used to hardcode `quality = "normal"`. Each slot selection is now
represented as a `{ name, quality }` table (quality defaults to `"normal"`), and every
read site tolerates both the new table AND a legacy bare string.

### 1. `render_module_buttons` — `scripts/gui.lua`

Switched the picker to Factorio 2.0's quality-aware chooser and seeded it from the
saved table; the name allow-list `elem_filters` is unchanged (quality is orthogonal to
the item filter).

Before:
```lua
local saved = options.module_selections[slot]
-- Drop a saved selection that is no longer allowed for this combo.
if saved and not allowed_set[saved] then
  saved = nil
  options.module_selections[slot] = nil
end

local button = module_icons.add({
  type = "choose-elem-button",
  name = GUI_MODULE_PREFIX .. slot,
  elem_type = "item",
  elem_filters = elem_filters,
  tooltip = "Choose a module for slot " .. slot .. ".",
})
if saved then
  button.elem_value = saved
end
```
After:
```lua
local saved = options.module_selections[slot]
-- Normalize the saved value's module NAME (legacy string OR new {name,quality}).
local saved_name
if type(saved) == "table" then
  saved_name = saved.name
elseif type(saved) == "string" then
  saved_name = saved
end
-- Drop a saved selection whose module is no longer allowed (allowed_set is name-keyed).
if saved and (not saved_name or not allowed_set[saved_name]) then
  saved = nil
  options.module_selections[slot] = nil
end

local button = module_icons.add({
  type = "choose-elem-button",
  name = GUI_MODULE_PREFIX .. slot,
  elem_type = "item-with-quality",
  elem_filters = elem_filters,
  tooltip = "Choose a module for slot " .. slot .. ".",
})
if saved then
  if type(saved) == "table" then
    button.elem_value = { name = saved.name, quality = saved.quality or "normal" }
  else
    button.elem_value = { name = saved }  -- legacy string; quality defaults in-game
  end
end
```

### 2. `on_gui_elem_changed` module branch — `control.lua`

Stopped discarding the quality; now stores a `{ name, quality }` table.

Before:
```lua
local value = event.element.elem_value
if type(value) == "table" then
  value = value.name
end
options.module_selections[slot] = value
```
After:
```lua
local value = event.element.elem_value
if type(value) == "table" then
  options.module_selections[slot] = { name = value.name, quality = value.quality or "normal" }
elseif type(value) == "string" then
  options.module_selections[slot] = { name = value, quality = "normal" }  -- defensive
else
  options.module_selections[slot] = nil  -- cleared
end
```

### 3. `handle_create_click` — `scripts/gui.lua`

Builds the slot-indexed array as `{ name, quality }` tables, normalizing legacy
strings; the "drop if `.name` not in allowed_set" guard is preserved (allowed_set is
name-keyed).

Before:
```lua
local module_name = options.module_selections[slot]
if module_name and allowed_set[module_name] then
  module_selections[slot] = module_name
end
```
After:
```lua
local saved = options.module_selections[slot]
local sel
if type(saved) == "table" and saved.name then
  sel = { name = saved.name, quality = saved.quality or "normal" }
elseif type(saved) == "string" then
  sel = { name = saved, quality = "normal" }
end
if sel and allowed_set[sel.name] then
  module_selections[slot] = sel
end
```

### 4. `build_blueprint_entities` — `scripts/blueprint.lua`

Now accepts per-slot `{ name, quality }` entries (nil-safe; a bare string is treated as
`{ name = s, quality = "normal" }`). Distinct (name, quality) pairs are collapsed under
a composite `name@quality` key so:
- The building's **logistic request filter** emits one filter per distinct
  (name, quality) pair with the REAL `quality` (was hardcoded `"normal"`), mirroring the
  existing filter shape (`index`, `name`, `count`, `quality`, `comparator = "="`).
- The **`items` insert-plan** groups `InventoryPosition`s by (name, quality) so each
  slot's `id = { name, quality = <that slot's quality> }` (was hardcoded `"normal"`).
  Per-slot `stack = slot_index - 1` is preserved, as are the `pcall` guard and the
  `defines.inventory.assembling_machine_modules` guard.
- The informational `quick_mall_modules` tag now joins `name:quality` per slot.

Collapse (before → after):
```lua
-- before: module_counts[name] = count ; module_slot_names = { name, ... }
-- after:  module_counts["name@quality"] = { name, quality, count }
--         module_slots = { { name, quality }, ... }
```
Request filter now uses `quality = bucket.quality`; the `items` id now uses
`quality = group.quality`.

### 5. Test — `tests/qm-blueprint-tests.lua`

Added `"per-slot module quality flows into request_filters + items id"` to the
`blueprint module (real source)` group. It discovers, at runtime, a real quality
prototype whose name is not `"normal"` (iterating `prototypes.quality` /
`game.quality_prototypes`), a real module item, and a building with module slots (via
the real `recipes.get_module_slot_count`). If any is absent (e.g. quality mod disabled
in this base install), it logs and returns (skips gracefully). It calls
`build_blueprint_entities` with one non-normal-quality module in slot 1 and asserts (a)
`request_filters.sections[1].filters` contains an entry for that module with the chosen
`quality`, and (b) the `items` insert-plan has an entry whose `id.quality` equals the
chosen quality (guarded, since `items` only exists when the module-inventory constant
resolves).

## How it was solved + backward-compat handling

- **`item-with-quality` chooser** is the documented Factorio 2.0 way to pick an item at
  a specific quality; its `elem_value` is a `PrototypeWithQuality` table `{ name,
  quality }`, so quality falls out naturally once we stop flattening the value to its
  name. The name allow-list filter is kept (quality is orthogonal to the item filter).
- **Composite `name@quality` key** keeps the "one filter/insert-entry per distinct
  module" collapse working while distinguishing the same module at different qualities.
- **Backward compatibility:** every place that reads `module_selections[slot]` accepts
  BOTH the new `{ name, quality }` table and a legacy bare string (normalizing the
  latter to `quality = "normal"`). This covers any `options.module_selections` persisted
  in a save from before this change, and a defensive path in the event handler if the
  game ever hands back a bare string.

## Validation (honest)

- `luac -p` on all four edited files (`control.lua`, `scripts/gui.lua`,
  `scripts/blueprint.lua`, `tests/qm-blueprint-tests.lua`) — **all PARSE_OK**. `luac -p`
  catches syntax only, not runtime behavior.
- `./scripts/run_tests.sh` **could not launch** in this worktree: the downloaded
  `factorio-test` mod requires **Factorio 2.1** while the installed binary is
  **2.0.77**, so Factorio aborts at save creation (`Incompatible Factorio version
  (current: 2.0, required: 2.1)`) before any spec runs. This blocks the entire suite,
  not just the new test. **No test pass is claimed here** — the suite must be run from
  the parent checkout / a compatible environment.

## Uncertain / must be verified in-game

1. **`elem_filters` name allow-list on `item-with-quality`:** documented as the item
   filter and expected to still apply, but if the game rejects a `{ filter = "name" }`
   filter on the quality-aware picker at runtime it cannot be detected statically — the
   allow-list was kept per the workitem note; confirm the picker still only offers the
   allowed modules.
2. The building's `request_filters` with a **non-normal `quality`** on a crafting
   machine is accepted and bots deliver that quality.
3. The `items` insert-plan `id = { name, quality }` at a non-normal quality shows the
   right module/quality per slot in the ghost (or the defensive `pcall` skips it
   silently without breaking the blueprint — delivery still works via the request).
4. A save carrying legacy bare-string `module_selections` still opens and builds
   correctly (backward-compat path).

## How to undo just this workitem
```bash
git revert $(git log --grep="workitem-15" -1 --format=%H)
```
No manual steps required. The change is a shape change to per-slot module selections
plus the picker type; reverting restores the normal-quality-only picker and the
name-only data path. Blueprints already placed in save games are unaffected (their
module request/quality lives in the blueprint entity data, not in code).

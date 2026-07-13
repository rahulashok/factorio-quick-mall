# Workitem 16 — Independent module slots + crash on opening GUI with a stale item

**Status:** 🔵 Needs In-Game Verification
**Type:** Bug (High)
**Files changed:** `scripts/gui.lua`, `scripts/blueprint.lua`, `scripts/prototypes.lua`, `tests/qm-blueprint-tests.lua`

This workitem fixes two independent in-game bugs.

---

## BUG 1 — modules dropped when an earlier module slot is empty

### What was wrong

Repro: a building with 5 module slots; the user leaves slot 1 empty and puts a
productivity module in slot 2 (or fills only the last slot). The built entity ends up
with **no modules at all**.

Root cause: `handle_create_click` in `scripts/gui.lua` built `module_selections` as a
**sparse** slot-indexed array — it wrote `module_selections[slot]` only for filled
slots, so index 1 could be `nil`. `build_blueprint_entities` in `scripts/blueprint.lua`
then iterated it with `ipairs`, which **stops at the first `nil`**. An empty slot 1 →
zero iterations → every module dropped. Module slots must be **independent**: any subset
(including only the last slot) must work.

### What work I did

#### `scripts/gui.lua` `handle_create_click`

Changed the collector from a sparse slot-indexed array to a **dense** list (no gaps)
where each entry carries its real physical slot in `.slot`.

Before:
```lua
local module_selections = {}
...
    for slot = 1, slot_count do
      local saved = options.module_selections[slot]
      local sel
      if type(saved) == "table" and saved.name then
        sel = { name = saved.name, quality = saved.quality or "normal" }
      elseif type(saved) == "string" then
        sel = { name = saved, quality = "normal" }
      end
      if sel and allowed_set[sel.name] then
        module_selections[slot] = sel        -- SPARSE: leaves nil holes
      end
    end
```

After:
```lua
local module_selections = {}
...
    for slot = 1, slot_count do
      local saved = options.module_selections[slot]
      local sel
      if type(saved) == "table" and saved.name then
        sel = { name = saved.name, quality = saved.quality or "normal" }
      elseif type(saved) == "string" then
        sel = { name = saved, quality = "normal" }
      end
      if sel and allowed_set[sel.name] then
        -- Append densely; carry the real slot index.
        module_selections[#module_selections + 1] = {
          slot = slot,
          name = sel.name,
          quality = sel.quality,
        }
      end
    end
```

#### `scripts/blueprint.lua` `build_blueprint_entities`

Changed the `module_selections` parameter contract to the **dense list of
`{ slot, name, quality }` entries**, updated the doc-comment, and made the
module-inventory `items` insert-plan derive its 0-based `stack` from each entry's
**`.slot - 1`** (the real physical slot) instead of the array position.

Normalization loop — before:
```lua
local module_counts = {}
local module_slots = {}
if module_selections then
  for _, sel in ipairs(module_selections) do
    local mname, mquality
    if type(sel) == "table" then
      mname = sel.name
      mquality = sel.quality or "normal"
    elseif type(sel) == "string" then
      mname = sel
      mquality = "normal"
    end
    if mname and mname ~= "" then
      ...
      table.insert(module_slots, { name = mname, quality = mquality })
    end
  end
end
```

After (backward-compatible + nil-safe; falls back to a running slot counter when an
entry has no explicit `.slot`, so legacy callers/state still work):
```lua
local module_counts = {}
local module_slots = {}
local fallback_slot = 1
if module_selections then
  for _, sel in ipairs(module_selections) do
    local mname, mquality, mslot
    if type(sel) == "table" then
      mname = sel.name
      mquality = sel.quality or "normal"
      mslot = sel.slot
    elseif type(sel) == "string" then
      mname = sel
      mquality = "normal"
    end
    if mname and mname ~= "" then
      if type(mslot) ~= "number" then
        mslot = fallback_slot
      end
      fallback_slot = fallback_slot + 1
      ...
      table.insert(module_slots, { slot = mslot, name = mname, quality = mquality })
    end
  end
end
```

`items` insert-plan `stack` — before:
```lua
for slot_index, slot in ipairs(module_slots) do
  ...
  table.insert(group.positions, {
    inventory = module_inventory,
    stack = slot_index - 1,     -- array position, WRONG when a slot is skipped
    count = 1,
  })
end
```

After:
```lua
for _, slot in ipairs(module_slots) do
  ...
  -- 0-based stack MUST be the REAL physical slot (slot.slot - 1).
  table.insert(group.positions, {
    inventory = module_inventory,
    stack = slot.slot - 1,
    count = 1,
  })
end
```

The `module_counts` collapse by `name@quality` and the building's logistic
request-filter emission keep the same logic; they just consume the dense list. All
existing `pcall` guards and the `defines.inventory.assembling_machine_modules` guard
are preserved.

### How it was solved (contract)

The `module_selections` argument is now a **dense list** `{ { slot, name, quality }, ... }`.
Because it has no nil holes, `ipairs` visits every entry regardless of which physical
slots are filled — fixing the "stop at first empty slot" drop. The physical slot is
carried explicitly in `.slot` so the module inventory pre-fill lands each module in its
chosen slot (`stack = slot - 1`). Legacy inputs (bare string, or `{ name, quality }`
without `.slot`) still work via a sequential fallback counter.

---

## BUG 2 — crash opening the GUI when a previously-chosen item no longer exists

### What was wrong

Real stack trace:
```
Unknown item name: lumber
  scripts/gui.lua:501: in function 'build_gui'
  control.lua:127
```

When a mod that added an item was later disabled, the saved
`options.item_selection` (a signal table `{ type, name, quality }`, or possibly a legacy
string) was assigned **directly** to the item picker's `elem_value` in `build_gui`
without validation. Factorio throws a non-recoverable error because the item no longer
exists. Other saved selections already had "drop if invalid" guards; the item one did
not.

### What work I did

#### `scripts/prototypes.lua` — new `is_valid_signal(signal)`

Added a pcall-guarded helper (and two small version-tolerant lookups,
`resolve_fluid_prototype` / `resolve_virtual_signal_prototype`) exported from the
module's return table:

```lua
local function is_valid_signal(signal)
  if signal == nil then return false end
  if type(signal) == "string" then
    return resolve_item_prototype(signal) ~= nil   -- legacy bare string = item
  end
  if type(signal) ~= "table" then return true end   -- unknown shape: permissive
  local sig_type = signal.type
  local name = signal.name
  if not name then return true end
  if sig_type == nil or sig_type == "item" then
    return resolve_item_prototype(name) ~= nil
  elseif sig_type == "fluid" then
    return resolve_fluid_prototype(name) ~= nil
  elseif sig_type == "virtual" then
    -- resolve if possible; never DROP a valid virtual signal.
    return true
  end
  return true                                        -- other/unexpected: permissive
end
```

Design: only **DROP** when we are confident the selection is invalid (a missing item or
fluid). For anything we cannot reliably resolve across Factorio versions (virtual
signals, unknown shapes), be permissive and keep the selection. Every prototype read is
wrapped in `pcall`, so the helper never throws.

#### `scripts/gui.lua` `build_gui`

Before:
```lua
if options.item_selection then
  item_picker.elem_value = options.item_selection
end
```

After (silently clears the stale selection — **no** `player.print` — and wraps the
assignment in `pcall` as defense-in-depth):
```lua
if options.item_selection and not prototypes.is_valid_signal(options.item_selection) then
  options.item_selection = nil
end
if options.item_selection then
  pcall(function()
    item_picker.elem_value = options.item_selection
  end)
end
```

The earlier reads of `existing_options.item_selection` in `build_gui`
(`build_building_options` / `build_recipe_options`, ~lines 414/435-436) only pass the
name through and never assign it as an `elem_value`, so they cannot reintroduce the
crash — left unchanged.

### How it was solved

The stale selection is validated with `is_valid_signal` before use; if invalid it is
cleared to `nil` so the picker opens empty, and the actual `elem_value` write is
`pcall`-guarded so no future prototype gap can crash GUI open. Backward compatibility is
preserved for legacy bare-string selections.

---

## Tests — `tests/qm-blueprint-tests.lua`

1. **Slot independence:** calls `build_blueprint_entities` with a dense list holding
   ONLY slot 2 (`{ { slot = 2, name = <real module>, quality = "normal" } }`) on a
   building with ≥ 2 slots, and asserts (a) a request filter exists for that module and
   (b) an `items` insert-plan `InventoryPosition` has `stack == 1` (slot 2 → 0-based 1).
2. **`is_valid_signal`:** asserts a bogus item name → `false`, a real runtime-discovered
   item → `true`, and `nil` → `false`.

Both discovery steps graceful-skip if a required prototype is missing.

---

## Validation

- `luac -p` passes on all edited files: `scripts/gui.lua`, `scripts/blueprint.lua`,
  `scripts/prototypes.lua`, `tests/qm-blueprint-tests.lua`.
- `./scripts/run_tests.sh` could **not launch** in this worktree — Factorio exited 1 at
  the initial `--create` (dummy save) step, the known factorio-test/Factorio version
  mismatch for this session. The tests were therefore **not** executed here; they must
  be run from the parent checkout. No pass is claimed.

## Areas of lower confidence

- Fluid/virtual-signal prototype access across Factorio versions
  (`prototypes.fluid` / `game.fluid_prototypes`, `prototypes.virtual_signal` /
  `game.virtual_signal_prototypes`) — all pcall-guarded and permissive-on-failure, but
  only confirmable in-game.
- The blueprint `items` insert-plan `stack` indexing (0-based physical slot) needs
  in-game confirmation that modules land in the intended slots.

## How to undo

Revert the single commit tagged `[workitem-16]`:

```sh
git revert <commit-hash>
```

(or `git revert` the range if follow-up commits were added). This restores the sparse
`module_selections` collector, the array-position `stack`, and removes `is_valid_signal`
plus the `build_gui` guard.

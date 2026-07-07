# Workitem 9 — Rename local `prototypes` to avoid shadowing global

**Status:** Done
**Type:** Minor / cleanup (Low)
**Files changed:** control.lua

## What was wrong
The Factorio 2.0 runtime exposes a global table named `prototypes` (accessed
elsewhere in `control.lua` as `prototypes.entity` and `prototypes.item`). Inside
`get_candidate_buildings()`, the statement `local prototypes = get_entity_prototypes()`
declared a local variable with the same name, shadowing that global within the
function scope. It was safe today (in that scope the local genuinely holds the
entity prototypes), but the shadowing was fragile and confusing — any future code
in that function needing the real global would silently get the local instead.

## What I changed
In `get_candidate_buildings()` (control.lua):
- Renamed the declaration `local prototypes = get_entity_prototypes()` →
  `local entity_prototypes = get_entity_prototypes()`.
- Renamed its in-scope uses: the `if prototypes then` guard →
  `if entity_prototypes then`, and `for name, prototype in pairs(prototypes) do` →
  `for name, prototype in pairs(entity_prototypes) do`.

I left the genuine global accesses (`prototypes.entity` / `prototypes.item`) in
`get_entity_prototypes`, `resolve_entity_prototype`, `get_item_prototypes`, and
`resolve_item_prototype` untouched — those refer to the real Factorio 2.0 global
and must stay as `prototypes`. The unrelated locals `prototypes_list` were also
left alone.

## How to undo just this workitem
Committed as a single commit tagged `workitem-9`.
```bash
git revert $(git log --grep="workitem-9" -1 --format=%H)
```

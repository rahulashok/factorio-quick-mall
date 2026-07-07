# Workitem 11 — Document control.lua

**Status:** Done
**Type:** Documentation (Low)
**Files changed:** control.lua (comments only — no logic changes)

## What I did
- Added a file-level header comment block at the very top of `control.lua`
  (above `local GUI_ROOT = ...`) explaining what the mod does (one-click "quick
  mall" blueprint: crafting building + input/output logistic chests + inserters
  for a chosen recipe), the overall flow (open GUI → pick item/building/recipe/
  chests/inserter → Build creates a blueprint in the cursor → ghost tags reapply
  recipe/quality on build), and the Factorio 1.1/2.0 compatibility strategy
  (`storage` vs `global`; `prototypes.*` global vs `game.*_prototypes` /
  `game.get_*_prototype`, all tried via pcall; chest-name aliases).
- Added a concise doc-comment above each local function and each event handler
  describing its purpose, key params, and non-obvious return shapes (e.g. the
  `{ names, labels, uncertain }` option lists, the `{nil}`-entry "no options"
  sentinel, the blueprint-entity layout, and the storage-root structure).
  Comments describe the current single definitions only (the previously
  duplicated functions are documented as their surviving single versions).
- Added group-level section banners for navigation:
  `-- === Prototype resolution helpers ===`, `-- === Option-list builders ===`,
  `-- === Recipe filtering & surface compatibility ===`,
  `-- === Candidate building / recipe option builders ===`,
  `-- === Storage / global state ===`,
  `-- === GUI lifecycle & blueprint construction ===`,
  `-- === GUI construction ===`, `-- === Ghost-tag application ===`,
  `-- === Event handlers ===`, and others.

Only comment lines (and no blank-line-only reformatting of code) were added.
No executable code was changed: no identifiers renamed, no statements
reordered, no strings altered, and no functionality added or removed. The code's
runtime behavior is identical.

## Verification
- `luac -p control.lua` → PARSE_OK
- Only comment lines added; no identifiers, strings, or statements changed.

## How to undo just this workitem
Committed as a single commit tagged `workitem-11`.
```bash
git revert $(git log --grep="workitem-11" -1 --format=%H)
```

# Workitem 13 — Automated tests every 6 hours + coverage reporting

**Status:** Done (🔵 first scheduled fire should be observed once — the on-demand
run passes; the recurring launch only fires while the machine is awake and the
Claude Code REPL is idle at the scheduled time)
**Type:** Platform Improvement (Medium)
**Files changed:** info.json, control.lua, .gitignore (all modified); tests/qm-blueprint-tests.lua, factorio-test.json, scripts/run_tests.sh, docs/test-results/latest.md (all new)

## Motivation

The repo's only test file, `tests.lua`, was a hand-rolled harness whose three
cases **re-implement the logic inline** — the code literally comments *"we define
the logic here as it was implemented"* — and never `require` `control.lua` or
`scripts/*.lua`. They therefore exercised **none** of the shipped code, ran only
manually in-game via `remote.call("quick_mall", "run_tests")`, and produced no
scheduled runs and no coverage numbers. Workitem #13 asks for automated runs every
6 hours reported in `docs/TASKS.md`, including a coverage rate.

## What changed

### Adopted FactorioTest (real in-game tests)
- **`info.json`** — added optional dependency `"? factorio-test"`. Optional (`?`)
  so the shipped mod never forces players to install it; it is only active during
  test runs.
- **`control.lua`** — appended a guarded init block:
  ```lua
  if script.active_mods["factorio-test"] then
    require("__factorio-test__/init")({ "tests.qm-blueprint-tests" }, { load_luassert = true })
  end
  ```
  Inert in normal play (the block is skipped unless factorio-test is installed).
  `load_luassert = true` swaps the global `assert` for luassert, giving the spec
  rich matchers (`assert.is_true` / `assert.equals` / `assert.is_nil` / ...). The
  legacy `remote.add_interface("quick_mall", { run_tests })` path is left intact.
- **`tests/qm-blueprint-tests.lua`** (new) — a FactorioTest spec using
  `describe`/`it` + luassert that calls the **real** `scripts/recipes.lua` and
  `scripts/blueprint.lua` inside a live headless Factorio (no inline logic copies,
  no mocks). Ported the three legacy behaviors (solid-input/output detection,
  blueprint bar from stack limit) to assert against the real functions, and added
  coverage of `get_recipes_for_item` (incl. its enabled/disabled filtering) and
  `build_blueprint_entities`' full entity layout + tags.

### Runner + config
- **`factorio-test.json`** (new) — CLI config: `modPath: "."`, an explicit
  `factorioPath` to the Steam macOS binary, and `mods: ["base"]`.
- **`scripts/run_tests.sh`** (new, executable) — launches Factorio headless via
  `npx factorio-test-cli run`, tees output to `docs/test-results/latest.md`, and
  exits non-zero on any test failure. Includes a macOS Steam-bundle data-path
  workaround (see below).

### Schedule (Claude Code scheduler, NOT system cron)
- A **durable Claude Code scheduled job** ("Quick Mall automated test run") runs
  `scripts/run_tests.sh` every 6 hours (cron `13 */6 * * *`, off-minute to avoid
  fleet-wide :00 pileups). It is stored in `.claude/scheduled_tasks.json` and
  survives session restarts. The system crontab was deliberately **not** used.
  - **Note:** Claude Code recurring jobs auto-expire after 7 days; re-create the
    job (or make a longer-lived arrangement) if runs past that are needed.
- **`.gitignore`** — added `factorio-test-data-dir/` (the CLI's generated working
  directory: downloaded mods, headless save, config, and a symlink back into this
  repo) so it is never committed.

## macOS Steam-bundle data-path workaround

On the macOS Steam build the binary lives at
`factorio.app/Contents/MacOS/factorio` but its `core`/`base` data are at
`factorio.app/Contents/data`. The default `config.ini` the CLI writes uses
`read-data=__PATH__executable__/../../data`, which the binary resolves to
`factorio.app/data` (nonexistent) and aborts with *"There is no package core"*.
`run_tests.sh` pre-seeds the data dir's `config.ini` with an **absolute**
`read-data` pointing at `.../Contents/data`; the CLI leaves an existing
`config.ini`'s `read-data` untouched (it only rewrites `write-data`), so the fix
sticks across runs.

## Coverage results

Factorio runs mods in its own VM with **no in-VM line-coverage tool** (luacov
cannot instrument the running game), so a line percentage cannot be measured
honestly. Reported instead is **functional coverage**:

- **Files:** 2 of 6 `scripts/*` modules directly exercised (`recipes.lua`,
  `blueprint.lua`); `constants.lua` + `prototypes.lua` load transitively.
  `gui.lua` / `storage.lua` need a player/GUI harness (future work).
- **Methods:** 5 real functions asserted — `recipes.has_solid_inputs`,
  `recipes.has_solid_outputs`, `recipes.get_recipes_for_item`,
  `blueprint.build_blueprint_entities`, `blueprint.get_item_requests`.
- **Lines:** not measurable in the Factorio VM (stated honestly, not fabricated).

The previous `tests.lua` reported "3/3 passed" but covered **0** real source
lines/functions (inline logic copies). These are the first figures reflecting the
shipped code.

## Verification

- `luac -p control.lua` → PARSE_OK. `luac -p tests/qm-blueprint-tests.lua` → PARSE_OK.
- `scripts/run_tests.sh` executed on-demand: launched headless Factorio 2.0.77
  (Steam) with factorio-test 3.0.1, ran the spec, **8 passed, 0 failed**, runner
  exit code 0. Report written to `docs/test-results/latest.md`.
- Confirmed factorio-test 3.0.1 (Factorio 2.0) is used, not 3.1.0 (requires
  Factorio 2.1, which is not installed) — the CLI reuses the 3.0.1 already present
  in the data dir.
- Claude Code scheduled job present (`.claude/scheduled_tasks.json`, verified via
  the scheduler); it is gitignored along with `factorio-test-data-dir/`.

### Needs follow-up observation (🔵)
- The **recurring** 6-hour fire depends on the machine being awake with the Claude
  Code REPL idle at the scheduled minute; observe one live fire to confirm.
- Requires network on first run so `npx` can fetch `factorio-test-cli`.
- Coverage is functional only; a luacov-capable harness outside the game would be
  needed for true line coverage (out of scope here).

## How to undo just this workitem

Committed as a single commit tagged `workitem-13`.
```bash
git revert $(git log --grep="workitem-13" -1 --format=%H)
```
Also delete the recurring schedule (it lives outside git): remove the
"Quick Mall automated test run" entry from `.claude/scheduled_tasks.json`, or use
the CronDelete tool in Claude Code (job id shown by CronList). The generated
`factorio-test-data-dir/` can be deleted with `rm -rf factorio-test-data-dir`.
```

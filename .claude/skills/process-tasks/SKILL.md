---
name: process-tasks
description: Process the docs/TASKS.md work-item tracker — find open (🔴) rows, implement each via worktree subagents, write a detailed workitem report with a revert plan, flip status to Done, and commit. Invoke on the 15-minute schedule or manually with /process-tasks.
---

# Process Quick Mall tasks

`docs/TASKS.md` is the long-running work-item tracker for this repo. This skill is
the source-of-truth procedure for working it. The durable cron job and manual
`/process-tasks` both run these steps.

## 1. Scan for actionable work

Read `docs/TASKS.md` and parse the **summary table** — the numbered rows that look
like `| 14 | <item> | <type> | <severity> | <status> |`.

**A row is OPEN (actionable) if its Status cell contains the 🔴 emoji.** Match on the
**🔴 emoji itself, not on exact text.** The status wording is authored by a human and
varies — e.g. `🔴 Todo`, `🔴 TODO`, `🔴 TODO: Reopened`, `🔴 In Progress (reopened)`
have all appeared. Treat ANY numbered table row whose Status cell contains 🔴 as open.
Do **not** rely on a case-sensitive string like `🔴 Todo`.

A concrete way to list open rows (the leading `| N |` filter excludes the legend
line, which is not a numbered table row):

```bash
grep -nE '^\| *[0-9]+ ' docs/TASKS.md | grep '🔴'
```

Ignore the status *legend* line (line ~6) and any row whose Status cell has no 🔴
(i.e. 🟢 Done, ⚪ Won't Do, 🟡 without 🔴, or 🔵). A **reopened** item (🔴 plus text
like "Reopened") is open — read its detail section AND its `docs/workitems/NN-*.md`
report, which may contain new failure information ("User feedback" / "In-game testing
failed") explaining why the prior fix was insufficient. Use that to drive the new fix.

**If no numbered row contains 🔴, do nothing and stop.** This is the normal case.

## 2. Implement each open item (worktree subagents)

Dispatch one subagent per open workitem, each in its own **git worktree**
(`isolation: "worktree"`). `control.lua` was split into `scripts/*.lua` modules
(workitem #12), so items touching *different* modules can run **in parallel**.

**Before fanning out, check for file overlap.** If two open items would edit the same
file/function (e.g. both restructure `scripts/gui.lua`'s `build_gui`), do NOT run them
concurrently — the worktree merges will conflict. Instead **serialize** them: run the
first, merge it to the main branch, then branch the second on top of the merged result
and re-read the now-current file. When in doubt about overlap, serialize.

Each subagent, for its workitem `NN`, must:

1. **Make the code change.**
2. **Parse-check** every edited Lua file: `luac -p <file>` (must print `PARSE_OK` /
   exit 0).
3. **Write the report** `docs/workitems/NN-slug.md` (see format below).
4. **Flip status to `🟢 Done`** in BOTH the summary-table row AND the item's detail
   section in `docs/TASKS.md`. Bump the `_Last updated:_` date.
5. **Commit** as a single commit whose message ends with the tag `[workitem-NN]`.

## 3. Finish up

After all subagents finish: merge the worktree commits back to the main branch,
re-run `luac -p` on all touched files, and report a concise summary of which
workitems were completed. Never force-push or rewrite shared history.

## Report format — docs/workitems/NN-slug.md

Match the existing reports in `docs/workitems/`. Every report MUST contain, in detail:

```markdown
# Workitem NN — <title>

**Status:** Done
**Type:** <Bug/Optimization/UX/...> (<Severity>)
**Files changed:** <files>

## What was wrong
<The problem, in detail — what the bug/gap was and why it mattered.>

## What work I did
<What was changed, with before/after code snippets and the exact files/functions.>

## How it was solved
<The approach and why; any alternatives rejected.>

## How to undo just this workitem
<The git-revert command plus any manual steps, in case this fix breaks.>
​```bash
git revert $(git log --grep="workitem-NN" -1 --format=%H)
​```
```

## Notes
- Factorio runs Lua in its own VM; `luac -p` catches syntax errors only, not runtime
  issues (invalid `LuaStyle` keys, bad `require` paths). Flag anything that needs
  in-game verification with `🔵 Needs In-Game Verification` rather than claiming Done.
- The recurring cron job auto-expires after 7 days — re-create it if it lapses.

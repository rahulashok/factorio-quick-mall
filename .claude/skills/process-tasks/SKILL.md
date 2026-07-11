---
name: process-tasks
description: Process the docs/TASKS.md work-item tracker — find 🔴 Todo rows, implement each via parallel worktree subagents, write a detailed workitem report with a revert plan, flip status to Done, and commit. Invoke on the 15-minute schedule or manually with /process-tasks.
---

# Process Quick Mall tasks

`docs/TASKS.md` is the long-running work-item tracker for this repo. This skill is
the source-of-truth procedure for working it. The durable cron job and manual
`/process-tasks` both run these steps.

## 1. Scan for actionable work

Read `docs/TASKS.md`. Find every row whose **Status is `🔴 Todo`** in the summary
table (lines like `| 14 | ... | 🔴 Todo |`). Ignore the status *legend* line and any
row already marked `🟢 Done`, `⚪ Won't Do`, `🟡 In Progress`, or `🔵`.

**If there are no 🔴 Todo rows, do nothing and stop.** This is the normal case.

## 2. Implement each Todo item (in parallel)

Dispatch one subagent per Todo workitem. Run independent items **in parallel**, each
in its own **git worktree** (`isolation: "worktree"`) — `control.lua` was split into
`scripts/*.lua` modules (workitem #12), so concurrent edits rarely collide. Only
serialize workitems that provably touch the same lines.

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

# Quick Mall

A Factorio 2.0 mod. Runtime entry point is `control.lua`; implementation lives in
`scripts/*.lua` modules (`constants`, `prototypes`, `storage`, `recipes`,
`blueprint`, `gui`). Lua runs in Factorio's own VM — `luac -p` catches syntax errors
only, not runtime issues, so blueprint/GUI changes need in-game verification.

## Task automation

`docs/TASKS.md` is the long-running work-item tracker. Rows marked `🔴 Todo` are
processed automatically: every 15 minutes a durable cron job
(`.claude/scheduled_tasks.json`) runs the **`process-tasks`** skill, which implements
each Todo via parallel worktree subagents, writes a detailed report to
`docs/workitems/NN-slug.md` (including a revert plan), flips the row to `🟢 Done`, and
commits it tagged `[workitem-NN]`.

- **The procedure lives in `.claude/skills/process-tasks/SKILL.md`** (source of truth).
- Run it manually anytime with `/process-tasks`.
- A second cron job (`13 */6 * * *`) runs `scripts/run_tests.sh` for workitem #13.
- Cron recurring jobs auto-expire after 7 days — re-create them if they lapse.

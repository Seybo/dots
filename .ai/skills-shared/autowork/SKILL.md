---
name: autowork
description: >-
  Pi-only command. Autonomously executes an existing task plan by coordinating
  visible Pi and Claude tmux panes, committing each code-changing iteration,
  collecting Claude reviews/debates, and running final checks. In Pi, invoke via
  /skill:autowork; /autowork is also accepted where that alias is exposed.
disable-model-invocation: true
---

# Autowork

This is a **Pi-only command skill**. Do not auto-use it from general requests; wait for explicit `/autowork`. Claude is a participant in this workflow, not the orchestrator, and must not run this skill directly.

```text
/skill:autowork
/autowork
/autowork <task_id> [full-base-branch-or-ref]
/autowork <project-or-session> [task_id] [full-base-branch-or-ref]
/autowork doctor [--no-send-test]
/autowork rebase-base [<base-ref>] [--task <task_id>]
autowork update-base <task_folder> <new-base-ref>
autowork manager-review-fix <task_folder>
autowork manager-review-pass <task_folder>
```

Implemented helper (Ruby orchestrator; `bin/autowork` + `lib/` in this skill folder):

```text
/Users/inseybo/.ai/skills-shared/autowork/bin/autowork
```

V1 is fully implemented: init/resume, step implementation prompts to `pi-worker`, status-JSON waits, `Step N` commits, blind Pi audits, Claude step reviews, Pi classification, `Step N fix M` commits, re-reviews, bounded debates, multi-step progression, final checks with fix/review loops, one final whole-branch `/claude-super-review`, super-fix adjudication, Pi final review, manager-context production-readiness gate with automated manager-fix loops, and `final_summary.md`. Unresolved debates pause for human arbitration — the manager must not decide which agent is correct.

## Reference files (read at the phase that needs them, not upfront)

- `references/preflight.md` — doctor command, task resolution + `save` commit rules, `/workit` preflight, the workit contract (`create-steps-only`, `step N`, `steps.md` heading format).
- `references/runtime.md` — autowork-log layout, tmux pane model, prompt delivery rules, status-JSON schema, waiting banners, timeout/pause/resume semantics.
- `references/review-protocol.md` — Claude step-review rules (`/gtm-revit`-style, no test/lint runs), finding classification, debate procedure.
- `references/final-gates.md` — final checks, final super-review gate + base-ref management, `rebase-base`, manager risk manifest, manager finding loop, final output.

## Core goal

Automate the existing manual loop:

1. Pi implements one planned step.
2. `/autowork` commits the code-changing iteration.
3. Pi performs one blind whole-diff audit without seeing manager hypotheses or historical risk data.
4. Claude independently reviews the complete step diff according to `/gtm-revit`-style rules.
5. Pi applies accepted fixes; `/autowork` commits every code-changing fix iteration.
6. Claude reviews again.
7. If Pi and Claude disagree, facilitate bounded debate rounds; after the round limit, pause for user arbitration.
8. Continue until all steps are accepted.
9. Run final full checks.
10. Run one final whole-branch `/claude-super-review`; Pi adjudicates/fixes findings with `/claude-super-fix` rules and room to disagree.
11. Rerun final checks after super-review fixes; Claude gives a normal scoped review of super-review fix commits (not another full super-review).
12. Ask `pi-worker` to review all changes for issues, gaps, and improvements (ignoring very minor issues).
13. Stop for pi-manager's manager-context production-readiness review.
14. If pi-manager finds issues: one structured findings file → `autowork manager-review-fix` → automated Pi fix, checks, scoped Claude review → fresh manager gate.
15. Mark complete only after pi-manager concludes the result is production-ready.

The user is not expected to review every intermediate step; the final result should be production-ready without relying on another user review.

## Git ownership

Invoking `/autowork` is explicit permission for that run to stage and commit changes according to this protocol.

Allowed by `/autowork` invocation: `git add -A` and commits named `Step N`, `Step N fix M`, `Final checks fix M`, `Super-review fix N`, `Manager review fix M`. During preflight only, `/workit ... create-steps-only` may perform its documented task-branch setup/verification (including the Shortcut branch create/switch path when safe and unambiguous).

Still forbidden unless separately approved: push, force-push, reset, rebase, merge, branch switch/create/delete outside the documented preflight, stash, tag changes.

Rules:

- require clean worktree at start and before every Pi prompt
- Pi may leave dirty changes after implementation/fix; `/autowork` stages and owns ALL commits
- `/workit step N` and Pi fix prompts must not commit
- before Claude reviews the worktree must be clean, and it must remain clean after review/debate
- no-code debate/resolution iterations do not create empty commits; they live in `autowork-log/` only

Core invariant:

```text
Pi must never produce two code-changing commits in a row without Claude reviewing the last commit.
```

## Limits

Default safety limits (checked before every commit; the commit limit counts implementation, step-fix, final-check-fix, super-review-fix, and manager-review-fix commits together):

```yaml
max_fix_iterations_per_step: 10
max_debate_rounds_per_disagreement: 5
max_final_check_fix_iterations: 5
max_super_review_fix_iterations: 3
max_manager_review_fix_iterations: 5
max_total_commits: 15
max_runtime_hours_per_run: 1
worker_status_timeout_minutes: 10
super_review_status_timeout_minutes: 20
run_final_super_review: true
```

`config.yml` also records `starting_head_commit`, `branch_name`, `original_review_base_ref/commit` (frozen at init), and `review_base_ref/commit` (active base; see `references/final-gates.md`).

If a limit is hit: write paused state and `autowork-log/paused_reason.md`, stop, and ask the user whether/how to continue.

## Run flow (with reference pointers)

1. **Start / doctor** — resolve the task, run the `save` commit rule and `/workit` preflight per `references/preflight.md`. `/autowork doctor` health-checks the environment (same file).
2. **Orchestration** — the Ruby helper drives panes, prompts, status waits, commits, and banners per `references/runtime.md`. Never bypass `Tmux#send_prompt`; on any wait or resume question, follow the timeout/resume semantics there.
3. **Reviews, findings, debates** — per `references/review-protocol.md`.
4. **Final phase** — final checks, super-review gate, Pi final review, manager gate, and completion per `references/final-gates.md`.

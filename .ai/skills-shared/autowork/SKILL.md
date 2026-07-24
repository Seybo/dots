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

This is a **Pi-only command skill**.

In Pi, use either:

```text
/skill:autowork
/autowork
/autowork <task_id> [full-base-branch-or-ref]
/autowork <project-or-session> [task_id] [full-base-branch-or-ref]
/autowork doctor
/autowork doctor --no-send-test
/autowork rebase-base
/autowork rebase-base <base-ref>
/autowork rebase-base <base-ref> --task <task_id>
autowork update-base <task_folder> <new-base-ref>
autowork manager-review-fix <task_folder>
autowork manager-review-pass <task_folder>
```

Do not auto-use this skill from general requests. Wait for explicit `/autowork`.
Claude is a participant in this workflow, not the orchestrator, and must not run this skill directly.

`/autowork doctor` is a permanent health/QA command. It should remain useful as the workflow grows.

## Current implementation status

V1 supports implementation, review, accepted fixes, re-review, bounded Pi/Claude debate facilitation, multi-step progression, final checks, automated final-check fix commits, final-check fix review, one final whole-branch `/claude-super-review`, a follow-up Pi-worker final review, `/claude-super-fix`-style Pi adjudication/fixes, normal scoped Claude review of super-review fix commits, final manager-context production-readiness review, automated manager-finding fix/check/Claude-review loops, and final summary. It can initialize/resume a run, send a Step N implementation prompt to `pi-worker`, wait for Pi status JSON, commit `Step N`, send a review prompt to `claude-worker`, wait for Claude review status JSON, ask Pi to classify findings, commit accepted fixes as `Step N fix M`, re-review fix commits, run bounded debate rounds for disputed/deferred findings, advance through planned steps, run configured final checks, commit final-check fixes as `Final checks fix M`, ask Claude to review final-check fix commits, run final super-review, resolve all Claude super-review findings, commit `Super-review fix N`, rerun final checks, ask Claude to review super-review fix commits, then ask pi-worker to review all changes for issues/gaps/improvements while ignoring very minor issues, stop for pi-manager's production-readiness review using manager-only context, and write `final_summary.md`. If debate remains unresolved after the configured round limit, `/autowork` pauses for human arbitration because the manager must not decide which agent is correct.

Implemented helper:

```text
/Users/inseybo/.ai/skills-shared/autowork/bin/autowork
```

It currently resolves/validates a task, relies on `/workit ... create-steps-only` preflight to create/update `steps.md` and verify/setup the task branch, requires a clean repo for normal orchestration start, discovers tmux panes, creates `autowork-log/`, writes config/state, sends prompts with `tmux send-keys`, waits for status JSON, commits Step N implementations, sends Claude review prompts, asks Pi to classify review findings, commits accepted fixes, sends follow-up review prompts, advances through planned steps, runs final checks, runs the final super-review gate, routes structured manager findings through automated Pi fix and scoped Claude review loops, and writes `final_checks.md`, `super-review.md`, manager/super-fix artifacts, `manager_review.md`, and `final_summary.md`.

## Doctor command

`/autowork doctor` is abstract environment health, not task QA. It does not take a project or task id. When panes are healthy, it sends one harmless "no action required" line to `pi-worker` and `claude-worker` so pane delivery is QA'd without repeating a second command. It may run on a dirty worktree and should report dirty/clean status instead of failing. It does not touch git state or repo files.

`/autowork doctor --no-send-test` keeps doctor fully read-only and skips the harmless tmux delivery test.

Use the seeded `my_autowork_qa` project for real end-to-end task QA with normal `/autowork my_autowork_qa 0001`; do not use `doctor` for that.

Doctor should report:

- helper path
- current repo root
- current branch
- worktree clean/dirty status
- current tmux window pane-title discovery for exact titles:
  - `pi-manager`
  - `pi-worker`
  - `claude-worker`
- pane IDs for each role
- whether all panes resolve to the same git root as the current repo
- status JSON validator health using a sample object
- prompt-delivery readiness

Doctor output should be human-readable and clear enough that the user can QA the shell/tmux environment from the `pi-manager` prompt.

## Core goal

Automate the existing manual loop:

1. Pi implements one planned step.
2. `/autowork` commits the code-changing iteration.
3. Claude reviews the last commit according to `/gtm-revit`-style rules.
4. Pi applies accepted fixes.
5. `/autowork` commits every code-changing fix iteration.
6. Claude reviews again.
7. If Pi and Claude disagree, facilitate bounded debate rounds.
8. If the agents still disagree after the round limit, pause for user arbitration.
9. Continue until all steps are accepted.
10. Run final full checks.
11. Run one final whole-branch `/claude-super-review`.
12. After Claude's super-review, ask `pi-worker` to review all the changes and try to find issues, gaps, and improvement opportunities, but ignore very minor issues.
13. Let Pi adjudicate/fix Claude's findings with `/claude-super-fix` rules and room to disagree.
14. Rerun final checks after super-review fixes.
15. Ask Claude for a normal scoped review of super-review fix commits, not another full super-review.
16. Stop for pi-manager's manager-context production-readiness review.
17. If pi-manager finds issues, write one structured findings file and invoke `autowork manager-review-fix <task_folder>`.
18. Let `/autowork` route the findings to Pi, commit `Manager review fix N`, rerun final checks, obtain a scoped Claude review, loop on review findings, and return to a fresh manager gate.
19. Mark complete only after pi-manager concludes the result is production-ready if the user does not perform another review.

The user is not expected to review every intermediate step, and the final result should be production-ready without relying on another user review.

## Final super-review gate

After final checks pass, `/autowork` runs one final whole-branch `/claude-super-review` through `claude-worker`.

Base branch/ref rules:

- Normal tasks default to `main`/`master` as the review base.
- If the task branch is stacked on another feature branch, the user passes the full parent branch/ref to `/autowork`; do not infer it from a numeric task/story ID.
- Invocation shapes:
  ```text
  /autowork <task_id>
  /autowork <task_id> <full-base-branch-or-ref>
  /autowork <project-or-session> <task_id> <full-base-branch-or-ref>
  ```
- Store the initial branch snapshot in `<task_folder>/autowork-log/config.yml` as `branch_name` and `starting_head_commit`.
- Store the initial resolved base in `<task_folder>/autowork-log/config.yml` as `original_review_base_ref` and `original_review_base_commit`.
- Store the active/current review base separately as `review_base_ref`, `review_base_ref_is_explicit`, and `review_base_commit`; run the final review against `review_base_ref...HEAD`.
- `original_review_base_*` is audit/debug context and must not change after run initialization. `review_base_*` may change after an explicit rebase/base update.
- For explicit stacked bases, `/autowork` must detect when the base ref resolves to a different commit than `review_base_commit`. If it changed, pause before starting the next step/final phase and ask for explicit rebase/base-change instructions. Do not rebase automatically.
- After an intentional rebase or base change, update the recorded review base explicitly:
  ```text
  autowork update-base <task_folder> <new-base-ref>
  ```
  Use this when the parent branch advanced, or when the parent task merged and this task should now review against `main`/`master`.
- The super-review report must state the exact diff base used.
- After Claude's whole-branch super-review findings and any super-review fix commits have been accepted by Claude's scoped review, `/autowork` sends `pi-worker` a review-only prompt containing this exact goal: `review all the changes and try to find issues, gaps, and improvement opportunities. But ignore very minor issues`.
- Pi reviews the entire `review_base_ref...HEAD` diff without editing files, writes `autowork-log/pi-final-review.md`, and reports actionable `BLOCKER`/`MINOR` findings in `step0_pi_final_reviewN_status.json`.
- `/autowork` resolves all Claude super-review findings first, including the scoped Claude review of any super-review fix commits. Only after that loop is accepted does it send the final review to pi-worker. Pi's final-review findings are recorded for the manager gate and are not combined with Claude's findings.

## Manual base rebase command

`/autowork rebase-base` is an explicit manual helper for stacked branches whose recorded autowork base advanced. It belongs in this skill because `/autowork` owns `review_base_ref` and `review_base_commit`, but normal orchestration must never auto-rebase.

Invocation:

```text
/autowork rebase-base
/autowork rebase-base <base-ref>
/autowork rebase-base <base-ref> --task <task_id>
```

Examples:

- Current base ref stays the same, but the ref advanced:
  ```text
  /autowork rebase-base
  ```
- Parent branch merged and the task should now be based on `master`:
  ```text
  /autowork rebase-base master
  ```
- The branch has no task-ID segment, so identify the task explicitly:
  ```text
  /autowork rebase-base main --task 0001
  ```
- Task should move from one stacked parent to another:
  ```text
  /autowork rebase-base origin/example-parent-branch
  ```

Rules:

1. Infer the task from the current repo/branch using normal task-resolution rules. If the branch has no inferable task-ID segment, require the explicit `--task <task_id>` fallback.
2. Load `<task_folder>/autowork-log/config.yml`.
3. Require `repo_dir`, `review_base_ref`, and `review_base_commit`; preserve `original_review_base_ref` and `original_review_base_commit` unchanged.
4. Require the repo worktree to be clean.
5. Require the current branch to equal stored `branch_name` when present.
6. Refuse to run while `<task_folder>/autowork-log/run.lock` exists.
7. Fetch origin.
8. If positional `<base-ref>` is passed, use that as the target base; otherwise use current `review_base_ref`.
9. Resolve the target base ref; after fetching, `master` means `origin/master` when it exists, and `main` means `origin/main` when it exists. Preserve full refs like `origin/example-parent-branch` exactly. Do not use branch upstream (`@{u}`).
10. Verify recorded `review_base_commit` is an ancestor of the current branch. If it is not, stop and ask for user direction.
11. Rebase the current branch from the recorded old base onto the target base ref:
    ```bash
    git -C <repo_dir> rebase --onto <target-base-ref> <review_base_commit>
    ```
12. If conflicts occur, resolve them when the correct resolution is clear.
    For each resolved conflict, write a report to `<task_folder>/autowork-log/rebase_conflicts.md` with:
    - file
    - what conflicted
    - kept side or combined resolution
    - reason
    - checks run

    If the correct resolution is not clear, leave the rebase paused, write the unresolved conflict report, and ask the user.
13. After a successful rebase, update active base metadata only:
    ```yaml
    review_base_ref: <target-base-ref>
    review_base_commit: <resolved-target-base-sha>
    ```
    Keep `original_review_base_ref` and `original_review_base_commit` unchanged.
14. Do not push.
15. Do not resume `/autowork` automatically; ask the user before continuing orchestration.

The final super-review wait uses `super_review_status_timeout_minutes: 20`, separate from normal `worker_status_timeout_minutes`.

If super-review finds actionable issues, `/autowork` sends them to `pi-worker` for `/claude-super-fix`-style adjudication and fixes. Pi may accept, disagree, mark already-fixed/out-of-scope/follow-up, or request user input. `/autowork` commits accepted code changes as `Super-review fix N`, reruns final checks, and sends those fix commits to Claude for a normal scoped review. It does not rerun full super-review by default. Only after Claude accepts that complete super-review/fix loop does `/autowork` send the final review prompt to `pi-worker`. Pi's final-review findings are saved in `pi-final-review.md` for the manager-context gate; they are not fed back into the Claude super-fix loop. Final super-review report-only advisories, later-story recommendations, deploy notes, and smoke-test notes should be emitted as status JSON `followups` so `final_summary.md` does not contradict a "merge with follow-ups" report.

## Task resolution

Resolve task folders the same way `/draftit`, `/taskit`, and `/workit` do.
Use the shared task-resolution rules from:

```text
/Users/inseybo/.ai/skills-shared/components/task-resolution.md
```

`/autowork` requires the selected task folder to contain `task.md`. It infers the project from the current checkout and the task ID from an `sc-<digits>` branch segment when possible. For arbitrary branch names, pass the task ID positionally, such as `/autowork 0001`. It also requires `steps.md` before the Ruby helper starts, but `/autowork` owns a preflight that creates or updates `steps.md` through `/workit` when needed.

Preflight before running the Ruby helper:

1. resolve the same `<project-or-session> [task_id] [full-base-branch-or-ref]` arguments that `/autowork` will pass to the helper
2. if a full base branch/ref was supplied, preserve it exactly; do not infer it from a numeric task/story ID
3. if `<task_folder>/steps.md` is missing, a base branch/ref was supplied, or branch setup/verification is needed, invoke `/workit ... create-steps-only` before the Ruby helper:
   ```text
   /workit <project-or-session> [task_id] create-steps-only
   /workit <project-or-session> [task_id] --base <full-base-branch-or-ref> create-steps-only
   ```
   Use the `--base` form when `/autowork` was invoked with a full base branch/ref. If project is inferred, pass the inferred task selector with `--base`, e.g. `/workit <task_id> --base <full-base-branch-or-ref> create-steps-only`.
4. rely on `/workit create-steps-only` to use the documented `/workit`/`/taskit` branch rules; for GTM Shortcut tasks this means the branch slug comes from the current Shortcut story `name`, fetched through the shared Shortcut CLI, not from the task folder suffix
5. if `/workit create-steps-only` stops for a branch decision, base-branch mismatch, rebase requirement, or plan problem, stop `/autowork` before running the helper and surface that decision to the user
6. after preflight succeeds, run the Ruby helper normally; the helper stores the same base as `review_base_ref` for final super-review

If `steps.md` already exists, `/autowork` may skip plan creation, but it must still not skip `/workit` branch setup/verification when a full base branch/ref was supplied. The Ruby helper also requires `steps.md` and will fail fast if the preflight did not create it.

## Required workit support

`/workit` should support creating only the steps plan:

```text
/workit <task> create-steps-only
```

Rules for `/workit ... create-steps-only`:

- read `task.md`
- perform normal project/branch setup or verification before returning to `/autowork`
- create or update `steps.md` using normal planning rules
- do not implement any step
- do not edit production code
- do not stage or commit
- stop after reporting `steps.md` path and branch status

`/workit` should also support executing exactly one planned step:

```text
/workit <task> step N
```

Rules for `/workit ... step N`:

- read `task.md`
- read `steps.md`
- treat `steps.md` as frozen
- execute only `## Step N` through before the next `## Step <number>` heading
- do not edit `steps.md` unless the step is impossible/stale, in which case stop and report
- do not commit
- leave code changes unstaged/uncommitted for `/autowork` to commit

`steps.md` must use parseable headings:

```md
## Step 1: ...
## Step 2: ...
```

`/autowork` parses steps with:

```text
^## Step ([0-9]+)\b
```

## Autowork log layout

Create all orchestration files under the task folder:

```text
<task_folder>/autowork-log/
  config.yml
  state.json
  run.lock

  control/
    pause

  prompts/
    step1_pi_implement_request.md
    step1_claude_review1_request.md
    step1_pi_fix1_request.md
    step1_debate_D1_round1_claude_request.md
    step1_debate_D1_round1_pi_request.md
    final_super_review1_request.md
    final_pi_review1_request.md
    super_review_pi_fix1_request.md
    super_review_claude_fix_review1_request.md

  reviews/
    step1_claude_review1_result.md
    step1_claude_review2_result.md

  debates/
    step1_debates.md
    step2_debates.md

  resolutions/
    step1_pi_review1_result.md
    step1_pi_review2_result.md

  super_fixes/
    super_review_pi_fix1_result.md
    super_review_claude_fix_review1_result.md

  manager_reviews/
    manager_review1.md
    manager_review1_findings.json

  manager_fixes/
    manager_review_pi_fix1_result.md
    manager_review_claude_fix_review1_result.md

  status/
    step1_pi_implement_status.json
    step1_claude_review1_status.json
    step1_pi_fix1_status.json
    step0_claude_super_review1_status.json
    step0_pi_final_review1_status.json
    step0_pi_super_fix1_status.json
    step0_claude_super_fix_review1_status.json
    step0_pi_manager_fix1_status.json
    step0_claude_manager_fix_review1_status.json

  final_checks.md
  super-review.md
  pi-final-review.md
  manager_review.md
  final_summary.md
```

`autowork-log/` lives only in the task folder and should not be committed to the feature repo.

## Tmux model

The user manually starts visible terminal agents in the same tmux window.

`/autowork` runs from the `pi-manager` pane and uses the current tmux window.
That window must have exactly one pane with each exact title:

```text
pi-manager
pi-worker
claude-worker
```

Initial discovery uses the current tmux window:

```sh
tmux list-panes -F '#{pane_index} #{pane_id} "#{pane_title}"'
```

Discovery rules:

- current tmux window is the task workspace
- find exact pane title `pi-manager`; this should be the current/orchestrator pane
- find exact pane title `pi-worker`; send implementation/fix prompts here
- find exact pane title `claude-worker`; send review/debate prompts here
- if any title is missing or duplicated, stop and ask the user to fix pane titles
- verify `pi-manager`, `pi-worker`, and `claude-worker` panes resolve to the same git root
- store pane IDs in `config.yml`

Resume rule:

- assume tmux state did not change
- verify stored pane IDs still exist
- do not rediscover by title on resume
- if any pane ID is gone, pause and ask the user to restore panes or restart cleanly

## Prompt delivery

`/autowork` writes prompt files and sends only the file path to the target pane.

Prompt submission must use the helper's tested literal-text path with a short configurable delay before Enter:

```sh
tmux send-keys -t "$claude_target" -l "Please read and follow: <prompt_file>"
sleep "${AUTOWORK_SEND_SUBMIT_DELAY_SECONDS:-0.2}"
tmux send-keys -t "$claude_target" Enter
```

Do not paste large prompt bodies into tmux panes. Do not bypass `Tmux#send_prompt` for manager fixes; `autowork manager-review-fix` owns delivery, status waits, commits, checks, and reviews.

Agents write their own review, debate, resolution, and status content into the assigned files.
`/autowork` coordinates the sequence.

For routine targeted checks, prompts should steer agents toward globally safe read-only commands such as `test -f`, `cmp`, `git show`, `git diff --exit-code`, `git diff-tree --no-commit-id --name-only -r HEAD`, and `git status --short`. Avoid heredoc interpreters such as `python3 - <<'PY'`, `ruby <<'RUBY'`, or `node <<'JS'` for content checks. Also avoid command substitution, backticks, and process substitution such as `$()`, `` `cmd` ``, `<(...)`, or `>(...)`; these trigger broad shell execution permissions and are usually unnecessary for autowork QA. For exact text checks, avoid literal multiline expected strings; prefer one argument per expected line, such as `printf '%s\n' 'line 1' 'line 2' | cmp -s - path/to/file`. When reviewing a clean worktree after `/autowork` committed, compare expected content directly against the repo file path instead of using `git show` through process substitution.

For file setup during implementation/fix turns, prompts should steer agents toward safe idempotent commands where possible, such as `mkdir -p qa-output` instead of `mkdir qa-output`, so retries/resumes do not fail on existing directories. Implementation and fix agents should create/update requested files first, then run verification checks; do not run exact-content checks for files the current turn is about to create before writing them.

## Status files

Use JSON status files, not empty `.done` markers.

Required fields:

```json
{
  "status": "done",
  "agent": "pi",
  "phase": "implement",
  "step": 1,
  "summary": "..."
}
```

Allowed statuses:

```text
done
needs_user
failed
```

Allowed agents:

```text
pi
claude
```

Common phases:

```text
implement
review
classify
fix
debate
final_checks
super_review
final_review
super_fix
super_fix_review
manager_fix
manager_fix_review
```

A completed `manager_fix_review` status must include a `findings` array, including an empty array for an accepted fix. `needs_user` and `failed` statuses may omit `findings`. If a status file is missing or invalid, ask the responsible agent once to rewrite it correctly. If still invalid, pause and ask the user.

If an agent needs user input, it writes:

```json
{
  "status": "needs_user",
  "agent": "claude",
  "phase": "review",
  "step": 1,
  "summary": "Need product decision",
  "question": "..."
}
```

Then `/autowork` pauses and surfaces the question.

## Waiting-stage banners

While the manager waits for a worker status file, it prints the current stage in this format:

```text
==================
[PI FINAL REVIEW]
==================
```

For step-scoped stages, the banner also includes the current plan heading, for example `[PI WORKER IMPLEMENTATION — Step 1: Build the parser]`.

The human-readable stage names map from the internal `waiting_for_*` phase and worker role:

- `pi:implement` — `PI WORKER IMPLEMENTATION`
- `claude:review` — `CLAUDE STEP REVIEW`
- `pi:classify` — `PI FINDING CLASSIFICATION`
- `pi:fix` — `PI STEP FIX`
- `claude:debate` / `pi:debate` — `CLAUDE DEBATE` / `PI DEBATE`
- `claude:final_checks` / `pi:final_checks` — `CLAUDE FINAL-CHECK REVIEW` / `PI FINAL-CHECK FIX`
- `claude:super_review` — `CLAUDE FINAL SUPER-REVIEW`
- `pi:final_review` — `PI FINAL REVIEW`
- `pi:super_fix` / `claude:super_fix_review` — `PI SUPER-REVIEW FIX` / `CLAUDE SUPER-REVIEW FIX REVIEW`
- `pi:manager_fix` / `claude:manager_fix_review` — `PI MANAGER FIX` / `CLAUDE MANAGER-FIX REVIEW`

## Waiting, worker timeout, pause, resume

Foreground wait model:

1. send prompt to Pi or Claude pane
2. wait up to the worker status timeout for expected status JSON
3. if status arrives, continue
4. if the worker status timeout expires, stop cleanly and report the current waiting phase and expected status path
5. user inspects the visible pane and/or state file
6. rerun `/autowork` only when the operator intends to resume orchestration

Timeout model:

- `/autowork` should not have a meaningful manager timeout. The manager process should not be killed by a short shell/tool timeout during normal operation.
- Timeouts belong to worker waits: `pi-worker` / `claude-worker` must write expected status JSON within `worker_status_timeout_minutes`.
- If invoking the Ruby helper through a shell tool, do not set a short timeout on the manager command. Prefer no outer timeout. If the tool requires one, use a long safety cap that comfortably exceeds the expected whole run; never use the worker status timeout as the manager command timeout.
- If an outer shell/tool timeout is unavoidable, it must be longer than the expected whole manager run. It is a safety cap, not part of autowork's protocol.

Important resume UX:

- Rerunning `/autowork` is not a read-only status check. It may continue the state machine immediately and can stage/commit if the worker finished while the manager process was not running.
- If the manager process was killed by an outer shell/tool timeout, do not rerun `/autowork` automatically. The previous request no longer counts as approval to resume. Read-only inspection is OK; rerun only after the operator gives a fresh explicit continue/resume instruction.
- Use `autowork status <task_folder>` or read `autowork-log/state.json` for safe inspection.
- Do not auto-resend an in-flight prompt on resume. Resume by checking whether the expected status file now exists.

Manual pause:

```sh
touch <task_folder>/autowork-log/control/pause
```

At safe checkpoints, if this file exists, write paused state and exit. Resume after the user removes it and invokes `/autowork` again.

Safe checkpoints include:

- before sending a prompt
- after Pi status, before commit
- after commit, before Claude review
- after Claude review, before Pi fixes
- between debate rounds
- before final checks

## Git ownership

Invoking `/autowork` is explicit permission for that run to stage and commit changes according to this protocol.

Allowed by `/autowork` invocation:

```sh
git add -A
git commit -m "Step N"
git commit -m "Step N fix M"
git commit -m "Final checks fix M"
git commit -m "Manager review fix M"
```

Also allowed by `/autowork` invocation during preflight only:

- `/workit ... create-steps-only` may perform its documented task-branch setup/verification, including the Shortcut branch create/switch path for projects registered with `task_provider: shortcut` when safe and unambiguous.

Still forbidden unless separately approved:

- push
- force-push
- reset
- rebase
- merge
- branch switch/create/delete outside the documented `/workit create-steps-only` preflight
- stash
- tag changes

Rules:

- require clean worktree at start
- require clean worktree before every Pi prompt
- Pi may leave dirty changes after implementation/fix
- `/autowork` stages all changes after a clean-baseline Pi unit
- `/autowork` owns all commits
- `/workit step N` and Pi fix prompts must not commit
- before Claude reviews, worktree must be clean
- after Claude review/debate, worktree must remain clean

No-code debate/resolution iterations do not create empty commits. They are tracked in `autowork-log/` only.

## Commit naming

Use short names:

```text
Step 1
Step 1 fix 1
Step 1 fix 2
Step 2
Step 2 fix 1
Final checks fix 1
Manager review fix 1
```

Core invariant:

```text
Pi must never produce two code-changing commits in a row without Claude reviewing the last commit.
```

Because `/autowork` owns commits, this means every `/autowork` code-changing commit is followed by Claude review before another code-changing Pi commit.

## Claude review protocol

Claude reviews should follow `/gtm-revit`-style rules, not a minimal blocker-only review.

Important: `/gtm-revit` does not require running RuboCop or RSpec. During normal step reviews, Claude should not run RSpec, RuboCop, linters, formatters, or any other test/check command — not full-suite and not targeted. Claude should inspect the diff/files and Pi's reported `checks_run`. Pi may run targeted checks during implementation/fix turns, and `/autowork` runs configured full final checks after all planned steps are accepted.

Claude should suggest everything that makes sense according to `/gtm-revit` rules and classify checklist items with:

```text
PASS
MINOR
BLOCKER
```

Expected summary shape:

```text
Summary: <N> BLOCKER / <M> MINOR / <K> PASS
Recommendation: accept | fix | split
```

`/autowork` prompt should ask Claude to review the last commit against the current step only:

- read `task.md`
- read `steps.md`
- use full `steps.md` for context
- scope findings to current `Step N`
- do not require future-step behavior unless current changes block or contradict future work
- do not edit repo files
- do not run RSpec, RuboCop, linters, formatters, or any other test/check command during step review — not full-suite and not targeted
- write review to the assigned `autowork-log/reviews/...` file
- write status JSON when done

## Handling findings

Claude review status JSON must include a machine-readable `findings` array. Use an empty array when there are no `BLOCKER` or `MINOR` findings. Each actionable finding should include `id`, `severity`, `title`, `body`, and `recommendation`.

After Claude review, Pi classifies all findings at once in a resolution file:

```text
autowork-log/resolutions/step1_pi_review1_result.md
```

For each finding, Pi chooses one:

```text
accept
accept_with_alternative_fix
dispute
follow_up
needs_user
```

Rules:

- Valid findings that are clearly in this task's scope must be fixed now, even when the fix naturally belongs to a later step.
- `MINOR` findings must be fixed now, even when they are outside this task's original scope, as long as they are minor/local/low-risk.
- Use `follow_up` only for valid non-minor findings that are outside this task's scope; `/autowork` carries them into `final_summary.md` instead of debating/fixing them.
- Use `dispute` only when the finding is invalid, not reachable, or contradicted by repo/task evidence.
- `needs_user` pauses immediately when product/scope input is required.
- Accepted fixes are implemented first.
- `/autowork` commits accepted code changes.
- Claude reviews the fix commit.
- Remaining disputes are recorded in `autowork-log/debates/stepN_debates.md` and debated up to `max_debate_rounds_per_disagreement`.
- If Claude agrees with Pi during debate, the finding is treated as resolved without code changes.
- If Pi accepts Claude's position during debate, `/autowork` sends a normal fix prompt, commits the fix, and sends it back to Claude for review.
- If both agents still disagree after the round limit, `/autowork` pauses for user arbitration. This pause is intentional because the manager cannot decide which agent is correct.

## Disagreement procedure

Disagreement escalation starts when Pi disputes a Claude finding or fix requirement:

- Claude says `BLOCKER`, Pi thinks it is invalid or not reachable
- Claude says `MINOR`, Pi thinks it is invalid or not reachable
- Claude suggests fix A, Pi thinks fix B is better
- Claude says prior fix is still wrong

Per-step debate file:

```text
autowork-log/debates/step1_debates.md
```

Each disagreement gets its own section:

```md
## D1 — Review 1 finding B: <short title>

### Round 1 — Claude
...

### Round 1 — Pi
...
```

`/autowork` facilitates debate rounds, but it must not pick a winner between Pi and Claude on its own.

Round flow:

1. send Pi's dispute/defer rationale to Claude
2. Claude either agrees with Pi or still disagrees
3. if Claude still disagrees, send Claude's response back to Pi
4. Pi either accepts and requests a fix turn, or still disagrees
5. repeat until agreement or `max_debate_rounds_per_disagreement`

If agreement happens:

- Claude agrees with Pi: no code change is required for that finding; continue to the next debate/finding/step
- Pi accepts Claude's concern: send a fix turn, commit it as `Step N fix M`, then send the fix commit back to Claude for review

If still unresolved after the round limit, pause for operator arbitration. After the operator decides:

- if a fix is needed, continue with an explicit instruction so Pi can implement it and `/autowork` can commit/re-review it
- if the finding is rejected or deferred, keep the rationale in the disagreement file and continue only with explicit operator approval

The `debates/` directory stores disagreement records and per-round responses.

## Final checks

Skip orchestrator-enforced checks between intermediate steps/fixes.
Pi may run targeted checks and report them, but `/autowork` does not block intermediate commits on tests.

After all planned steps pass Claude review, run configured final checks.
For Ruby projects with a `Gemfile`, default to:

```sh
bundle exec rubocop
bundle exec rspec
```

For non-Ruby or unconfigured repos, record final checks as skipped with a clear reason.

Final checks run through a non-login shell (`bash -c`) so the manager pane environment, including asdf shims in `PATH`, is preserved. Do not use `bash -lc` here; on macOS login-shell startup can reset `PATH` to system Ruby and make `bundle` resolve to `/usr/bin/bundle`.

If final checks fail:

1. write `final_checks.md`
2. send the failure output to Pi
3. Pi fixes without committing, or reports that no repo fix is needed
4. if Pi changed repo files, `/autowork` commits `Final checks fix M`
5. if Pi made no repo changes, `/autowork` reruns final checks without creating an empty commit
6. when checks pass, send any final-check fix commits to Claude for review
7. Claude reviews final-check fix commits without running RSpec, RuboCop, linters, formatters, or any other test/check command; it reads `final_checks.md` and inspects the fix commits
8. if Claude finds issues, send them to Pi as another final-check fix iteration
9. repeat until checks pass and Claude accepts, or until `max_final_check_fix_iterations` is hit

After final checks pass and any final-check fix commits are accepted, run the final super-review gate described above. The gate runs Claude's whole-branch review and resolves all Claude findings first, including scoped review of super-review fixes. Only then does it run the Pi-worker final review. Then stop at `ready_for_manager_final_review` so pi-manager can perform a manager-context production-readiness review using the original conversation, task creation, grilling, scope, and other manager-only context.

## Manager-context finding loop

The manager gate is the only phase that can use manager-only conversation context. It must still use the orchestrator for any code-changing response.

If manager review finds actionable issues:

1. Write all findings in one pass to the exact `manager_reviews/manager_reviewN_findings.json` path printed by `/autowork` and listed in `manager_review.md`.
2. Use this shape. Manager findings must use the existing autowork actionable severity vocabulary: `BLOCKER` or `MINOR`. Each gate also preserves a per-iteration human-readable copy at `manager_reviews/manager_reviewN.md`; `manager_review.md` is the current-gate copy.
   ```json
   {
     "summary": "Why manager review did not pass",
     "findings": [
       {
         "id": "MR1",
         "severity": "BLOCKER",
         "title": "Short title",
         "body": "What is wrong and why it matters",
         "recommendation": "Concrete required fix"
       }
     ],
     "followups": []
   }
   ```
3. Invoke `autowork manager-review-fix <task_folder>` immediately. The original `/autowork` invocation grants this manager loop permission to stage and commit according to the protocol; do not ask the user to route each finding.
4. The helper validates the findings and clean branch, sends a Pi fix prompt through `Tmux#send_prompt`, waits for status JSON, commits `Manager review fix N`, reruns configured full final checks, and sends the commit to Claude for scoped review.
5. If Claude finds issues in the manager fix, `/autowork` sends all of them back to Pi in the next manager-fix iteration. Pi may request user input but may not silently defer or dispute a manager-context requirement.
6. When Claude accepts, `/autowork` returns to a fresh `ready_for_manager_final_review` gate. Pi-manager reviews the final result again using manager-only context.
7. Only `autowork manager-review-pass <task_folder>` marks the run complete.

Do not manually call `tmux send-keys`, stage, commit, or construct ad hoc manager-fix status files. Normal resume rules apply if a worker timeout interrupts the manager-fix loop.

Finish only when final checks pass, final-check fix commits are accepted, all Claude super-review findings and fix reviews are resolved, the Pi final review has completed, every manager-fix commit has passed scoped Claude review, and pi-manager records that the result is production-ready if the user does not perform another review. Successful completion writes `final_summary.md`.

## Limits

Default safety limits:

```yaml
max_fix_iterations_per_step: 10
max_debate_rounds_per_disagreement: 5
max_final_check_fix_iterations: 5
max_super_review_fix_iterations: 3
max_manager_review_fix_iterations: 5
max_total_commits: 15
max_runtime_hours_per_run: 1
starting_head_commit: <sha>
worker_status_timeout_minutes: 10
super_review_status_timeout_minutes: 20
run_final_super_review: true
original_review_base_ref: main | master | <full-base-branch-or-ref>
original_review_base_commit: <sha-or-null>
review_base_ref: main | master | <full-base-branch-or-ref>
review_base_commit: <sha-or-null>
```

The commit limit counts implementation, step-fix, final-check-fix, super-review-fix, and manager-review-fix commits together. It is checked before every commit.

If a limit is hit:

- write paused state
- write `autowork-log/paused_reason.md`
- stop and ask the user whether/how to continue

## Final output

At the manager review gate, write:

```text
autowork-log/final_summary.md
autowork-log/manager_review.md
```

Include:

- task path
- repo path
- steps completed
- commits created
- reviews and outcomes
- debates and final decisions
- final checks and results
- final super-review, Pi final-review, and super-review fix outcomes
- manager-context production-readiness review result
- any unresolved caveats

Then stop and tell pi-manager where to review. If findings exist, write the printed structured findings file and route it with:

```text
autowork manager-review-fix <task_folder>
```

After the automated fix/check/Claude-review loop returns to a fresh manager gate, review again. If the manager-context review passes, record completion with:

```text
autowork manager-review-pass <task_folder>
```

Final output after that pass:

```text
/autowork complete. Production-readiness manager review passed.
- summary: <task_folder>/autowork-log/final_summary.md
- manager review: <task_folder>/autowork-log/manager_review.md
```

No push, no PR creation, no squash.

## Implementation notes

Planned implementation shape:

```text
/Users/inseybo/.ai/skills-shared/autowork/
  SKILL.md
  TODO.md
  bin/
    autowork
  lib/
    autowork.rb
    tmux.rb
    git_repo.rb
    state.rb
    prompts.rb
```

The executable orchestrator should be implemented in Ruby under this skill folder.

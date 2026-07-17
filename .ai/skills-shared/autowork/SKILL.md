---
name: autowork
description: >-
  Pi-only command. Autonomously executes an existing task plan by coordinating
  visible Pi and Claude tmux panes, committing each code-changing iteration,
  collecting Claude reviews/debates, and running final checks. Invoke only via
  /autowork.
---

# Autowork

This is a **Pi-only command skill**.

Invoke only with:

```text
/autowork
/autowork <project-or-gtm-session> [task_id]
/autowork doctor
/autowork doctor --no-send-test
```

Do not auto-use this skill from general requests. Wait for explicit `/autowork`.
Claude is a participant in this workflow, not the orchestrator, and must not run this skill directly.

`/autowork doctor` is a permanent health/QA command. It should remain useful as the workflow grows.

## Current implementation status

V1 supports implementation, review, accepted fixes, re-review, bounded Pi/Claude debate facilitation, multi-step progression, final checks, automated final-check fix commits, final-check fix review, and final summary. It can initialize/resume a run, send a Step N implementation prompt to `pi-worker`, wait for Pi status JSON, commit `Step N`, send a review prompt to `claude-worker`, wait for Claude review status JSON, ask Pi to classify findings, commit accepted fixes as `Step N fix M`, re-review fix commits, run bounded debate rounds for disputed/deferred findings, advance through planned steps, run configured final checks, commit final-check fixes as `Final checks fix M`, ask Claude to review final-check fix commits, and write `final_summary.md`. If debate remains unresolved after the configured round limit, `/autowork` pauses for human arbitration because the manager must not decide which agent is correct.

Implemented helper:

```text
/Users/inseybo/.ai/skills-shared/autowork/bin/autowork
```

It currently resolves/validates a task, relies on `/workit ... create-steps-only` preflight to create/update `steps.md` and verify/setup the task branch, requires a clean repo for normal orchestration start, discovers tmux panes, creates `autowork-log/`, writes config/state, sends prompts with `tmux send-keys`, waits for status JSON, commits Step N implementations, sends Claude review prompts, asks Pi to classify review findings, commits accepted fixes, sends follow-up review prompts, advances through planned steps, runs final checks, writes `final_checks.md`, and writes `final_summary.md`.

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
11. Stop for user final review.

The user reviews the final result, not every intermediate step.

## Task resolution

Resolve task folders the same way `/draftit`, `/taskit`, and `/workit` do.
Use the shared task-resolution rules from:

```text
/Users/inseybo/.ai/skills-shared/components/task-resolution.md
```

`/autowork` requires the selected task folder to contain `task.md`. It also requires `steps.md` before the Ruby helper starts, but `/autowork` owns a preflight that creates or updates `steps.md` through `/workit` when needed.

Preflight before running the Ruby helper:

1. resolve the same `<project-or-gtm-session> [task_id]` arguments that `/autowork` will pass to the helper
2. if `<task_folder>/steps.md` is missing, invoke:
   ```text
   /workit <project-or-gtm-session> [task_id] create-steps-only
   ```
3. if branch setup/verification is needed, rely on `/workit create-steps-only` to use the documented `/workit`/`/taskit` branch rules; for GTM Shortcut tasks this means the branch slug comes from the current Shortcut story `name`, fetched through the shared Shortcut CLI, not from the task folder suffix
4. if `/workit create-steps-only` stops for a branch decision or plan problem, stop `/autowork` before running the helper and surface that decision to the user
5. after preflight succeeds, run the Ruby helper normally

If `steps.md` already exists, `/autowork` may skip plan creation, but it must still not proceed on a forbidden branch. The Ruby helper also requires `steps.md` and will fail fast if the preflight did not create it.

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

  reviews/
    step1_claude_review1_result.md
    step1_claude_review2_result.md

  debates/
    step1_debates.md
    step2_debates.md

  resolutions/
    step1_pi_review1_result.md
    step1_pi_review2_result.md

  status/
    step1_pi_implement_status.json
    step1_claude_review1_status.json
    step1_pi_fix1_status.json

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

Example tmux send:

```sh
tmux send-keys -t "$claude_target" "Please read and follow: <prompt_file>" C-m
```

Do not paste large prompt bodies into tmux panes.

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
```

If a status file is missing or invalid, ask the responsible agent once to rewrite it correctly. If still invalid, pause and ask the user.

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
```

Also allowed by `/autowork` invocation during preflight only:

- `/workit ... create-steps-only` may perform its documented task-branch setup/verification, including the GTM Shortcut branch create/switch path from `/taskit` when safe and unambiguous.

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
```

Core invariant:

```text
Pi must never produce two code-changing commits in a row without Claude reviewing the last commit.
```

Because `/autowork` owns commits, this means every `/autowork` code-changing commit is followed by Claude review before another code-changing Pi commit.

## Claude review protocol

Claude reviews should follow `/gtm-revit`-style rules, not a minimal blocker-only review.

Important: `/gtm-revit` does not require running RuboCop or RSpec. During normal step reviews, Claude should not run full RuboCop or full RSpec. Pi may run targeted checks during implementation/fix turns, and `/autowork` runs configured full final checks after all planned steps are accepted.

Claude should suggest everything that makes sense according to `/gtm-revit` rules and classify checklist items with:

```text
PASS
MINOR
BLOCKER
```

Expected summary shape:

```text
Summary: <N> BLOCKER / <M> MINOR / <K> PASS
Recommendation: merge | amend | split
```

`/autowork` prompt should ask Claude to review the last commit against the current step only:

- read `task.md`
- read `steps.md`
- use full `steps.md` for context
- scope findings to current `Step N`
- do not require future-step behavior unless current changes block or contradict future work
- do not edit repo files
- do not run full RuboCop or full RSpec during step review
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
defer_minor
needs_user
```

Rules:

- `BLOCKER` findings must be fixed or debated.
- `MINOR` findings should be applied if they are cheap/local/low-risk.
- Pi may defer a `MINOR` when it is larger, risky, out of step scope, or not worth destabilizing the step.
- Accepted fixes are implemented first.
- `/autowork` commits accepted code changes.
- Claude reviews the fix commit.
- Remaining disputes are recorded in `autowork-log/debates/stepN_debates.md` and debated up to `max_debate_rounds_per_disagreement`.
- If Claude agrees with Pi during debate, the finding is treated as resolved without code changes.
- If Pi accepts Claude's position during debate, `/autowork` sends a normal fix prompt, commits the fix, and sends it back to Claude for review.
- If both agents still disagree after the round limit, `/autowork` pauses for user arbitration. This pause is intentional because the manager cannot decide which agent is correct.

## Disagreement procedure

Disagreement escalation starts when Pi does not simply apply a Claude finding:

- Claude says `BLOCKER`, Pi thinks it is not a blocker
- Claude says `MINOR`, Pi wants to defer
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
7. Claude reviews final-check fix commits without rerunning full RuboCop/RSpec; it reads `final_checks.md` and inspects the fix commits
8. if Claude finds issues, send them to Pi as another final-check fix iteration
9. repeat until checks pass and Claude accepts, or until `max_final_check_fix_iterations` is hit

Finish when final checks pass or are explicitly skipped because no final check commands are configured, and Claude has accepted any final-check fix commits. Successful completion writes `final_summary.md`.

## Limits

Default safety limits:

```yaml
max_fix_iterations_per_step: 10
max_debate_rounds_per_disagreement: 5
max_final_check_fix_iterations: 5
max_total_commits: steps_count * 3
max_runtime_hours_per_run: 1
worker_status_timeout_minutes: 10
```

If a limit is hit:

- write paused state
- write `autowork-log/paused_reason.md`
- stop and ask the user whether/how to continue

## Final output

At the end, write:

```text
autowork-log/final_summary.md
```

Include:

- task path
- repo path
- steps completed
- commits created
- reviews and outcomes
- debates and final decisions
- final checks and results
- any unresolved caveats

Then stop and tell the user where to review:

```text
/autowork complete. Review final result:
- git log range: ...
- summary: <task_folder>/autowork-log/final_summary.md
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

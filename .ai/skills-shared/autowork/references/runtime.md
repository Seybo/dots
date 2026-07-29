# Runtime mechanics — log layout, tmux, prompt delivery, status files, waiting

Read this file when operating or debugging a live run.

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
    step1_pi_blind_audit_request.md
    step1_reviewer_review1_request.md
    step1_pi_fix1_request.md
    step1_debate_D1_round1_reviewer_request.md
    step1_debate_D1_round1_pi_request.md
    final_super_review1_request.md
    final_pi_review1_request.md
    super_review_pi_fix1_request.md
    super_review_fix_reviewer_review1_request.md

  reviews/
    step1_pi_blind_audit_result.md
    step1_reviewer_review1_result.md
    step1_reviewer_review2_result.md

  debates/
    step1_debates.md
    step2_debates.md

  resolutions/
    step1_pi_review1_result.md
    step1_pi_review2_result.md

  super_fixes/
    super_review_pi_fix1_result.md
    super_review_fix_reviewer_review1_result.md

  manager_reviews/
    manager_review1.md
    manager_review1_findings.json

  manager_fixes/
    manager_review_pi_fix1_result.md
    manager_review_fix_reviewer_review1_result.md

  status/
    step1_pi_implement_status.json
    step1_pi_audit_status.json
    step1_codex_review1_status.json
    step1_pi_fix1_status.json
    step0_codex_super_review1_status.json
    step0_pi_final_review1_status.json
    step0_pi_super_fix1_status.json
    step0_codex_super_fix_review1_status.json
    step0_pi_manager_fix1_status.json
    step0_codex_manager_fix_review1_status.json

  final_checks.md
  review-risk-manifest.json
  super-review.md
  super-review-adjudication1.json
  pi-final-review.md
  manager_review.md
  final_summary.md
```

`autowork-log/` lives only in the task folder and should not be committed to the feature repo.

Reviewer prompt/result artifact names are provider-neutral. Runs created before this naming change may retain `claude` in existing prompt/result filenames; the helper continues to honor those paths so interrupted runs can resume safely. Status filenames remain agent-specific and use the configured reviewer (`codex` by default).

## Tmux model

The user manually starts visible terminal agents in the same tmux window.

`/autowork` runs from the `agent-manager` pane and uses the current tmux window. That window must have exactly one pane with each exact title:

```text
agent-manager
agent-worker
agent-reviewer
```

Initial discovery uses the current tmux window:

```sh
tmux list-panes -F '#{pane_index} #{pane_id} "#{pane_title}"'
```

Discovery rules:

- current tmux window is the task workspace
- find exact pane title `agent-manager`; this should be the current/orchestrator pane
- find exact pane title `agent-worker`; send implementation/fix prompts here
- find exact pane title `agent-reviewer`; send review/debate prompts here
- if any title is missing or duplicated, stop and ask the user to fix pane titles
- verify `agent-manager`, `agent-worker`, and `agent-reviewer` panes resolve to the same git root
- store pane IDs as `agent_manager_target`, `agent_worker_target`, and `agent_reviewer_target` in `config.yml`
- store `super_review_agent` as `codex` (default) or `claude`; `agent-reviewer` must run that selected software

Resume rule:

- normal `/autowork` keeps the stored pane targets and waits for the current worker result
- `/autowork --retry` means the operator confirms workers are no longer running; rediscover exact pane titles in the current window, verify their git roots, and update stored targets before resending the interrupted stage
- if a required title is missing or duplicated, stop and ask the user to fix pane titles

## Prompt delivery

`/autowork` writes prompt files and sends only the file path to the target pane.

Prompt submission must use the helper's tested literal-text path with a short configurable delay before Enter:

```sh
tmux send-keys -t "$reviewer_target" -l "Please read and follow: <prompt_file>"
sleep "${AUTOWORK_SEND_SUBMIT_DELAY_SECONDS:-0.2}"
tmux send-keys -t "$reviewer_target" Enter
```

Do not paste large prompt bodies into tmux panes. Do not bypass `Tmux#send_prompt` for manager fixes; `autowork manager-review-fix` owns delivery, status waits, commits, checks, and reviews.

Agents write their own review, debate, resolution, and status content into the assigned files. `/autowork` coordinates the sequence.

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

Allowed statuses: `done`, `needs_user`, `failed`. Allowed agents: `pi`, `claude`, `codex`. Reviewer status filenames and the JSON `agent` value use the configured `super_review_agent`.

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
  "agent": "codex",
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

The human-readable stage names map from the internal phase and selected agent. Reviewer stages are labeled `CLAUDE ...` or `CODEX ...` accordingly:

- implementation/audit/classification/fix stages — `PI ...`
- step review/debate — `<CLAUDE|CODEX> STEP REVIEW` / `<CLAUDE|CODEX> DEBATE`
- final-check review — `<CLAUDE|CODEX> FINAL-CHECK REVIEW`
- final super-review — `<CLAUDE|CODEX> FINAL SUPER-REVIEW`
- scoped super-review/manager-fix reviews — `<CLAUDE|CODEX> ... REVIEW`
- final Pi review and code-changing fixes — `PI ...`

## Waiting, worker timeout, pause, resume

Foreground wait model:

1. send the prompt to `agent-worker` or `agent-reviewer`
2. wait up to the worker status timeout for expected status JSON
3. if status arrives, continue
4. if the worker status timeout expires, stop cleanly and report the current waiting phase and expected status path
5. user inspects the visible pane and/or state file
6. rerun `/autowork` only when the operator intends to resume orchestration

Timeout model:

- `/autowork` should not have a meaningful manager timeout. The manager process should not be killed by a short shell/tool timeout during normal operation.
- Timeouts belong to worker waits: `agent-worker` / `agent-reviewer` must write expected status JSON within `worker_status_timeout_minutes`.
- If invoking the Ruby helper through a shell tool, do not set a short timeout on the manager command. Prefer no outer timeout. If the tool requires one, use a long safety cap that comfortably exceeds the expected whole run; never use the worker status timeout as the manager command timeout.
- If an outer shell/tool timeout is unavoidable, it must be longer than the expected whole manager run. It is a safety cap, not part of autowork's protocol.

Important resume UX:

- Rerunning `/autowork` is not a read-only status check. It may continue the state machine immediately and can stage/commit if the worker finished while the manager process was not running.
- If the manager process was killed by an outer shell/tool timeout, do not rerun `/autowork` automatically. The previous request no longer counts as approval to resume. Read-only inspection is OK; rerun only after the operator gives a fresh explicit continue/resume instruction.
- Use `autowork status <task_folder>` or read `autowork-log/state.json` for safe inspection.
- Plain `/autowork` does not resend an in-flight prompt; it waits for the current status file.
- `/autowork --retry` explicitly abandons that wait and resends the current `waiting_for_*` stage. Prompt generation deletes that attempt's expected status file or allocates a new numbered attempt path before sending. It requires the operator to have stopped the workers first.

Manual pause:

```sh
touch <task_folder>/autowork-log/control/pause
```

At safe checkpoints, if this file exists, write paused state and exit. Resume after the user removes it and invokes `/autowork` again.

Safe checkpoints include:

- before sending a prompt
- after Pi status, before commit
- after commit, before reviewer pass
- after reviewer pass, before Pi fixes
- between debate rounds
- before final checks

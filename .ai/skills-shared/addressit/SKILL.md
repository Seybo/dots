---
name: addressit
description: >-
  agent-manager command that fetches GitHub PR review comments, asks the operator to
  approve a classified batch, coordinates worker and reviewer agents in tmux, consolidates
  each review round into one commit, and waits for final agent-manager review.
  Command-only skill. In Pi, invoke via /skill:addressit; /addressit is also
  accepted where that alias is exposed.
disable-model-invocation: true
---

# Addressit

This is an **agent-manager-only command skill**. The selected reviewer is a review
participant and must not invoke addressit.

Helper:

```text
/Users/inseybo/.ai/skills-shared/addressit/bin/addressit
```

## Invocation state (mandatory)

If Pi presents this skill as a `<skill name="addressit">` block, an explicit
`/skill:addressit` command has already been invoked. Do not ask the user to
invoke it again or downgrade the request to a general review request.

`disable-model-invocation: true` disables automatic invocation; it does not
block explicit user invocation.

Pi appends command arguments verbatim. With no PR target, the helper discovers
the current branch's pull request through `gh pr view`. Pass an explicit PR
number or GitHub PR URL only when addressing a different pull request. The helper
accepts:

```text
addressit [pr-number-or-github-url] [filters] [--task <local-task-id>] [--clipboard] [--agent claude|codex]
```

## Invocation

```text
/skill:addressit [pr-number-or-github-url] [filters] [--task <local-task-id>] [--clipboard] [--agent claude|codex]
/addressit [pr-number-or-github-url] [filters] [--task <local-task-id>] [--clipboard] [--agent claude|codex]
```

Examples:

```text
/addressit
/addressit --task 0001
/addressit --agent claude
/addressit 123
/addressit https://github.com/org/repo/pull/123
/addressit 123 comments from @octocat
/addressit 123 comments since 12 hours ago
/addressit 123 comments from @octocat since 2026-06-04T09:00:00Z
```

Codex is the default reviewer. Pass `--agent claude` to use Claude, or
`--agent codex` explicitly when desired. Addressit persists the selected agent for
the run. Existing runs without `review_agent` migrate to Claude for compatibility.
Changing agents after the reviewer stage has begun is rejected; select the agent before that stage or for the next round.

Do not auto-use this skill from a general review-related request. Wait for an
explicit `/addressit` invocation.

## Task and branch preflight

Addressit uses the current checkout and the same project/task resolution rules as
`/autowork` and `/workit`:

1. infer the project from the current checkout using the shared registry
2. use `--task <local-task-id>` for an arbitrary local/ad-hoc branch, or infer
   the task/story ID from an `sc-<digits>` branch segment
3. require exactly one matching folder under `/Volumes/dev/_tasks/<project>/`
4. require that folder to contain `task.md`
5. when starting a new addressit run (no `addressit-log/state.json`), go to the
   related task repo root at `/Volumes/dev/_tasks/<project>/` and stage changes only
   from finished task folders. A task is finished when autowork state is `status:
   done` and `phase: complete`; an existing addressit state must also be
   `phase: complete`, but missing addressit state is allowed. Include
   `review-risk-registry.json` only when no other task has an active autowork or
   addressit state. Commit the selected changes as `save`; skip when there are no
   selected changes and stop if staging or committing fails
6. require a clean worktree
7. require current-window tmux panes titled exactly `agent-manager`, `agent-worker`,
   and `agent-reviewer`, all rooted at the same repository

If no task folder can be found, report that fact and stop. Do not create a task
folder, suggest a creation command, or create partial addressit state.

Addressit never pushes. It commits locally; the operator pushes the branch and
waits for GitHub to receive any new review comments before invoking addressit
again.

## Round workflow

The operator is the polling mechanism. Each explicit invocation handles one
snapshot of unresolved/new comments:

1. Fetch inline PR review comments through `gh api`, or read the copied local review with `pbpaste` when `--clipboard` is used.
2. Apply the existing PR URL, reviewer, time, and specific-comment/review filters in GitHub mode.
3. Keep exactly two terminal comment-ID arrays in state: `addressed_ids` and
   `skipped_ids`.
4. Ignore a comment when its GitHub comment ID is in either array. An ID in either
   array is terminal and must never be selected again.
5. Save the selected comments under `<task_folder>/addressit-log/`.
6. Stop and show the concise selected-comment list. Do not launch agent-worker yet.

Review summaries and issue-level PR comments are not included by default. Use the
existing explicit all-comments behavior when those are requested. A clipboard review is
imported as one review item, preserving its full text for classification and worker prompts.

A round has one universal approval gate. agent-manager must read the saved full
comment artifact and classify every selected comment.

COPYABLE OUTPUT - HARD RULE: Never use Markdown tables, ASCII tables, aligned
columns, or other cell-based layouts in any Addressit user-facing response. Table
cells and wrapped columns are difficult to select in terminal UIs.

At the initial approval gate, show every selected comment in a separate numbered
Markdown block. Do not show classifications without the full comment text. Include
its path, full text, classification, validity, proposed decision, and reason. When
a selected GitHub comment is a reply, fetch its direct parent through `gh api` and
include the parent text as thread context before the selected reply. Preserve the
comment text verbatim except for removing GitHub badge markup. Include only the
direct parent and selected reply unless the operator asks for the complete thread.

```markdown
### 1. Comment 123456789

Path: `app/services/example.rb:42`
URL: https://github.com/org/repo/pull/123#discussion_r123456789

> **Comment title, if present**
>
> Full selected comment text, with its paragraphs and code preserved.

**Author reply**

> Full selected reply text.

Classification: minor
Valid: yes
Proposed decision: approved
Reason: The concrete, copyable explanation, including file/line context when useful.

---

### 2. Comment 123456790

Path: `app/services/example.rb:88`
URL: https://github.com/org/repo/pull/123#discussion_r123456790

> Full selected comment text.

Classification: not_minor
Valid: no
Proposed decision: skipped
Reason: The concrete, copyable explanation.
```

Use `minor` or `not_minor` for Classification and `yes` or `no` for Valid. Keep
each reason as normal text rather than splitting it across columns. Apply this
format to initial triage, approval summaries, manual-verification findings, debate
summaries, and manager-gate findings. The initial approval gate must end by
explicitly stating that Addressit is waiting for a decision for every selected
comment.

Then wait for the operator. The operator may approve or correct the labels. The
operator's response must put every selected comment into exactly one state:

- `approved`: send it to agent-worker
- `skipped`: do not address it

No comment remains pending after the approval response. Approved comments include
minor comments. The helper writes the exact decision set to the round approval
JSON and launches the worker only after every selected comment has a decision.

## Command timeout safety

HARD RULE: Never set a tool timeout on an Addressit command that can wait for a
worker: `addressit`, `addressit approve`, `addressit audit-start`,
`addressit audit-reconcile`, `addressit manager-fix`, or `addressit resolve`.
These commands own the orchestration lock while they wait for a status artifact;
a timeout can terminate the helper before it advances the round. Run them without
a tool timeout. Use `addressit status <task_folder>` with a short timeout only
for read-only polling.

Approval JSON shape:

```json
{
  "comments": [
    {
      "id": "123456789",
      "minor": true,
      "valid": true,
      "decision": "approved",
      "rationale": "The reviewer is correct because ..."
    },
    {
      "id": "123456790",
      "minor": false,
      "valid": false,
      "decision": "skipped",
      "rationale": "This path is unreachable because ..."
    }
  ]
}
```

Before approving a finding, require a concrete trigger and evidence from provider documentation, observed data, or a credible normal execution path. A merely theoretical, near-impossible edge case is not actionable: classify it as low-likelihood/theoretical, skip it, and preserve the rationale in the approval or manager artifact instead of sending it to agent-worker. Do not add code or tests for it unless the operator confirms the risk matters.

For every new public method, argument, provider capability, abstraction, or related test, verify a production caller and an acceptance criterion in the current task. A unit test alone is not evidence that the surface is needed. Uncalled speculative surface must be removed or explicitly deferred as tech debt, not approved as extra scope.

The selected comments are one task batch. agent-worker receives one prompt for all
approved comments and leaves changes unstaged/uncommitted. Addressit may create
temporary commits while workers iterate, but it squashes every commit made in the
review round at the manager gate into exactly one final commit:

```text
Add review updates <N>
```

The final commit contains the implementation, reviewer-requested fixes, and any
agent-manager fixes from that round. Addressit resets implementation/fix/review
iteration counters at each new round. It selects `<N>` from existing round comment
artifacts and first-parent `Add review updates <N>` history, preventing duplicate
final names without storing round history in state. It does not create or modify `steps.md`
and does not invoke `/workit`.

## Blind audits, reviewer pass, and fix loop

After the combined implementation commit, addressit pauses for agent-manager to write
current-only review hypotheses. Do not read historical risk data yet. Resume with:

```text
addressit audit-start <task_folder> <hypotheses-json>
```

Addressit then sends agent-worker one blind, whole-diff audit. agent-worker must not read
the manager hypotheses, historical risk registry, or other audit artifacts. The
worker writes only its normal concise review artifact and structured findings.

Agent-generated findings from the blind audit, reviewer, or risk manifest are
actionable only when they contain non-empty `trigger`, `mechanism`, and `evidence`
fields plus one accepted `reachability_source`:

- `task_acceptance_criterion`
- `production_caller`
- `test_reproduction`
- `provider_documentation`
- `observed_runtime_data`
- `normal_execution_path`

They must also use `verification: actionable`. A test that proves isolated behavior
without a production caller is not reachability evidence. Missing fields, an
unsupported source, or `verification: needs_context` mechanically routes the finding
to operator verification; it cannot enter the automatic classification/fix loop.

After the Pi audit, Addressit sends the selected reviewer one normal review covering:

- every approved GitHub comment
- the complete current diff, not only comment locations
- regressions and risks outside the approved comments

The selected reviewer must independently review the diff and must not read the
manager hypotheses, historical registry, or Pi's blind audit. The reviewer does
not run tests, linters, or formatters during this review.

Addressit then pauses for agent-manager to read the project risk registry and write a
compact risk manifest with `coverage_gaps: []`. The manifest must also acknowledge
every hypothesis exactly once in `hypothesis_coverage`.

For every active registry risk that the current diff and audits confirm, include an
update for that existing risk ID in `registry_updates`, even when no new risk is
being added. Existing-ID updates record the task/round recurrence and recompute the
risk weight. Do not treat `registry_updates` as new entries only. Do not update a
risk merely because it was considered: omit unmatched or unconfirmed risks and
explain important exclusions in `manager_review.md`.

Resume with:

```text
addressit audit-reconcile <task_folder> <manifest-json>
```

The manifest may include generalized `registry_updates` and structured
`additional_findings`. The same evidence gate applies to those findings. No per-file
coverage inventory is required.

If any finding needs context, Addressit writes
`audits/round<N>_manual_verification.json` and pauses before incrementing the fix
iteration. The operator must classify every candidate in that artifact as `accept`
or `skip` with `addressit resolve`. Explicitly accepted findings may then enter the
fix loop; skipped findings do not. This gate applies only to agent-generated
findings—human PR comments still use the earlier operator approval gate.

If the reviewer or blind Pi audit reports findings:

1. agent-worker classifies every finding as accept, alternative fix, dispute,
   follow-up, or needs-user.
2. Accepted findings are fixed together in one Pi turn.
3. Addressit commits them temporarily and tracks them as part of round `<N>`.
4. The selected reviewer reviews the fix commit again.
5. Repeat until the reviewer accepts or operator input is required; all round commits
   are squashed at the final manager gate into `Add review updates <N>`.

If the selected reviewer reports findings:

1. agent-worker classifies every finding as accept, alternative fix, dispute,
   follow-up, or needs-user.
2. Accepted findings are fixed together in one Pi turn.
3. Addressit commits them temporarily and tracks them as part of round `<N>`.
4. The selected reviewer reviews the fix commit again.
5. Repeat until the reviewer accepts or operator input is required; all round commits
   are squashed at the final manager gate into `Add review updates <N>`.

If Pi and the selected reviewer disagree, use the bounded debate flow from `/autowork`. Do not
silently choose a winner. Pause for operator arbitration after three debate rounds
or when either worker requests user input. For a persisted user
arbitration pause, record one decision for every reviewer finding and resume with:

```text
addressit resolve <task_folder> <resolution-json>
```

The resolution JSON uses `finding_id` and `decision` (`accept` or `skip`).

## Waiting-stage banners

While agent-manager waits for a worker status file, addressit prints the current stage in this format:

```text
==================
[PI WORKER IMPLEMENTATION — Round 1]
==================
```

The stage names are:

- `PI WORKER IMPLEMENTATION`
- `PI BLIND AUDIT`
- `PI MANAGER FIX`
- `CODEX REVIEW` or `CLAUDE REVIEW`
- `CODEX FIX REVIEW` or `CLAUDE FIX REVIEW`
- `PI FINDING CLASSIFICATION`
- `CODEX DEBATE` or `CLAUDE DEBATE`
- `PI DEBATE`
- `PI FIX`

Each banner includes the current review round and, when applicable, the worker iteration.

## Checks and manager gate

Derive final checks from the current repository:

- Ruby repositories with a `Gemfile` default to:
  `bundle exec rubocop` and `bundle exec rspec`
- non-Ruby or unconfigured repositories record checks as skipped
- Pi may run focused checks during implementation/fix turns
- the selected reviewer does not rerun checks during review

After the selected reviewer accepts and final checks pass, Addressit stops at the
final agent-manager gate. agent-manager must review the original comments,
classifications, approvals, diff, temporary commits, blind audit, reviewer artifacts, risk manifest,
and final checks using manager-only conversation context. The project risk registry
is passive data; agent-manager reads it and may add only confirmed generalized lessons
through the final manifest. The manager pass then squashes all commits from
the round into `Add review updates <N>`. Write the result to:

```text
<task_folder>/addressit-log/manager_review.md
```

Only after that review passes may agent-manager run:

```text
addressit manager-pass <task_folder>
```

That command marks the approved comment IDs as `addressed`. Skipped IDs remain
`skipped`. Addressit does not mark comments addressed merely because the reviewer
accepted the code.

If manager review finds an issue, write a findings JSON file and run:

```text
addressit manager-fix <task_folder> <findings-json>
```

The helper sends the findings to agent-worker, creates a manager-fix commit, reruns
configured checks, sends the commit to the selected reviewer for scoped review,
and returns to a fresh manager gate.

## Persisted artifacts

```text
<task_folder>/addressit-log/
  state.json
  rounds/round<N>_comments.json
  rounds/round<N>_approval.json
  rounds/round<N>_resolutions.json  # only when agent findings require decisions
  prompts/
    round<N>_reviewer_review<I>_request.md
    round<N>_reviewer_debate<I>_request.md
  reviews/
    round<N>_reviewer_review<I>.md
  audits/
    round<N>_manager_initial_review_hypotheses.json
    round<N>_pi_blind_audit.md
    round<N>_risk_coverage_manifest.json
    round<N>_risk_reconciliation.json
    round<N>_manual_verification.json  # only when evidence is incomplete
  status/
    round<N>_pi_audit.json
    round<N>_codex_review<I>.json  # or claude
  debates/
  final_checks.md
  manager_review.md
```

Use read-only status inspection when needed:

```text
addressit status <task_folder>
```

The internal approval handoff is:

```text
addressit approve <task_folder> <approval-json>
addressit audit-start <task_folder> <hypotheses-json>
addressit audit-reconcile <task_folder> <manifest-json>
```

agent-manager uses this only after the operator has approved or skipped every
selected comment. Hypotheses must be non-empty objects with unique `id`, `kind`,
`check`, and `reason` strings. Reconciliation must include each hypothesis ID in
`hypothesis_coverage` with `status: "covered"` and a non-empty note.

`state.json` permanently stores only `review_agent`, `phase`, `addressed_ids`, and
`skipped_ids`. During an active round it also stores only the current round number,
Git checkpoints, commit SHAs, iteration counters, and an active operator question.
Addressit deletes those transient fields when the round is skipped, has no comments,
or completes. Comments, findings, decisions, reviews, and checks live only in their
artifacts.

A later `/addressit` invocation fetches the current branch's pull request again
and creates the next round from comment IDs that are not addressed or skipped.
`--task <local-task-id>` remains available when the branch does not
contain an inferable task ID.

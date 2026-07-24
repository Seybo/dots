---
name: addressit
description: >-
  Pi-manager command that fetches GitHub PR review comments, asks the operator to
  approve a classified batch, coordinates Pi and Claude workers in tmux, consolidates
  each review round into one commit, and waits for final Pi-manager review.
  Command-only skill. In Pi, invoke via /skill:addressit; /addressit is also
  accepted where that alias is exposed.
disable-model-invocation: true
---

# Addressit

This is a **Pi-manager-only command skill**. Claude is a review participant and
must not invoke addressit.

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

Pi appends command arguments verbatim. Extract the PR number or GitHub PR URL
from anywhere in those arguments, ignoring conversational filler, and pass the
PR target first to the helper. The helper requires:

```text
addressit <pr-number-or-github-url> [filters] [--task <local-task-id>]
```

## Invocation

```text
/skill:addressit <pr-number-or-github-url> [filters] [--task <local-task-id>]
/addressit <pr-number-or-github-url> [filters] [--task <local-task-id>]
```

Examples:

```text
/addressit 123
/addressit https://github.com/org/repo/pull/123
/addressit 123 comments from @octocat
/addressit 123 comments since 12 hours ago
/addressit 123 comments from @octocat since 2026-06-04T09:00:00Z
/addressit 123 --task 0001
```

Do not auto-use this skill from a general review-related request. Wait for an
explicit `/addressit` invocation.

## Task and branch preflight

Addressit uses the current checkout and the same project/task resolution rules as
`/autowork` and `/workit`:

1. infer the project from the current checkout using the shared registry
2. use `--task <local-task-id>` for an arbitrary local/ad-hoc branch, or infer
   the task/story ID from `sc-<digits>` or a local four-digit branch prefix
3. require exactly one matching folder under `/Volumes/dev/_tasks/<project>/`
4. require that folder to contain `task.md`
5. require a clean worktree
6. require current-window tmux panes titled exactly `pi-manager`, `pi-worker`,
   and `claude-worker`, all rooted at the same repository

If no task folder can be found, report that fact and stop. Do not create a task
folder, suggest a creation command, or create partial addressit state.

Addressit never pushes. It commits locally; the operator pushes the branch and
waits for GitHub to receive any new review comments before invoking addressit
again.

## Round workflow

The operator is the polling mechanism. Each explicit invocation handles one
snapshot of unresolved/new comments:

1. Fetch inline PR review comments through `gh api`.
2. Apply the existing PR URL, reviewer, time, and specific-comment/review filters.
3. Ignore a comment only when the local ledger records the same GitHub comment ID
   and the same `updated_at` as `addressed` or `skipped`.
4. If a previously addressed/skipped comment was edited, treat the edited
   version as new.
5. Save the selected comments under `<task_folder>/addressit-log/`.
6. Stop and show the concise selected-comment list. Do not launch Pi-worker yet.

Review summaries and issue-level PR comments are not included by default. Use the
existing explicit all-comments behavior when those are requested.

A round has one universal approval gate. Pi-manager must read the saved full
comment artifact, classify every selected comment, and present a concise table:

- `minor` or `not_minor`
- `valid` or `not_valid`
- short reasoning, including file/line context when useful

Then wait for the operator. The operator may approve or correct the labels. The
operator's response must put every selected comment into exactly one state:

- `approved`: send it to Pi-worker
- `skipped`: do not address it

No comment remains pending after the approval response. Approved comments include
minor comments. The helper writes the exact decision set to the round approval
JSON and launches the worker only after every selected comment has a decision.

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

The selected comments are one task batch. Pi-worker receives one prompt for all
approved comments and leaves changes unstaged/uncommitted. Addressit may create
temporary commits while workers iterate, but it squashes every commit made in the
review round at the manager gate into exactly one final commit:

```text
Add review updates #<N>
```

The final commit contains the implementation, Claude-requested fixes, and any
Pi-manager fixes from that round. It does not create or modify `steps.md` and does
not invoke `/workit`.

## Claude review and fix loop

After the combined implementation commit, addressit sends Claude one scoped review
prompt covering:

- every approved GitHub comment
- regressions introduced by the implementation
- the exact commit and current diff

Claude writes a human-readable review and status JSON. Claude does not run tests,
linters, or formatters during this review.

If Claude reports findings:

1. Pi-worker classifies every finding as accept, alternative fix, dispute,
   follow-up, or needs-user.
2. Accepted findings are fixed together in one Pi turn.
3. Addressit commits them temporarily and tracks them as part of round `<N>`.
4. Claude reviews the fix commit again.
5. Repeat within the configured fix limit; all round commits are squashed at the
   final manager gate into `Add review updates #<N>`.

If Pi and Claude disagree, use the bounded debate flow from `/autowork`. Do not
silently choose a winner. Pause for operator arbitration when the configured
round limit is reached or either worker requests user input. For a persisted user
arbitration pause, record one decision for every Claude finding and resume with:

```text
addressit resolve <task_folder> <resolution-json>
```

The resolution JSON uses `finding_id` and `decision` (`accept` or `skip`).

## Checks and manager gate

Reuse `/autowork`'s configured final-check rules:

- Ruby repositories with a `Gemfile` default to:
  `bundle exec rubocop` and `bundle exec rspec`
- non-Ruby or unconfigured repositories record checks as skipped
- Pi may run focused checks during implementation/fix turns
- Claude does not rerun checks during review

After Claude accepts and final checks pass, addressit stops at the final
Pi-manager gate. Pi-manager must review the original comments, classifications,
approvals, diff, temporary commits, Claude reviews, and final checks using
manager-only conversation context. The manager pass then squashes all commits from
the round into `Add review updates #<N>`. Write the result to:

```text
<task_folder>/addressit-log/manager_review.md
```

Only after that review passes may Pi-manager run:

```text
addressit manager-pass <task_folder>
```

That command marks the approved comment IDs as `addressed`. Skipped IDs remain
`skipped`. Addressit does not mark comments addressed merely because Claude
accepted the code.

If manager review finds an issue, write a findings JSON file and run:

```text
addressit manager-fix <task_folder> <findings-json>
```

The helper sends the findings to Pi-worker, creates a manager-fix commit, reruns
configured checks, sends the commit to Claude for scoped review, and returns to a
fresh manager gate.

## Persisted artifacts

```text
<task_folder>/addressit-log/
  state.json
  config.yml
  rounds/round<N>_comments.json
  rounds/round<N>_approval.json
  prompts/
  reviews/
  status/
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
```

Pi-manager uses this only after the operator has approved or skipped every
selected comment.

A later `/addressit <same-pr>` invocation fetches GitHub again and creates the
next round from comment IDs/versions that are not addressed or skipped.

---
name: autofix
description: >-
  Import and decide reported issues from the current GitHub pull request or a
  local review copied to the clipboard, or explicitly rebase its completed Task.
  Command-only skill.
disable-model-invocation: true
---

# Autofix

Helper:

```text
/Volumes/dev/bin/skills/autofix
```

Supported invocations:

```text
/skill:autofix
/skill:autofix --local --task <task-id>
/skill:autofix --rebase-base
/skill:autofix --rebase-base <base-ref>
```

## Operator attention notifications

At the final Manager presentation boundary, begin the complete operator-facing
turn with the exact prefix `[MM_NTF]` whenever Autofix cannot continue without
operator input or action. This includes:

- every Fix, Skip, or Unclear Reported Issue assessment
- clarification questions and genuine decision ambiguity
- optional squash approval
- ambiguous rebase-conflict resolution questions
- participant, Work Cycle, import, rebase, squash, or helper failures that
  require operator direction
- interrupted-rebase recovery instructions

When retained progress and a blocking request share one turn, put `[MM_NTF]`
before the retained progress so it is the first text in the complete turn.
Instructions below to return or surface helper output unchanged mean preserve
the helper content after this presentation prefix when operator direction is
required; never alter the helper output before parsing it.

Do not prefix normal progress, successful completion, no-issue or
no-unresolved-issue results, participant messages, or Manager machine-control
lines such as `Issue: <id>`, `AutoFixCycle <id>`, `AutoFixRole <role>`,
`WaitWorkCycle <id>`, `AutoFixSquash <id>`, `AutoFixRebaseConflict <id>`,
`RebaseTargetRef <ref>`, and `RebaseTargetCommit <sha>`. Continue to retain,
parse, remove, or route those control lines exactly as specified below.

## Task resolution

Before **Resume** or **Rebase completed Task**, read and follow
[`../../components/task-resolution.md`](../../components/task-resolution.md)
completely.

- For a Shortcut project, infer the Task ID from the current `sc-<digits>`
  branch segment and resolve exactly one Task folder.
- For a local-provider project, require `--local --task <task-id>` and resolve
  that explicit numeric Task selector. Never infer a local Task from
  `main`/`master` or the newest Task.
- Retain the canonical Task folder path. Ruby verifies that it belongs to the
  current checkout and configured branch and that Autoimplement reached
  terminal `final_checks_passed` state.

Reject missing, duplicate, or unsupported arguments before **Resume**. The only
normal source forms are no arguments for GitHub and `--local --task <task-id>`
for local review. `--rebase-base` is Shortcut-only and uses the same inferred
Task; never offer or invoke it for a local-provider Task.

## Rebase completed Task

Treat `--rebase-base` as a separate explicit operation for the resolved
Shortcut Task. Accept either no value or one exact base ref after it. Reject
combinations with `--local`, `--base`, `--task`, or any other argument. This
operation is valid before Review import and while one Review remains incomplete.
Do not enter **Resume**, collect a source, or continue normal Review
orchestration during or after it.

1. Resolve the canonical Task folder through **Task resolution**.
2. With no supplied base ref, run:

   ```text
   /Volumes/dev/bin/skills/autofix rebase-task <canonical-task-path>
   ```

   With a supplied base ref, preserve it exactly and run:

   ```text
   /Volumes/dev/bin/skills/autofix rebase-task <canonical-task-path> <base-ref>
   ```

3. If the helper returns successful Task rebase output without conflict control
   lines, append one blank line and this exact final line, then return the
   combined output and stop:

   ```text
   Resolved conflicts: none.
   ```

   The helper output identifies the Task, an active Review when present, old
   and new active refs and full SHAs, remapped Task and optional Review starting
   SHAs, and confirms that no push occurred. Do not reopen Autoimplement, replay
   Task Work Cycles, rerun final reviews, or expose Work Cycle commit SHAs.
4. A conflict handoff contains exactly these Manager control lines:

   ```text
   AutoFixRebaseConflict <task-id>
   RebaseTargetRef <target-ref>
   RebaseTargetCommit <full-target-sha>
   ```

5. Read and follow
   [`../../components/rebase-conflict-resolution.md`](../../components/rebase-conflict-resolution.md)
   completely. For this caller, retain the canonical Task path with the shared
   control data and run only this continuation command after resolving each
   current set of conflicts:

   ```text
   /Volumes/dev/bin/skills/autofix continue-task-rebase <canonical-task-path> <target-ref> <full-target-sha>
   ```

   The original explicit operation named by the shared policy is
   `/skill:autofix --rebase-base [<base-ref>]`.

## Resume

Before collecting a GitHub or local source:

1. Run `git branch --show-current` and retain the exact branch name.
2. Run:

   ```text
   /Volumes/dev/bin/skills/autofix resume <canonical-task-path>
   ```

3. Continue to source collection only when stdout is exactly
   `No incomplete Review.`.
4. If stdout contains an `AutoFixCycle <id>` or `WaitWorkCycle <id>` line, follow
   **Work Cycle handoff** below without reading the source or repeating base
   selection.
5. If stdout contains an `AutoFixSquash <review-id>` line, follow **Optional
   squash** below.
6. Otherwise follow **Issue assessment** when stdout contains an `Issue: <id>`
   block. Return any other stdout unchanged and stop.

## Repository final-check preflight

After **Resume** returns exactly `No incomplete Review.` and before collecting a
new Review source, read `<canonical-checkout>/.autowork.yml`.

When the file exists, Agent-manager reads it and loosely confirms that its
`final_checks` directory-to-command mapping is usable for the repository. The
repository owns the mapping and commands.

When the file is missing:

1. Stop before source collection, Review import, new workflow database state, or
   participant work.
2. Agent-manager discovers established commands from repository evidence such as
   `bin/check`, Gemfiles, package scripts, CI configuration, and documented test
   commands.
3. Propose exact `.autowork.yml` contents using only evidenced commands.
4. Require operator approval before creating the file.
5. After creation, require separate explicit approval to commit it as repository
   setup.
6. Require clean Git after that setup commit, then tell the operator to re-invoke
   Autofix from the start.

Ruby never discovers final-check commands. Add no strict Ruby validator, and use
no root-`Gemfile` fallback when `.autowork.yml` is missing.

## GitHub

With no source argument:

1. Use the branch name retained during resume.
2. Run `gh pr view --json number,baseRefName` for the current pull request.
3. Run `git fetch origin`.
4. Select exactly `origin/<baseRefName>` from the pull request.
5. Run `git rev-parse <base-ref>^{commit}` and retain the full base commit SHA.
6. Run the following command with the pull request number, preserving all pages:

   ```text
   gh api repos/{owner}/{repo}/pulls/<number>/comments --paginate --slurp
   ```

7. Flatten the returned pages. For each comment, read its current project file
   and relevant code context when the file exists.
8. Read `app/prompts/normalize_github_issue.md` from this skill directory and
   follow it for each comment using the comment's ID, body, path, line,
   original line, diff hunk, and current code context. Omit only `null` results.
9. Write this object to `/tmp/autofix-github-review.json`:

   ```json
   {
     "branch_name": "<branch>",
     "base_ref": "<base ref>",
     "base_commit_sha": "<full base commit SHA>",
     "issues": [
       {"source_id": "<comment ID>", "body": "<normalized issue>"}
     ]
   }
   ```

10. Run:

    ```text
    /Volumes/dev/bin/skills/autofix import-github-review /tmp/autofix-github-review.json <canonical-task-path>
    ```

11. Delete `/tmp/autofix-github-review.json` after the helper returns, including
    when it fails.
12. Follow **Issue assessment** when helper stdout contains an `Issue: <id>`
    block. Return any other stdout unchanged. Surface failures after deleting
    the file.

Do not write raw GitHub responses to temporary files or SQLite. Do not decide a
concrete concern's validity during normalization. Do not refetch GitHub while
settling the imported Review.

## Local

With `--local --task <task-id>`:

1. Read `app/prompts/extract_issues_from_clipboard.md` from this skill directory.
2. Run `pbpaste` directly and treat its complete output as the review.
3. Follow the prompt to extract the Reported Issue bodies.
4. Write this object to `/tmp/autofix-local-review.json`:

   ```json
   {"issues": ["<issue body>"]}
   ```

5. Run:

   ```text
   /Volumes/dev/bin/skills/autofix import-local-review /tmp/autofix-local-review.json <canonical-task-path>
   ```

6. Delete `/tmp/autofix-local-review.json` after the helper returns, including
   when it fails.
7. Follow **Issue assessment** when helper stdout contains an `Issue: <id>`
   block. Return any other stdout unchanged. Surface failures after deleting
   the file.

Do not add special handling for empty clipboard text. Do not store the original
clipboard review.

## Work Cycle handoff

A new Work Cycle handoff contains these paired Manager control lines:

```text
AutoFixCycle <id>
AutoFixRole <manager|worker|reviewer>
```

When helper stdout contains that pair:

1. Retain any completed-step block before the control lines. A completed-step
   block begins with `Worker implementation completed`, `Reviewer review
   completed`, `Worker review completed`, or `Manager review completed`. Do not
   retain or display the `AutoFixCycle` or `AutoFixRole` control lines.
2. For role `manager`, perform the review inline in this conversation:
   - run `/Volumes/dev/bin/skills/autofix show-work-cycle <id>` and treat its
     JSON as authoritative
   - use the returned `task_path`, `feature_path`, and `feature_text`: when the Feature fields are non-null, apply that shared goal, scope, and constraint context before reading the complete Task files, ignore the Feature inventory, and do not persist or rediscover the Feature text; Task-specific requirements and Reported Issues win conflicts
   - when the Feature fields are null, do not perform a Feature lookup; read the Task files from `task_path` normally
   - review the complete committed diff from `starting_commit_sha` through
     current `HEAD`, every input and decision, relevant surrounding code, and
     the full conversation and workflow context
   - primarily look for missing requirements, contradictions, integration
     gotchas, incomplete work, regressions, and concrete security, data-loss,
     performance, or operational risks; report anything else worth mentioning
     when encountered
   - do not edit, stage, commit, or run checks
   - write `/tmp/autofix-work-cycle-<id>.json` with the common completed review
     fields and one self-contained actionable body per `reported_issues`
     element; use an empty array when no issues are reported
   - copy `PI_PROVIDER`, `PI_MODEL`, and `PI_REASONING_LEVEL` when present and
     otherwise use JSON `null`; add no verdict, summary, severity, or other
     fields
   - if the review cannot complete, write the common failed result with a
     concise sanitized `error`
   - run `/Volumes/dev/bin/skills/autofix wait-work-cycle <id>` after writing
     the result
3. For role `worker` or `reviewer`, map the role to the fixed pane title:
   - `worker` → `agent-worker`
   - `reviewer` → `agent-reviewer`
4. For role `worker` or `reviewer`, require the dynamic `$TMUX_PANE` value for
   Manager's pane. Resolve its window with
   `tmux display-message -p -t "$TMUX_PANE" '#{window_id}'`, then run
   `tmux list-panes -t <resolved-window-id> -F '#{pane_id}\t#{pane_title}'`.
   Select the only pane with the mapped title and fail if there is not exactly
   one in that window. Never use `tmux list-panes -a`, search another window or
   session, hardcode a tmux ID, or fall back outside Manager's resolved window.
   Do not add pane-root checks or other preflight behavior.
5. For role `worker` or `reviewer`, send only the literal participant message
   without the role line:

   ```text
   tmux send-keys -t <pane-id> -l 'AutoFixCycle <id>'
   tmux send-keys -t <pane-id> Enter
   ```

6. For role `worker` or `reviewer`, immediately run the following command
   without a tool timeout and perform no other Autofix work while it blocks:

   ```text
   /Volumes/dev/bin/skills/autofix wait-work-cycle <id>
   ```

7. If wait-command stdout contains another paired handoff, retain its completed
   block and repeat the handoff in this invocation.
8. Otherwise retain its final workflow output in Work Cycle order. Follow
   **Optional squash** when it contains an `AutoFixSquash <review-id>` line, or
   follow **Issue assessment** instead of retaining or displaying any
   `Issue: <id>` block. Retain `No unresolved issues.` unchanged. Separate
   completed review blocks with one blank line. Surface failures unchanged and
   do not expose Manager control lines.

When helper stdout contains a line exactly `WaitWorkCycle <id>`, do not send
another tmux message. Run the same blocking `wait-work-cycle` command without a
tool timeout. If its stdout contains a paired handoff, follow the role routing
above in the same invocation. Otherwise follow **Optional squash** when its
stdout contains an `AutoFixSquash <review-id>` line, follow **Issue assessment**
when it contains an `Issue: <id>` block, or return its complete workflow output
or failure unchanged.

## Optional squash

Whenever helper stdout contains an exact `AutoFixSquash <review-id>` line, the
Review is already completed and all durable workflow state is final.

1. Retain all other completed workflow output, remove the control line, and
   present the retained output.
2. Ask exactly:

   ```text
   [MM_NTF] Should i squash?
   ```

3. Retain the Review ID only in the current conversation. Do not persist the
   question, answer, pending state, or squash result.

For the operator's next reply while this question is active:

- Treat `yes`, `go`, `squash`, `approve`, or `approved` as approval and run:

  ```text
  /Volumes/dev/bin/skills/autofix squash-review <review-id>
  ```

- Treat `no`, `skip`, or `leave` as declining. Run no helper and report that the
  Work Cycle commits remain unchanged.
- A question or unrelated message is not an answer. Answer it without running a
  helper, then ask `[MM_NTF] Should i squash?` again, with `[MM_NTF]` as the
  first text in that complete Manager turn.

Return squash success or failure unchanged. Never run `resume`, alter Review
state, persist squash metadata, push, automatically retry, or make the answer or
result affect the completed Review.

## Issue assessment

Whenever helper stdout contains an `Issue: <id>` block, treat the ID and quoted
stored body as Manager handoff data. Render the complete original body first in
the operator assessment, followed by TLDR and Recommendation. This boundary
applies uniformly after resume, GitHub or local import,
Worker/Reviewer/Manager result import, and a decision that selects the next
issue.

1. Retain the ID and complete stored body.
2. Read `../app/prompts/assess_issue.md` from the shared package.
3. Inspect only relevant current project code and existing Review/conversation
   context. Do not edit files or run tests, linters, or formatters.
4. Follow the prompt and present its concise assessment. With no completed-step
   output, use the prompt's prefixed presentation. If completed-step output
   preceded the issue block, put `[MM_NTF]` first, then the completed-step
   output, one blank line, and the assessment beginning at `Issue <id>` without
   repeating the prefix.
5. Treat the recommendation as advisory. Do not run `store-decision`, create a
   Work Cycle, contact a participant, or persist assessment state until the
   operator clearly decides.

If the operator asks for more details, begin the response with `[MM_NTF]`, show
useful code and Review context without recording a decision, and request the
still-needed decision. When resume returns the same undecided issue, regenerate
its assessment from current code and context.

For an `Unclear` recommendation, ask the prompt's one precise question,
preferring a yes-or-no question when possible, and persist nothing. Treat the
operator's next reply as clarification, including `yes` or `go`, and reassess
the same issue. Follow the shared decision-reason policy: when the clarification
makes Fix or Skip unambiguous and supplies its factual basis, apply its
understanding and agreement rules; otherwise begin with `[MM_NTF]` and ask one
precise decision question.

## Decisions

Read and follow
[`../../components/reported-issue-decision-reasons.md`](../../components/reported-issue-decision-reasons.md)
completely. It owns reason retention, acceptance, contrary decisions, safe
helper arguments, and exact stored output. Use the mappings below to identify
the requested outcome; persist it only when the shared policy has a reason.

Use the currently assessed issue ID for the operator's next clear decision:

- Treat `fix`, `approve`, and `approved` as `approved`.
- Treat `skip`, `ignore`, `reject`, and `invalid` as `skipped`.
- Treat any unambiguous affirmative response to Manager's current
  recommendation—including `go`, `yes`, `ok`, `okay`, `accept`, `approved`, or
  equivalent clear language—as accepting it: `Fix` becomes `approved`, and
  `Skip` becomes `skipped`.
- An `Unclear` recommendation has no initial decision to accept. Treat `yes` or
  `go` as clarification, reassess it, and apply the shared policy before deciding
  whether anything can be persisted.
- A question, details request, clarification, or unrelated message is not a
  decision.
- For genuine decision ambiguity, begin the complete Manager turn with
  `[MM_NTF]`, name the affected Reported Issue ID, and ask one precise question.
  Do not run `store-decision`, persist escalation state,
  or create a Work Cycle until the operator gives a clear decision.

For a decision with its required reason, run:

```text
/Volumes/dev/bin/skills/autofix store-decision <id> <approved|skipped> <shell-escaped-reason>
```

Preserve the helper's exact stored `Decision:` and `Reason:` lines.

When stdout contains an `AutoFixCycle <id>` line, follow **Work Cycle handoff**.
When it contains an `AutoFixSquash <review-id>` line, follow **Optional squash**.
Otherwise follow **Issue assessment** when stdout contains another issue, or
return stdout unchanged. An all-skipped Reviewer batch may return the Review's
one final Worker handoff; follow it normally. When stdout is exactly
`No unresolved issues.`, return it and stop without creating another Work
Cycle. Run one decision command per reply; do not process the queue
automatically. Do not refetch or re-import source data between decisions.

Reject any other skill arguments, including unsupported combinations with
`--rebase-base`.

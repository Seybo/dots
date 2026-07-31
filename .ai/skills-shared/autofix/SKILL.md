---
name: autofix
description: >-
  Import and decide reported issues from the current GitHub pull request or a
  local review copied to the clipboard. Command-only skill.
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
/skill:autofix --base <ref>
/skill:autofix --local
/skill:autofix --local --base <ref>
```

## Resume

Before collecting a GitHub or local source:

1. Run `git branch --show-current` and retain the exact branch name.
2. Run:

   ```text
   /Volumes/dev/bin/skills/autofix resume <branch>
   ```

3. Continue to source collection only when stdout is exactly
   `No incomplete Review.`.
4. If stdout contains an `AutoFixCycle <id>` or `WaitWorkCycle <id>` line, follow
   **Work Cycle handoff** below without reading the source or repeating base
   selection.
5. Otherwise return stdout unchanged and stop.

## GitHub

With no source argument:

1. Use the branch name retained during resume.
2. Run `gh pr view --json number,baseRefName` for the current pull request.
3. Run `git fetch origin`.
4. Select the supplied `--base <ref>` when present. Otherwise select
   `origin/<baseRefName>` from the pull request.
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
    /Volumes/dev/bin/skills/autofix import-github-review /tmp/autofix-github-review.json
    ```

11. Delete `/tmp/autofix-github-review.json` after the helper returns, including
    when it fails.
12. Return helper stdout unchanged. Surface failures after deleting the file.

Do not write raw GitHub responses to temporary files or SQLite. Do not decide a
concrete concern's validity during normalization. Do not refetch GitHub while
settling the imported Review.

## Local

With `--local`:

1. Use the branch name retained during resume.
2. Run `git fetch origin`.
3. Select the supplied `--base <ref>` when present. Otherwise run
   `git rev-parse --verify --quiet origin/main^{commit}` and select `origin/main`
   when it succeeds; if it fails, run the same command for `origin/master` and
   select `origin/master`.
4. Run `git rev-parse <base-ref>^{commit}` and retain the full base commit SHA.
5. Read `app/prompts/extract_issues_from_clipboard.md` from this skill directory.
6. Run `pbpaste` directly and treat its complete output as the review.
7. Follow the prompt to extract the Reported Issue bodies.
8. Write this object to `/tmp/autofix-local-review.json`:

   ```json
   {
     "branch_name": "<branch>",
     "base_ref": "<base ref>",
     "base_commit_sha": "<full base commit SHA>",
     "issues": ["<issue body>"]
   }
   ```

9. Run:

   ```text
   /Volumes/dev/bin/skills/autofix import-local-review /tmp/autofix-local-review.json
   ```

10. Delete `/tmp/autofix-local-review.json` after the helper returns, including
    when it fails.
11. Return helper stdout unchanged. Surface failures after deleting the file.

Do not add special handling for empty clipboard text. Do not store the original
clipboard review.

## Work Cycle handoff

A new Work Cycle handoff contains these paired Manager control lines:

```text
AutoFixCycle <id>
AutoFixRole <worker|reviewer>
```

When helper stdout contains that pair:

1. Retain any completed-step block before the control lines. A completed-step
   block begins with `Worker implementation completed`, `Reviewer review
   completed`, or `Worker review completed`. Do not retain or display the
   `AutoFixCycle` or `AutoFixRole` control lines.
2. Map the role to the fixed pane title:
   - `worker` → `agent-worker`
   - `reviewer` → `agent-reviewer`
3. Require the dynamic `$TMUX_PANE` value for Manager's pane. Resolve its window
   with `tmux display-message -p -t "$TMUX_PANE" '#{window_id}'`, then run
   `tmux list-panes -t <resolved-window-id> -F '#{pane_id}\t#{pane_title}'`.
   Select the only pane with the mapped title and fail if there is not exactly
   one in that window. Never use `tmux list-panes -a`, search another window or
   session, hardcode a tmux ID, or fall back outside Manager's resolved window.
   Do not add pane-root checks or other preflight behavior.
4. Send only the literal participant message without the role line:

   ```text
   tmux send-keys -t <pane-id> -l 'AutoFixCycle <id>'
   tmux send-keys -t <pane-id> Enter
   ```

5. Immediately run the following command without a tool timeout and perform no
   other Autofix work while it blocks:

   ```text
   /Volumes/dev/bin/skills/autofix wait-work-cycle <id>
   ```

6. If wait-command stdout contains another paired handoff, retain its completed
   block and repeat the handoff in this invocation.
7. Otherwise append its complete final workflow output to the retained blocks,
   including any `Issue: <id>` or `No unresolved findings.` block after the
   completed-step block. Return all retained output in Work Cycle order and
   separate completed review blocks with one blank line. Surface failures
   unchanged and do not expose Manager control lines.

When helper stdout contains a line exactly `WaitWorkCycle <id>`, do not send
another tmux message. Run the same blocking `wait-work-cycle` command without a
tool timeout. If its stdout contains a paired handoff, follow the role routing
above in the same invocation. Otherwise return its complete workflow output or
failure unchanged, including any finding-selection block.

## Decisions

When either flow displays `Issue: <id>`, use that ID for the operator's next
clear decision about the issue:

- Treat affirmative continuation such as `go`, `yes`, or `approved` as
  `approved`.
- Treat a clear request to skip, ignore, reject, or mark the issue invalid as
  `skipped`.
- A question or unrelated message is not a decision.

For a decision, run:

```text
/Volumes/dev/bin/skills/autofix store-decision <id> <approved|skipped>
```

When stdout contains an `AutoFixCycle <id>` line, follow **Work Cycle handoff**.
Otherwise return stdout unchanged. When the output displays another issue, apply
the same behavior to the operator's next reply. When stdout is exactly
`No unresolved findings.`, return it and stop without dispatching corrections.
Run one decision command per reply; do not process the queue automatically. Do
not refetch or re-import source data between decisions.

Reject any other skill arguments.

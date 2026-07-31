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

When helper stdout contains a line exactly `AutoFixCycle <id>`:

1. Run `tmux list-panes -F '#{pane_id}\t#{pane_title}'` in the current tmux
   window.
2. Select the only pane whose title is exactly `agent-worker`. Fail if there is
   not exactly one. Do not add pane-root checks or other preflight behavior.
3. Send the literal message without interpretation:

   ```text
   tmux send-keys -t <pane-id> -l 'AutoFixCycle <id>'
   tmux send-keys -t <pane-id> Enter
   ```

4. Immediately run the following command without a tool timeout and perform no
   other Autofix work while it blocks:

   ```text
   /Volumes/dev/bin/skills/autofix wait-work-cycle <id>
   ```

5. Return wait-command stdout unchanged. Surface failures unchanged.

When helper stdout contains a line exactly `WaitWorkCycle <id>`, do not send
another tmux message. Run the same blocking `wait-work-cycle` command without a
tool timeout and return its stdout or failure unchanged.

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
the same behavior to the operator's next reply. Run one decision command per
reply; do not process the queue automatically. Do not refetch or re-import
source data between decisions.

Reject any other skill arguments.

---
name: addressit
description: >-
  Interactively fetch and address GitHub PR review comments one at a time.
  Accepts PR links, review/comment links, reviewer filters, and time windows.
  Command-only skill. Invoke only via /addressit.
---

# Addressit

This is a command-only skill for addressing PR review feedback interactively.

## Invocation

Use only:

```text
/addressit <pr-number-or-github-url-or-filter>
```

Examples:

```text
/addressit 123
/addressit https://github.com/org/repo/pull/123
/addressit https://github.com/org/repo/pull/123#discussion_r123456789
/addressit https://github.com/org/repo/pull/123#pullrequestreview-987654321
/addressit 123 comments from @octocat
/addressit 123 comments since 12 hours ago
/addressit 123 comments from @octocat since 2026-06-04T09:00:00Z
```

Do not auto-use this skill from a vague review-related request. Wait for the explicit slash command.

## What it does

Fetch GitHub PR review comments and guide the operator through them one by one:

1. paste the comment here
2. give an opinion on whether it is valid/actionable
3. propose one or more solutions
4. wait for the operator to choose/approve a solution
5. implement only the approved solution
6. summarize changes, then automatically continue to the next comment (no separate approval to advance)

Start from the first comment automatically. Advance through the queue on your own, but never implement a comment's fix until the operator approves that comment's solution — one solution-approval gate per comment, no batching.

## Inputs supported

The command may include one or more of:

- a PR number in the current repo: `123`
- a full PR URL: `https://github.com/org/repo/pull/123`
- a specific review URL: `https://github.com/org/repo/pull/123#pullrequestreview-987654321`
- a specific inline comment/discussion URL fragment such as `#discussion_r123456789`
- a reviewer filter: `from @username`, `from username`, `comments from @username`
- a time filter: `since 12 hours ago`, `since yesterday`, `since 2026-06-04T09:00:00Z`

If the PR/repo cannot be determined, ask for a PR number or PR URL.

## Fetching comments

1. **Determine repo and PR:**
   - If a full GitHub PR URL is provided, extract `owner/repo` and PR number from the URL.
   - Otherwise, use the current repository:
     ```bash
     gh repo view --json nameWithOwner -q .nameWithOwner
     ```
   - Extract the PR number from the command arguments.

2. **Detect optional filters:**
   - `from @username` / `from username` filters comments by `.user.login`.
   - `since <time expression>` filters comments by `.created_at` or `.updated_at` at or after that time.
   - For relative time expressions, compute an ISO-8601 UTC timestamp locally with `date` where possible. If ambiguous, ask the operator to clarify.
   - Specific review IDs come from URL fragments like `#pullrequestreview-987654321`.
   - Specific comment IDs come from URL fragments like `#discussion_r123456789`; the numeric id is `123456789`.

3. **Fetch comments:**

   Specific review:
   ```bash
   gh api repos/${REPO}/pulls/${PR_NUMBER}/reviews/${REVIEW_ID}/comments
   ```

   Otherwise, all inline PR review comments:
   ```bash
   gh api repos/${REPO}/pulls/${PR_NUMBER}/comments
   ```

   Also fetch review summaries and issue-level PR comments when the user asks for "all comments" or when no inline comments are found:
   ```bash
   gh api repos/${REPO}/pulls/${PR_NUMBER}/reviews
   gh api repos/${REPO}/issues/${PR_NUMBER}/comments
   ```

4. **Normalize each comment into this shape:**
   ```json
   {
     "id": "github comment/review id",
     "kind": "inline_review_comment | review_summary | issue_comment",
     "user": "login",
     "created_at": "timestamp",
     "updated_at": "timestamp",
     "path": "file path if present",
     "line": "line/start_line/or null",
     "url": "html_url if present",
     "body": "full comment body"
   }
   ```

5. **Apply filters:**
   - Specific comment URL: keep only the matching comment ID.
   - Specific review URL: keep comments belonging to that review.
   - Reviewer filter: keep only comments from that user.
   - Since filter: keep comments with `created_at` or `updated_at` at/after the threshold.
   - Remove duplicate comments by `id` + `kind`.

6. **Present a queue:**
   - Show how many comments were found after filtering.
   - List each comment as:
     ```text
     1. <kind> @<user> <path>:<line> <url>
     ```
   - Do not ask which comment to start with. Start with comment `1` and work down the list in order.

## Per-comment workflow

For exactly one selected comment at a time:

1. **Paste the comment:**
   - Include author, kind, URL, file path, line/range, timestamp.
   - Quote the full body verbatim in a Markdown blockquote.
   - If the comment contains sensitive prospect data, emails, phone numbers, credentials, or PII, redact it before echoing and say it was redacted.

2. **Give your opinion:**
   - Say whether the comment is valid, partially valid, not valid, or needs clarification.
   - Evaluate whether the scenario described by the reviewer is actually possible/reachable in the current code path before proposing a fix.
   - If the scenario is impossible or unreachable, explain why and recommend skipping or replying instead of changing code.
   - Explain briefly using the current code context.
   - If uncertain, say what file/code you need to inspect before deciding, then inspect it.

3. **Propose solution(s):**
   - Provide one recommended solution.
   - Provide alternatives only when there is a real tradeoff.
   - Include expected files to change and likely test/check commands.
   - Do not implement yet.

4. **Wait for operator approval:**
   - Ask the operator to choose/approve a solution. This is the one required gate per comment.
   - If the operator rejects the comment or asks to skip, mark it skipped in the queue and automatically continue to the next comment.

5. **Implement approved solution:**
   - Make the smallest targeted change that addresses the approved comment.
   - Follow repo instructions and existing style.
   - Do not opportunistically fix unrelated feedback.
   - If implementation reveals that the approved plan is wrong or too broad, stop and ask before changing course.

6. **Verify:**
   - Run the smallest relevant checks/tests first.
   - Before running commands likely to take more than a few seconds, state what they will do and why.
   - Summarize pass/fail results.

7. **Report and auto-advance:**
   - Report changed files, checks run, and whether the comment appears addressed.
   - Then continue to the next comment automatically — do not ask for approval to advance. Go straight into the per-comment workflow for the next queued comment (present it, give an opinion, propose solutions, then stop at that comment's solution-approval gate).
   - When the queue is empty, stop and report the final state: which comments were addressed, which were skipped.
   - The operator can still interrupt at any time to pause, redirect, or stop the run.

## Important notes

- Never implement before presenting the comment, opinion, and proposed solution(s).
- Never batch multiple comments unless the operator explicitly says to address a group together.
- If multiple comments are duplicates or tightly coupled, explain that and ask whether to group them.
- Preserve a clear queue state in chat: pending, current, addressed, skipped.
- Prefer `gh api` over web fetching for GitHub review data.
- If a GitHub URL specifies a different repo than the current working directory, fetch from that repo but ask before editing if the local checkout does not match.
- For PR review URLs or review IDs, fetch the review directly and fetch inline comments from that review; do not rely only on `gh pr view`.

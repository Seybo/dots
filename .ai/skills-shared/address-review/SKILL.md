---
name: address-review
description: >-
  Fetch GitHub PR review comments and create a todo list to address them.
  Command-only skill. Invoke only via /address-review.
---

# Address Review

This is a command-only skill.

## Invocation

Use only:

```text
/address-review <pr-number-or-github-pr-url>
```

Do not auto-use this skill from a vague review-related request. Wait for the explicit slash command.

## What it does

Fetch review comments from a GitHub PR in the current repository and create a todo list to address each comment.

## Instructions

1. **Determine the current repository:**
   ```bash
   REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
   ```

2. Extract the PR number and optional review ID from the command arguments:
   - PR number only: `12345` or `https://github.com/org/repo/pull/12345`
   - Specific review: `https://github.com/org/repo/pull/12345#pullrequestreview-123456789`
   - Extract review ID from the hash fragment (for example `123456789`)
   - If a full GitHub URL is provided, extract the `org/repo` from the URL instead of using the current repo

3. Fetch review comments:

   **If a specific review ID is provided:**
   ```bash
   gh api repos/${REPO}/pulls/{PR_NUMBER}/reviews/{REVIEW_ID}/comments | jq '[.[] | {path: .path, body: .body, line: .line, start_line: .start_line, user: .user.login}]'
   ```

   **If only PR number is provided:**
   ```bash
   gh api repos/${REPO}/pulls/{PR_NUMBER}/comments | jq '[.[] | {path: .path, body: .body, line: .line, start_line: .start_line, user: .user.login}]'
   ```

4. Parse the JSON output and create a todo list with TodoWrite containing:
   - one todo per review comment
   - `content`: `{file}:{line} - {comment_summary} (@{username})`
   - `activeForm`: `Addressing {file}:{line}`
   - all todos start with status: `pending`

5. Present the todos to the user. **Do not automatically start addressing them.**
   - show a summary of how many comments were found
   - list the todos clearly
   - wait for the user to tell you which ones to address

## Important Notes

- Automatically detect the repository using `gh repo view` for the current working directory
- If a GitHub URL is provided, extract the `org/repo` from the URL
- Include file path and line number in each todo for easy navigation
- Include the reviewer's username in the todo text
- If a comment does not have a specific line number, note it as `general comment`
- **Never automatically address all review comments**
- When given a specific review URL, no need to ask for more information

---
name: delete-merged-branches
description: >-
  Delete local git branches that were merged and removed from remote.
  Command-only skill. Invoke only via /delete-merged-branches.
---

# Delete Merged Branches

This is a command-only skill.

## Invocation

Use only:

```text
/delete-merged-branches [prefix]
```

Do not auto-use this skill from general git cleanup requests. Wait for the explicit slash command.

## What it does

Delete local branches that had remote tracking configured but no longer have a remote, meaning they were merged and deleted upstream.

## Instructions

1. **Extract the branch prefix from the command arguments:**
   - look for a username or prefix in the command arguments, for example `mikhail` or `john`
   - if no prefix is provided, use `*` to match all branches

2. **Find branches with remote tracking configured:**
   ```bash
   git config --get-regexp '^branch\.{PREFIX}.*\.remote' | awk '{print $1}' | sed 's/branch\.\(.*\)\.remote/\1/'
   ```

3. **Check which tracked branches no longer have remotes:**
   For each branch with tracking, check whether the remote still exists:
   ```bash
   git ls-remote --heads origin {BRANCH_NAME}
   ```
   If the command returns empty output, the remote was deleted.

4. **Present the list of branches to delete:**
   - show all branches that had tracking but no longer have remotes
   - include a count of how many branches will be deleted
   - list each branch name clearly

5. **Ask for confirmation before deleting:**
   - never automatically delete branches without user confirmation
   - wait for explicit approval from the user

6. **Delete the branches:**
   Once confirmed, delete using:
   ```bash
   git branch -d {BRANCH_NAME}
   ```
   Use `-d` for safe deletion that verifies the branch is merged.
   If branches fail with `-d`, ask whether the user wants to force delete with `-D`.

7. **Remove git config tracking sections for deleted branches:**
   After deleting branches, clean up their remote tracking configuration:
   ```bash
   git config --remove-section branch.{BRANCH_NAME}
   ```
   This prevents the branches from appearing in shell autocomplete suggestions.

8. **Clean up stashes from deleted branches:**
   After deleting branches, check for stashes on those branches:
   ```bash
   git stash list
   ```
   For each stash on a deleted branch:
   - present the list of stashes that reference deleted branches
   - show stash index, branch name, and age
   - ask for confirmation before dropping
   - drop confirmed stashes using:
   ```bash
   git stash drop stash@{N}
   ```
   **Important:** drop stashes from highest index to lowest to prevent index shifting issues.

9. **Prune stale remote-tracking branches:**
   After all deletions, clean up stale remote-tracking references:
   ```bash
   git remote prune origin
   ```
   This only affects the local machine and removes local references to remote branches that no longer exist.

## Important Notes

- Only delete branches that have remote tracking configured
- Leave local-only branches untouched
- Use `-d` for safe deletion
- **Always ask for confirmation before deleting**
- Show a summary of what was deleted after completion
- If a branch cannot be deleted with `-d`, report it to the user
- After deleting branches, always check for and offer to clean up stashes from deleted branches
- When dropping stashes, start from the highest index and work down
- Clean up git config tracking sections so deleted branches stop appearing in autocomplete
- Always run `git remote prune origin` at the end

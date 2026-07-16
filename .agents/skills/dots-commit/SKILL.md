---
name: dots-commit
description: Prepare focused commits for the dotfiles repo. Runs dots-check on uncommitted changes first, stops on findings, reviews whether changes belong in the dotfiles repo, then proposes focused commit groups and commit messages matching recent history. Review-only; does not stage or commit without explicit user approval.
---

# Dots Commit

Prepare focused commits for `/Users/inseybo/.dots` without committing automatically.

This skill is repo-specific and lives in `.dots` at `.agents/skills/dots-commit`.

## Invocation

There is exactly one command-style invocation for this skill:

- `/skill:dots-commit`

In pi, when the user types `/skill:dots-commit`, the agent may receive this `SKILL.md` content as a `<skill name="dots-commit" ...>` block instead of seeing the raw slash command in the conversation. **That skill block means the skill was invoked.**

Do not ask the user to invoke it again. Treat the invocation and/or received skill block as an execution request.

## Hard rules

- Do not stage files.
- Do not commit.
- Do not mutate git history, branches, tags, stashes, remotes, or commit state.
- Only suggest commit groups and commit messages unless the user later gives explicit approval for a specific git mutation.
- If `dots-check` reports any finding, stop before reviewing commit groups. Ask the user whether each finding should be fixed or intentionally ignored.
- If the user explicitly approves creating commits, run `dots-check` again after the commits for every new commit created in the session and verify that every finding is expected.

## Workflow

1. **Resolve repo and status**
   - Work in `/Users/inseybo/.dots`.
   - Record the starting commit before any later approved commit work:
     ```bash
     git -C /Users/inseybo/.dots rev-parse HEAD
     ```
   - Run:
     ```bash
     git -C /Users/inseybo/.dots status --short
     ```
   - If there are no staged, unstaged, or untracked changes, report that there is nothing to commit and stop.

2. **Run dots-check before reviewing content**
   - Always scan unstaged tracked changes and untracked files:
     ```bash
     ./.agents/skills/dots-check/scripts/scan.rb --unstaged --untracked
     ```
   - If staged changes exist, also scan the staged set with the default scanner:
     ```bash
     ./.agents/skills/dots-check/scripts/scan.rb
     ```
   - Interpret exit codes:
     - `0`: continue.
     - `1`: findings present. Stop and summarize the findings. Ask the user whether to fix or explicitly ignore them. If the user explicitly ignores a finding, remember its rule/path/snippet as an expected finding for the post-commit scan.
     - `2`: usage/fatal error. Stop and report the error.

3. **Inspect all uncommitted changes**
   - Review changed paths and stats:
     ```bash
     git -C /Users/inseybo/.dots status --short
     git -C /Users/inseybo/.dots diff --stat
     git -C /Users/inseybo/.dots diff --cached --stat
     git -C /Users/inseybo/.dots ls-files --others --exclude-standard
     ```
   - Read diffs for tracked changes. Use targeted `git diff -- <paths>` / `git diff --cached -- <paths>` commands when the full diff is large.
   - For untracked files, list the files first, then read only relevant text files. Do not dump large binaries or generated artifacts.

4. **Check repo fit**
   - Treat this repo as the user's dotfiles / development-environment repo: shell/editor/terminal/tmux/zellij/Ghostty/Hammerspoon config, themes, local helper scripts, agent skills/config, and dev-env reference docs belong here.
   - Flag changes as questionable if they look like:
     - secrets, credentials, auth/session files, raw provider responses, or private tokens
     - runtime caches, generated archives, logs, screenshots, or app data
     - project-specific application code that belongs under `/Volumes/dev/projects/...`
     - local-only settings that should live in `.git/info/exclude`, `private/`, or an ignored local file instead of the shared dotfiles history
   - If any change does not clearly fit this repo's purpose, call it out and ask the user before suggesting it in a commit group.

5. **Infer commit-message style from history**
   - Run:
     ```bash
     git -C /Users/inseybo/.dots log --oneline -50
     ```
   - Match the existing style: short imperative-ish subject, usually `<area>: <change>`.
   - Prefer scopes already present in recent history when they fit, such as `ai:`, `tmux:`, `nvim:`, `theme:`, `monit:`, or `env:`.

6. **Suggest focused commits**
   - Group changes by purpose, not by file extension.
   - Keep unrelated areas separate, for example:
     - agent skill behavior/docs
     - Pi/Claude permission/config changes
     - tmux/session config
     - Neovim plugin config
     - browser monitoring helpers
     - dev-env references/docs
   - For each suggested commit, provide:
     - commit subject
     - short rationale
     - exact paths to include
     - any paths to exclude or handle separately
   - If a group is mixed or risky, say what needs user guidance.

7. **After explicitly approved commits, scan the new commits**
   - This step applies only if the user gives explicit approval to stage/commit specific groups and commits are created in this session.
   - Count commits created since the starting commit from step 1:
     ```bash
     git -C /Users/inseybo/.dots rev-list --count <starting_head>..HEAD
     ```
   - If the count is greater than zero, scan all new commits:
     ```bash
     ./.agents/skills/dots-check/scripts/scan.rb --last-commits <count>
     ```
   - If the scan returns `0`, report that the post-commit dots-check passed.
   - If the scan returns `1`, compare findings against findings the user explicitly approved ignoring during the pre-commit scan. Treat a finding as expected only when the rule, path, and relevant snippet clearly match the approved finding. Stop and ask the user about any new or changed finding.
   - If the scan returns `2`, stop and report the scanner error.
   - Include the post-commit scan result in the final response.

## Output format

Use this structure:

```text
Dots-check: pass|findings|error
Repo-fit review:
- ok: ...
- questionable: ...

Suggested commits:
1. <subject>
   Include:
   - path
   Rationale: ...

Post-commit dots-check:
- not run|pass|expected findings|unexpected findings|error

Needs your decision:
- ...
```

Keep the output concise but specific enough that the user can stage the suggested groups manually.

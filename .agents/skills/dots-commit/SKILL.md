---
name: dots-commit
description: Prepare focused commits for the dotfiles repo. Runs dots-check, reviews repo fit, presents focused commit groups, waits for approval, then creates the approved commits.
---

# Dots Commit

Prepare focused commits for `/Users/inseybo/.dots`, show them, wait for approval, then create the approved commits.

This skill is repo-specific and lives in `.dots` at `.agents/skills/dots-commit`.

## Invocation

There is exactly one command-style invocation for this skill:

- `/skill:dots-commit`

In pi, when the user types `/skill:dots-commit`, the agent may receive this `SKILL.md` content as a `<skill name="dots-commit" ...>` block instead of seeing the raw slash command in the conversation. **That skill block means the skill was invoked.**

Do not ask the user to invoke it again. Treat the invocation and/or received skill block as an execution request.

## Hard rules

- Prepare and present commit groups first; wait for explicit user approval before staging or committing.
- Do not mutate git history, branches, tags, stashes, remotes, or commit state before approval.
- After approval, stage and commit only the approved paths and groups.
- If `dots-check` reports any finding, stop before proposing commits. Ask whether each finding should be fixed or explicitly ignored.
- After approved commits, run `dots-check` again for every commit created in the session and verify that every finding is expected.

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

6. **Prepare and present focused commits**
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
   - Present the groups and wait for explicit approval before staging or committing.
   - Include `Needs your decision` only when the agent cannot proceed without user input, such as a dots-check finding or questionable repo fit. Do not use it to tell the user to stage or commit manually.

7. **After explicit approval, create the approved commits**
   - State the exact approved paths and commit subjects.
   - Stage only those paths and create the approved commits.
   - Do not ask the user to stage or commit manually unless they specifically request Git commands instead.

8. **After approved commits, scan the new commits**
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
```

Add a `Needs your decision:` section only when the agent is blocked and cannot proceed without user input. Do not add it merely because approval is pending.

Keep the output concise and specific. Show the proposed groups, then end with the exact question: `proceed with all the commits?` If no approval has been given, state that no files were staged or committed.

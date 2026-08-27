---
name: dots-commit
description: Prepare focused commits for the active dotfiles repo from STOW_DIR and its nested dev-environment references repo. Runs dots-check, reviews repo fit, presents focused commit groups, waits for approval, then creates the approved commits in the correct repository.
---

# Dots Commit

Prepare focused commits for `$STOW_DIR` and its nested `$STOW_DIR/refs/dev-env` repository, show them, wait for approval, then create the approved commits.

This shared skill lives in `.dots` at `.agents/skills/dots-commit`.

## Invocation

There is exactly one command-style invocation for this skill:

- `/skill:dots-commit`

In pi, when the user types `/skill:dots-commit`, the agent may receive this `SKILL.md` content as a `<skill name="dots-commit" ...>` block instead of seeing the raw slash command in the conversation. **That skill block means the skill was invoked.**

Do not ask the user to invoke it again. Treat the invocation and/or received skill block as an execution request.

## Hard rules

- Require `STOW_DIR`; stop if it is missing or not a Git repository.
- Treat `$STOW_DIR` and `$STOW_DIR/refs/dev-env` as separate Git repositories. Never combine their paths in one commit.
- When `STOW_DIR=$HOME/.omadots`, never mutate `$HOME/.dots`; it is a pull-only shared source.
- Prepare and present commit groups first; wait for explicit user approval before staging or committing.
- Do not mutate git history, branches, tags, stashes, remotes, or commit state before approval.
- After approval, stage and commit only the approved paths and groups in their stated repository.
- If `dots-check` reports any finding in either repository, stop before proposing commits. Ask whether each finding should be fixed or explicitly ignored.
- After approved commits, run `dots-check` again for every commit created in each repository and verify that every finding is expected.

## Workflow

1. **Resolve repositories and status**
   - Use these repositories:
     ```text
     dots: $STOW_DIR
     refs: $STOW_DIR/refs/dev-env
     ```
   - Record each starting commit before any later approved commit work:
     ```bash
     git -C "$STOW_DIR" rev-parse HEAD
     git -C "$STOW_DIR/refs/dev-env" rev-parse HEAD
     ```
   - Run status in both repositories:
     ```bash
     git -C "$STOW_DIR" status --short
     git -C "$STOW_DIR/refs/dev-env" status --short
     ```
   - If neither repository has staged, unstaged, or untracked changes, report that there is nothing to commit and stop.
   - Continue with only the repositories that have changes.

2. **Run dots-check before reviewing content**
   - In every changed repository, scan unstaged tracked changes and untracked files. Run the scanner from that repository so it resolves the correct Git root:
     ```bash
     cd "$STOW_DIR" && "$HOME/.dots/.agents/skills/dots-check/scripts/scan.rb" --unstaged --untracked
     cd "$STOW_DIR/refs/dev-env" && "$HOME/.dots/.agents/skills/dots-check/scripts/scan.rb" --unstaged --untracked
     ```
   - If a changed repository has staged changes, also run its default staged scan from that repository.
   - Interpret exit codes separately for each repository:
     - `0`: continue.
     - `1`: findings present. Stop and summarize the findings with their repository. Ask the user whether to fix or explicitly ignore them. If the user explicitly ignores a finding, remember its repository/rule/path/snippet as an expected finding for the post-commit scan.
     - `2`: usage/fatal error. Stop and report the error.

3. **Inspect all uncommitted changes**
   - Review changed paths and stats in every changed repository:
     ```bash
     git -C <repo> status --short
     git -C <repo> diff --stat
     git -C <repo> diff --cached --stat
     git -C <repo> ls-files --others --exclude-standard
     ```
   - Read diffs for tracked changes. Use targeted `git -C <repo> diff -- <paths>` / `git -C <repo> diff --cached -- <paths>` commands when the full diff is large.
   - For untracked files, list the files first, then read only relevant text files. Do not dump large binaries or generated artifacts.
   - Only when `STOW_DIR=$HOME/.dots`, check Claude settings drift. `~/.claude/settings.json` is deliberately not stow-linked because Claude Code rewrites it. Its ignored repo-local baseline is `.claude/settings.json`:
     ```bash
     diff "$HOME/.claude/settings.json" "$STOW_DIR/.claude/settings.json"
     ```
     If they differ, show the diff and ask whether the live changes are intentional. After the operator confirms, copy the live file over the baseline, then scan it:
     ```bash
     "$HOME/.dots/.agents/skills/dots-check/scripts/scan.rb" --file "$STOW_DIR/.claude/settings.json"
     ```
     Apply the dots-check exit-code rules from step 2. The baseline is ignored and must not be staged or included in a commit group.

4. **Check repo fit**
   - Run `$STOW_DIR/bin/stow_check`. Stop on any conflict.
   - Treat `$STOW_DIR` as the machine's active dotfiles repository.
   - When `STOW_DIR=$HOME/.dots`, shell/editor/terminal/tmux/zellij/Ghostty/Hammerspoon config, themes, local helper scripts, and shared agent skills/config belong there.
   - When `STOW_DIR=$HOME/.omadots`, only Oma-specific wiring and config belong there; shared rules and skills belong in pull-only `$HOME/.dots`.
   - Treat `refs/dev-env` as the development-environment reference repository. Documentation belongs there; executable configuration, credentials, and runtime state do not.
   - Flag changes as questionable if they look like:
     - secrets, credentials, auth/session files, raw provider responses, or private tokens
     - runtime caches, generated archives, logs, screenshots, or app data
     - project-specific application code that belongs under `$DEV_ROOT/projects/...`
     - local-only settings that should live in `.git/info/exclude`, `private/`, or an ignored local file instead of the shared dotfiles history
   - If any change does not clearly fit its repository's purpose, call it out and ask the user before suggesting it in a commit group.

5. **Infer commit-message style from history**
   - Read history in every changed repository:
     ```bash
     git -C <repo> log --oneline -50
     ```
   - Follow the commit-subject rules in the global agent instructions.
   - Use each repository's history to choose established area and component names. Do not copy an area name from one repository when it does not describe the other repository's change.

6. **Prepare and present focused commits**
   - Group changes by repository first, then by purpose rather than file extension.
   - Keep unrelated areas separate, for example:
     - agent skill behavior/docs
     - Pi/Claude permission/config changes
     - tmux/session config
     - Neovim plugin config
     - browser monitoring helpers
     - dev-env references/docs
   - For each suggested commit, provide:
     - repository (`dots` or `refs`)
     - commit subject
     - short rationale
     - exact repository-relative paths to include
     - any paths to exclude or handle separately
   - If a group is mixed or risky, say what needs user guidance.
   - Present the groups and wait for explicit approval before staging or committing.
   - Include `Needs your decision` only when the agent cannot proceed without user input, such as a dots-check finding or questionable repo fit. Do not use it to tell the user to stage or commit manually.

7. **After explicit approval, create the approved commits**
   - State each repository's exact approved paths and commit subjects.
   - Stage only those paths in the stated repository and create the approved commits there.
   - Never stage from the parent repository as a substitute for committing `refs/dev-env` directly.
   - Do not ask the user to stage or commit manually unless they specifically request Git commands instead.

8. **After approved commits, scan the new commits**
   - This step applies only if the user gives explicit approval to stage/commit specific groups and commits are created in this session.
   - For each repository where a commit was created, count commits since that repository's starting commit:
     ```bash
     git -C <repo> rev-list --count <starting_head>..HEAD
     ```
   - If the count is greater than zero, run the scanner from that repository:
     ```bash
     cd "$STOW_DIR" && "$HOME/.dots/.agents/skills/dots-check/scripts/scan.rb" --last-commits <dots-count>
     cd "$STOW_DIR/refs/dev-env" && "$HOME/.dots/.agents/skills/dots-check/scripts/scan.rb" --last-commits <refs-count>
     ```
   - If the scan returns `0`, report that repository's post-commit dots-check passed.
   - If the scan returns `1`, compare findings against findings the user explicitly approved ignoring during the pre-commit scan. Treat a finding as expected only when the repository, rule, path, and relevant snippet clearly match the approved finding. Stop and ask the user about any new or changed finding.
   - If the scan returns `2`, stop and report the scanner error.
   - Include each changed repository's post-commit scan result in the final response.

## Output format

Use this structure:

```text
Dots-check:
- dots: pass|findings|error|not run
- refs: pass|findings|error|not run
Repo-fit review:
- ok: ...
- questionable: ...

Suggested commits:
1. [dots|refs] <subject>
   Include:
   - path
   Rationale: ...

Post-commit dots-check:
- dots: not run|pass|expected findings|unexpected findings|error
- refs: not run|pass|expected findings|unexpected findings|error
```

Add a `Needs your decision:` section only when the agent is blocked and cannot proceed without user input. Do not add it merely because approval is pending.

Keep the output concise and specific. Show the proposed groups, then end with the exact question: `proceed with all the commits?` If no approval has been given, state that no files were staged or committed.

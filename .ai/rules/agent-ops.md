# Agent operating rules

General agent workflow and command-use rules. These are language- and project-neutral unless a project's local instructions override them.

## Pi slash commands and skills

When the user asks about a Pi "skill" or `/command`, treat that as any Pi slash command, not only an Agent Skill from `<available_skills>`. Pi slash commands can come from prompt templates (`/name`), Agent Skills (`/skill:name`), extension commands, or built-in commands. If a command appears in Pi autocomplete, it exists even when it is not listed in `<available_skills>`. Do not say a `/command` is unavailable solely because it is absent from `<available_skills>`; ask the user to run it or check prompt templates/commands if needed.

## Git safety

- Never mutate git history, branches, tags, stashes, remotes, or commit state without explicit user approval for that exact action. This includes `commit`, `commit --amend`, `reset`, `rebase`, `merge`, `cherry-pick`, `revert`, `switch`/`checkout` that changes branches, branch create/delete/rename, tag create/delete, stash create/apply/pop/drop, force-push, and remote changes.
- Reading git state is allowed: `status`, `diff`, `log`, `show`, `branch --show-current`, and similar read-only commands.
- Staging files (`git add`) is also a git state mutation. Ask first unless the user explicitly asked to commit or prepare a commit.
- If approval is ambiguous, stop and ask.

## Dotfiles stow safety

- In the dotfiles repo, never manually create symlinks from `~/.dots` into `$HOME`. Dotfile linking must go through the user's `stow_check` dry-run and `stow_do` apply commands.
- If `stow_check` reports a conflict, stop and explain the conflict. Do not work around Stow by running `ln -s`, replacing targets manually, or using `stow --adopt` unless the user explicitly approves that exact action.

## Command efficiency

- Prefer targeted, low-latency commands over broad scans or mass replacements. Scope `rg`, tests, RuboCop, and file edits to the smallest relevant paths first; run full checks only at step boundaries or when needed.
- Avoid broad `perl -pi`, `sed -i`, or repo-wide replacements when strings overlap (for example rename/revert work). Use precise `edit` replacements or a small script with explicit file lists and post-change verification.
- Before running a command that may take more than a few seconds, state what it will do and why. After it returns, immediately summarize the result and next action.
- To avoid avoidable Pi permission prompts, do not send multiline bash payloads when the same work can be done with separate tool calls or one safe line joined with `;` / `&&`. Pi permission checks handle pipelines/segments better than newline-separated pasted blocks.
- Avoid shell command substitution for file discovery plus reading, such as `cat $(find app -name 'foo.rb' | head -1)`. Prefer one safe listing command (`find app -name 'foo.rb' -print -quit` or `rg --files app | rg 'foo\.rb$'`) followed by the read tool on the discovered path.
- For numbered file snippets, prefer the read tool or `nl -ba <file> | sed -n '<range>p'`; avoid ad-hoc `awk` line-numbering commands when `nl -ba` does the same job.

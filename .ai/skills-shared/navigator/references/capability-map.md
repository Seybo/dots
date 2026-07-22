# Navigator Capability Map

This file is the curated, human-friendly map. Keep it concise. Generated inventory lives in `inventory.generated.md`.

## Navigator

- `/skill:navigator <question>` — ask what tool, skill, command, abbreviation, or source to use.
- `/skill:navigator update` — the only valid update trigger; refreshes generated inventory and uncategorized lists.

## GitHub / PRs / code review

- `/skill:claude-super-review` — default deep code-review workflow for PRs, branches, diffs, and uncommitted changes.
- `/skill:claude-super-fix` — verify and apply real, in-scope fixes from a saved super-review report.
- `/skill:addressit` — interactively fetch and address GitHub PR review comments one at a time.
- `/skill:delete-merged-branches` — delete local git branches that were merged and removed from remote.
- GitHub PR review fetch rule — source: `/Users/inseybo/.pi/agent/AGENTS.md` and project `AGENTS.md` files.

## Shortcut / task workflow

- `/skill:shortcut` — read Shortcut stories, create minimal Shortcut stories, and update story descriptions.
- `/skill:projectit` — create a project task root, expected code directory, and git repo for the task workflow.
- `/skill:taskit` — create task folders under `/Volumes/dev/_tasks`, or create a Shortcut story from `task.md`.
- `/skill:draftit` — save selected conversation context into a draft task folder.
- `/skill:workit` — start work from an existing task folder.
- `/skill:sumit` — summarize a task file into PR-description text with reviewer gotchas and copy it to the clipboard.
- `/skill:autowork` — orchestrate an existing task plan across Pi and Claude panes, with commits, reviews, checks, and bounded fixes.

## Local dev environment / dotfiles

- `/skill:agent-permissions` — explain or update Claude Code and Pi command permissions/allowlists.
- `/skill:dots-backup` — report dotfiles backup destinations, coverage, overlaps, and stored run status.
- `/skill:dots-check` — scan dotfiles changes for secrets or sensitive data before publishing.
- `/skill:dots-commit` — review uncommitted dotfiles changes and suggest focused commit groups and messages.
- `/skill:skills-manager` — audit and manage external Claude and Pi skills through the controlled installer.
- `/skill:misc-helper` / `/misc-helper` — run small personal helper utilities, currently DaVinci Resolve process cleanup.
- Dev-env refs — source: `/Users/inseybo/.dots/refs/dev-env`.
- Dots repo rules — source: `/Users/inseybo/.dots/AGENTS.md` and `/Users/inseybo/.pi/agent/AGENTS.md`.

## Themes / UI environment

- `/skill:theme` — create, update, and debug environment themes across Ghostty, Neovim, Starship, fzf, Zellij, Pi, Claude Code, and Lazygit.

## Neovim / terminal app help

- `/skill:app-help` — answer short how-to questions about terminal apps and Neovim plugins using local registry docs.
- `/skill:nvim-update` — audit whether pinned Neovim lazy.nvim plugins can be safely bumped. Report only; never edit.

## Ruby / Rails console

- `/skill:run-in-pry` — run Ruby code inside a project's Pry/Rails console setup.

## Documentation lookup

- `/skill:find-docs` — fetch current documentation, API references, and examples for libraries, frameworks, SDKs, CLIs, and cloud services.
- `/skill:web-search` — search current public information through the isolated Brave broker.

## Explaining code and flows

- `/skill:explain-file` — explain one file paragraph by paragraph.
- `/skill:explain-flow` — trace how a specific feature or flow executes through a codebase.

## Planning / communication modes

- `/skill:grilling` — stress-test a plan or design with relentless one-question-at-a-time interviewing.
- `/skill:grillme` — legacy/direct plan-grilling command.
- `/skill:grillme-docs` — plan-grilling variant that also maintains domain docs.
- `/skill:domain-modeling` — sharpen domain terminology, ubiquitous language, glossary entries, and ADRs.
- `/skill:caveman` — compressed communication mode for lower token usage.

## Abbreviations

- `00ao` — answer only after investigating; do not change files or state.
- `00ex` — explain referenced text in simple, precise terms.
- `00gf` — give feedback on referenced idea or text.
- `00rar` — read the other agent's latest task-folder review file (`claude_review*.md` in Pi, `pi_review*.md` in Claude).
- `00rvu` — review unstaged changes only; do not run specs or RuboCop.

## Pi system docs

Use Pi docs only when the question is about Pi itself, its SDK, extensions, themes, skills, prompt templates, TUI, keybindings, custom providers, models, or packages.

Primary docs root:

```text
/Users/inseybo/.asdf/installs/nodejs/24.0.1/lib/node_modules/@earendil-works/pi-coding-agent/docs
```

# Navigator Capability Map

This file is the curated, human-friendly map. Keep it concise. Generated inventory lives in `inventory.generated.md`.

## Navigator

- `/skill:navigator <question>` — ask what tool, skill, command, abbreviation, or source to use.
- `/skill:navigator update` — the only valid update trigger; refreshes generated inventory and uncategorized lists.

## GitHub / PRs / code review

- `/skill:claude-super-review` — default deep code-review workflow for PRs, branches, diffs, and uncommitted changes.
- `/skill:addressit` — interactively fetch and address GitHub PR review comments one at a time.
- `/skill:address-review` — fetch PR review comments and create a todo list.
- `/skill:delete-merged-branches` — delete local git branches that were merged and removed from remote.
- GitHub PR review fetch rule — source: `/Users/inseybo/.pi/agent/AGENTS.md` and project `AGENTS.md` files.

## Shortcut / task workflow

- `/skill:shortcut` — read Shortcut stories, create minimal Shortcut stories, and update story descriptions.
- `/skill:taskit` — create task folders under `/Volumes/dev/_tasks`, or create a Shortcut story from `task.md`.
- `/skill:draftit` — save selected conversation context into a draft task folder.
- `/skill:workit` — start work from an existing task folder.

## Local dev environment / dotfiles

- `/skill:agent-permissions` — explain or update Claude Code and Pi command permissions/allowlists.
- `/skill:dots-check` — scan dotfiles changes for secrets or sensitive data before publishing.
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

## Explaining code and flows

- `/skill:explain-file` — explain one file paragraph by paragraph.
- `/skill:explain-flow` — trace how a specific feature or flow executes through a codebase.

## Planning / communication modes

- `/skill:grillme` — stress-test a plan or design with relentless questions.
- `/skill:caveman` — compressed communication mode for lower token usage.

## Abbreviations

- `00ex` — explain referenced text in simple, precise terms.
- `00gf` — give feedback on referenced idea or text.
- `00rvu` — review unstaged changes only; do not run specs or RuboCop.

## Pi system docs

Use Pi docs only when the question is about Pi itself, its SDK, extensions, themes, skills, prompt templates, TUI, keybindings, custom providers, models, or packages.

Primary docs root:

```text
/Users/inseybo/.asdf/installs/nodejs/24.0.1/lib/node_modules/@earendil-works/pi-coding-agent/docs
```

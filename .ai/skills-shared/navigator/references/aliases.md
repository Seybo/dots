# Navigator Aliases

Use this file to map vague user wording to likely capabilities. The exact source of truth remains the named skill or reference file.

## GitHub / PRs

- `github`, `gh`, `pr`, `pull request`, `review PR`, `review my branch`, `look at diff`, `code review` → `/skill:claude-super-review`
- `review comments`, `address comments`, `inline comments`, `review id` → `/skill:addressit`
- `stale branches`, `merged branches`, `delete branches` → `/skill:delete-merged-branches`

## Shortcut / tasks

- `shortcut`, `story`, `stories`, `clubhouse` → `/skill:shortcut`
- `create project`, `project setup`, `new project workspace`, `project task root` → `/skill:projectit`
- `create task`, `task folder`, `task.md`, `shortcut story from task` → `/skill:taskit`
- `draft task`, `save this for later`, `capture context` → `/skill:draftit`
- `start task`, `work on task` → `/skill:workit`
- `summarize task`, `task summary`, `PR text from task`, `PR description from task` → `/skill:sumit`

## Local dev environment / dotfiles

- `local dev environment`, `dev env`, `dev-env refs`, `refs/dev-env` → read `/Users/inseybo/.dots/refs/dev-env`
- `permission`, `allowlist`, `approval prompt`, `agent permissions`, `pi permissions`, `claude permissions` → `/skill:agent-permissions`
- `publish dots`, `secret scan`, `sensitive data`, `dotfiles check` → `/skill:dots-check`
- `davinci`, `resolve stuck`, `kill resolve`, `stuck app process` → `/skill:misc-helper` or `/misc-helper davinci-kill`

## Themes / UI

- `theme`, `colors`, `ghostty`, `starship`, `fzf`, `zellij`, `lazygit`, `env-active` → `/skill:theme`

## Neovim / app help

- `nvim plugin`, `neovim plugin`, `terminal app`, `how do I use app/plugin` → `/skill:app-help`
- `update nvim plugins`, `lazy-lock`, `plugin bump` → `/skill:nvim-update`

## Ruby / Rails

- `pry`, `rails console`, `ruby console`, `run in console` → `/skill:run-in-pry`

## Docs

- `docs`, `documentation`, `api reference`, `how do I use library`, `version migration`, `CLI usage` → `/skill:find-docs`

## Explanation

- `explain file`, `walk through file` → `/skill:explain-file`
- `explain flow`, `what happens when`, `walk me through feature` → `/skill:explain-flow`

## Planning / communication

- `grill me`, `stress-test`, `challenge this plan`, `grilling` → `/skill:grilling` or `/skill:grillme`
- `grill with docs`, `grill and document`, `grillme-docs` → `/skill:grillme-docs`
- `domain model`, `ubiquitous language`, `glossary`, `ADR`, `architecture decision` → `/skill:domain-modeling`
- `caveman`, `be brief`, `less tokens`, `compressed` → `/skill:caveman`

## Abbreviations

- `00ex` → explain referenced text.
- `00gf` → give feedback on referenced text or idea.
- `00rar` → read the other agent's latest task-folder review file (`claude_review*.md` in Pi, `pi_review*.md` in Claude).
- `00rvu` → review unstaged changes only; no specs or RuboCop.

---
name: app-help
description: Helps answer short how-to questions about terminal apps and Neovim plugins by checking app-specific sources in apps/<app>.md and plugin-specific sources in nvim/plugins/<plugin>.md, preferring local docs first, and creating a new registry file when the app or plugin is unknown and decent sources can be discovered.
---

# App Help

Use this skill for short how-to questions about command-line or terminal applications, and for Neovim plugins.

Typical input:

- `lf how to show hidden files?`
- `tmux rename window`
- `fzf preview file contents`

## Goals

- Answer briefly
- Prefer local documentation first
- Include local config files in the context when they exist
- Keep a small app registry in `apps/`
- Keep a small Neovim plugin registry in `nvim/plugins/`
- Use registry files only as source registries, not as replacement manuals
- If an app is unknown, discover sources and add `apps/<app>.md` before answering
- If a Neovim plugin is unknown, discover sources and add `nvim/plugins/<plugin>.md` before answering
- Always cite the source actually used

## Files

- Skill root: `~/.dots/.agents/skills/app-help`
- App registry: `~/.dots/.agents/skills/app-help/apps`
- App template: `~/.dots/.agents/skills/app-help/apps/_template.md`
- Neovim plugin registry: `~/.dots/.agents/skills/app-help/nvim/plugins`
- Local dotfiles root: `~/.dots`

The local dotfiles tree is managed by GNU Stow by the user. Do not run any `stow` commands.

## Input parsing

Treat the first token of the user input as the app name.
Treat the rest as the question.

Examples:

- `lf how to show hidden files?` → app: `lf`, question: `how to show hidden files?`
- `git how do I undo the last commit?` → app: `git`, question: `how do I undo the last commit?`

If the input is ambiguous or missing the app name, ask one short clarifying question.

## Workflow

1. Parse whether the question is about a terminal app or a Neovim plugin, then extract the name and question.
2. For terminal apps, look for `~/.dots/.agents/skills/app-help/apps/<app>.md`.
3. For Neovim plugins, look for `~/.dots/.agents/skills/app-help/nvim/plugins/<plugin>.md`.
4. If the registry file exists, read it only to learn which sources and config files to consult.
5. Then consult the actual docs and local config files named there for the current question, even if the same question was answered before.
6. If the registry file does not exist:
   - discover decent sources for the app or plugin
   - discover likely local config files under `~/.dots`
   - create the appropriate registry file
   - then consult the actual docs/configs and answer
7. Answer in a short form.
8. Include the source used.

## Source priority

Use sources in this order unless the app file says otherwise:

1. Local man page: `man <app>`
2. Local help output:
   - `<app> --help`
   - `<app> -h`
   - `<app> help`
3. Known local docs named in the app file
4. Known local config files named in the app file, when the question is about behavior, defaults, keybindings, or setup in the user's environment
5. Official online docs named in the app file
6. Other official upstream sources if clearly identified during discovery

Do not prefer random third-party pages over official docs when official docs are available.

## Unknown app discovery

When `apps/<app>.md` or `nvim/plugins/<plugin>.md` is missing, do a best-effort discovery.

### Local discovery

Try these first:

```bash
man <app>
<app> --help
<app> -h
<app> help
command -v <app>
which <app>
```

Also inspect local documentation paths if they are easy to infer from help output or package layout.

### Local config discovery

Check whether the app has local config files under `~/.dots`.
Look for obvious app-specific paths and filenames such as:

```bash
find ~/.dots -iname '*<app>*'
```

Also look for standard XDG-style and dotfile-style locations when they are easy to infer, for example:

- `.config/<app>/...`
- `.<app>rc`
- app-specific config filenames mentioned by `man <app>` or `<app> -doc`

Only record config paths that actually exist in `~/.dots`.
Do not run `stow`.

### Official source discovery

If local docs mention a homepage, repo, maintainer URL, or bundled doc path, use that.
For Neovim plugins, prefer the plugin repo, README, `:help` tags, and any bundled docs under the plugin.
If a clearly official upstream source can be identified, include it in the new registry file.

### Creation rule

Create `apps/<app>.md` or `nvim/plugins/<plugin>.md` only if you found at least one decent source, such as:

- a working man page
- usable help output
- a clear local doc path
- a real local config path in `~/.dots`
- a clearly official upstream doc or repo

If discovery is too weak, do not create a low-quality registry file. Answer from the best local evidence available and say that a curated registry file was not added yet.

## Registry file format

Keep each app or plugin registry file concise and structured. Follow `apps/_template.md` for app files, and use the same structure for plugin files under `nvim/plugins/`.

Registry files are only source registries. They should point to the real manuals and docs, not summarize them.

Expected sections:

- `# <app>`
- `## Local sources`
- `## Local configs`
- `## Official sources`

When creating or updating a registry file:

- prefer concrete commands, file paths, and URLs
- keep bullets short
- avoid speculative claims
- only list local config files that actually exist
- do not copy factual answers from the docs into the app file
- do not add tips, summaries, keybindings, config explanations, or mini-manual content unless they are needed to locate the real docs or real config files

## Answer format

Keep answers short. Usually use 2-4 bullets max.

Preferred style:

- direct answer first
- exact command, keybinding, or config snippet if relevant
- mention the local config path when the answer depends on user config
- one source line

Examples:

- Use `zh` to toggle hidden files.
- Source: `man lf`

or

- Rename the current window with `Ctrl-b ,`.
- Source: `man tmux`

For online sources, include a short label and URL:

- Source: `lf doc.md` — `https://...`

## Source citation rules

- If the answer came from a local doc source, cite the command or document name only.
- If the answer came from a local config file, cite the config file path.
- If the answer came from an online source, cite a short label plus URL.
- Cite the actual source used, not every source consulted.

## When updating registry files

Update an existing app or plugin registry file when discovery reveals a clearly better official source, local doc path, `:help` entry, plugin repo, or real local config path.
Keep edits small and maintain the existing structure.

## Constraints

- Focus on terminal apps and Neovim plugins.
- Assume the installed app or plugin is reasonably up to date.
- Do not over-explain unless asked.
- Prefer local docs over memory.
- Prefer official docs over third-party pages.
- Re-check the actual manual/docs for every query; do not treat `apps/<app>.md` as authoritative content.
- If the answer is uncertain, say so briefly.

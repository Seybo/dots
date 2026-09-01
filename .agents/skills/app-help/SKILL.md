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
- Keep a small shared app registry in `apps/`
- Keep Oma-authored app additions in its writable pending registry until Squirrel promotes them
- Keep a small Neovim plugin registry in `nvim/plugins/`
- Use registry files primarily as source registries
- Add a gotcha only when it captures a hard-won issue that was genuinely difficult to solve and is likely to recur
- Never add project-specific names, commands, layouts, or paths to the public app registry
- Never use registry files as snapshots of volatile runtime config or current app state
- If an app is unknown, discover sources and add it to the registry owned by the current machine before answering
- If a Neovim plugin is unknown, discover sources and add `nvim/plugins/<plugin>.md` on Squirrel before answering
- Always cite the source actually used

## Files

- Skill root: `~/.dots/.agents/skills/app-help`
- Shared app registry: `~/.dots/.agents/skills/app-help/apps`
- Oma pending app registry: `$STOW_DIR/.agents/app-help/apps`
- App template: `~/.dots/.agents/skills/app-help/apps/_template.md`
- Neovim plugin registry: `~/.dots/.agents/skills/app-help/nvim/plugins`
- Shared dotfiles root: `~/.dots`

Require `MACHINE_NAME=squirrel|oma`. Require `STOW_DIR=$HOME/.dots` on Squirrel and `STOW_DIR=$HOME/.omadots` on Oma. The local dotfiles tree is managed by GNU Stow by the user. Do not run any `stow` commands.

## Input parsing

An exact `--promote-oma` argument invokes the explicit promotion workflow below. Reject that flag when it has any additional argument. Do not interpret it as an app name.

For every other invocation, treat the first token of the user input as the app name.
Treat the rest as the question.

Examples:

- `lf how to show hidden files?` → app: `lf`, question: `how to show hidden files?`
- `git how do I undo the last commit?` → app: `git`, question: `how do I undo the last commit?`

If the input is ambiguous or missing the app name, ask one short clarifying question.

## Workflow

1. Parse whether the question is about a terminal app or a Neovim plugin, then extract the name and question.
2. For terminal apps:
   - on Squirrel, read only `~/.dots/.agents/skills/app-help/apps/<app>.md`
   - on Oma, read both the shared file and `$STOW_DIR/.agents/app-help/apps/<app>.md` when they exist; treat the Oma file as additions and use its machine-specific evidence when the files conflict
3. For Neovim plugins, look for `~/.dots/.agents/skills/app-help/nvim/plugins/<plugin>.md`. This registry remains shared and read-only on Oma.
4. Read registry files only to learn which sources and config files to consult.
5. Then consult the actual docs and local config files named there for the current question, even if the same question was answered before.
6. If no registry file exists:
   - discover decent sources for the app or plugin
   - discover likely local config files on the current machine
   - on Squirrel, create the appropriate shared registry file
   - on Oma, create terminal-app entries under `$STOW_DIR/.agents/app-help/apps/`; create the parent directory when missing, but do not create or update shared registry files
   - then consult the actual docs/configs and answer
7. Answer in a short form.
8. Include the source used.
9. Before finishing, update a registry only when the task resolved a hard-won, non-obvious issue that was genuinely difficult to solve and is likely to recur. Routine lookups, obvious config facts, local conventions, and project-specific details do not qualify. On Squirrel, add a qualifying note to the related shared registry file. On Oma, add only the qualifying new terminal-app information to the pending file without copying shared content. Keep the shared Neovim plugin registry read-only on Oma.

## Promote Oma app knowledge

Run this workflow only for the exact invocation:

```text
/skill:app-help --promote-oma
```

1. Require `MACHINE_NAME=squirrel`, `STOW_DIR=$HOME/.dots`, and a current Git repository root exactly equal to `$HOME/.dots`. Stop without SSH or mutation when any requirement fails.
2. Through SSH alias `oma`, list every first-level Markdown file under `$HOME/.omadots/.agents/app-help/apps/`. If the directory or matching files do not exist, report that nothing is pending and stop. Do not inspect this directory during normal app-help use.
3. Read every pending file completely. For each item, use its cited source and relevant shared entry to decide whether the information is general or Oma-specific. Do not classify information from its storage location alone.
4. Prepare one complete proposed merge into the shared app registry. Preserve portable sources as general information and keep machine-specific behavior clearly scoped to Oma. If any item is unclear or should remain pending, stop the whole batch and explain what must be adjusted; do not add selection or partial-promotion controls.
5. Show the complete proposed changes and wait for one explicit approval. Before approval, do not edit shared files or remove Oma files.
6. After approval, apply every merge to the shared registry and re-read the affected files. Verify that every pending source and useful gotcha is preserved with the correct scope. If any merge or verification fails, remove no Oma files.
7. Only after the complete batch verifies, remove the promoted Oma files using their exact literal paths. Do not remove the pending directory or unrelated files. Report Oma's `systemctl --user --failed --no-legend` result.
8. Do not stage, commit, push, pull, create promotion state or markers, or add another synchronization pass.

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

Check obvious paths under the active dotfiles repository and standard machine-local config locations such as `~/.config/<app>/`. Also inspect app-specific filenames mentioned by `man <app>` or `<app> -doc`.

Only record config paths that exist on the machine they are scoped to. A shared registry file may point to an Oma-local source when its machine scope is explicit. Never copy credentials or mutable config values into registry prose. Do not run `stow`.

### Official source discovery

If local docs mention a homepage, repo, maintainer URL, or bundled doc path, use that.
For Neovim plugins, prefer the plugin repo, README, `:help` tags, and any bundled docs under the plugin.
If a clearly official upstream source can be identified, include it in the new registry file.

### Creation rule

Create a registry entry only if you found at least one decent source, such as:

- a working man page
- usable help output
- a clear local doc path
- a real local config path on the scoped machine
- a clearly official upstream doc or repo

If discovery is too weak, do not create a low-quality registry file. Answer from the best local evidence available and say that a curated registry file was not added yet.

## Registry file format

Keep each app or plugin registry file concise and structured. Follow `apps/_template.md` for app files, and use the same structure for plugin files under `nvim/plugins/`.

Registry files are primarily source registries. They should point to the real manuals and docs, not summarize them. A gotcha is exceptional: include it only when it records a hard-won issue that was genuinely difficult to solve and is likely to save substantial investigation later.

Expected sections:

- `# <app>`
- optional `## Machine scope`
- `## Local sources`
- `## Local configs`
- `## Official sources`

A pending Oma file may contain only the sections and bullets being added; it must not duplicate the shared entry.

When creating or updating a registry file:

- prefer concrete commands, file paths, and URLs
- keep bullets short
- avoid speculative claims
- only list local config files that actually exist
- do not copy factual answers from the docs into the app file
- do not add generic tips, summaries, keybindings, config explanations, mini-manual content, or project-specific names, commands, layouts, and paths
- do not record volatile runtime state, current settings, generated rules, current thresholds, current durations, current process lists, installed plugin versions, active sessions, cache contents, or other values that are already represented in a real config/runtime file
- do not mirror config values from source files into registry prose; instead point to the source file or command that shows the current value
- add a local gotcha only for a source-backed, hard-won issue that was genuinely difficult to solve and is likely to recur

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
Update it with a gotcha only when the work resolved a hard-won, non-obvious issue that was genuinely difficult to solve and is likely to recur.
Do not update the registry for routine discoveries, project-specific details, local conventions, or because you changed a runtime setting, threshold, key value, generated wrapper, installed process rule, or other mutable config. The registry should point to where shared app knowledge lives, not duplicate project or runtime state.
Keep edits small and maintain the existing structure.

## Constraints

- Focus on terminal apps and Neovim plugins.
- Assume the installed app or plugin is reasonably up to date.
- Do not over-explain unless asked.
- Prefer local docs over memory.
- Prefer official docs over third-party pages.
- Re-check the actual manual/docs for every query; do not treat `apps/<app>.md` as authoritative content.
- If the answer is uncertain, say so briefly.

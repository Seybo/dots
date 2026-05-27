---
name: theme
description: Create, update, and debug this dotfiles repo's environment themes across Ghostty, Neovim, Starship, fzf, Zellij, Pi, and Claude Code. Use when the user asks to add a theme, modify theme colors, switch/theme behavior, or investigate theme rendering issues.
---

# Theme Skill

Use this skill for theme work in `~/.dots`: creating new themes, updating existing themes, or debugging theme questions/issues.

## First steps

1. Read the current local reference: `refs/dev-env/themes.md`.
2. Inspect the current implementation files relevant to the request:
   - `themes/theme_switcher.rb`
   - `no_stow/.zsh_aliases_public`
   - `.config/nvim/lua/plugins/theme.lua`
   - `.config/ghostty/config`
   - `.config/starship.toml`
   - `.config/zellij/config.kdl`
   - `.pi/agent/settings.json` when Pi theming is involved
   - `~/.claude/themes/theme.json` symlink when Claude Code theming is involved
3. Inspect at least one nearby existing theme under `themes/<name>/`; prefer `themes/dayfox/` for a simple complete modern theme and `themes/everforest-hard-light/` or `themes/nordfox/` for Pi-aware examples.
4. For upstream colors, use official source files whenever possible. Do not invent colors from screenshots or memory.

## Design principles

- No ad-hoc per-app switcher hacks. Prefer stable, app-native pointers into `themes/active/` such as config imports, theme directories, or symlinks.
- The switcher should stay generic: copy the selected theme directory into `themes/active/` and perform only broadly necessary notifications such as touching Zellij config. Do not add app-specific file copying or settings mutation unless there is no app-native integration path and the user explicitly approves it.
- For new app integrations, first ask: "Can this app load or symlink to a file under `themes/active/`?" Use that before modifying the switcher.

## How this environment's themes work

- Theme variants live in `themes/<name>/`.
- `themes/active/` is the active theme, but it is copied files, not symlinks.
- The switcher is `themes/theme_switcher.rb <theme>` and depends on `$STOW_DIR` (normally `~/.dots`).
- The normal user-facing command is the zsh function `theme <name>` in `no_stow/.zsh_aliases_public`.
- Agents should not switch the live theme themselves. Ask the user to run `theme <name>`.
- The switcher rejects `active`, deletes `themes/active/*`, copies every file from `themes/<name>/`, then touches `~/.config/zellij/config.kdl` so running Zellij sessions notice theme changes.
- `theme <name>` also reloads tmux if present, prints a Ghostty reload reminder when in Ghostty, and re-sources `themes/active/fzf.zsh` for the current shell.
- Claude Code should not get switcher-specific copy/settings logic. Claude only reads custom themes from `~/.claude/themes/`, so bridge it with a symlink: `~/.claude/themes/theme.json -> ~/.dots/themes/active/claude.json`. The user selects that custom theme with `/theme`; future `theme <name>` runs update the symlink target through the existing active-theme copy flow.

## App integration map

- `.zshrc` sets `STOW_DIR="$HOME/.dots"` and sources `themes/active/fzf.zsh`.
- Ghostty: `.config/ghostty/config` loads `~/.dots/themes/active/ghostty` with `config-file`.
- Starship: `.config/starship.toml` imports `~/.dots/themes/active/starship.toml`.
- Zellij: `.config/zellij/config.kdl` uses `theme_dir "/Users/inseybo/.dots/themes/active"` and `theme "active"`.
- Neovim: `.config/nvim/lua/plugins/theme.lua` defines theme plugins and an `active-theme` entry that runs `dofile(vim.env.STOW_DIR .. '/themes/active/nvim.lua')`.
- Pi: `.pi/agent/settings.json` selects `"theme": "env-active"` and loads `~/.dots/themes/active/pi.json` via its `themes` array.
- Claude Code: custom theme file `~/.claude/themes/theme.json` is a symlink to `~/.dots/themes/active/claude.json`; select it in Claude with `/theme`. Claude Code watches `~/.claude/themes/` and reloads custom theme files automatically.
- tmux is legacy only. `.tmux.conf.local` may source `themes/active/tmux.conf`, but new themes should not add tmux files unless the user explicitly asks for legacy support.
- Alacritty is retired. Do not add Alacritty theme files.
- Claude Code is wired through the symlink above, not by modifying the switcher or writing `~/.claude/settings.json` on every switch.

## Files in a theme directory

A standard modern theme should have a file for each current app integration:

- `fzf.zsh`
- `ghostty`
- `nvim.lua`
- `starship.toml`
- `zellij.kdl`
- `pi.json`
- `claude.json`

Older themes may lack `pi.json` or `claude.json` until they are modernized. Legacy Rose Pine themes may have `tmux.conf`; do not copy that pattern for new themes unless explicitly requested.

## Creating a new theme

1. Pick a slug such as `tokyonight-night`; create `themes/<slug>/`.
2. Find official upstream colors:
   - Prefer official generated files for Ghostty, Starship, Zellij, fzf, and Neovim.
   - If a tool-specific upstream file does not exist, derive from the canonical upstream palette only.
   - Add comments in converted files naming the exact upstream URL/file.
3. Add the standard modern files listed above.
4. For `nvim.lua`, configure and apply the colorscheme, e.g.:

   ```lua
   require('nightfox').setup({})
   vim.cmd('colorscheme dayfox')
   ```

5. If the Neovim colorscheme plugin is not already in `.config/nvim/lua/plugins/theme.lua`, add it as a separate top-level plugin entry. Do not make unrelated theme plugins dependencies of each other.
6. If `.config/nvim/lua/plugins/theme.lua` changed, stop and ask the user to run `nvim` so Lazy can install the plugin and verify the current active theme still works. Continue only after confirmation.
7. Ask the user to run `theme <slug>` and validate runtime behavior.

## Updating an existing theme

1. Identify the source theme directory, e.g. `themes/nordfox/`, and whether it is currently active by comparing files under `themes/active/`.
2. Update the source directory first, not only `themes/active/`. `themes/active/` will be overwritten on the next switch.
3. If the active theme is the one being edited and the app supports hot reload:
   - Pi reloads the active custom theme file automatically.
   - fzf in the current shell updates only after `source themes/active/fzf.zsh` or `re_fzf`.
   - Ghostty usually needs manual reload (`cmd+shift+,`) or restart.
   - Neovim usually needs restart/re-source because `active/nvim.lua` runs during plugin config.
   - Starship updates on a new prompt render after active file changes.
   - Zellij may update after config touch; otherwise reload/restart the session.
4. If editing a non-active theme, ask the user to switch to it for validation.

## File-specific rules

### `fzf.zsh`

- Exports `FZF_DEFAULT_OPTS`.
- Preserve these options unless intentionally changing behavior: `--height 40%`, `--layout=reverse`, `--ansi`.
- Change only the color section for normal theme edits.

### `ghostty`

- Contains Ghostty color settings only.
- Prefer upstream-generated Ghostty files.
- It is loaded through `.config/ghostty/config`, not stowed directly.

### `nvim.lua`

- Loads/configures the relevant colorscheme plugin and applies the colorscheme.
- Any required plugin must be declared in `.config/nvim/lua/plugins/theme.lua`.
- After plugin list changes, ask the user to open Neovim for Lazy install/verification before proceeding.

### `starship.toml`

- Usually contains only `palette = "..."` and the needed `[palettes.<name>]` table.
- Do not copy upstream `format` or module config unless intentionally changing prompt layout.
- Use only palette keys consumed by the main `.config/starship.toml` config.

### `zellij.kdl`

- Must define a theme named `active` because the global config selects `theme "active"`.
- If adapting an upstream theme, rename only the theme key to `active`.
- Hex colors are acceptable.

### `claude.json`

- Claude Code only discovers custom themes under `~/.claude/themes/`; it does not directly load arbitrary files from `~/.dots`.
- Do not add special copy or settings mutation to `themes/theme_switcher.rb` for Claude Code.
- Use a stable symlink instead: `~/.claude/themes/theme.json -> ~/.dots/themes/active/claude.json`.
- The user must select that custom theme in Claude Code with `/theme`. Do not edit `~/.claude/settings.json` from the switcher.
- If only one theme has Claude support for now, that is acceptable. Switching to a theme without `claude.json` leaves the symlink target missing until a Claude-aware theme is active again.
- Use Claude Code's custom theme JSON shape: `name`, `base`, and `overrides`. Prefer deriving colors from the local theme palette.

### `pi.json`

- Pi loads `~/.dots/themes/active/pi.json` and selects theme name `env-active`.
- The JSON `name` must be `env-active` for this unified active-theme flow.
- Include the Pi schema:

  ```json
  "$schema": "https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json"
  ```

- Define reusable colors in `vars` and reference them from `colors`.
- Pi requires all core theme tokens. Use existing `themes/nordfox/pi.json` or `themes/everforest-hard-light/pi.json` as local templates.
- Optional `export` controls `/export` HTML colors.
- If changing Pi theme semantics or token names, read Pi docs at `/Users/inseybo/.asdf/installs/nodejs/24.0.1/lib/node_modules/@earendil-works/pi-coding-agent/docs/themes.md`.

## Debugging checklist

- Wrong theme active: list `themes/active/` and compare with expected `themes/<name>/`.
- Switch command fails: verify `$STOW_DIR`, theme directory exists, and name is not `active`.
- Active edits disappear: changes were made directly in `themes/active/`; update the source `themes/<name>/` instead.
- fzf unchanged in an old shell: run `re_fzf` or `re_source`; new shells source active fzf automatically.
- Ghostty unchanged: reload with `cmd+shift+,` or restart Ghostty.
- Starship unchanged: verify `.config/starship.toml` import and the palette name in active `starship.toml`; trigger a new prompt.
- Zellij unchanged: verify `themes/active/zellij.kdl` defines `active`, then touch/reload `.config/zellij/config.kdl` or restart the Zellij session.
- Neovim missing colorscheme: check `.config/nvim/lua/plugins/theme.lua`, Lazy install state, and `themes/active/nvim.lua`.
- Pi unchanged: verify `.pi/agent/settings.json` points to `~/.dots/themes/active/pi.json`, active `pi.json` has `"name": "env-active"`, and JSON is valid.
- Claude Code unchanged: verify `~/.claude/themes/theme.json` is a symlink to `~/.dots/themes/active/claude.json`, active `claude.json` exists and is valid JSON, and Claude has selected the custom `theme` theme via `/theme`.

## Validation commands

Prefer targeted, read-only checks first:

```bash
ls themes/<name>
ruby -c themes/theme_switcher.rb
ruby -rjson -e 'JSON.parse(File.read(ARGV[0])); puts "ok"' themes/<name>/pi.json
ruby -rjson -e 'JSON.parse(File.read(ARGV[0])); puts "ok"' themes/<name>/claude.json
rg -n 'theme "active"|theme_dir' .config/zellij/config.kdl
rg -n 'themes/active|active-theme|colorscheme' .config/nvim/lua/plugins/theme.lua themes/<name>/nvim.lua
```

Do not launch Neovim, switch active themes, reload terminal apps, or otherwise mutate the user's live UI session unless the user explicitly asks.

## Maintenance

If the theme mechanism changes, update both:

- `refs/dev-env/themes.md`
- this skill file: `.agents/skills/theme/SKILL.md`

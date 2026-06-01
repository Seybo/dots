# zellij

## Local sources

- `zellij --help`

## Local configs

- `~/.dots/.config/zellij/config.kdl`
- `~/.dots/.config/zellij/layouts/`
- `~/.dots/.config/zellij/themes/`

## Official sources

- Keybindings docs: `https://zellij.dev/documentation/keybindings`
- Configuration docs: `https://zellij.dev/documentation/configuration.html`
- Default keybindings reference: `https://github.com/zellij-org/zellij/blob/main/zellij-utils/assets/config/default.kdl`
- Built-in tab-bar source: `https://github.com/zellij-org/zellij/blob/main/default-plugins/tab-bar/src/tab.rs`

## Known issues

- Tab label shows `[ ]` / colored block: this is the tab-bar multiplayer focused-client indicator, not the app running there. Check clients with `ZELLIJ_SESSION_NAME=<session> zellij action list-clients`; remove stale attached clients by killing the matching `zellij attach <session>` PID from `ps -axo pid,ppid,stat,command | rg 'zellij'`. Do not kill `zellij --server .../<session>` unless you want to kill the session.

## Common defaults

- Sessions: `Ctrl-o`, then `w` opens session manager for create / switch / delete
- Tabs: `Ctrl-t`, then `n` create; `Ctrl-t`, then `x` delete
- Panes: `Ctrl-p`, then `n` create; `d` split down; `r` split right; `s` stacked; `x` delete
- Borders: `Ctrl-p`, then `z`
- Tabs nav: `Ctrl-t`, then `h/l`

# tmux

## Local sources

- `man tmux`
- `tmux -V`
- `tmux list-keys -N`

## Local configs

- `~/.dots/.tmux.conf`
- `~/.dots/no_stow/.zsh_aliases_public`
- `~/.dots/.config/ghostty/config`
- `~/.dots/themes/active/tmux.conf` when present
- `~/.dots/themes/*/tmux.conf`

## Official sources

- Upstream repository/wiki: `https://github.com/tmux/tmux/wiki`
- Upstream manual source: `https://github.com/tmux/tmux/blob/master/tmux.1`

## Local gotchas

- Local tmux keeps the default `Ctrl-b` prefix; Ghostty `Cmd-p` enters local pane mode, where `n` splits right and `N` splits down.
- Local tmux theme loading expects `~/.dots/themes/active/tmux.conf` when the active theme provides tmux styling; otherwise tmux keeps its base styling.
- With local `allow-set-title off`, tmux prevents programs such as Pi and Claude from overwriting tmuxinator `select-pane -T` pane titles after startup.
- Local config has `mouse on`; tmux's default `MouseDrag1Border` binding resizes panes and can be unbound while keeping mouse scroll/click support.
- Local `claude`, `pi-p`, and `pi-w` shell wrappers start `no_stow/bin/tmux/agent-attention-notify --pane "$TMUX_PANE"`, which polls `tmux capture-pane` for approval/input notifications.
- The agent count is wrapper bookkeeping in global `@agent-running-*` options, not a process count; stale pane IDs can remain because the watcher’s `display-message -t` existence check returns success even for missing targets.
- Status-bar rounded ends are simulated with theme-specific Powerline glyphs in `~/.dots/themes/*/tmux.conf`; tmux cannot round status-cell backgrounds natively.

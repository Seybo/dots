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
- Local tmux theme loading currently expects `~/.dots/themes/active/tmux.conf`, but most current themes only have Zellij/Ghostty/etc. files.
- With local `allow-set-title on`, programs such as Pi and Claude can overwrite tmuxinator `select-pane -T` pane titles after startup.
- Local config has `mouse on`; tmux's default `MouseDrag1Border` binding resizes panes and can be unbound while keeping mouse scroll/click support.
- Local `claude`, `pi-p`, and `pi-w` shell wrappers start `no_stow/bin/tmux/agent-attention-notify --pane "$TMUX_PANE"`, which polls `tmux capture-pane` for approval/input notifications.

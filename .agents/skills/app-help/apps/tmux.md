# tmux

## Local sources

- `man tmux`
- `tmux -V`
- `tmux list-keys -N`

## Local configs

- `~/.dots/.tmux.conf`
- `~/.dots/.tmux.conf.local`
- `~/.dots/no_stow/.zsh_aliases_public`
- `~/.dots/.config/ghostty/config`
- `~/.dots/themes/active/tmux.conf` when present
- `~/.dots/themes/*/tmux.conf`

## Official sources

- Upstream repository/wiki: `https://github.com/tmux/tmux/wiki`
- Upstream manual source: `https://github.com/tmux/tmux/blob/master/tmux.1`

## Local gotchas

- Local tmux uses `F4` as prefix, not the default `Ctrl-b`; `.tmux.conf.local` also unsets `prefix2` and unbinds `C-B`.
- Local tmux theme loading currently expects `~/.dots/themes/active/tmux.conf`, but most current themes only have Zellij/Ghostty/etc. files.

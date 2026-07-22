# nvim

## Local sources
- `man nvim`
- `nvim --help`

## Local configs
- `~/.dots/.config/nvim/lua/plugins/theme.lua`
- `~/.dots/themes/active/nvim.lua`
- `~/.dots/themes/theme_switcher.rb`

## Known local gotchas
- `themes/active/nvim.lua` must be reloaded as Lua with `dofile(...)`; `:source` would parse it as Vimscript.

## Official sources
- https://neovim.io/doc/user/

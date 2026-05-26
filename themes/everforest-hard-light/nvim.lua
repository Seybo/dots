-- Everforest hard light Neovim colors.
-- Customized local variant using the official upstream Everforest theme.
-- Upstream: https://github.com/sainnhe/everforest
vim.o.background = 'light'
vim.g.everforest_background = 'hard'
vim.g.everforest_enable_italic = 1
vim.g.everforest_colors_override = {
  fg = { '#3D484D', '239' },
  bg0 = { '#FFFDF6', '230' },
}
vim.cmd('colorscheme everforest')

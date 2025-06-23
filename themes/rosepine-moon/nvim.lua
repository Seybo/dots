local bg_color = '#282c34'

require('rose-pine').setup({
  palette = {
    moon = {
      base = bg_color,
      surface = bg_color,
      overlay = bg_color,
    },
  },
})

vim.cmd('colorscheme rose-pine-moon')

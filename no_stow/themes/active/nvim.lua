-- ==============================================================================
-- THIS FILE IS GENERATED AUTOMATICALLY
-- IT IS COMMITED ONLY ONCE FOR DEMONSTRATION PURPOSES
-- ==============================================================================
-- bg color is defined in alacritty theme config
local bg_color = vim.env.BG_COLOR

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

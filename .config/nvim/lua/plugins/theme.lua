return {
  -- kanagawa
  -- "rebelot/kanagawa.nvim",
  -- config=function()
  --   require('kanagawa').setup({
  --     compile = false,             -- enable compiling the colorscheme
  --   })

  --   vim.cmd("colorscheme kanagawa-wave")
  -- end

  -- rose-pine
  'rose-pine/neovim',
  config = function()
    local bg_color = vim.env.BG_COLOR

    require('rose-pine').setup({
      palette = {
        moon = {
          base = bg_color,
          surface = bg_color, -- panels & borders
          overlay = bg_color, -- pop-ups & floats
        },
      },
    })

    vim.cmd('colorscheme rose-pine-moon')
  end,
}

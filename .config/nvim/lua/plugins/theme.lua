return {
  -- tokyonight
  -- "folke/tokyonight.nvim",
  -- lazy = false, -- make sure we load this during startup if it is your main colorscheme
  -- priority = 1000, -- make sure to load this before all the other start plugins
  -- config = function()
  --   -- load the colorscheme here
  --   vim.cmd([[colorscheme tokyonight]])
  -- end,

  -- catppuccin
  -- "catppuccin/nvim",
  -- name = "catppuccin",
  -- priority = 1000,
  -- config = function()
  --   require("catppuccin").setup({
  --     flavour = "macchiato", -- latte, frappe, macchiato, mocha
  --     background = {         -- :h background
  --       light = "latte",
  --       dark = "mocha",
  --     },
  --     styles = {                 -- Handles the styles of general hi groups (see `:h highlight-args`):
  --       comments = { "italic" }, -- Change the style of comments
  --       conditionals = { "italic" },
  --     },
  --   })
  --
  --   -- setup must be called before loading
  --   vim.cmd.colorscheme "catppuccin"
  -- end,


  -- "rebelot/kanagawa.nvim",
  -- config = function()
  --   require('kanagawa').setup({
  --     compile = false, -- enable compiling the colorscheme
  --     colors = {
  --       palette = {
  --         -- replace every use of waveBlue1 (#223249 or #213249) with your new hex
  --         waveBlue1 = "#242424", -- ← your dark-gray choice
  --       },
  --       theme = {
  --         -- for *every* theme:
  --         all = {
  --           ui = {
  --             bg = "#2A2A37",
  --             bg_visual = "#1f1f28", -- your new Visual-mode bg
  --           },
  --         },
  --         -- OR just for wave:
  --         -- wave = {
  --         --   ui = { bg = "#eeeeee" },
  --         -- },
  --       },
  --     },
  --   })
  --
  --   vim.cmd("colorscheme kanagawa-wave")
  -- end

  "rose-pine/neovim",
  config = function()
    require("rose-pine").setup({
      palette = {
        moon = {
          base = "#2A2A37",
          surface = "#2A2A37", -- panels & borders
          overlay = "#2A2A37", -- pop-ups & floats
        },
      },
    })

    vim.cmd("colorscheme rose-pine-moon")
  end
}

-- [[ Tips ]]
-- You can use :source $VIMRUNTIME/syntax/hitest.vim to see all highlighting groups.
-- You can use :lua print(vim.inspect(require('catppuccin/nvim'))) command to check all available colors.
-- To see all the hightligt groups: :highlight
-- To see the color of element under cursor: :Inspect
-- To update the color returned by :Inspect update what it says it "links to": hi @variable guifg=#FF0000

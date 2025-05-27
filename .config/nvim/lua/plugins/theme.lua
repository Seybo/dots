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
  "catppuccin/nvim",
  name = "catppuccin",
  priority = 1000,
  config = function()
    require("catppuccin").setup({
      flavour = "macchiato", -- latte, frappe, macchiato, mocha
      background = {         -- :h background
        light = "latte",
        dark = "mocha",
      },
      styles = {                 -- Handles the styles of general hi groups (see `:h highlight-args`):
        comments = { "italic" }, -- Change the style of comments
        conditionals = { "italic" },
      },
    })

    -- setup must be called before loading
    vim.cmd.colorscheme "catppuccin"
  end,
}

-- [[ Tips ]]
-- You can use :source $VIMRUNTIME/syntax/hitest.vim to see all highlighting groups.
-- You can use :lua print(vim.inspect(require('catppuccin/nvim'))) command to check all available colors.
-- To see all the hightligt groups: :highlight
-- To see the color of element under cursor: :Inspect
-- To update the color returned by :Inspect update what it says it "links to": hi @variable guifg=#FF0000

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

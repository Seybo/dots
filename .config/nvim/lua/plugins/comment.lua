return {
  {
    'numToStr/Comment.nvim',
    opts = {},
    config = function(_, opts)
      local plugin = require "Comment"

      plugin.setup {
	-- LHS of toggle mappings in NORMAL mode
        toggler = {
            -- Line-comment toggle keymap
            line = "<C-c><C-c>",
            -- Block-comment toggle keymap
            block = "<C-c><C-b>",
        },
        -- LHS of operator-pending mappings in NORMAL and VISUAL mode
        opleader = {
            -- Line-comment keymap
            line = "<C-c><C-c>",
            -- Block-comment keymap
            block = "<C-c><C-b>",
        },
      }
    end,
  }
}

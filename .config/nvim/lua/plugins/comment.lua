return {
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    ---@module "ibl"
    ---@type ibl.config
    opts = {},
    config = function(_, opts)
      local plugin = require "ibl"

      plugin.setup {
        indent = {
          char = "⋅",
          -- show dots for all the spaces, don't cap
          smart_indent_cap = false,
        },
      }
    end
  }
}

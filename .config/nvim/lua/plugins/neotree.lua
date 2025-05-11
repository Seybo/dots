return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    lazy = false, -- neo-tree will lazily load itself
    config = function()
      -- vim.keymap.set("n", "<A-f><A-f>", "<Cmd>Neotree reveal<CR>")
      -- Using vim.api.nvim_set_keymap
vim.api.nvim_set_keymap("n", "<A-f><A-f>", "<Cmd>Neotree reveal<CR>", { noremap = true, silent = true })

    end,
  }
}



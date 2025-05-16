return {
  {
    "nvim-pack/nvim-spectre",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    config = function(_, opts)
      local plugin = require "spectre"

      plugin.setup {
        default = {
          find = {
            cmd = "rg",
            options = {},
          },
          replace = {
            cmd = "sed",
            options = {},
          },
        },
      }

      local function toggle()
        plugin.toggle()
        plugin.resume_last_search()
      end

      map { "<A-s><A-t>", "Search toggle", toggle, mode = { "n" } }
      map { "<A-s><A-r>", "Search toggle", "<cmd>lua require('spectre').resume_last_search()<CR>", mode = { "n" } }
      map { "<A-s><A-w>",
        "Search word under cursor",
        "<cmd>lua require('spectre').open_visual({select_word=true})<CR>",
        mode = { "n" },
      }
      map { "<A-s><A-w>", "Search selection", "<cmd>lua require('spectre').open_visual()<CR>", mode = { "v" } }
      map { "<A-s><A-f>", "Search on current file",
        "<cmd>lua require('spectre').open_file_search({select_word=true})<CR>", mode = {
        "v" } }
    end,
  }
}

return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      git = { enabled = true },
      gitbrowse = { enabled = true },
      picker = {
        enabled = true,
        sources = {
          explorer = {
            layout = {
              -- hide search input by default
              auto_hide = { "input" },
            },
          },
        },
      },
      scroll = {
        enabled = true,
        filter = function(buf)
          return vim.bo[buf].buftype ~= "terminal"
              and vim.bo[buf].filetype ~= "Avante"
        end,
      },
    },
    keys = {
      { "<leader>sp", function() Snacks.picker() end,           desc = "[Snacks] Picker" },
      { "<Leader>sb", function() Snacks.picker.lines() end,     desc = "[Snacks] Fuzzy search in current buffer" },
      { "<leader>sw", function() Snacks.picker.grep_word() end, desc = "[Snacks] Visual selection or word",      mode = { "n", "x" } },
      {
        "<leader>sf",
        function()
          Snacks.explorer({
            auto_close = true,
            hidden = true,
            ignored = true,
            layout = {
              preset = "default",
            },
          })
        end,
        desc = "[Snacks] File Explorer"
      },
    },
  }
}

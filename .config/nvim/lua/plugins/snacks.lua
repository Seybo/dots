return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      git = { enabled = true },
      gitbrowse = { enabled = true },
      picker = { enabled = true },
      scroll = { enabled = true },
    },
    keys = {
      { "<leader>sp", function() Snacks.picker() end, desc = "[Snacks] Picker" },
      {
        "<leader>sf",
        function()
          Snacks.explorer({
            auto_close = true,
            hidden = true,
            ignored = true,
          })
        end,
        desc = "[Snacks] File Explorer"
      },
    },
  }
}

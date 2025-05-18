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
    },
    keys = {
      { "<leader>pp", function() Snacks.picker() end, desc = "[Snacks] Picker" },
      {
        "<leader>pe",
        function()
          Snacks.explorer({
            auto_close = true,
            hidden = true,
          })
        end,
        desc = "[Snacks] Explorer"
      },
    },
  }
}

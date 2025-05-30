return {
  {
    "supermaven-inc/supermaven-nvim",
    opts = {
      disable_keymaps = true,
      condition = function()
        return string.match(vim.fn.expand("%:t"), "%.log$") -- skip log files
      end,
    }
  },
}

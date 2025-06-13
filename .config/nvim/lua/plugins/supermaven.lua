return {
  {
    'supermaven-inc/supermaven-nvim',
    opts = {
      disable_keymaps = true,
      condition = function()
        -- Skip log files
        if string.match(vim.fn.expand('%:t'), '%.log$') then return true end

        return false
      end,
    },
    config = function(opts) require('supermaven-nvim').setup(opts) end,
  },
}

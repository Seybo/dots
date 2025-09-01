return {
  {
    'supermaven-inc/supermaven-nvim',
    opts = {
      disable_keymaps = true,
      ignore_filetypes = { 'json.kulala_ui' },
      condition = function()
        local filename = vim.fn.expand('%:t')

        -- Skip log files
        if string.match(filename, '%.log$') then return true end

        return false
      end,
    },
    keys = {
      {
        '<c-t>m',
        ':SupermavenToggle<cr>',
        desc = '[ Toggl ] SuperMaven',
      },
    },
    config = function(_, opts) require('supermaven-nvim').setup(opts) end,
  },
}

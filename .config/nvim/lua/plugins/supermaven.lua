return {
  {
    'supermaven-inc/supermaven-nvim',
    opts = {
      disable_keymaps = true,
      ignore_filetypes = { 'json.kulala_ui', 'log', 'railslog' },
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

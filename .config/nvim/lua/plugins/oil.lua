return {
  'stevearc/oil.nvim',
  -- Lazy loading is not recommended because it is very tricky to make it work correctly in all situations.
  lazy = false,
  -- Optional dependencies
  dependencies = { 'nvim-tree/nvim-web-devicons' }, -- use if you prefer nvim-web-devicons
  ---@module 'oil'
  ---@type oil.SetupOpts
  opts = {
    keymaps = {
      ['q'] = { 'actions.close', mode = 'n' },
      ['<esc>'] = { 'actions.close', mode = 'n' },
    },
    view_options = {
      show_hidden = true,
    },
  },
  keys = {
    { '<leader>fo', ':Oil --preview<cr>', desc = '[ Oil ] Open' },
  },
}

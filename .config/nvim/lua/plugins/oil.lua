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
    {
      '<leader>fo',
      function()
        local path = vim.api.nvim_buf_get_name(0)
        local dir = path ~= '' and vim.fs.dirname(path) or vim.fn.getcwd()
        vim.cmd('Oil --preview ' .. vim.fn.fnameescape(dir))
      end,
      desc = '[ Oil ] Open current file directory',
    },
  },
}

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
        local oil = require('oil')
        oil.open(nil, nil, function()
          -- Oil positions the cursor asynchronously; preview only after that scheduled jump.
          vim.schedule(function()
            local entry = oil.get_cursor_entry()
            if entry and entry.id and entry.id ~= 0 then
              oil.open_preview()
            end
          end)
        end)
      end,
      desc = '[ Oil ] Open current file directory',
    },
  },
}

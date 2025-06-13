return {
  {
    'vim-test/vim-test',
    config = function(_, opts)
      -- so the focus doesnt switch to the terminal window
      local function NoFocusSwitch(cmd)
        -- Save the buffer if there are changes
        vim.cmd('update')
        vim.cmd('bel 15 new')
        vim.fn.termopen(cmd)
        vim.cmd('wincmd p') -- switch back to the last window
        -- vim.api.nvim_feedkeys("``", "n", false) -- for some reason it jumps to the beginning of buffer
      end

      vim.g['test#custom_strategies'] = { no_focus_switch = NoFocusSwitch }
      vim.g['test#strategy'] = 'no_focus_switch'
      -- vim.g["test#javascript#runner"] = "jest"
      -- vim.g["test#javascript#jest#executable"] = "yarn test"
      -- vim.g["test#javascript#jest#file_pattern"] = ".*\\.test\\.jsx$"
      -- vim.g["test#project_root"] = "/mnt/dev/shaka/popmenu"

      vim.keymap.set('n', '<leader>tss', vim.cmd.TestNearest, { desc = 'Test single' })
      vim.keymap.set('n', '<leader>tsr', '<c-w>jii:TestNearest<cr>', { desc = 'Test single (reopen terminal)' })
      vim.keymap.set('n', '<leader>tff', vim.cmd.TestFile, { desc = 'Test file' })
      vim.keymap.set('n', '<leader>tfr', '<c-w>jii:TestFile<cr>', { desc = 'Test file (reopen terminal)' })
      vim.keymap.set('n', '<leader>tll', vim.cmd.TestLast, { desc = 'Test last' })
      vim.keymap.set('n', '<leader>tlr', '<c-w>jii:TestLast<cr>', { desc = 'Test last (reopen terminal)' })
    end,
  },
}

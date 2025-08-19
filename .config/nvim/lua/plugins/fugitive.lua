return {
  {
    'tpope/vim-fugitive',
    config = function()
      vim.keymap.set('n', 'gbl', ':Git blame<cr>', { desc = 'Fugitive: Git blame' })
    end,
  },
}

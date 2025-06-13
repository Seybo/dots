return {
  {
    'AckslD/nvim-neoclip.lua',
    opts = {},
    dependencies = {
      -- for persistent history between sessions
      { 'kkharji/sqlite.lua', module = 'sqlite' },
      { 'ibhagwan/fzf-lua' },
    },
    config = function()
      require('neoclip').setup({
        enable_persistent_history = true,
      })
      vim.keymap.set('n', '<leader>cc', require('neoclip.fzf'), { desc = 'Open clipboard history' })
      -- to clear history: require('neoclip').clear_history()
    end,
  },
}

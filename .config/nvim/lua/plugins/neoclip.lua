return {
  {
    'AckslD/nvim-neoclip.lua',
    opts = {
      enable_persistent_history = true,
    },
    dependencies = {
      -- for persistent history between sessions
      { 'kkharji/sqlite.lua', module = 'sqlite' },
      { 'ibhagwan/fzf-lua' },
    },
    config = function(_, opts)
      require('neoclip').setup(opts)
      vim.keymap.set('n', '<a-c>', require('neoclip.fzf'), { desc = 'Open clipboard history' })
      -- to clear history: require('neoclip').clear_history()
    end,
  },
}

return {
  {
    "AckslD/nvim-neoclip.lua",
    opts = {},
    dependencies = {
      -- for persistent history between sessions
      { 'kkharji/sqlite.lua',           module = 'sqlite' },
      { 'nvim-telescope/telescope.nvim' },
      { 'ibhagwan/fzf-lua' },
    },
    config = function()
      require('neoclip').setup({
        enable_persistent_history = true,
      })
    end,
  }
}

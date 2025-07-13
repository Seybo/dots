return {
  'folke/flash.nvim',
  event = 'VeryLazy',
  ---@type Flash.Config
  opts = {},
  config = function(_, opts)
    local plugin = require('flash')

    plugin.setup(opts)
    vim.keymap.set({ 'n', 'x', 'o' }, 'f', function() require('flash').jump() end, { desc = 'Flash' })
    vim.keymap.set({ 'n', 'x', 'o' }, 'F', function() require('flash').treesitter() end, { desc = 'Flash Treesitter' })
  end,
}

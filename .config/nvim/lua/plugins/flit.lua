return {
  {
    'ggandor/flit.nvim',
    config = function(_, opts)
      local plugin = require('flit')

      plugin.setup({
        labeled_modes = 'v',
        multiline = true,
      })
    end,
  },
}

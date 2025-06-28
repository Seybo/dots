return {
  {
    'ggandor/flit.nvim',
    enabled = false, -- switching to flash
    config = function(_, opts)
      local plugin = require('flit')

      plugin.setup({
        labeled_modes = 'v',
        multiline = true,
      })
    end,
  },
}

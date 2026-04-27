return {
  'alex35mil/pi.nvim',

  -- Optional: required only for `:PiPasteImage` (clipboard image paste).
  -- dependencies = { 'HakonHarnes/img-clip.nvim' },

  keys = {
    { '<leader>pp', '<Cmd>Pi<CR>', desc = 'Pi' },
    { '<leader>px', '<Cmd>PiStop<CR>', desc = 'Pi stop' },
    { '<leader>pt', '<Cmd>PiToggleChat<CR>', desc = 'Pi toggle chat' },
    { '<leader>pr', '<Cmd>PiResume<CR>', desc = 'Pi resume' },
    { '<leader>pl', '<Cmd>PiToggleLayout<CR>', desc = 'Pi toggle layout' },
  },

  -- if you're fine with defaults:
  config = true,
  opts = {
    -- Chat layout
    layout = {
      -- Default layout when opening the chat: "side" or "float".
      default = 'float',
      float = {
        width = 0.9,
        height = 0.9,
        border = 'rounded',
      },
    },
  },
}

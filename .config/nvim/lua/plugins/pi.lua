return {
  'alex35mil/pi.nvim',

  -- Optional: required only for `:PiPasteImage` (clipboard image paste).
  -- dependencies = { 'HakonHarnes/img-clip.nvim' },

  -- if you're fine with defaults:
  config = true,
  opts = {
    -- Chat layout
    layout = {
      -- Default layout when opening the chat: "side" or "float".
      default = 'float',
    },
  },
}

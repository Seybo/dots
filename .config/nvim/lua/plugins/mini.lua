return {
  'echasnovski/mini.surround',
  version = false,
  enabled = false, -- TODO: the only mapping that works is sa
  config = function(_, opts) require('mini.surround').setup(opts) end,
}

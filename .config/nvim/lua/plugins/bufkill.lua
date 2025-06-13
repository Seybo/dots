return {
  { -- deleting a buffer no longer closes its window or split
    'qpkorr/vim-bufkill',
    event = 'BufEnter',
    init = function()
      -- disable default bufkill mappings
      vim.g.BufKillCreateMappings = 0
    end,
    keys = {
      { 'qq', ':BW<cr>', desc = '[ Buffers ] Bufkill close buffer' },
    },
  },
}

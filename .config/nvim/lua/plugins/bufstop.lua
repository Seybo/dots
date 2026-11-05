return {
  { -- improves next/prev buffers to be scoped to window
    'mihaifm/bufstop',
    event = 'BufEnter',
    keys = {
      { '<a-u>', ':BufstopBack<cr>', desc = '[ Buffers ] Prev buffer (in scope of window)' },
      { '<a-m>', ':BufstopForward<cr>', desc = '[ Buffers ] Next buffer (in scope of window)' },
    },
  },
}

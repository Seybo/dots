return {
  { -- improves next/prev buffers to be scoped to window
    'mihaifm/bufstop',
    event = 'BufEnter',
    keys = {
      { '<c-,>', ':BufstopBack<cr>', desc = '[ Buffers ] Prev buffer (in scope of window)' },
      { '<c-.>', ':BufstopForward<cr>', desc = '[ Buffers ] Next buffer (in scope of window)' },
    },
  },
}

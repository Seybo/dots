return {
  { -- improves next/prev buffers to be scoped to window
    'mihaifm/bufstop',
    event = 'BufEnter',
    keys = {
      { '<pageup>', ':BufstopBack<cr>', desc = '[ Buffers ] Prev buffer (in scope of window)' },
      { '<pagedown>', ':BufstopForward<cr>', desc = '[ Buffers ] Next buffer (in scope of window)' },
    },
  },
}

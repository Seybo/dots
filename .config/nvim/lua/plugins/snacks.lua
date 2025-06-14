return {
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      debug = { enabled = true },
      dim = { enabled = false },
      git = { enabled = true },
      gitbrowse = { enabled = true },
      input = { enabled = true },
      notifier = { enabled = true },
      picker = { enabled = false },
      scroll = {
        enabled = true,
        animate = {
          -- smaller per‐step delay and total time
          duration = { step = 10, total = 125 },
          easing = 'linear',
        },
        animate_repeat = {
          -- as soon as you scroll twice within 100ms, it’ll be even snappier
          delay = 100,
          duration = { step = 3, total = 30 },
          easing = 'linear',
        },
        filter = function(buf) return vim.bo[buf].buftype ~= 'terminal' and vim.bo[buf].filetype ~= 'Avante' end,
      },
      zen = { enabled = true },
    },
    keys = {
      -- git browse/blame [gb]
      { 'gbl', function() Snacks.git.blame_line() end, desc = '[Snacks] Git blame line' },
      { 'gbo', function() Snacks.gitbrowse.open() end, desc = '[Snacks] Git blame' },
      { 'gbm', function()
        require('snacks.gitbrowse').open({
          what = 'file',
          branch = 'master',
        })
      end, mode = { 'n', 'v' }, desc = '[Snacks] Git blame' },
      { '<leader>u', function() Snacks.picker.undo() end, desc = '[Snacks] Undo history' },
      { '<leader>n', function() Snacks.notifier.show_history() end, desc = '[Snacks] Show notifications history' },
    },
  },
}

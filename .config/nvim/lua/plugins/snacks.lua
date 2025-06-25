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
    config = function(_, opts)
      require('snacks').setup(opts)

      vim.g.autoformat = true
      require('snacks').toggle
        .new({
          id = '[Toggle] Format on Save',
          name = '[Toggle] Format on Save',
          get = function() return vim.g.autoformat end,
          set = function() vim.g.autoformat = not vim.g.autoformat end,
        })
        :map('<c-t>f')

      vim.g.diags_enabled = false
      require('snacks').toggle
        .new({
          id = '[Toggle] Diagnostics',
          name = '[Toggle] Diagnostics',
          get = function() return vim.g.diags_enabled end,
          set = function()
            vim.g.diags_enabled = not vim.g.diags_enabled
            vim.diagnostic.config({
              virtual_text = vim.g.diags_enabled,
              signs = vim.g.diags_enabled,
              underline = vim.g.diags_enabled,
              update_in_insert = false,
            })
          end,
        })
        :map('<c-t>d')
      vim.g.spell_enabled = false
      require('snacks').toggle
        .new({
          id = '[Toggle] Spell Check',
          name = '[Toggle] Spell Check',
          get = function() return vim.wo.spell end,
          set = function() vim.wo.spell = not vim.wo.spell end,
        })
        :map('<c-t>s')
    end,
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

return {
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      bigfile = { enabled = true },
      debug = { enabled = true },
      dim = { enabled = false },
      explorer = { enabled = true, replace_netrw = false },
      git = { enabled = true },
      gitbrowse = { enabled = true },
      input = { enabled = true },
      notifier = { enabled = true },
      picker = {
        enabled = true,
        sources = {
          explorer = {
            auto_close = true,
            diagnostics_open = true,
            git_status_open = true,
            hidden = true,
            jump = { close = true },
            layout = {
              fullscreen = true,
              preview = true,
              layout = {
                backdrop = false,
                box = 'horizontal',
                border = 'none',
                {
                  box = 'vertical',
                  width = 0.3,
                  {
                    win = 'input',
                    height = 1,
                    border = true,
                    title = '{title} {live} {flags}',
                    title_pos = 'center',
                  },
                  { win = 'list', border = 'none' },
                },
                {
                  win = 'preview',
                  width = 0.7,
                  border = 'left',
                  title = '{preview}',
                  title_pos = 'center',
                },
              },
            },
          },
        },
      },
      quickfile = { enabled = true },
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

      local function set_explorer_highlights()
        vim.api.nvim_set_hl(0, 'SnacksPickerPathHidden', { link = 'Normal' })
      end
      set_explorer_highlights()
      vim.api.nvim_create_autocmd('ColorScheme', {
        group = vim.api.nvim_create_augroup('snacks_explorer_highlights', { clear = true }),
        callback = set_explorer_highlights,
      })

      vim.g.autoformat = true
      require('snacks').toggle
        .new({
          id = '[Toggle] Format on Save',
          name = '[Toggle] Format on Save',
          get = function() return vim.g.autoformat end,
          set = function() vim.g.autoformat = not vim.g.autoformat end,
        })
        :map('<a-o>f')

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
        :map('<a-o>d')
      vim.g.spell_enabled = false
      require('snacks').toggle
        .new({
          id = '[Toggle] Spell Check',
          name = '[Toggle] Spell Check',
          get = function() return vim.wo.spell end,
          set = function() vim.wo.spell = not vim.wo.spell end,
        })
        :map('<a-o>s')

      require('snacks').toggle
        .new({
          id = '[Toggle] Wrap',
          name = '[Toggle] Wrap',
          get = function() return vim.wo.wrap end,
          set = function() vim.wo.wrap = not vim.wo.wrap end,
        })
        :map('<a-o>w')
    end,
    keys = {
      -- git browse [gb]
      { 'gbo', function() Snacks.gitbrowse.open() end, desc = '[Snacks] Git blame' },
      { 'gbm', function()
        require('snacks.gitbrowse').open({
          what = 'file',
          branch = 'master',
        })
      end, mode = { 'n', 'v' }, desc = '[Snacks] Git blame' },
      { '<leader>fo', function() Snacks.explorer.reveal() end, desc = '[Snacks] File explorer' },
      { '<leader>u', function() Snacks.picker.undo() end, desc = '[Snacks] Undo history' },
      { '<leader>n', function() Snacks.notifier.show_history() end, desc = '[Snacks] Show notifications history' },
    },
  },
}

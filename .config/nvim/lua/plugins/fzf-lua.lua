return {
  'ibhagwan/fzf-lua',
  -- optional for icon support
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  opts = {
    winopts = {
      border = 'none',
      fullscreen = true,
      fzf_colors = true,
      preview = {
        border = 'rounded',
        horizontal = 'down:60%',
        layout = 'horizontal',
      },
    },
    prompt = '🔍 ',
  },
  config = function(_, opts)
    require('fzf-lua').setup(opts)
    -- register it as the ui.select backend
    require('fzf-lua').register_ui_select()
  end,
  keys = {
    { '<leader>fb', function() require('fzf-lua').builtin() end, desc = '[Fzf] Builtin' },
    { '<leader>fa', function() require('fzf-lua').files() end, desc = '[Fzf] Search All Files' },
    { '<leader>ff', function() require('fzf-lua').git_files() end, desc = '[Fzf] Search Git Files' },
    { '<leader>fm', function() require('fzf-lua').files({ cwd = './_mydev' }) end, desc = '[Fzf] Search _mydev Files' },
    { '<leader>fc', function() require('fzf-lua').git_status() end, desc = '[Fzf] Search Git Changed Files' },
    { '<leader>fha', function() require('fzf-lua').oldfiles() end, desc = '[Fzf] Files History (all)' },
    { '<leader>fhf', function() require('fzf-lua').oldfiles({ cwd_only = true }) end, desc = '[Fzf] Files History (within repo)' },
    { '<leader>fhc', function() require('fzf-lua').command_history() end, desc = '[Fzf] Commands History' },
    { '<leader>fhs', function() require('fzf-lua').search_history() end, desc = '[Fzf] Search History' },
    { '<leader>fk', function() require('fzf-lua').keymaps() end, desc = '[Fzf] Search keymaps' },
    { '<leader>fv', function() require('fzf-lua').files({ cwd = vim.fn.stdpath('config') }) end, desc = '[Fzf] Browse vim config' },
    { '<leader>gm', function() require('fzf-lua').live_grep() end, desc = '[Fzf] Grep manual' },
    { '<leader>gs', function() require('fzf-lua').grep_visual() end, mode = 'v', desc = '[Fzf] Grep selection' },
    { '<leader>gw', function() require('fzf-lua').grep_cword() end, desc = '[Fzf] Grep word' },
    { '<leader>gW', function() require('fzf-lua').grep_cWORD() end, desc = '[Fzf] Grep WORD' },
    { '<leader>gb', function() require('fzf-lua').lgrep_curbuf() end, desc = '[Fzf] Grep within buffer' },
    { '<leader>gr', function() require('fzf-lua').live_grep_resume() end, desc = '[Fzf] Grep resume' },
    -- _MM search keys
    { '<leader>ja', function() require('fzf-lua').grep({ search = '_MM:' }) end, desc = '[Fzf] Search all _MM' },
    { '<leader>js', function() require('fzf-lua').grep({ search = 'START_MM:' }) end, desc = '[Fzf] Search all START_MM' },
    { '<leader>jt', function() require('fzf-lua').grep({ search = 'TODO_MM:' }) end, desc = '[Fzf] Search all TODO_MM' },
    { '<leader>jq', function() require('fzf-lua').grep({ search = 'QUESTION_MM:' }) end, desc = '[Fzf] Search all QUESTION_MM' },
    { '<leader>jc', function() require('fzf-lua').grep({ search = 'COMMENT_MM:' }) end, desc = '[Fzf] Search all COMMENT_MM' },
    { '<leader>jc', function() require('fzf-lua').grep({ search = 'DEBUG_MM:' }) end, desc = '[Fzf] Search all DEBUG_MM' },
  },
}

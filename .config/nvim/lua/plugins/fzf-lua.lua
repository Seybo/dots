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
    local dev_root = assert(vim.env.DEV_ROOT, 'DEV_ROOT is not set')
    local fzf = require('fzf-lua')
    fzf.setup(opts)
    -- register it as the ui.select backend
    fzf.register_ui_select()

    -- if no action is done in the fzf window, it moves cursor to the last change after close
    -- lets preserve cursor position
    local function with_cursor_restore(picker, picker_opts)
      -- grab current position
      local cur_win = vim.api.nvim_get_current_win()
      local cur_pos = vim.api.nvim_win_get_cursor(cur_win)

      -- 1st arg = "force", 2nd arg = {} (base), 3rd = user opts, 4th = our winopts
      local resulting_opts = vim.tbl_deep_extend(
        'force', -- merge mode
        {}, -- start with an empty table
        picker_opts or {}, -- supplied opts (must be a table or nil)
        { -- injected opts
          winopts = {
            on_close = function()
              if vim.api.nvim_win_is_valid(cur_win) then
                vim.api.nvim_set_current_win(cur_win)
                vim.api.nvim_win_set_cursor(cur_win, cur_pos)
              end
            end,
          },
        }
      )

      picker(resulting_opts)
    end

    local function map_with_cursor_restore(mode, lhs, picker, picker_opts, desc)
      vim.keymap.set(mode, lhs, function() with_cursor_restore(picker, picker_opts) end, { desc = desc })
    end

    map_with_cursor_restore('n', '<leader>fb', fzf.builtin, nil, '[Fzf] Builtin')
    map_with_cursor_restore('n', '<leader>fa', fzf.files, { no_ignore = true }, '[Fzf] Search All Files')
    map_with_cursor_restore('n', '<leader>ff', fzf.git_files, nil, '[Fzf] Search Git Files')
    map_with_cursor_restore('n', '<leader>fc', function()
      fzf.files({ cwd = vim.fn.expand('%:p:h') })
    end, nil, '[Fzf] Search Current File Directory')
    map_with_cursor_restore('n', '<leader>fp', fzf.files, { cwd = dev_root .. '/_apis' }, '[Fzf] Search in my api')
    map_with_cursor_restore('n', '<leader>fm', fzf.files, { cwd = '../_mydev' }, '[Fzf] Search in my dev')
    local task_root = dev_root .. '/_tasks'
    local function select_task_project(prefix, prompt)
      local projects = {}
      for name, entry_type in vim.fs.dir(task_root) do
        if entry_type == 'directory' and vim.startswith(name, prefix) then
          table.insert(projects, name)
        end
      end
      table.sort(projects)

      vim.ui.select(projects, { prompt = prompt }, function(project)
        if project then
          with_cursor_restore(fzf.files, {
            cwd = task_root .. '/' .. project,
            raw_cmd = 'rg --files --sortr modified',
          })
        end
      end)
    end

    map_with_cursor_restore('n', '<leader>ft', fzf.files, { cwd = task_root }, '[Fzf] Search in all tasks')
    vim.keymap.set('n', '<leader>tas', function() select_task_project('shaka_', 'Shaka tasks project') end, { desc = '[Fzf] Choose Shaka task project' })
    vim.keymap.set('n', '<leader>tap', function() select_task_project('my_', 'Personal tasks project') end, { desc = '[Fzf] Choose personal task project' })
    vim.keymap.set('n', '<leader>tam', function() select_task_project('misc_', 'Misc tasks project') end, { desc = '[Fzf] Choose misc task project' })
    map_with_cursor_restore('n', '<leader>tae', fzf.files, { cwd = task_root .. '/env', raw_cmd = 'rg --files --sortr modified' }, '[Fzf] Search env tasks')
    map_with_cursor_restore('n', '<leader>fgc', fzf.git_status, nil, '[Fzf] Search Git Changed Files')
    map_with_cursor_restore('n', '<leader>fha', fzf.oldfiles, nil, '[Fzf] Files History (all)')
    map_with_cursor_restore('n', '<leader>fhf', function() fzf.oldfiles({ cwd_only = true }) end, nil, '[Fzf] Files History (within repo)')
    map_with_cursor_restore('n', '<leader>fhc', fzf.command_history, nil, '[Fzf] Commands History')
    map_with_cursor_restore('n', '<leader>fhs', fzf.search_history, nil, '[Fzf] Search History')
    map_with_cursor_restore('n', '<leader><leader>', fzf.keymaps, nil, '[Fzf] Search keymaps')
    map_with_cursor_restore('n', '<leader>fv', function() fzf.files({ cwd = vim.fn.stdpath('config') }) end, nil, '[Fzf] Browse vim config')
    map_with_cursor_restore('n', '<leader>gm', fzf.live_grep, nil, '[Fzf] Grep manual')
    map_with_cursor_restore('v', '<leader>gs', fzf.grep_visual, nil, '[Fzf] Grep selection')
    map_with_cursor_restore('n', '<leader>gw', fzf.grep_cword, nil, '[Fzf] Grep word')
    map_with_cursor_restore('n', '<leader>gW', fzf.grep_cWORD, nil, '[Fzf] Grep WORD')
    map_with_cursor_restore('n', '<leader>gb', fzf.lgrep_curbuf, nil, '[Fzf] Grep within buffer')
    map_with_cursor_restore('n', '<leader>gr', fzf.live_grep_resume, nil, '[Fzf] Grep resume')
    -- _MM search keys
    map_with_cursor_restore('n', '<leader>ja', function() fzf.grep({ search = '_MM:' }) end, nil, '[Fzf] Search all _MM')
    map_with_cursor_restore('n', '<leader>js', function() fzf.grep({ search = 'START_MM:' }) end, nil, '[Fzf] Search all START_MM')
    map_with_cursor_restore('n', '<leader>jt', function() fzf.grep({ search = 'TODO_MM:' }) end, nil, '[Fzf] Search all TODO_MM')
    map_with_cursor_restore('n', '<leader>jq', function() fzf.grep({ search = 'QUESTION_MM:' }) end, nil, '[Fzf] Search all QUESTION_MM')
    map_with_cursor_restore('n', '<leader>jc', function() fzf.grep({ search = 'COMMENT_MM:' }) end, nil, '[Fzf] Search all COMMENT_MM')
    map_with_cursor_restore('n', '<leader>jc', function() fzf.grep({ search = 'DEBUG_MM:' }) end, nil, '[Fzf] Search all DEBUG_MM')
  end,
}

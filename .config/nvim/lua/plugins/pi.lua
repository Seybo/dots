local function open_pi_with_account_notice()
  local auth_path = vim.fn.expand '~/.pi/agent/auth.json'
  local link = vim.uv.fs_readlink(auth_path) or ''
  local label = 'unknown'
  local account_type = 'unknown'

  if link:match 'auth%-personal%.json$' then
    label = 'personal'
  elseif link:match 'auth%-work%.json$' then
    label = 'work'
  end

  local ok_lines, lines = pcall(vim.fn.readfile, auth_path)
  if ok_lines and lines then
    local ok_json, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
    if ok_json and type(decoded) == 'table' then
      account_type = next(decoded) or account_type
    end
  end

  vim.notify('Pi account: ' .. label .. ' (' .. account_type .. ')', vim.log.levels.INFO, { title = 'pi.nvim' })
  vim.cmd 'Pi'
end

return {
  'alex35mil/pi.nvim',

  -- Optional: required only for `:PiPasteImage` (clipboard image paste).
  -- Disable img-clip's global drag/drop paste interception: pi.nvim already handles
  -- image-file drops in its own prompt buffer, and the global handler is noisy for text pastes.
  dependencies = {
    {
      'HakonHarnes/img-clip.nvim',
      opts = {
        default = {
          drag_and_drop = {
            enabled = false,
          },
        },
      },
    },
  },

  keys = {
    { '<leader>pp', open_pi_with_account_notice, desc = 'Pi' },
    { '<leader>px', '<Cmd>PiStop<CR>', desc = 'Pi stop' },
    { '<leader>pt', '<Cmd>PiToggleChat<CR>', desc = 'Pi toggle chat' },
    { '<leader>pr', '<Cmd>PiResume<CR>', desc = 'Pi resume' },
    { '<leader>pl', '<Cmd>PiToggleLayout<CR>', desc = 'Pi toggle layout' },
  },

  config = function(_, opts)
    require('pi').setup(opts)

    -- pi.nvim registers highlights on ColorScheme/VimEnter, but this plugin is lazy-loaded
    -- after those events. Re-fire ColorScheme so Pi highlight groups are actually created.
    if vim.g.colors_name then
      vim.api.nvim_exec_autocmds('ColorScheme', { pattern = vim.g.colors_name })
    end

    local pi = require 'pi'
    local group = vim.api.nvim_create_augroup('pi-custom-keybinds', { clear = true })

    local keymap = function(key, event, action)
      vim.keymap.set({ 'n', 'i', 'v' }, key, action, { buffer = event.buf })
    end

    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = { 'pi-chat-history' },
      callback = function(event)
        keymap('<S-Down>', event, function()
          pi.focus_chat_prompt()
        end)
      end,
    })

    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = { 'pi-chat-prompt' },
      callback = function(event)
        keymap('<S-Up>', event, function()
          pi.focus_chat_history()
        end)
        keymap('<S-Down>', event, function()
          pi.focus_chat_attachments()
        end)
      end,
    })

    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = { 'pi-chat-attachments' },
      callback = function(event)
        keymap('<S-Up>', event, function()
          pi.focus_chat_prompt()
        end)
      end,
    })
  end,
  opts = {
    -- Chat layout
    layout = {
      -- Default layout when opening the chat: "side" or "float".
      default = 'float',
      float = {
        width = 0.9,
        height = 0.9,
        border = 'rounded',
      },
    },
  },
}

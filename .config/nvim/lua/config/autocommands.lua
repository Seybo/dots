local diagnostics_icons = require('utils.icons').diagnostics

-- higlight yanked text quickly
vim.api.nvim_create_autocmd('TextYankPost', {
  group = vim.api.nvim_create_augroup('YankHighlight', { clear = true }),
  pattern = '*',
  callback = function()
    vim.highlight.on_yank()
  end,
  desc = 'Hightlight yank',
})

-- -- [[ Saving folds across sessions ]] --
-- create an augroup so you can clear it later if needed
local view_grp = vim.api.nvim_create_augroup('SaveFolds', { clear = true })
-- save a view (folds, cursor, window layout, etc.) on buffer/window leave
vim.api.nvim_create_autocmd({ 'BufWinLeave', 'WinLeave' }, {
  group = view_grp,
  pattern = '*',
  command = 'silent! mkview',
})
-- restore that view when you come back
vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
  group = view_grp,
  pattern = '*',
  command = 'silent! loadview',
})

-- vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
--   callback = function(ev)
--     vim.diagnostic.open_float(ev.buf, {
--       focusable = false,
--       border = 'rounded',
--       scope = 'line', -- message is shown as soon as the cursor is on the problematic line
--       prefix = function(d)
--         local sev = d.severity
--         if sev == vim.diagnostic.severity.ERROR then
--           return diagnostics_icons.Error
--         elseif sev == vim.diagnostic.severity.WARN then
--           return diagnostics_icons.Warn
--         elseif sev == vim.diagnostic.severity.INFO then
--           return diagnostics_icons.Info
--         elseif sev == vim.diagnostic.severity.HINT then
--           return diagnostics_icons.Hint
--         else
--           return ''
--         end
--       end,
--     })
--   end,
-- })

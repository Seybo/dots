vim.keymap.set('i', 'jj', '<esc>', { silent = true })
vim.keymap.set('t', 'jj', '<c-\\><c-n>', { silent = true })
vim.keymap.set({ 'n', 'v' }, 'Q', ':qa<cr>', { silent = true })

-- -- [[ Search }} -- --
vim.keymap.set('n', '*', '<Cmd>keepjumps normal! mi*`i<cr>', {
  desc = '[ Search ] Dont jump to next search result on * (search word under cursor)',
})

-- -- [[ Copy/Paste ]] -- --
-- makes sense only if not used set clipboard=unnamedplus
vim.keymap.set('v', '<a-y>', '"+y', { desc = '[ Copy/Paste ] Copy to system clipboard' })
vim.keymap.set('v', '<a-d>', '"+d', { desc = '[ Copy/Paste ] Cut to system clipboard' })
vim.keymap.set('v', '<a-p>', '"+p', { desc = '[ Copy/Paste ] Paste from system clipboard' })
vim.keymap.set('n', '<a-y><a-y>', '"+yy', { desc = '[ Copy/Paste ] Copy the line to system clipboard' })
vim.keymap.set('n', '<a-d><a-d>', '"+dd', { desc = '[ Copy/Paste ] Cut the line to system clipboard' })
vim.keymap.set('n', '<a-p>', '"+p', { desc = '[ Copy/Paste ] Paste from system clipboard' })
vim.keymap.set('v', '<a-.>', ":t'><cr>", { desc = '[ Copy/Paste ] Duplicate visual selection' })

-- -- [[ Selection ]] -- --
vim.keymap.set('n', '<c-a><c-a>', 'ggVG<cr>', { desc = '[ Selection ] Select all' })
vim.keymap.set('n', '<esc>', ':noh<cr>', { desc = '[ Selection ] Deselect all' })
vim.keymap.set('n', '<a-g><a-f>', function()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()

  -- Get word around cursor
  local left = line:sub(1, col + 1)
  local right = line:sub(col + 2)
  local joined = left .. right

  -- Try to extract a Ruby constant like Foo::Bar or just Foo
  local match = joined:match('([%a_][%w_]*::[%w_:]+)') or joined:match('([%a_][%w_]*)')
  if not match then
    vim.notify('No valid constant near cursor', vim.log.levels.WARN)
    return
  end

  -- Strip any trailing .call, .new, etc.
  match = match:gsub('%..*$', '')

  -- Convert CamelCase → snake_case + nested paths
  local snake_path = match:gsub('::', '/'):gsub('([a-z0-9])([A-Z])', '%1_%2'):gsub('([A-Z])([A-Z][a-z])', '%1_%2'):lower()

  -- List of fallback roots to search from (with ** recursive globbing)
  local roots = {
    'packs/*/app/services/',
    'packs/*/app/models/',
    'packs/*/app/components/',
    'packs/*/lib/',
    'app/components/',
    'app/jobs/',
    'app/models/',
    'app/services/',
    'lib/',
  }

  for _, root in ipairs(roots) do
    local glob = root .. snake_path .. '.rb'
    local full_path = vim.fn.glob(glob, 0, 1)[1]
    if full_path and full_path ~= '' then
      vim.cmd('edit ' .. full_path)
      return
    end
  end

  vim.notify('File not found for: ' .. snake_path .. '.rb', vim.log.levels.WARN)
end, { noremap = true, silent = true, desc = 'Smart Rails-style gf' })

-- -- [[ Edit ]] -- --
vim.keymap.set('n', '<a-s>', ':w<cr>', { desc = '[ Edit ] Save file' })
vim.keymap.set('n', '<a-j>', ':m .+1<cr>==', { desc = '[ Edit ] Move line under cursor down' })
vim.keymap.set('n', '<a-k>', ':m .-2<cr>==', { desc = '[ Edit ] Move line under cursor up' })
vim.keymap.set('v', '<a-j>', ":m '>+1<cr>gv=gv", { desc = '[ Edit ] Move lines selection down' })
vim.keymap.set('v', '<a-k>', ":m '<-2<cr>gv=gv", { desc = '[ Edit ] Move lines selection up' })
vim.keymap.set('n', '<a-l>', '>>', { desc = '[ Edit ] Indent line under cursor right' })
vim.keymap.set('n', '<a-h>', '<<', { desc = '[ Edit ] Indent line under cursor left' })
vim.keymap.set('v', '<a-l>', '>gv', { desc = '[ Edit ] Indent lines selection right' })
vim.keymap.set('v', '<a-h>', '<gv', { desc = '[ Edit ] Indent lines selection left' })
vim.keymap.set('n', '<a-r>', ':e!<cr>', { desc = '[ Edit ] Revert all the changes in the file' })

-- -- [[ Tabs ]] -- --
local function open_or_switch_to_terminal()
  local term_tab_index = -1
  -- loop through tabs to find terminal
  for i = 1, vim.fn.tabpagenr('$') do
    if vim.fn.tabpagewinnr(i, '$') == 1 and vim.fn.getbufvar(vim.fn.tabpagebuflist(i)[1], '&buftype') == 'terminal' then
      term_tab_index = i
      break
    end
  end
  -- if terminal tab found, switch to it
  if term_tab_index > -1 then
    vim.cmd('tabn ' .. term_tab_index)
  else
    vim.cmd('tablast | tabnew | term')
  end
  vim.cmd('startinsert')
end

vim.keymap.set('n', '<a-t><a-t>', open_or_switch_to_terminal, { desc = '[ Tabs ] Switch to terminal tab' })
vim.keymap.set('n', '<a-t><a-c>', ':tabnew<CR>', { desc = '[ Tabs ] New tab' })
vim.keymap.set('n', '<a-t><a-x>', ':tabclose<CR>', { desc = '[ Tabs ] Close tab' })
vim.keymap.set('n', '<pageup>', ':tabprevious<CR>', { desc = '[ Tabs ] Prev tab' })
vim.keymap.set('n', '<pagedown>', ':tabnext<CR>', { desc = '[ Tabs ] Next tab' })

-- -- [[ Windows ]] -- --
vim.keymap.set('n', 'sp', ':sp<CR>', { silent = true }) -- split horizontal
vim.keymap.set('n', 'sv', ':vsp<CR>', { silent = true }) -- split vertical
vim.keymap.set('n', 'so', ':only<CR>', { silent = true }) -- leave only current window
vim.keymap.set('n', 'sq', ':close<CR>', { silent = true }) -- close window
vim.keymap.set('n', 'sh', '<c-w>h', { silent = true }) -- switch to left
vim.keymap.set('n', 'sl', '<c-w>l', { silent = true }) -- switch to right
vim.keymap.set('n', 'sj', '<c-w>j', { silent = true }) -- switch to down
vim.keymap.set('n', 'sk', '<c-w>k', { silent = true }) -- switch to up
vim.keymap.set('n', 'st', '<c-w><c-w>', { silent = true }) -- switch between recent
vim.keymap.set('n', 'smm', '<c-w>_', { silent = true }) -- maximize current
vim.keymap.set('n', 'smj', '<c-w>j<c-w>_', { silent = true }) -- maximize bottom
vim.keymap.set('n', 'smk', '<c-w>k<c-w>_', { silent = true }) -- maximize up
vim.keymap.set('n', 'sd', '<c-w>=', { silent = true }) -- revert maximize (d - default)
vim.keymap.set('n', 'sr', '<c-w>r', { silent = true }) -- rotate
vim.keymap.set('n', 'sH', '<c-w>H', { silent = true }) -- horizontal => vertical
vim.keymap.set('n', 'sK', '<c-w>K', { silent = true }) -- vertical => horizontal

vim.keymap.set('n', '<S-right>', function() vim.cmd('vertical resize +' .. 5) end, { silent = true })
vim.keymap.set('n', '<S-left>', function() vim.cmd('vertical resize -' .. 5) end, { silent = true })
vim.keymap.set('n', '<S-up>', function() vim.cmd('resize +' .. 3) end, { silent = true })
vim.keymap.set('n', '<S-down>', function() vim.cmd('resize -' .. 3) end, { silent = true })

-- -- [[ Spellcheck ]] -- --

-- vim.keymap.set('n', '<A-s><A-r>', ':set spelllang=ru_yo<CR>', { silent = true }) -- RU
-- vim.keymap.set('n', '<A-s><A-e>', ':set spelllang=en_us<CR>', { silent = true }) -- EN
-- local function ToggleSpellCheck()
--   -- Toggle the 'spell' option
--   vim.cmd('set spell!')
--
--   -- Check the state of the 'spell' option and echo the corresponding message
--   if vim.o.spell then
--     print('Spellcheck ON')
--   else
--     print('Spellcheck OFF')
--   end
-- end
-- vim.keymap.set('n', '<A-s><A-t>', ToggleSpellCheck, { silent = true })

-- -- [[ Misc ]] -- --

vim.keymap.set('n', '<a-n><a-n>', ':set nornu<CR>', { silent = true }) -- absolute line numbers
vim.keymap.set('n', '<a-n><a-r>', ':set rnu<CR>', { silent = true }) -- relative line numbers
vim.keymap.set('n', '<a-r><a-r>', ':%s/', { silent = true }) -- replace text
vim.keymap.set('n', '<a-r><a-w>', ':%s/<C-r><C-w>/', { silent = true }) -- replace word under cursor
-- replace selection
vim.keymap.set('v', '<a-r><a-w>', "\"sy:%s/<C-r>=substitute(@s, '\\n', '', 'g')<cr>/", { silent = true })
vim.keymap.set('n', '<a-f><a-f>', ':b#<CR>', { silent = true }) -- swetch between last two buffers

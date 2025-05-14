-- -- [[ General ]] -- --
map { "jj",
  "[ General ] Go to normal mode from instert mode",
  "<Esc>",
  mode = "i" }
map { "jj",
  "[ General ] Enter normal mode",
  "<C-\\><C-n>",
  mode = "t" }

-- -- [[ Search ]] -- --
map { "*",
  "[ Search ] Don't jump to next search result on * (search word under cursor)",
  "<Cmd>keepjumps normal! mi*`i<CR>",
  mode = "n" }

map { "*",
  "[ Search ] Don't jump on * (search selection)",
  [["*y:silent! let searchTerm = '\V'.substitute(escape(@*, '\/'), "\n", '\\n', "g") <bar> let @/ = searchTerm <bar> echo '/'.@/ <bar> call histadd("search", searchTerm) <bar> set hls<cr>]],
  mode = "v" }

-- -- [[ Edit ]] -- --
map { "<C-s>",
  "[ Edit ] Save buffer",
  ":w<CR>",
  mode = "n" }
map { "<A-j>",
  "[ Edit ] Move line under cursor down",
  ":m .+1<CR>==",
  mode = "n" }
map { "<A-k>",
  "[ Edit ] Move line under cursor up",
  ":m .-2<CR>==",
  mode = "n" }
map { "<A-j>",
  "[ Edit ] Move lines selection down",
  ":m '>+1<CR>gv=gv",
  mode = "v" }
map { "<A-k>",
  "[ Edit ] Move lines selection up",
  ":m '<-2<CR>gv=gv",
  mode = "v" }
map { "<A-l>",
  "[ Edit ] Indent line under cursor right",
  ">>",
  mode = "n" }
map { "<A-h>",
  "[ Edit ] Indent line under cursor left",
  "<<",
  mode = "n" }
map { "<A-l>",
  "[ Edit ] Indent lines selection right",
  ">gv",
  mode = "v" }
map { "<A-h>",
  "[ Edit ] Indent lines selection left",
  "<gv",
  mode = "v" }

-- -- [[ Navigation ]] -- --
map { "Q",
  "[ Navigation ] Exit vim",
  ":qa<CR>",
  mode = { "n", "v", "t" } }
map { "qd",
  "[ Navigation ] Close winDow",
  ":q<CR>",
  mode = "n" }
map { "zz",
  "[ Navigation ] Center screen to cursor position and deselect all searches",
  "zz:nohlsearch<CR>",
  mode = "n" }
-- map { "k",
-- "[ Navigation ] Go one line up (regardless of line split by vim)",
-- "v:count == 0 ? 'gk' : 'k'",
-- mode = { "n", "v" } }
-- map { "j",
-- "[ Navigation ] Go one line down (regardless of line split by vim)",
-- "v:count == 0 ? 'gj' : 'j'",
-- mode = { "n", "v" } }

-- TODO_MM: figure out how to use map with expr = true
vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- -- [[ Copy/Paste ]] -- --
-- makes sense only if not used set clipboard=unnamedplus
map { "<A-y>",
  "[ Copy/Paste ] Copy to system clipboard",
  "\"+y",
  mode = "v" }
map { "<A-d>",
  "[ Copy/Paste ] Cut to system clipboard",
  "\"+d",
  mode = "v" }
map { "<A-p>",
  "[ Copy/Paste ] Paste from system clipboard",
  "\"+p",
  mode = "v" }
map { "<A-d><A-d>",
  "[ Copy/Paste ] Cut the line to system clipboard",
  "\"+dd",
  mode = "n" }
map { "<A-d><A-d>",
  "[ Copy/Paste ] Cut the line to system clipboard",
  "\"+dd",
  mode = "n" }
map { "<A-p>",
  "[ Copy/Paste ] Paste from system clipboard",
  "\"+p",
  mode = "n" }
map { "<A-.>",
  "[ Copy/Paste ] Copy-paste visual selection",
  ":t'><CR>",
  mode = "v" }

-- -- [[ Selection ]] -- --
map { "<C-a><C-a>",
  "[ Selection ] Select all",
  "ggVG<CR>",
  mode = "n" }
map { "<CR>",
  "[ Selection ] Deselect all",
  ":noh<CR><CR>",
  mode = "n" }
local function select_text_up_to_dot_or_quote()
  local _row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  -- Adjusting for 0-based indexing in Vim
  col = col + 1
  local before_cursor = line:sub(1, col - 1)
  local after_cursor = line:sub(col)
  -- Detect if the cursor is within quotes and adjust the bounds accordingly
  local quote_type = before_cursor:match("(['\"])[^%s]*$")
  local start_quote, end_quote
  if quote_type then
    -- Find the starting position of the preceding quote
    start_quote = before_cursor:reverse():find(quote_type)
    start_quote = start_quote and (#before_cursor - start_quote + 2) -- +2 to move after the quote
    -- Find the ending position of the following quote
    end_quote = after_cursor:find(quote_type)
    end_quote = end_quote and (col + end_quote - 2) -- -2 to exclude the quote itself
  end
  local start_col, end_col
  if start_quote and end_quote then
    -- If within quotes, adjust start and end based on quotes' positions
    start_col = start_quote
    end_col = end_quote
  else
    -- Normal operation, calculate start and end positions for selection
    local reverse_index = before_cursor:reverse():find("%s")
    start_col = reverse_index and (#before_cursor - reverse_index + 2) or 1
    end_col = after_cursor:find("%.") and (col + after_cursor:find("%.") - 2) or (col + #after_cursor - 1)
  end
  -- Preparing key sequence for visual selection
  local move_to_start = "0" .. string.rep("l", start_col - 1)
  local select_to_end = "v" .. string.rep("l", end_col - start_col)
  -- Combining commands and executing
  local keys = move_to_start .. select_to_end
  vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "")
end
-- gf for rails calls like Foo::Bar::Baz.call
-- TODO_MM: sort out how to better do that
vim.keymap.set("n", "<A-g><A-f>", function()
  select_text_up_to_dot_or_quote()
  vim.fn.feedkeys(vim.api.nvim_replace_termcodes("gf", true, false, true), "x")
end, { noremap = true, silent = true })

-- -- [[ Buffers ]] -- --
map { "<A-u>",
  "[ Buffers ] Prev buffer (in scope of window)",
  ":BufstopBack<CR>",
  mode = "n" }
map { "<A-m>",
  "[ Buffers ] Next buffer (in scope of window)",
  ":BufstopForward<CR>",
  mode = "n" }
map { "qq",
  "[ Buffers ] Bufkill close buffer",
  ":BW<CR>",
  mode = "n" }

-- vim-rails
-- TODO_MM: should be in vim-rails
-- vim.keymap.set("n", "ra", ":A<CR>", { silent = true }) -- switch to spec

-- -- [[ Files ]] -- --
map { "<Leader>fot",
  "[ Files ] Open temp file",
  ":e ./_mydev/temp.md<CR>",
  mode = "n" }
map { "<A-f>pa",
  "[ Files ] Copy absolute path",
  ":let @+ = expand('%:p')<CR>",
  mode = "n" }
map { "<A-f>pr",
  "[ Files ] Copy relative path",
  ":let @+ = expand('%')<CR>",
  mode = "n" }
map { "<A-f>pf",
  "[ Files ] Copy filename",
  ":let @+ = expand('%:t')<CR>",
  mode = "n" }

-- -- [[ LSP ]] -- --
map { "do",
  "[ LSP ] Open diagnosic message in floating window",
  vim.diagnostic.open_float,
  mode = "n" }
map { "]d",
  "[ LSP ] Go to next diagnosic message",
  vim.diagnostic.goto_next,
  mode = "n" }
map { "[d",
  "[ LSP ] Go to prev diagnosic message",
  vim.diagnostic.goto_prev,
  mode = "n" }
map { "gf",
  "[ LSP ] Go to definition",
  vim.lsp.buf.definition,
  mode = "n" }
map { "ff",
  "[ LSP ] Format",
  vim.lsp.buf.format,
  mode = "n" }


-- -- [[ Tabs ]] -- --
local function open_or_switch_to_terminal()
  local term_tab_index = -1
  -- loop through tabs to find terminal
  for i = 1, vim.fn.tabpagenr("$") do
    if vim.fn.tabpagewinnr(i, "$") == 1 and
        vim.fn.getbufvar(vim.fn.tabpagebuflist(i)[1], "&buftype") == "terminal" then
      term_tab_index = i
      break
    end
  end
  -- if terminal tab found, switch to it
  if term_tab_index > -1 then
    vim.cmd("tabn " .. term_tab_index)
  else
    vim.cmd("tablast | tabnew | term")
  end
  vim.cmd("startinsert")
end

map { "<A-t><A-t>",
  "[ Tabs ] Switch to terminal tab",
  open_or_switch_to_terminal,
  mode = "n" }

local function open_or_switch_to_git_status()
  local status_tab_index = -1

  for i = 1, vim.fn.tabpagenr("$") do
    local bufnr = vim.fn.tabpagebuflist(i)[1]
    local filetype = vim.bo[bufnr].filetype

    if vim.fn.tabpagewinnr(i, "$") == 1 and filetype == "fugitive" then
      status_tab_index = i
      break
    end
  end

  -- if tab found, switch to it
  if status_tab_index ~= -1 then
    vim.cmd("tabn " .. status_tab_index)
  else
    vim.cmd("tabnew | Git | wincmd k | q")
  end
end
map { "<A-t><A-g>",
  "[ Tabs ] Switch to git status",
  open_or_switch_to_git_status,
  mode = "n" }
map { "<A-t><A-c>",
  "[ Tabs ] New tab",
  ":tab new<CR>",
  mode = "n" }
map { "<A-t><A-x>",
  "[ Tabs ] Close tab",
  ":tab close<CR>",
  mode = "n" }
map { "<PageDown>",
  "[ Tabs ] Next tab",
  ":tabn<CR>",
  mode = "n" }
map { "<PageUp>",
  "[ Tabs ] Prev tab",
  ":tabp<CR>",
  mode = "n" }

-- -- [[ Windows ]] -- --
vim.keymap.set("n", "sp", ":sp<CR>", { silent = true })       -- split horizontal
vim.keymap.set("n", "sv", ":vsp<CR>", { silent = true })      -- split vertical
vim.keymap.set("n", "so", ":only<CR>", { silent = true })     -- leave only current window
vim.keymap.set("n", "sq", ":close<CR>", { silent = true })    -- close window
vim.keymap.set("n", "sh", "<c-w>h", { silent = true })        -- switch to left
vim.keymap.set("n", "sl", "<c-w>l", { silent = true })        -- switch to right
vim.keymap.set("n", "sj", "<c-w>j", { silent = true })        -- switch to down
vim.keymap.set("n", "sk", "<c-w>k", { silent = true })        -- switch to up
vim.keymap.set("n", "st", "<c-w><c-w>", { silent = true })    -- switch between recent
vim.keymap.set("n", "smm", "<c-w>_", { silent = true })       -- maximize current
vim.keymap.set("n", "smj", "<c-w>j<c-w>_", { silent = true }) -- maximize bottom
vim.keymap.set("n", "smk", "<c-w>k<c-w>_", { silent = true }) -- maximize up
vim.keymap.set("n", "sd", "<c-w>=", { silent = true })        -- revert maximize (d - default)
vim.keymap.set("n", "sr", "<c-w>r", { silent = true })        -- rotate
vim.keymap.set("n", "sH", "<c-w>H", { silent = true })        -- horizontal => vertical
vim.keymap.set("n", "sK", "<c-w>K", { silent = true })        -- vertical => horizontal
-- resizing
-- vim.keymap.set("n", "<right>", ":5wincmd ><CR>", { silent = true })
-- vim.keymap.set("n", "<left>", ":5wincmd <<CR>", { silent = true })
-- vim.keymap.set("n", "<up>", ":3wincmd -<CR>", { silent = true })
-- vim.keymap.set("n", "<down>", ":3wincmd +<CR>", { silent = true })
vim.keymap.set("n", "<right>", function() vim.cmd("vertical resize +" .. 5) end, { silent = true })
vim.keymap.set("n", "<left>", function() vim.cmd("vertical resize -" .. 5) end, { silent = true })
vim.keymap.set("n", "<up>", function() vim.cmd("resize +" .. 3) end, { silent = true })
vim.keymap.set("n", "<down>", function() vim.cmd("resize -" .. 3) end, { silent = true })

-- -- [[ Spellcheck ]] -- --

vim.keymap.set("n", "<A-s><A-r>", ":set spelllang=ru_yo<CR>", { silent = true }) -- RU
vim.keymap.set("n", "<A-s><A-e>", ":set spelllang=en_us<CR>", { silent = true }) -- EN
local function ToggleSpellCheck()
  -- Toggle the 'spell' option
  vim.cmd("set spell!")

  -- Check the state of the 'spell' option and echo the corresponding message
  if vim.o.spell then
    print("Spellcheck ON")
  else
    print("Spellcheck OFF")
  end
end
vim.keymap.set("n", "<A-s><A-t>", ToggleSpellCheck, { silent = true })

-- -- [[ Misc ]] -- --

vim.keymap.set("n", "<A-n><A-n>", ":set nornu<CR>", { silent = true })  -- absolute line numbers
vim.keymap.set("n", "<A-n><A-r>", ":set rnu<CR>", { silent = true })    -- relative line numbers
vim.keymap.set("n", "<A-r><A-r>", ":%s/", { silent = true })            -- replace text
vim.keymap.set("n", "<A-r><A-w>", ":%s/<C-r><C-w>/", { silent = true }) -- replace word under cursor
-- replace selection
vim.keymap.set("v", "<A-r><A-w>", "\"sy:%s/<C-r>=substitute(@s, '\\n', '', 'g')<cr>/", { silent = true })
vim.keymap.set("n", "<A-f><A-f>", ":b#<CR>", { silent = true }) -- swetch between last two buffers
-- make <F9> work in vim the same way as in ubuntu UI
vim.keymap.set("n", "<F9>", ":call system('copyq toggle')<CR>", { silent = true })
-- <C-o> is a temp switch to normal mode for insert
vim.keymap.set("i", "<F9>", "<C-o>:call system('copyq toggle')<CR>", { silent = true })
-- <C-\><C-n> is a temp switch to normal mode for terminal
vim.keymap.set("t", "<F9>", "<C-\\><C-n>:call system('copyq toggle')<CR>", { silent = true })

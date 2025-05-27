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
map { "<A-f><A-r>",
  "[ Edit ] Revert all the changes in the file",
  ":e!<CR>",
  mode = { "v", "n" } }

-- -- [[ Navigation ]] -- --
map { "Q",
  "[ Navigation ] Exit vim",
  ":qa<CR>",
  mode = { "n", "v" } }
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

vim.keymap.set("n", "<A-g><A-f>", function()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()

  -- Get word around cursor
  local left = line:sub(1, col + 1)
  local right = line:sub(col + 2)
  local joined = left .. right

  -- Try to extract a Ruby constant like Foo::Bar or just Foo
  local match = joined:match("([%a_][%w_]*::[%w_:]+)") or joined:match("([%a_][%w_]*)")
  if not match then
    vim.notify("No valid constant near cursor", vim.log.levels.WARN)
    return
  end

  -- Strip any trailing .call, .new, etc.
  match = match:gsub("%..*$", "")

  -- Convert CamelCase → snake_case + nested paths
  local snake_path = match
      :gsub("::", "/")
      :gsub("([a-z0-9])([A-Z])", "%1_%2")
      :gsub("([A-Z])([A-Z][a-z])", "%1_%2")
      :lower()

  -- List of fallback roots to search from (with ** recursive globbing)
  local roots = {
    "packs/*/app/services/",
    "packs/*/app/models/",
    "packs/*/lib/",
    "app/components/",
    "app/jobs/",
    "app/models/",
    "app/services/",
    "lib/"
  }

  for _, root in ipairs(roots) do
    local glob = root .. snake_path .. ".rb"
    local full_path = vim.fn.glob(glob, 0, 1)[1]
    if full_path and full_path ~= "" then
      vim.cmd("edit " .. full_path)
      return
    end
  end

  vim.notify("File not found for: " .. snake_path .. ".rb", vim.log.levels.WARN)
end, { noremap = true, silent = true, desc = "Smart Rails-style gf" })


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
  ":let @+ = expand('%:.')<CR>",
  mode = "n" }
-- vim.keymap.set("n", "<A-f>pr", function()
--     local relative_path = vim.fn.expand("%:.")  -- Get the relative path
--     vim.fn.setreg("+", relative_path)  -- Copy the relative path to the clipboard
--     print("Copied relative path: " .. relative_path)  -- Optional: print confirmation
-- end, { desc = "[Files] Copy relative path" })

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
-- map { "<A-t><A-g>",
--   "[ Tabs ] Switch to git status",
--   open_or_switch_to_git_status,
--   mode = "n" }
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

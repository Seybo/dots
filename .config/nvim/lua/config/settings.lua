-- -- [[ Global ]] -- --
-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
--  leader and localleader are set in plugins/lazy.lua
vim.g.have_nerd_font = true
vim.o.mouse = 'a' -- Enable mouse mode, can be useful for resizing splits for example
vim.o.showmode = false -- Don't show the mode, since it's already in the status line
vim.o.termguicolors = true

-- [[ Setting options ]]
-- See `:help vim.o`
-- For more options, you can see `:help option-list`

-- Line number
vim.o.number = true -- Show by default
vim.o.relativenumber = true -- Relative numbers, to help with jumping

-- Indentation
vim.o.breakindent = true -- Enable break indent
vim.o.expandtab = true -- Convert tabs to spaces
vim.o.shiftwidth = 2 -- How manu spaces to use for indentation by default
vim.o.tabstop = 2 -- This is similar to shiftwidth and it doesn't make sense to set them different
vim.o.softtabstop = 2 -- This is similar to shiftwidth and it doesn't make sense to set them different
vim.o.smarttab = true
vim.o.smartindent = false
vim.o.autoindent = true -- Keep indentation from the prev line

-- Folding
vim.o.foldmethod = 'expr'
vim.o.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
vim.o.foldlevel = 99 -- all folds up to level 99 will be open
vim.o.foldlevelstart = 99 -- when opening a file, start with these folds open

-- Save undo history
vim.o.undofile = true
vim.o.undolevels = 1000

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep signcolumn on by default
vim.o.signcolumn = 'yes'

-- Decrease update time
vim.o.updatetime = 250

-- Decrease mapped sequence wait time
vim.o.timeoutlen = 300

-- Configure how new splits should be opened
vim.o.splitright = true
vim.o.splitbelow = true

-- Sets how neovim will display certain whitespace characters in the editor.
--  See `:help 'list'`
--  and `:help 'listchars'`
--
--  Notice listchars is set using `vim.opt` instead of `vim.o`.
--  It is very similar to `vim.o` but offers an interface for conveniently interacting with tables.
--   See `:help lua-options`
--   and `:help lua-options-guide`
vim.o.list = true
vim.opt.listchars = { tab = '» ', trail = '⋅', nbsp = '␣' }

-- Preview substitutions live, as you type
vim.o.inccommand = 'split'

-- Show which line your cursor is on
vim.o.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.o.scrolloff = 5

-- if performing an operation that would fail due to unsaved changes in the buffer (like `:q`),
-- instead raise a dialog asking if you wish to save the current file(s)
-- See `:help 'confirm'`
vim.o.confirm = true

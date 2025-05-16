-- -- [[ Global ]] -- --
vim.ortermguicolors = true
vim.g.mapleader = " "
vim.opt.mouse = "a"        -- enable mouse support
vim.opt.backupcopy = "yes" -- create backup copy of file on save

-- -- [[ Folding ]] -- --
vim.opt.foldenable = false -- don't fold on file open
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"

-- -- [[ Tabline ]] -- --
vim.opt.showtabline = 2 -- always visible

-- -- [[ History ]] -- --
vim.opt.undofile = true
vim.opt.undolevels = 1000

-- -- [[ Indentation ]] -- --
vim.opt.smartindent = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2

-- -- [[ LSP ]] -- --
-- time before writing swap files to disk
-- and lsp diagnostics floating windows showup time
vim.o.updatetime = 1000
-- use lua print(:vim.lsp.get_log_path()) to see the log file path for below
-- vim.lsp.set_log_level("debug")

-- vim.opt.hidden = true
-- vim.opt.splitright = true
-- vim.opt.splitbelow = true
-- vim.opt.wrapscan = true
-- vim.opt.backup = false
-- vim.opt.writebackup = false
-- vim.opt.showcmd = true
-- vim.opt.showmatch = true
-- vim.opt.ignorecase = true
-- vim.opt.hlsearch = true
-- vim.opt.smartcase = true
-- vim.opt.errorbells = false
-- vim.opt.joinspaces = false
-- vim.opt.title = true
-- vim.opt.encoding = "UTF-8"
-- vim.opt.completeopt = { "menu", "menuone", "noselect" }
-- vim.opt.laststatus = 3
-- vim.opt.timeoutlen = 500
-- if vim.fn.has("nvim-0.9.0") == 1 then
--     vim.opt.splitkeep = "screen"
-- end
-- vim.opt.tabstop = 2
-- vim.opt.spelllang = "it"
-- vim.opt.softtabstop = 2
-- vim.opt.swapfile = false
-- vim.opt.number = true
-- vim.opt.relativenumber = false
-- vim.opt.signcolumn = "yes:1"
-- vim.opt.cursorline = false

-- to remove checkhealth warning: "Neovim::Ext" cpan module is not installed
-- vim.g.loaded_perl_provider = 0
-- vim.g.ruby_host_prog = "~/.rbenv/versions/2.7.6/bin/neovim-ruby-host"
-- vim.g.python3_host_prog = "$HOME/.pyenv/versions/3.12.2/bin/python"

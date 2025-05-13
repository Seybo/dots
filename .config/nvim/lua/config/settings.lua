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
vim.o.updatetime = 500
-- use lua print(:vim.lsp.get_log_path()) to see the log file path for below
-- vim.lsp.set_log_level("debug")

-- -- [[ Global ]] -- --

vim.ortermguicolors = true
vim.g.mapleader = " "
vim.opt.clipboard:append("unnamedplus") -- copy to system clipboard
vim.opt.mouse = "a" -- enable mouse support
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

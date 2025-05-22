-- Mark the task as undone
vim.keymap.set("n", "zu", "F[lr ", { noremap = true, silent = true })

-- Mark the task done
vim.keymap.set("n", "zd", "F[lrx", { noremap = true, silent = true })

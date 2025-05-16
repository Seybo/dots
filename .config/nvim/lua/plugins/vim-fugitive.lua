return {
  {
    "tpope/vim-fugitive",
    dependencies = {
      "junegunn/gv.vim",
      "tpope/vim-rhubarb",
    },
    config = function(_, opts)
      map { "<Leader>gm", "Fugitive: Git blame", ":Git blame<CR>", mode = { "n" } }
      map { "<Leader>gpf", "Fugitive: Git browse origin", ":Git push --force-with-lease<CR>", mode = { "n", "v" } }
      map { "<Leader>gbb", "Fugitive: Git browse", ":GBrowse<CR>", mode = { "n", "v" } }
      map { "<Leader>gbo", "Fugitive: Git browse origin", ":GBrowse origin:%<CR>", mode = { "n", "v" } }
    end,
  },
}

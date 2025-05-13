return {
  { -- deleting a buffer no longer closes its window or split
    "qpkorr/vim-bufkill",
    version = "*",
    event = "BufEnter",
  },
}

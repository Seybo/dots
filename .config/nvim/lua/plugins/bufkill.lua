return {
  { -- deleting a buffer no longer closes its window or split
    "qpkorr/vim-bufkill",
    event = "BufEnter",
  },
}

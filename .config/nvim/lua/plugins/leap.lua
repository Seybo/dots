return {
  {
    "ggandor/leap.nvim",
    config = function(_, opts)
      require "leap"

      map { "ss",
        "[ Search ] Leap search forward",
        "<Plug>(leap-forward-to)",
        mode = { "n", "x", "o" } }
      map { "SS",
        "[ Search ] Leap search backward",
        "<Plug>(leap-backward-to)",
        mode = { "n", "x", "o" } }
    end,
  }
}

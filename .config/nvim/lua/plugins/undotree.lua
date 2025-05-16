return {
  {
    "mbbill/undotree",
    config = function(_, opts)
      map { "<F5>",
        "[ Search ] Undo tree",
        vim.cmd.UndotreeToggle,
        mode = { "n" } }
    end,
  }
}

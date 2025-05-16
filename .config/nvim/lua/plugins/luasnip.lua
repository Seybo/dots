return {
  {
    "L3MON4D3/LuaSnip",
    event = "BufEnter",
    config = function(_, opts)
      local plugin = require "luasnip"
      local snippets_folder = "~/.config/nvim/lua/snippets/"
      require("luasnip.loaders.from_lua").load({ paths = snippets_folder })

      map { "<C-j>",
        "[ Cmp ] Luasnip jump to next input",
        function() plugin.jump(1) end,
        mode = { "i", "s" } }
      map { "<C-k>",
        "[ Cmp ] Luasnip jump to prev input",
        function() plugin.jump(-1) end,
        mode = { "i", "s" } }
      map { "<F6>",
        " [ Cmp ] Luasnip edit snippets",
        require("luasnip.loaders").edit_snippet_files,
        mode = { "n" } }
    end,
  }
}

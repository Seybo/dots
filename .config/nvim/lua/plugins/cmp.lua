return {
  {
    "hrsh7th/nvim-cmp",
    branch = "main",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-nvim-lua",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      "onsails/lspkind.nvim",
      "saadparwaiz1/cmp_luasnip",
    },
    config = function(_, opts)
      local plugin = require "cmp"
      local lsnip = require "luasnip"

      local has_words_before = function()
        unpack = unpack or table.unpack
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
      end

      plugin.setup {
        completion = {
          completeopt = "menu, menuone",
          preselect = "always",
        },
        sources = {
          { name = "luasnip" },
          { name = "nvim_lsp" },
          { name = "nvim_lua" },
          { name = "buffer" },
          { name = "path" },
        },
        snippet = {
          expand = function(args)
            lsnip.lsp_expand(args.body)
          end,
        },
        formatting = {
          fields = { "kind", "abbr", "menu" },
          format = function(entry, vim_item)
            local kind = require("lspkind").cmp_format({
              mode = "symbol_text",
              menu = {
                luasnip = "Snip",
                nvim_lua = "Lua",
                nvim_lsp = "LSP",
                buffer = "Buf",
                path = "Path",
              },
              maxwidth = 50,
            })(entry, vim_item)

            local strings = vim.split(kind.kind, "%s", { trimempty = true })
            kind.kind = " " .. strings[1] .. " "
            if strings[2] then
              kind.menu = "    [" .. kind.menu .. ": " .. strings[2] .. "]"
            else
              kind.menu = "    [" .. kind.menu .. "]"
            end
            return kind
          end,
        },
        mapping = {
          ["<Down>"] = plugin.mapping(function(fallback)
            if plugin.visible() then
              plugin.select_next_item()
              -- You could replace the expand_or_jumpable() calls with expand_or_locally_jumpable()
              -- they way you will only jump inside the snippet region
            elseif lsnip.expand_or_jumpable() then
              lsnip.expand_or_jump()
            elseif has_words_before() then
              plugin.complete()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<Up>"] = plugin.mapping(function(fallback)
            if plugin.visible() then
              plugin.select_prev_item()
            elseif lsnip.jumpable(-1) then
              lsnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<Right>"] = plugin.mapping.confirm({
            behavior = plugin.ConfirmBehavior.Replace,
            select = true,
          }),
          ["<C-u>"] = plugin.mapping.scroll_docs(-4),
          ["<C-d>"] = plugin.mapping.scroll_docs(4),
          -- ["<C-Space>"] = plugin.mapping.complete(),
          -- ["<C-e>"] = plugin.mapping.close(),
        },
      }
    end,
  }
}

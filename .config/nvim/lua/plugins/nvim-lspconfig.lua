return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      -- "folke/neodev.nvim",
      "williamboman/mason.nvim",
      "mason-org/mason-lspconfig.nvim",
    },
    config = function()
      local mason = require "mason"
      local mason_cfg = require "mason-lspconfig"
      local lsp_cfg = require "lspconfig"
      local util = require "lspconfig/util"
      -- local neodev = require "neodev"

      mason.setup {}

      mason_cfg.setup {
        ensure_installed = {
          -- https://github.com/williamboman/mason-lspconfig.nvim/blob/main/doc/server-mapping.md
          "cssls",
          "eslint",
          "graphql",
          "html",
          "jsonls",
          "lua_ls",
          "pylsp", -- for linter use ruff
          "rubocop",
          "rust_analyzer",
          "solargraph",
          "ts_ls",
          "vimls",
          "yamlls",
        },
      }

      lsp_cfg.ts_ls.setup {}
      lsp_cfg.eslint.setup {
        settings = {
          eslint = {
            autoformat = true,
          },
        },
      }

      lsp_cfg.pylsp.setup {}
      lsp_cfg.graphql.setup {}
      lsp_cfg.rust_analyzer.setup {}
    end,
  },
}

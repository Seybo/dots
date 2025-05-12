return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "folke/neodev.nvim",
      "williamboman/mason.nvim",
      "mason-org/mason-lspconfig.nvim",
    },
    config = function()
      local mason = require "mason"
      local mason_cfg = require "mason-lspconfig"
      local lsp_cfg = require "lspconfig"
      local util = require "lspconfig/util"
      local neodev = require "neodev"

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

      -- js
      lsp_cfg.ts_ls.setup {}
      lsp_cfg.eslint.setup {
        settings = {
          eslint = {
            autoformat = true,
          },
        },
      }

      -- lua
      neodev.setup {}
      lsp_cfg.lua_ls.setup {
        settings = {
          Lua = {
            diagnostics = {
              -- Get the language server to recognize the `vim` global
              globals = { "vim" },
            },
            hints = {
              enable = true,  -- Enable hints
            },
            workspace = { -- fixes "LSP[lua_ls][Info] Too large file:" and broken undo history
              preloadFileSize = 5000,
              -- to get rid of "Do you need to configure your work environment as `luv`?"
              checkThirdParty = false,
            },
          },
        },
      }


      -- ruby
      -- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md#solargraph
      lsp_cfg.solargraph.setup {
        cmd = { "rbenv", "exec", "solargraph", "stdio" },
        root_dir = util.root_pattern("Gemfile", ".git", "."),
        init_options = {
          autoformat = true,
          formatting = true,
        },
        settings = {
          solargraph = {
            useBundler = true,
            autoformat = true,
            completion = true,
            diagnostic = true,
            formatting = true,
            folding = true,
            references = true,
            rename = true,
            symbols = true,
            definitions = true,
            hover = true,
          },
        },
      }
      -- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md#rubocop
      lsp_cfg.rubocop.setup {
        cmd = { "rbenv", "exec", "bundle", "exec", "rubocop", "--lsp" },
      }

      -- Python
      lsp_cfg.pylsp.setup {}
      lsp_cfg.graphql.setup {}

      -- Rust
      lsp_cfg.rust_analyzer.setup {}
    end,
  },
}

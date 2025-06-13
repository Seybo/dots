return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'master',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      local configs = require('nvim-treesitter.configs')

      configs.setup({
        ensure_installed = {
          'bash',
          'diff',
          'html',
          'javascript',
          'jsdoc',
          'json',
          'jsonc',
          'lua',
          'vim',
          'vimdoc',
          'html',
          'markdown',
          'markdown_inline',
          'printf',
          'python',
          'query',
          'regex',
          'ruby',
          'toml',
          'tsx',
          'typescript',
          'vim',
          'vimdoc',
          'xml',
          'yaml',
        },
        sync_install = false,
        highlight = { enable = true },
        -- indentation as you type. Indentation fixes on save are handled by lsp (autocommand)
        indent = { enable = true },
        -- Incremental selection based on the named nodes from the grammar
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = '<Enter>', -- set to `false` to disable one of the mappings
            node_incremental = '<Enter>',
            scope_incremental = false,
            node_decremental = '<Backspace>',
          },
        },
      })
    end,
  },
}

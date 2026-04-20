local parsers = {
  'bash',
  'diff',
  'html',
  'javascript',
  'jsdoc',
  'json',
  'lua',
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
}

return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    main = 'nvim-treesitter',
    lazy = false,
    build = ':TSUpdate',
    init = function()
      local ts_filetypes = vim.tbl_filter(function(parser)
        return parser ~= 'markdown_inline' and parser ~= 'printf'
      end, parsers)

      vim.api.nvim_create_autocmd('FileType', {
        pattern = ts_filetypes,
        callback = function(event)
          pcall(vim.treesitter.start, event.buf)

          -- indentation as you type. Indentation fixes on save are handled by lsp (autocommand)
          if vim.bo[event.buf].filetype ~= 'ruby' then
            vim.bo[event.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
    config = function()
      require('nvim-treesitter').setup()
    end,
  },
}

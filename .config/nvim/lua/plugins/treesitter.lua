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
      vim.api.nvim_create_autocmd('FileType', {
        callback = function(event)
          if vim.b[event.buf].ts_highlight then
            return
          end

          -- Generic startup is needed so custom filetypes like pi-chat-history can still
          -- resolve to a real parser via treesitter language aliases (pi maps to markdown).
          local lang = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)
          if lang and vim.treesitter.language.add(lang) then
            pcall(vim.treesitter.start, event.buf, lang)
          end

          -- indentation as you type. Indentation fixes on save are handled by lsp (autocommand)
          -- Skip pi-chat-history: it's a rendered chat buffer, not an editable source buffer.
          if vim.bo[event.buf].filetype ~= 'ruby' and vim.bo[event.buf].filetype ~= 'pi-chat-history' then
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

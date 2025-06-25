return {
  'stevearc/conform.nvim',
  opts = function()
    return {
      formatters_by_ft = {
        html = { 'htmlbeautifier' },
        eruby = { 'htmlbeautifier' },
        ['eruby.yaml'] = { 'rubocop' },
        lua = { 'stylua' },
        ruby = { 'rubocop' },
        rust = { 'rustfmt' },
        toml = { 'taplo' },
      },
      formatters = {
        htmlbeautifier = {
          -- preserve blank lines
          append_args = { '--keep-blank-lines', '1' },
        },
      },
      format_on_save = function(bufnr)
        if vim.g.autoformat then
          local disable_filetypes = {}
          local lsp_format_opt
          if disable_filetypes[vim.bo[bufnr].filetype] then
            lsp_format_opt = 'never'
          else
            lsp_format_opt = 'fallback'
          end
          return {
            timeout_ms = 5000,
            lsp_format = lsp_format_opt,
          }
        else
          return
        end
      end,
    }
  end,
}

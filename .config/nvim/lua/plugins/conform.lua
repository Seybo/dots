return {
  'stevearc/conform.nvim',
  opts = {
    formatters_by_ft = {
      -- jsx/tsx formatting is handled by lsp
      lua = { 'stylua' },
      ruby = { 'rubocop' },
      rust = { 'rustfmt' },
      toml = { 'taplo' },
    },
    format_on_save = {
      -- These options will be passed to conform.format()
      timeout_ms = 5000,
      -- if no other formatters available and lsp allows it, use lsp formatting
      lsp_format = 'fallback',
    },
  },
}

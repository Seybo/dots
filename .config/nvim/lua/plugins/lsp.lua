return {
  'neovim/nvim-lspconfig',
  dependencies = {
    { 'mason-org/mason.nvim', opts = {} },
    { 'mason-org/mason-lspconfig.nvim' }, -- no opts here
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    {
      'j-hui/fidget.nvim',
      opts = { notification = { window = { align = 'top' } } },
    },
  },
  config = function()
    -- disable Mason-LSPConfig auto-attach
    require('mason-lspconfig').setup({
      ensure_installed = {},
      automatic_enable = false,
    })

    local lspconfig = require('lspconfig')
    local caps = require('cmp_nvim_lsp').default_capabilities()

    local servers = {
      bashls = {},
      html = {},
      lua_ls = {},
      marksman = {},
      rubocop = {},
      solargraph = {},
      rust_analyzer = {},
      cssls = {},
      eslint = {},
      graphql = {},
      ts_ls = {},
    }

    -- install servers
    require('mason-tool-installer').setup({
      ensure_installed = vim.tbl_keys(servers),
    })

    -- updatetime for CursorHold
    vim.opt.updatetime = 250

    -- diagnostics signs / float style
    vim.diagnostic.config({
      float = { border = 'rounded', source = 'if_many' },
      -- … your other diagnostic config …
    })

    -- open a floating diagnostic window on hover
    vim.api.nvim_create_augroup('MyDiagnosticFloat', { clear = true })
    vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
      group = 'MyDiagnosticFloat',
      callback = function() vim.diagnostic.open_float(nil, { focusable = false }) end,
    })

    for name, opts in pairs(servers) do
      if name == 'rubocop' then
        lspconfig.rubocop.setup({
          cmd = { 'bundle', 'exec', 'rubocop', '--lsp' },
          capabilities = caps,
        })
      else
        lspconfig[name].setup({
          capabilities = caps,
          unpack(opts),
        })
      end
    end

    -- keys
    -- Rename the variable under your cursor
    vim.keymap.set('n', 'glm', vim.lsp.buf.rename, { desc = '[[ LSP ]] Rename' })
    -- Execute a code action (normal + visual)
    vim.keymap.set({ 'n', 'x' }, 'gla', vim.lsp.buf.code_action, { desc = '[[ LSP ]] Goto Code Action' })
    -- Find references for the word under your cursor
    vim.keymap.set('n', 'glr', require('fzf-lua').lsp_references, { desc = '[[ LSP ]] Goto References' })
    -- Jump to the implementation of the word under your cursor
    vim.keymap.set('n', 'gli', require('fzf-lua').lsp_implementations, { desc = '[[ LSP ]] Goto Implementation' })
    -- Jump to the definition of the word under your cursor
    vim.keymap.set('n', 'gld', require('fzf-lua').lsp_definitions, { desc = '[[ LSP ]] Goto Definition' })
    -- Go to declaration (e.g. header in C)
    vim.keymap.set('n', 'glD', vim.lsp.buf.declaration, { desc = '[[ LSP ]] Goto Declaration' })
    -- Fuzzy-find all symbols in the current document
    vim.keymap.set('n', 'gls', require('fzf-lua').lsp_document_symbols, { desc = '[[ LSP ]] Open Document Symbols' })
    -- Fuzzy-find all symbols in the worspace
    vim.keymap.set('n', 'glw', require('fzf-lua').lsp_live_workspace_symbols, { desc = '[[ LSP ]] Open Workspace Symbols' })
    -- Jump to the type definition of the symbol under your cursor
    vim.keymap.set('n', 'glt', require('fzf-lua').lsp_typedefs, { desc = '[[ LSP ]] Goto Type Definition' })
    -- Open Lsp log
    vim.keymap.set('n', 'gll', ':e ~/.local/state/nvim/lsp.log<cr>', { desc = '[[ LSP ]] Open Log' })
    -- Open Lsp Info
    vim.keymap.set('n', 'glf', ':LspInfo<cr>', { desc = '[[ LSP ]] Open LspInfo' })
  end,
}

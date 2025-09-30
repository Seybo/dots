return {
  'neovim/nvim-lspconfig',
  dependencies = {
    { 'mason-org/mason.nvim', opts = {} },
    { 'mason-org/mason-lspconfig.nvim' }, -- no opts here; handled below
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    {
      'j-hui/fidget.nvim',
      opts = { notification = { window = { align = 'top' } } },
    },
  },
  config = function()
    -- Disable automatic LSP setup from mason-lspconfig. We will enable
    -- servers explicitly via vim.lsp.enable().
    require('mason-lspconfig').setup({
      ensure_installed = {},
      automatic_enable = false,
    })

    -- Capabilities advertised to language servers, extended via nvim-cmp
    local caps = require('cmp_nvim_lsp').default_capabilities()
    -- Alias to the vim.lsp module for convenience
    local lsp = vim.lsp

    -- Define the language servers you want to manage. Additional per‑server
    -- settings can be supplied in the value tables.
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

    -- Ensure the language servers are installed via mason.
    require('mason-tool-installer').setup({
      ensure_installed = vim.tbl_keys(servers),
    })

    -- Make CursorHold trigger more quickly so that diagnostics float sooner.
    vim.opt.updatetime = 250

    -- Configure diagnostic display. Rounded borders for hover floats and
    -- show sources only when multiple are present.
    vim.diagnostic.config({
      float = { border = 'rounded', source = 'if_many' },
      -- … add other diagnostic configuration here …
    })

    -- Create a floating diagnostic window on hover.
    vim.api.nvim_create_augroup('MyDiagnosticFloat', { clear = true })
    vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
      group = 'MyDiagnosticFloat',
      callback = function() vim.diagnostic.open_float(nil, { focusable = false }) end,
    })

    -- Configure and enable each server using the new API. For rubocop we
    -- specify a custom command.
    for name, opts in pairs(servers) do
      -- Start with a shallow copy of opts
      local config = vim.tbl_deep_extend('force', {}, opts)
      if name == 'rubocop' then
        -- Run rubocop via bundler to ensure gems are loaded from the project
        config.cmd = { 'bundle', 'exec', 'rubocop', '--lsp' }
      end
      -- Attach capabilities
      config.capabilities = caps
      -- Define the server configuration. This merges your config with any
      -- built‑in configs provided by nvim‑lspconfig under the lsp/ directory.
      lsp.config(name, config)
      -- Enable the server so it activates for its filetypes.
      lsp.enable(name)
    end

    -- Keymaps for common LSP actions. These use vim.lsp.buf and fzf‑lua for
    -- navigation. Descriptions appear in which‑key or other mapping UIs.
    vim.keymap.set('n', 'glm', lsp.buf.rename, { desc = '[[ LSP ]] Rename' })
    vim.keymap.set({ 'n', 'x' }, 'gla', lsp.buf.code_action, { desc = '[[ LSP ]] Goto Code Action' })
    vim.keymap.set('n', 'glr', require('fzf-lua').lsp_references, { desc = '[[ LSP ]] Goto References' })
    vim.keymap.set('n', 'gli', require('fzf-lua').lsp_implementations, { desc = '[[ LSP ]] Goto Implementation' })
    vim.keymap.set('n', 'gld', require('fzf-lua').lsp_definitions, { desc = '[[ LSP ]] Goto Definition' })
    vim.keymap.set('n', 'glD', lsp.buf.declaration, { desc = '[[ LSP ]] Goto Declaration' })
    vim.keymap.set('n', 'gls', require('fzf-lua').lsp_document_symbols, { desc = '[[ LSP ]] Open Document Symbols' })
    vim.keymap.set('n', 'glw', require('fzf-lua').lsp_live_workspace_symbols, { desc = '[[ LSP ]] Open Workspace Symbols' })
    vim.keymap.set('n', 'glt', require('fzf-lua').lsp_typedefs, { desc = '[[ LSP ]] Goto Type Definition' })
    vim.keymap.set('n', 'gll', ':e ~/.local/state/nvim/lsp.log<cr>', { desc = '[[ LSP ]] Open Log' })
    vim.keymap.set('n', 'glf', ':LspInfo<cr>', { desc = '[[ LSP ]] Open LspInfo' })
  end,
}

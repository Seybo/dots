return {
  {
    'hrsh7th/nvim-cmp',
    branch = 'main',
    event = 'InsertEnter',
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-nvim-lua',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-cmdline',
      'onsails/lspkind.nvim',
      'saadparwaiz1/cmp_luasnip',
    },
    config = function(_, opts)
      local plugin = require('cmp')
      local lsnip = require('luasnip')
      local supermaven = require('supermaven-nvim.completion_preview')

      local has_words_before = function()
        unpack = unpack or table.unpack
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match('%s') == nil
      end

      local function accept_line(suggestion_function)
        local line = vim.fn.line('.')
        local line_count = vim.fn.line('$')

        suggestion_function()

        local added_lines = vim.fn.line('$') - line_count

        if added_lines > 1 then
          vim.api.nvim_buf_set_lines(0, line + 1, line + added_lines, false, {})
          local last_col = #vim.api.nvim_buf_get_lines(0, line, line + 1, true)[1] or 0
          vim.api.nvim_win_set_cursor(0, { line + 1, last_col })
        end
      end

      -- it creates more undo breakpoints (actually after every tab+something),
      -- so when several tabs, I can undo each, and not the whole edit
      function My_undobreak() vim.o.undolevels = vim.o.undolevels end

      plugin.setup({
        preselect = plugin.PreselectMode.None,
        sources = {
          { name = 'luasnip' },
          { name = 'nvim_lsp' },
          { name = 'nvim_lua' },
          { name = 'buffer' },
          { name = 'path' },
        },
        snippet = {
          expand = function(args) lsnip.lsp_expand(args.body) end,
        },
        formatting = {
          fields = { 'kind', 'abbr', 'menu' },
          format = function(entry, vim_item)
            local kind = require('lspkind').cmp_format({
              mode = 'symbol_text',
              menu = {
                luasnip = 'Snip',
                nvim_lua = 'Lua',
                nvim_lsp = 'LSP',
                buffer = 'Buf',
                path = 'Path',
              },
              maxwidth = 50,
            })(entry, vim_item)

            local strings = vim.split(kind.kind, '%s', { trimempty = true })
            kind.kind = ' ' .. strings[1] .. ' '
            if strings[2] then
              kind.menu = '    [' .. kind.menu .. ': ' .. strings[2] .. ']'
            else
              kind.menu = '    [' .. kind.menu .. ']'
            end
            return kind
          end,
        },
        mapping = {
          ['<down>'] = plugin.mapping(function(fallback)
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
          end, { 'i', 's' }),
          ['<up>'] = plugin.mapping(function(fallback)
            if plugin.visible() then
              plugin.select_prev_item()
            elseif lsnip.jumpable(-1) then
              lsnip.jump(-1)
            else
              fallback()
            end
          end, { 'i', 's' }),
          ['<PageUp>'] = plugin.mapping(function(fallback)
            if lsnip.expand_or_jumpable() then
              plugin.confirm({
                behavior = plugin.ConfirmBehavior.Replace,
                select = true,
              })
              -- defer the exit so confirm() can finish feeding its keys
              vim.schedule(function() vim.cmd('stopinsert') end)
            elseif supermaven.has_suggestion() then
              My_undobreak()
              supermaven.on_accept_suggestion_word()
            else
              fallback()
            end
          end, { 'i', 's' }),
          ['<left>'] = plugin.mapping(function(fallback)
            if supermaven.has_suggestion() then
              supermaven.on_dispose_inlay()
            else
              fallback()
            end
          end, { 'i', 's' }),
          ['<Tab>'] = plugin.mapping(function(fallback)
            if supermaven.has_suggestion() then
              supermaven.on_accept_suggestion()
              vim.schedule(function() vim.cmd('stopinsert') end)
            else
              fallback()
            end
          end, { 'i', 's' }),
          ['<PageDown>'] = plugin.mapping(function(fallback)
            if supermaven.has_suggestion() then
              My_undobreak()
              accept_line(supermaven.on_accept_suggestion)
            else
              fallback()
            end
          end, { 'i', 's' }),
          ['<C-u>'] = plugin.mapping.scroll_docs(-4),
          ['<C-d>'] = plugin.mapping.scroll_docs(4),
          ['<Esc>'] = plugin.mapping.close(),
        },
      })
    end,
  },
}

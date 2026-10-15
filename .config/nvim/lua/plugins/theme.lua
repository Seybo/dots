return {
  {
    'rose-pine/neovim',
  },
  {
    'EdenEast/nightfox.nvim',
  },
  {
    'projekt0n/github-nvim-theme',
    name = 'github-theme',
  },
  {
    'sainnhe/everforest',
  },
  {
    name = 'active-theme',
    dir = vim.fn.stdpath('config'),
    config = function()
      local theme_path = vim.env.STOW_DIR .. '/themes/active/nvim.lua'
      dofile(theme_path)
      local modified = vim.uv.fs_stat(theme_path).mtime

      vim.api.nvim_create_autocmd('FocusGained', {
        group = vim.api.nvim_create_augroup('ActiveTheme', { clear = true }),
        callback = function()
          local stat = vim.uv.fs_stat(theme_path)
          -- The switcher briefly removes active files before copying the new theme.
          if not stat or (stat.mtime.sec == modified.sec and stat.mtime.nsec == modified.nsec) then
            return
          end
          dofile(theme_path)
          modified = stat.mtime
        end,
      })
    end,
  },
}

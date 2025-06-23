return {
  'rose-pine/neovim',
  config = function()
    -- the whole env theme is managed by the theme script: themes/theme_switcher.rb and its zsh alias 'theme'
    dofile(vim.env.STOW_DIR .. '/themes/active/nvim.lua')
  end,
}

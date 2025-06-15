return {
  'rose-pine/neovim',
  config = function()
    -- the whole env theme is managed by the theme script: themes/theme_switcher.rb and its zsh alias 'theme'
    dofile(vim.fn.expand('~/.dots/no_stow/themes/active/nvim.lua'))
  end,
}

local js_like = {
  left_var = "console.info('",
  right = "')",
  mid_var = "', ",
  right_var = '); // DEBUG_MM:',
}

return {
  'andrewferrier/debugprint.nvim',
  dependencies = {
    'echasnovski/mini.nvim', -- Optional: Needed for line highlighting (full mini.nvim plugin)
    'echasnovski/mini.hipatterns', -- Optional: Needed for line highlighting ('fine-grained' hipatterns plugin)
    'ibhagwan/fzf-lua', -- Optional: If you want to use the `:Debugprint search` command with fzf-lua
  },
  lazy = false, -- Required to make line highlighting work before debugprint is first used
  version = '*', -- Remove if you DON'T want to use the stable version
  opts = {
    display_location = false,
    display_snippet = false,
    print_tag = 'DEBUG_MM',
    filetypes = {
      ['javascript'] = js_like,
      ['javascriptreact'] = js_like,
      ['typescript'] = js_like,
      ['typescriptreact'] = js_like,
      ['ruby'] = {
        left_var = "puts('",
        right = "')",
        mid_var = "', ",
        right_var = ') # DEBUG_MM:',
      },
    },
    keymaps = {
      normal = {
        plain_below = 'g?p',
        plain_above = 'g?P',
        variable_below = 'g?v',
        variable_above = 'g?V',
        variable_below_alwaysprompt = 'g??',
      },
    },
  },
  config = function(_, opts) require('debugprint').setup(opts) end,
}

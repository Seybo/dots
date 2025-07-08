return {
  {
    'ggandor/leap.nvim',
    enabled = false, -- switching to flash
    opts = {
      -- make jumps more flexible: symbols within each group considered the same
      equivalence_classes = {
        ' \t\r\n', -- whitespace group (default)
        '([{', -- opening brackets
        ')]}', -- closing brackets
        '\'"`', -- single/double/backtick quotes
      },
      safe_labels = {}, -- disable auto-jumping to the first match
      preview_filter = function() -- don't show label after the first keypress
        return false
      end,
    },
    config = function(_, opts)
      require('leap').setup(opts)
      -- grey out the search area
      vim.api.nvim_set_hl(0, 'LeapBackdrop', { link = 'Comment' })
    end,
    keys = {
      { 'ss', '<Plug>(leap-forward-to)', desc = 'Leap search forward' },
      { 'SS', '<Plug>(leap-backward-to)', desc = 'Leap search backward' },
    },
  },
}

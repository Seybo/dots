return {
  'f-person/git-blame.nvim',
  event = 'VeryLazy',
  opts = {
    enabled = false, -- disable by default
    message_template = ' <summary> • <date> • <author> • <<sha>>',
    date_format = '%Y-%m-%d %H:%M:%S',
  },
  config = function(_, opts)
    require('gitblame').setup(opts)
    vim.g.gitblame_message_when_not_committed = ' :: You better commit it'
  end,
  keys = {
    { '<c-t>b', ':GitBlameToggle<cr>', desc = '[Toggle] Git blame', silent = true },
  },
}

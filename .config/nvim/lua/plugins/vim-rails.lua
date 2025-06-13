return {
  {
    'tpope/vim-rails',
    event = { 'BufReadPre', 'BufNewFile' },
    keys = {
      { 'ra', '', desc = '[ Vim Rails ] Revert the original binding replaced with :A' },
      { '<a-r><a-a>', ':A<CR>', desc = '[ Vim Rails ] Alternative file' },
      { '<a-r><a-s>', ':R<CR>', desc = '[ Vim Rails ] Alternative file' },
      {
        '<a-g><a-b>',
        "viw\"sy:Efixtures <C-r>=tolower(substitute(substitute(@s, '\\n', '', 'g'), '/', '\\\\/', 'g'))<cr>_factories<cr>",
        desc = '[ Vim Rails ] Fixtures',
      },
      {
        '<a-g><a-c>',
        "viw\"sy:Econtrollers <C-r>=substitute(substitute(@s, '\\n', '', 'g'), '/', '\\\\/', 'g')<cr>",
        'v',
        desc = '[ Vim Rails ] Fixtures',
      },
    },
  },
}

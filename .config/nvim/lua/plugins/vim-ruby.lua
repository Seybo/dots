return {
  { -- used only for indentaion, which is disabled for ruby files in treesitter
    -- because it doesnt correctly handle new line indentation in scenarios like
    --  args: foo,
    --        bar,
    --        baz
    --  or call(foo,
    --         bar,
    --         baz)
    'vim-ruby/vim-ruby',
  },
}

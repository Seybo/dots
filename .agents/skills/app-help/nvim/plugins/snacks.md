# snacks.nvim

## Local sources
- `~/.local/share/nvim/lazy/snacks.nvim/doc/snacks.nvim-notifier.txt`
- `~/.local/share/nvim/lazy/snacks.nvim/docs/explorer.md`
- `~/.local/share/nvim/lazy/snacks.nvim/README.md`

## Local configs
- `~/.dots/.config/nvim/lua/plugins/snacks.lua`

## Official sources
- https://github.com/folke/snacks.nvim

## Local gotchas
- Snacks replaces `vim.notify`; its notifier defaults to `width = { min = 40, max = 0.4 }`, so even short messages render at least 40 columns wide.
- Explorer defaults `formatters.file.git_status_hl = true`; untracked filenames then use `SnacksPickerGitStatusUntracked`, which links to the pale `NonText` highlight.

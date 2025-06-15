-- disable macros map `q` but allow `commands history` command (q:)
local function handle_q()
  local next_key = vim.fn.nr2char(vim.fn.getchar())
  if next_key == ':' then
    vim.api.nvim_feedkeys('q:', 'n', false)
  else
    -- Do nothing
  end
end

vim.keymap.set('n', 'q', handle_q, { noremap = true, silent = true })

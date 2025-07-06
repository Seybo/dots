return {
  'mistweaverco/kulala.nvim',
  keys = {
    { 's', desc = 'Send request' },
    { 'a', desc = 'Send all requests' },
    { 'b', desc = 'Open scratchpad' },
  },
  ft = { 'http', 'rest' },
  opts = {
    global_keymaps = true,
    global_keymaps_prefix = '<leader>r',
    kulala_keymaps_prefix = '',
  },
}

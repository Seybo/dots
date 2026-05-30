return {
  'mistweaverco/kulala.nvim',
  keys = {
    { 's', desc = 'Send request' },
    { 'a', desc = 'Send all requests' },
    { 'b', desc = 'Open scratchpad' },
  },
  ft = { 'http', 'rest' },
  opts = {
    -- New .http buffers start on the `dev` environment (env selection is
    -- per-buffer via environment_scope = 'b'), so {{BASE_URL}} etc. resolve
    -- without running set_selected_env('dev') each time.
    default_env = 'dev',
    global_keymaps = true,
    global_keymaps_prefix = '<leader>r',
    kulala_keymaps_prefix = '',
    kulala_keymaps = {
      ['Show verbose'] = { 'Z', function() require('kulala.ui').show_verbose() end },
    },
    ui = {
      display_mode = 'float',
      -- removed script_output
      default_winbar_panes = { 'body', 'headers', 'headers_body', 'verbose', 'report', 'help' },
      max_response_size = 32000000,
    },
  },
}

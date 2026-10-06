local function send_to_pi(msg)
  local cli = require('sidekick.cli')
  local state = require('sidekick.cli.state')

  if #state.get({ name = 'pi', attached = true }) > 0 then
    cli.send({ name = 'pi', msg = msg })
    return
  end

  local result = vim.system({ 'tmux', 'display-message', '-p', '-t', '{left-of}', '#{pane_pid}' }, { text = true }):wait()
  if result.code == 0 then
    local filter = {
      name = 'pi',
      external = true,
      started = true,
      session = 'tmux ' .. vim.trim(result.stdout),
    }
    if #state.get(filter) == 1 then
      cli.send({ filter = filter, msg = msg })
      return
    end
  end

  cli.send({ name = 'pi', msg = msg })
end

return {
  {
    'folke/sidekick.nvim',
    opts = {
      nes = { enabled = false },
      cli = {
        mux = {
          enabled = true,
          backend = 'tmux',
        },
      },
    },
    keys = {
      {
        '<leader>at',
        function() send_to_pi('{this}') end,
        mode = { 'n', 'x' },
        desc = '[Sidekick] Send location to Pi',
      },
      {
        '<leader>av',
        function() send_to_pi('{selection}') end,
        mode = 'x',
        desc = '[Sidekick] Send selection to Pi',
      },
    },
  },
}

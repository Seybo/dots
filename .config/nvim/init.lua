require('config.debugger')
require('config.settings')

if vim.env.MACHINE_NAME == 'oma' then
  require('config.remote_clipboard').setup()
end

require('config.lazy')
require('config.mappings')
require('config.autocommands')
require('utils.autoload')

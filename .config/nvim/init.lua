-- should go first as defines global mapping function
require("utils.map")
-- these settings are expected to run before lazy vim is initialized
require("config.settings")
require("config.lazy")
require("config.mappings")
require("config.autocommands")
require("utils.autoload")

-- should go first as defines global mapping function
require("utils.map")
-- these settings are expected to run before lazy vim is initialized
require("config.settings")
require("config.lazy")
require("config.mappings")
-- TODO_MM: remove if not needed here
-- require("lazy").setup("plugins")

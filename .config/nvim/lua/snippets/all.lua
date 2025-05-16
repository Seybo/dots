local plugin = require "luasnip"
local s = plugin.snippet
local t = plugin.text_node
local i = plugin.insert_node
local r = require("luasnip.extras").rep

return {
    s("print_var3", {
        t("print(\""),
        i(1, "desrc"),
        t(" | "),
        i(2, "the_variable"),
        t(" : \" .. "),
        r(2),
        t(")"),
    }),
}

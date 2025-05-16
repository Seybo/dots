local plugin = require "luasnip"
local s = plugin.snippet
local t = plugin.text_node
local i = plugin.insert_node
local r = require("luasnip.extras").rep

return {
    s("bpp (debugger)", {
        t("debugger; // eslint-disable-line REVERT_MM:"),
    }),
    s("clg (console.log)", {
        t("console.log('================ TODO_MM: "),
        i(1, "message"),
        t("')"),
    }),
    s("clg2 (console.log)", {
        t("console.log('================ TODO_MM: "),
        i(1, "message"),
        t("')"),
        -- Linebreak
        t({ "", "\t" }),
        t("console.log("),
        i(2, "variable"),
        t(")"),
    }),
    s("tds (START_MM:)", {
        t("// START_MM: "),
        i(1, ""),
        t({ "", "" }), -- linebreak
        t("// ⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻"),
    }),
    s("tdd (TODO_MM:)", {
        t("// TODO_MM: "),
        i(1, ""),
    }),
    s("tdb (BOOKMARK_MM:)", {
        t("// BOOKMARK_MM: "),
        i(1, ""),
    }),
    s("tdr (REVERT_MM:)", {
        t("// REVERT_MM: "),
        i(1, ""),
    }),
    s("tdc (COMMENT_MM:)", {
        t("// COMMENT_MM: "),
        i(1, ""),
        t({ "", "" }), -- linebreak
        t("// ⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻"),
    }),
    s("tdq (QUESTION_MM:)", {
        t("// QUESTION_MM: "),
        i(1, ""),
        t({ "", "" }), -- linebreak
        t("// ⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻"),
    }),
}

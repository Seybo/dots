local plugin = require "luasnip"
local s = plugin.snippet
local t = plugin.text_node
local i = plugin.insert_node
local r = require("luasnip.extras").rep

return {
    s("bpp (binding.pry)", {
        t("binding.pry if @foo.nil? # REVERT_MM:"),
    }),
    s("bpi (binding.pry if ...)", {
        t("binding.pry if @foo.nil? && "),
        i(1, "condition"),
        t(" # REVERT_MM:"),
    }),
    s("tds (START_MM:)", {
        t("# START_MM: "),
        i(1, ""),
        t({ "", "" }), -- linebreak
        t("# ⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻"),
    }),
    s("tdd (TODO_MM:)", {
        t("# TODO_MM: "),
        i(1, ""),
        t({ "", "" }), -- linebreak
        t("# ⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻"),
    }),
    s("tdb (BOOKMARK_MM:)", {
        t("# BOOKMARK_MM: "),
        i(1, ""),
        t({ "", "" }), -- linebreak
        t("# ⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻"),
    }),
    s("tdr (REVERT_MM:)", {
        t("# REVERT_MM: "),
        i(1, ""),
    }),
    s("tdc (COMMENT_MM:)", {
        t("# COMMENT_MM: "),
        i(1, ""),
        t({ "", "" }), -- linebreak
        t("# ⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻"),
    }),
    s("tdq (QUESTION_MM:)", {
        t("# QUESTION_MM: "),
        i(1, ""),
        t({ "", "" }), -- linebreak
        t("# ⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻⎻"),
    }),
    s("mmln (MM log new)", {
        t("MM.log_new"),
    }),
    s("mmlv (MM log var)", {
        t("MM.log_info \""),
        i(1, "var"),
        t(": #{"),
        r(1),
        t("}\" # REVERT_MM:"),
    }),
    s("mmli (MM log message)", {
        t("MM.log_info \""),
        i(1, "message"),
        t("\" # REVERT_MM:"),
    }),
    s("mmlg (MM using logger)", {
        t("MM.using_mm_logger do"),
    }),
    s("mmlt (MM using logger (with time))", {
        t("MM.using_mm_logger(:with_time) \""),
        i(1, "message"),
        t("\" # REVERT_MM:"),
    }),
    s("mmll (MM using logger(with_label))", {
        t("MM.using_mm_logger(with_label: '"),
        i(1, "message"),
        t("') do # REVERT_MM:"),
    }),
}

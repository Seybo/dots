-- helpers for Snacks.debug
_G.dd = function(...) Snacks.debug.inspect(...) end
_G.bt = function() Snacks.debug.backtrace() end
-- override vim.print so `vim.print { a = 1 }` shows a notification
vim.print = _G.dd

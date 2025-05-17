return {
  {
    "nanozuki/tabby.nvim",
    config = function()
      local theme = {
        fill = "TabLineFill",
        -- Also you can do this: fill = { fg='#f2e9de', bg='#907aa9', style='italic' }
        head = "TabLine",
        current_tab = "TabLineSel",
        tab = "TabLine",
        win = "TabLine",
        tail = "TabLine",
      }

      local function shorten(filename)
        if filename == "index" then
          return "git"
        end
        -- exclude extension
        filename = vim.fn.fnamemodify(filename, ":r")
        -- shorten if longer than 35 chars
        if string.len(filename) > 35 then
          filename = ".." .. string.sub(filename, -25)
        end
        return filename
      end

      require("tabby.tabline").set(function(line)
        return {
          {
            { "  ", hl = theme.head },
          },
          line.tabs().foreach(function(tab)
            local hl = tab.is_current() and theme.current_tab or theme.tab
            return {
              line.sep("", hl, theme.fill),
              shorten(tab.name()),
              line.sep("", hl, theme.fill),
              hl = hl,
              margin = " ",
            }
          end),
          hl = theme.fill,
        }
      end)
    end
  }
}

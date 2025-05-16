return {
  {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function(_, opts)
      local function should_ignore_filetype()
        local ft = vim.bo.filetype

        return
            ft == "alpha"
            or ft == "lazy"
            or ft == "mason"
            or ft == "neo-tree"
            or ft == "TelescopePrompt"
            or ft == "lazygit"
            or ft == "DiffviewFiles"
            or ft == "spectre_panel"
            or ft == "sagarename"
            or ft == "sagafinder"
            or ft == "saga_codeaction"
      end
      local plugin = require "lualine"
      local linemode = require "lualine.utils.mode"
      -- local color_theme = require "rose-pine.palette"

      local mode_section = {
        function()
          local m = linemode.get_mode()
          if m == "NORMAL" then
            return "N"
          elseif m == "VISUAL" then
            return "V"
          elseif m == "SELECT" then
            return "S"
          elseif m == "INSERT" then
            return "I"
          elseif m == "REPLACE" then
            return "R"
          elseif m == "COMMAND" then
            return "C"
          elseif m == "EX" then
            return "X"
          elseif m == "TERMINAL" then
            return "T"
          else
            return m
          end
        end,
      }

      local filename_section = {
        "filename",
        path = 0,
        fmt = function(v, _ctx)
          if should_ignore_filetype() then
            return nil
          else
            return v
          end
        end,
      }

      local searchcount_section = "searchcount"

      local encoding_section = {
        "encoding",
      }

      local diff_section = {
        colored = false,
        "diff",
      }

      local diagnostics_section = {
        colored = false,
        "diagnostics",
      }

      local filetype_section = {
        "filetype",
        colored = false,
        fmt = function(v, _ctx)
          if should_ignore_filetype() then
            return nil
          else
            if v == "markdown" then
              return "md"
            else
              return v
            end
          end
        end,
      }

      local progress_section = {
        "progress",
        separator = { left = "" },
      }

      local location_seciton = {
        "location",
        padding = { left = 0, right = 1 },
      }

      local theme = {
        normal = {
          -- a = { fg = color_theme.pine, bg = color_theme.base, gui = "bold" },
          -- b = { fg = color_theme.foam, bg = color_theme.base },
        },
      }

      plugin.setup {
        options = {
          theme = theme,
          icons_enabled = true,
          component_separators = "",
          section_separators = {
            left = "",
            -- left = "",
            right = "",
          },
          disabled_filetypes = {},
          ignore_focus = {},
          always_divide_middle = true,
          globalstatus = true,
        },
        sections = {
          lualine_a = {
            mode_section,
          },
          lualine_b = {
            -- show icon before filename
            { "filetype", icon_only = true, separator = "", padding = { right = 0, left = 1 } },
            filename_section,
          },
          lualine_c = {
            diff_section,
            diagnostics_section,
          },
          lualine_x = {},
          lualine_y = {
            searchcount_section,
            encoding_section,
            filetype_section,
            progress_section,
          },
          lualine_z = {
            location_seciton,
          },
        },
      }
    end,
  }
}

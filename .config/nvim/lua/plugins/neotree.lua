return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    enabled = false,
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    lazy = false, -- neo-tree will lazily load itself
    config = function()
      local plugin = require "neo-tree"
      local commands = require "neo-tree.command"

      local function close()
        commands.execute({ action = "close" })
      end

      plugin.setup {
        close_if_last_window = true,
        popup_border_style = "rounded",
        enable_git_status = true,
        enable_diagnostics = false,

        window = {
          width = 60,
          mapping_options = {
            noremap = true,
            nowait = true,
          },
        },
        event_handlers = {
          {
            event = "file_opened",
            handler = close,
          },
        },
      }

      local function open_file_tree()
        vim.cmd "Neotree source=filesystem position=left toggle=true reveal=true"
      end

      local function open_git_tree_index()
        vim.cmd "Neotree source=git_status position=float toggle=true reveal=true"
      end

      -- TODO_MM: sort out how to handle main/master here
      local function open_git_tree_all_changes()
        vim.cmd "Neotree source=git_status git_base=main position=float toggle=true reveal=true"
      end

      -- TODO_MM: sort out
      -- local function open_sessions()
      --   vim.cmd "Neotree ~/.local/share/nvim/sessions toggle=true reveal=true"
      -- end

      map { "<C-f>f",
        "[Neo-tree] Open file tree",
        open_file_tree,
        mode = "n" }

      map { "<C-f>i",
        "[Neo-tree] Open git tree index",
        open_file_tree,
        mode = "n" }

      map { "<C-f>c",
        "[Neo-tree] Open git tree all changes",
        open_git_tree_all_changes,
        mode = "n" }

      -- vim.keymap.set("n", "<A-f><A-s>", open_sessions)
    end,
  }
}

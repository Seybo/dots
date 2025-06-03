return {
  {

    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function(_, opts)
      local plugin = require "telescope"
      local builtin = require "telescope.builtin"
      local actions = require "telescope.actions"
      local layout = require "telescope.actions.layout"

      plugin.setup {
        defaults = {
          initial_mode = "normal",
          winblend = 10,
          layout_strategy = "vertical",
          layout_config = {
            vertical = {
              width = 0.8,
              height = 0.95,
              preview_cutoff = 10,
              mirror = true,
            },
          },
          mappings = {
            i = {
              ["<A-p>"] = layout.toggle_preview,
            },
            n = {
              ["qq"] = actions.close,
              ["<A-p>"] = layout.toggle_preview,
            },
          },
          prompt_prefix = "🔎 ",
          file_ignore_patterns = {
            "%.git/",
            "node_modules",
            "docker",
            "undodir",
          },
          pickers = {
            oldfiles = {
              initial_mode = "insert",
            },
          },
        },
      }

      -- Bindings

      local function current_buffer_fuzzy_find()
        -- You can pass additional configuration to telescope to change theme, layout, etc.
        builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown {
          initial_mode = "insert",
          previewer = false,
        })
      end

      local function find_files()
        builtin.find_files({
          hidden = true,
          no_ignore = false,
          initial_mode = "insert",
          previewer = true,
        })
      end

      local function find_files_pop_pack_heartland()
        builtin.find_files({
          hidden = true,
          no_ignore = false,
          initial_mode = "insert",
          previewer = true,
          cwd = "./packs/heartland_pos",
        })
      end

      local function oldfiles()
        builtin.oldfiles({
          initial_mode = "insert",
        })
      end

      local function get_visual_selection()
        vim.cmd('noau normal! "vy"')
        local text = vim.fn.getreg("v")
        vim.fn.setreg("v", {})

        text = string.gsub(text, "\n", "")
        if #text > 0 then
          return text
        else
          return ""
        end
      end

      local function live_grep_visual()
        local text = get_visual_selection()
        builtin.grep_string({
          search = text,
        })
      end

      local function live_grep()
        builtin.live_grep({
          initial_mode = "insert",
        })
      end

      local function commands()
        builtin.commands({
          initial_mode = "insert",
        })
      end

      local function command_history()
        builtin.command_history({
          initial_mode = "insert",
        })
      end

      map { "<Leader>tt", "telescope tags", builtin.help_tags, mode = { "n" } }
      map { "<Leader>tb", "telescope buffers", builtin.buffers, mode = { "n" } }
      map { "<Leader>td", "telescope diagnostics", builtin.diagnostics, mode = { "n" } }
      map { "<Leader>ff", "telescope find files", find_files, mode = { "n" } }
      map { "<Leader>fph", "telescope find files heartland", find_files_pop_pack_heartland, mode = { "n" } }
      -- using with snaks atm
      -- map { "<Leader>sb", "telescope fuzzy search in current buffer", current_buffer_fuzzy_find, mode = { "n" } }
      map { "<Leader>ss", "telescope live grep (word)", builtin.grep_string, mode = { "n" } }
      map { "<Leader>ss", "telescope live grep (selection)", live_grep_visual, mode = { "v" } }
      map { "<Leader>sm", "telescope live grep (manual)", live_grep, mode = { "n" } }
      map { "<Leader>tk", "telescope keymaps", builtin.keymaps, mode = { "n" } }
      map { "<Leader>cc", "telescope commands", commands, mode = { "n" } }
      map { "<Leader>ch", "telescope commands history", command_history, mode = { "n" } }
      map { "<Leader>fh", "telescope previously opened files", oldfiles, mode = { "n" } }
      map { "<Leader>gl", "telescope git log", builtin.git_commits, mode = { "n" } }
      map { "<Leader>gs", "telescope git stash", builtin.git_stash, mode = { "n" } }
      map { "<Leader>gt", "telescope git status", builtin.git_status, mode = { "n" } }

      -- TODOs are set in luasnip.lua
      local ts_grep = ":lua require('telescope.builtin').grep_string({ search = "
      local ts_keys = ":TodoTelescope keywords="
      local todo_desc = "telescope TODO "

      local todo_mappings = {
        { "<Leader>js", " (START_MM)",                ts_keys .. "START_MM initial_mode=normal<CR>" },
        { "<Leader>jt", todo_desc .. "(TODO_MM)",     ts_keys .. "TODO_MM initial_mode=normal<CR>" },
        { "<Leader>jq", todo_desc .. "(QUESTION_MM)", ts_keys .. "QUESTION_MM initial_mode=normal<CR>" },
        { "<Leader>jc", todo_desc .. "(COMMENT_MM)",  ts_keys .. "COMMENT_MM initial_mode=normal<CR>" },
        { "<Leader>ja", todo_desc .. "(all _MM)",     ts_grep .. "\"_MM:\", initial_mode=\"normal\"})<CR>" },
        { "<Leader>jp", "telescope binding.pry",      ts_grep .. "\" binding.pry\"})<CR>" },
        { "<Leader>jd", "telescope debugger",         ts_grep .. "\"debugger; // eslint-disable-line\"})<CR>" },
      }

      for _, mapping in ipairs(todo_mappings) do
        map {
          mapping[1], -- key
          mapping[2], -- description
          mapping[3], -- command
          mode = { "n" },
        }
      end

      require('telescope').load_extension('fzf')
    end,
  }
}

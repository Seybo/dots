return {
  { -- sessions management
    "gennaro-tedesco/nvim-possession",
    dependencies = {
      "ibhagwan/fzf-lua",
    },
    config = function()
      local possession = require("nvim-possession")

      possession.setup({
        save_hook = function()
          -- close terminal tabs as they can't be restored and break plugin
          local all_tabpages = vim.api.nvim_list_tabpages()
          local tabpages_to_close = {}

          -- Collect tabpages with terminal buffers
          for _, tabpage in ipairs(all_tabpages) do
            local win_ids = vim.api.nvim_tabpage_list_wins(tabpage)
            for _, win_id in ipairs(win_ids) do
              local bufnr = vim.api.nvim_win_get_buf(win_id)
              if vim.api.nvim_buf_get_option(bufnr, "buftype") == "terminal" then
                table.insert(tabpages_to_close, vim.api.nvim_tabpage_get_number(tabpage))
                break
              end
            end
          end

          -- Close the collected tabpages
          for _, tabnum in ipairs(tabpages_to_close) do
            vim.cmd(tabnum .. "tabclose")
          end
        end,
      })

      map { "<A-s>l",
        "[ Session ] List",
        possession.list,
        mode = "n" }
      map { "<A-s>n",
        "[ Session ] New",
        possession.new,
        mode = "n" }
    end,
  },
}

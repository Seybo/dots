return {
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    version = false, -- Never set this value to "*"! Never!
    -- commit = "f9aa75459d403d9e963ef2647c9791e0dfc9e5f9",
    -- working commit: d44db10
    opts = {
      provider = "claude",
      -- provider = "openai",
      openai = {
        endpoint = "https://api.openai.com/v1",
        model = "o4-mini",            -- your desired model (or use gpt-4o, etc.)
        timeout = 30000,              -- Timeout in milliseconds, increase this for reasoning models
        temperature = 0,
        max_completion_tokens = 8192, -- Increase this to include reasoning tokens (for reasoning models)
        --reasoning_effort = "medium", -- low|medium|high, only used for reasoning models
        disabled_tools = { "replace_in_file" },
        -- disable_tools = true, -- disable tools!
      },
      claude = {
        endpoint = "https://api.anthropic.com",
        model = "claude-3-5-haiku-20241022",
        timeout = 30000, -- Timeout in milliseconds
        temperature = 0,
        max_tokens = 4096,
        disabled_tools = { "replace_in_file" },
        -- disabled_tools = { "python" },
      },
      windows = {
        width = 70, -- default % based on available width
      },
      -- maps
      map { "<Leader>an", "[ Avante ] New chat", ":AvanteChatNew<CR>", mode = { "n" } },
      map { "<Leader>as", "[ Avante ] Stop", ":AvanteStop<CR>", mode = { "n" } },
      map { "<Leader>at", "[ Avante ] Toggle", ":AvanteToggle<CR>", mode = { "n" } },
      map { "<Leader>apc", "[ Avante ] Switch provider to Claude", ":AvanteSwitchProvider claude<CR>", mode = { "n" } },
      map { "<Leader>apo", "[ Avante ] Switch provider to OpenAI", ":AvanteSwitchProvider openai-gpt-4o-mini<CR>", mode = { "n" } },
    },
    -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
    build = "make",
    -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      --- The below dependencies are optional,
      -- "echasnovski/mini.pick",       -- for file_selector provider mini.pick
      "nvim-telescope/telescope.nvim", -- for file_selector provider telescope
      "hrsh7th/nvim-cmp",              -- autocompletion for avante commands and mentions
      "ibhagwan/fzf-lua",              -- for file_selector provider fzf
      "nvim-tree/nvim-web-devicons",   -- or echasnovski/mini.icons
      -- "zbirenbaum/copilot.lua",        -- for providers='copilot'
      -- {
      --   -- support for image pasting
      --   "HakonHarnes/img-clip.nvim",
      --   event = "VeryLazy",
      --   opts = {
      --     -- recommended settings
      --     default = {
      --       embed_image_as_base64 = false,
      --       prompt_for_file_name = false,
      --       drag_and_drop = {
      --         insert_mode = true,
      --       },
      --       -- required for Windows users
      --       use_absolute_path = true,
      --     },
      --   },
      -- },
      {
        -- Make sure to set this up properly if you have lazy=true
        'MeanderingProgrammer/render-markdown.nvim',
        opts = {
          file_types = { "markdown", "Avante" },
        },
        ft = { "markdown", "Avante" },
      },
    },
  }
}


-- debug instructions:
-- Enable avante.nvim's debug mode: ad
-- Reproduce the bug, then enter :messages to find the path of the last *-request-body.json file
-- cat <the path of *-request-body.json> | jq -r ".messages" or cat <the path of *-request.body.json> | jq -r ".contents"
-- Send me the content from above

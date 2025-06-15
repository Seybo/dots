return {
  {
    'yetone/avante.nvim',
    event = 'VeryLazy',
    version = false, -- Never set this value to "*"! Never!
    opts = {
      provider = 'claude',
      mode = 'legacy', -- in legace mode disabled_tools are respected
      providers = {
        openai = {
          endpoint = 'https://api.openai.com/v1',
          model = '4o-mini-high',
          disabled_tools = { 'replace_in_file' },
          timeout = 30000,
          extra_request_body = {
            temperature = 0.75,
            max_completion_tokens = 8192,
          },
        },
        claude = {
          endpoint = 'https://api.anthropic.com',
          model = 'claude-3-5-haiku-20241022',
          disabled_tools = { 'replace_in_file' },
          timeout = 30000,
          extra_request_body = {
            temperature = 0,
            max_tokens = 8192,
          },
        },
      },
      windows = {
        width = 70, -- default % based on available width
      },
    },
    keys = {
      { '<leader>an', ':AvanteChatNew<cr>', desc = '[Avante] New chat', mode = 'n' },
      { '<leader>as', ':AvanteStop<cr>', desc = '[Avante] Stop', mode = 'n' },
      { '<leader>at', ':AvanteToggle<cr>', desc = '[Avante] Toggle chat window', mode = 'n' },
      { '<leader>apc', ':AvanteSwitchProvider claude<cr>', desc = '[Avante] Use Claude', mode = 'n' },
      { '<leader>apo', ':AvanteSwitchProvider openai-gpt-4o-mini<cr>', desc = '[Avante] Use OpenAI GPT-4o-mini', mode = 'n' },
    },
    -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
    build = 'make',
    -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      'stevearc/dressing.nvim',
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      --- The below dependencies are optional,
      -- "echasnovski/mini.pick",       -- for file_selector provider mini.pick
      'nvim-telescope/telescope.nvim', -- for file_selector provider telescope
      'hrsh7th/nvim-cmp', -- autocompletion for avante commands and mentions
      'ibhagwan/fzf-lua', -- for file_selector provider fzf
      'nvim-tree/nvim-web-devicons', -- or echasnovski/mini.icons
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
          file_types = { 'markdown', 'Avante' },
        },
        ft = { 'markdown', 'Avante' },
      },
    },
  },
}

-- debug instructions:
-- Enable avante.nvim's debug mode: ad
-- Reproduce the bug, then enter :messages to find the path of the last *-request-body.json file
-- cat <the path of *-request-body.json> | jq -r ".messages" or cat <the path of *-request.body.json> | jq -r ".contents"
-- Send me the content from above

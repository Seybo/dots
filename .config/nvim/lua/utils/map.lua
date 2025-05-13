local default_options = { noremap = true, silent = true }

_G.map = function(mapping)
    -- it is important to remove items in reverse order to avoid shifting
    local cmd = table.remove(mapping, 3)
    local desc = table.remove(mapping, 2)
    local key = table.remove(mapping, 1)

    local mode = mapping.mode or { "n" }
    local msg = mapping.msg

    -- Remove 'mode' and 'msg' from mapping to prevent errors
    mapping.mode, mapping.msg = nil, nil

    -- Prepare options by merging default_options with any additional options from mapping
    -- This is done once here to avoid duplication and ensure efficiency
    local options = vim.tbl_extend("force", default_options, mapping)

    if msg then
        local final_cmd = function()
            print(msg)                                            -- Print the message
            vim.defer_fn(function() vim.cmd('echo ""') end, 2000) -- Clear message after 2 seconds

            if type(cmd) == "function" then
                cmd() -- Execute the command if it's a Lua function
            elseif type(cmd) == "string" then
                -- If cmd is a string, simulate key presses
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(cmd, true, false, true), "t", false)
            end
        end
        -- Apply the final_cmd with message handling
        vim.keymap.set(mode, key, final_cmd, options)
    else
        -- If no message is provided, use cmd as is
        vim.keymap.set(mode, key, cmd, options) -- cmd is used directly
    end
end

-- lua/loop/init.lua
local M = {}

-- Dependencies
local config = require("loop-debug.config")
local debugui = require("loop-debug.ui.debugui")
local strtools = require("loop.tools.strtools")

-----------------------------------------------------------
-- Defaults
-----------------------------------------------------------

---@type loop-debug.Config
local DEFAULT_CONFIG = {
    default_keymaps = true,
    stack_levels_limit = 100,
    auto_switch_page = true,
    sign_priority = {
        breakpoints = 12,
        currentframe = 13,
    },
    debuggers = require("loop-debug.debuggers")
}

-----------------------------------------------------------
-- State
-----------------------------------------------------------

local setup_done = false
local initialized = false

-----------------------------------------------------------
-- Setup (user config only)
-----------------------------------------------------------

---@param opts loop-debug.Config?
function M.setup(opts)
    if vim.fn.has("nvim-0.10") ~= 1 then
        error("loop.nvim requires Neovim >= 0.10")
    end

    config.current = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})
    setup_done = true

    M.init()
end

-----------------------------------------------------------
-- Initialization (runs once)
-----------------------------------------------------------

function M.init()
    if initialized then
        return
    end
    initialized = true

    -- Apply defaults if setup() was never called
    if not setup_done then
        config.current = DEFAULT_CONFIG
    end

    require('loop-debug.ui.signs').init()


    if config.current.default_keymaps then
        vim.keymap.set("n", "<leader>db", ":LoopDebug breakpoint<CR>", { desc = "Toggle breakpoint", silent = true })
        vim.keymap.set("n", "<leader>dB", ":LoopDebug breakpoint list<CR>", { desc = "List breakpoints", silent = true })
        vim.keymap.set("n", "<leader>dm", ":LoopDebug debug_mode<CR>", { desc = "Toggle debug mode", silent = true })
        vim.keymap.set("n", "<leader>ds", ":LoopDebug debug session<CR>",
            { desc = "Select debug session", silent = true })
        vim.keymap.set("n", "<leader>dt", ":LoopDebug debug thread<CR>", { desc = "Select thread", silent = true })
        vim.keymap.set("n", "<leader>dc", ":LoopDebug debug continue<CR>",
            { desc = "Continue paused session", silent = true })
        vim.keymap.set("n", "<leader>dC", ":LoopDebug debug continue_all<CR>",
            { desc = "Continue all paused sesions", silent = true })
        vim.keymap.set("n", "<leader>dK", ":LoopDebug debug terminate_all<CR>",
            { desc = "Terminal all debug sessions", silent = true })
    end
end

-----------------------------------------------------------
-- Command completion
-----------------------------------------------------------

local function _debug_subcommands(args)
    if #args == 0 then
        return { "session", "thread", "continue", "step_in", "step_out", "step_over", "step_back", "terminate",
            "continue_all", "terminate_all" }
    end
    return {}
end

function M.complete(arg_lead, cmd_line)
    M.init()

    local function filter(strs)
        local out = {}
        for _, s in ipairs(strs or {}) do
            if not vim.startswith(s, '_') and vim.startswith(s, arg_lead) then
                table.insert(out, s)
            end
        end
        return out
    end

    local args = strtools.split_shell_args(cmd_line)
    if cmd_line:match("%s+$") then
        table.insert(args, ' ')
    end

    if #args == 2 then
        local values = filter(_debug_subcommands())
        return values
    end

    return {}
end

-----------------------------------------------------------
-- Dispatcher
-----------------------------------------------------------

function M.dispatch(opts)
    M.init()

    local args = strtools.split_shell_args(opts.args)
    local subcmd = args[1]

    if not subcmd or subcmd == "" then
        vim.notify(
            "Usage: :LoopDebug <command> [args...]",
            vim.log.levels.WARN
        )
        return
    end
    if not vim.tbl_contains(_debug_subcommands(), subcmd) then
        vim.notify("LoopDebug invalid command " .. subcmd, vim.log.levels.ERROR)
        return
    end
    local ok, err = pcall(debugui.debug_command, unpack(args))
    if not ok then
        vim.notify(
            "LoopDebug " .. subcmd .. " failed: " .. tostring(err),
            vim.log.levels.ERROR
        )
    end
end

return M

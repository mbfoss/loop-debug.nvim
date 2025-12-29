-- lua/loop/init.lua
local M = {}

-- Dependencies
local config = require("loop-debug.config")
local manager = require("loop-debug.manager")
local debugui = require("loop-debug.ui")
local strtools = require("loop.tools.strtools")

-----------------------------------------------------------
-- Defaults
-----------------------------------------------------------

---@type loop-debug.Config
local DEFAULT_CONFIG = {
    stack_levels_limit = 100,
    auto_switch_page = true,
    sign_priority = {
        breakpoints = 12,
        currentframe = 13,
    },
    symbols = {
        running                  = "▶",
        paused                   = "■",
        success                  = "✓",
        failure                  = "✗",
        active_breakpoint        = "●",
        inactive_breakpoint      = "○",
        logpoint                 = "◆",
        logpoint_inactive        = "◇",
        cond_breakpoint          = "■",
        cond_breakpoint_inactive = "□",
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

    require('loop-debug.breakpoints').init()
    require('loop-debug.tools.signsmgr').init()
    require('loop-debug.breakpointsmonitor').init()
    require('loop-debug.curframe_sign').init()
    require('loop-debug.ui').init()
end

-----------------------------------------------------------
-- Command completion
-----------------------------------------------------------
local function _debug_commands()
    return {
        -- UI
        "ui",
        -- Breakpoints
        "breakpoint",
        -- Execution control
        "continue",
        "continue_all",
        "pause",
        -- Stepping
        "step_over",
        "step_in",
        "step_out",
        "step_back",
        -- Navigation
        "session",
        "thread",
        "frame",
        -- Inspection
        "inspect",
        -- Termination
        "terminate",
        "terminate_all",
    }
end


local function _debug_subcommands(args)
    if #args == 2 then
        return _debug_commands()
    end
    if #args == 3 and args[2] == "breakpoint" then
        return { "list", "toggle", "logpoint", "clear_file", "clear_all" }
    end
    return {}
end

function M.complete(arg_lead, cmd_line)
    M.init()

    local function filter(strs)
        local out = {}
        for _, s in ipairs(strs or {}) do
            if vim.startswith(s, arg_lead) then
                table.insert(out, s)
            end
        end
        return out
    end

    local args = strtools.split_shell_args(cmd_line)
    if cmd_line:match("%s+$") then
        table.insert(args, ' ')
    end

    return filter(_debug_subcommands(args))
end

function M.select_command()
    ---@type loop.tools.Cmd[]
    local all_cmds = {}

    ------------------------------------------------------------------
    -- Top-level debug commands
    ------------------------------------------------------------------
    local debug_cmds = {
        -- Session
        { "ui",            "Toggle debug UI" },
        -- Breakpoints
        { "breakpoint",    "Breakpoint operations" },
        -- Execution control
        { "continue",      "Continue execution" },
        { "continue_all",  "Continue all sessions" },
        { "pause",         "Pause execution" },
        { "step_over",     "Step over" },
        { "step_in",       "Step into" },
        { "step_out",      "Step out" },
        { "step_back",     "Step back" },
        -- Navigation
        { "session",       "Select debug session" },
        { "thread",        "Select thread" },
        { "frame",         "Select stack frame" },
        -- Inspection
        { "inspect",       "Inspect variable at the cursor location" },
        -- Termination
        { "terminate",     "Terminate debug session" },
        { "terminate_all", "Terminate all sessions" },
    }

    for _, cmd in ipairs(debug_cmds) do
        table.insert(all_cmds, {
            vimcmd = "LoopDebug " .. cmd[1],
            help = cmd[2],
        })
    end

    ------------------------------------------------------------------
    -- Breakpoint subcommands
    ------------------------------------------------------------------
    local breakpoint_cmds = {
        { "list",       "List breakpoints" },
        { "toggle",     "Toggle breakpoint" },
        { "logpoint",   "Toggle logpoint" },
        { "clear_file", "Clear breakpoints in file" },
        { "clear_all",  "Clear all breakpoints" },
    }

    for _, cmd in ipairs(breakpoint_cmds) do
        table.insert(all_cmds, {
            vimcmd = "LoopDebug breakpoint " .. cmd[1],
            help = cmd[2],
        })
    end

    require("loop.tools.cmdmenu").select_and_run_command(all_cmds)
end

-----------------------------------------------------------
-- Dispatcher
-----------------------------------------------------------

function M.do_command(...)
    local cmd = select(1, ...)
    if cmd == "ui" then
        debugui.toggle()
        return
    end
    manager.debug_command(...)
end

function M.dispatch(opts)
    M.init()

    local args = strtools.split_shell_args(opts.args)
    local subcmd = args[1]

    if not subcmd or subcmd == "" then
        M.select_command()
        return
    end
    if not vim.tbl_contains(_debug_commands(), subcmd) then
        vim.notify("LoopDebug invalid command " .. subcmd, vim.log.levels.ERROR)
        return
    end
    local ok, err = pcall(M.do_command, unpack(args))
    if not ok then
        vim.notify(
            "LoopDebug " .. subcmd .. " failed: " .. tostring(err),
            vim.log.levels.ERROR
        )
    end
end

return M

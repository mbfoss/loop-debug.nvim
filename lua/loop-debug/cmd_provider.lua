local M = {}

local manager = require("loop-debug.manager")
local debugui = require("loop-debug.ui")
local strtools = require("loop.tools.strtools")

local function _debug_commands(args)
    if #args == 0 then
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
    if #args == 1 and args[1] == "breakpoint" then
        return { "list", "toggle", "logpoint", "conditional", "clear_file", "clear_all" }
    end
    return {}
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
        { "list",        "List breakpoints" },
        { "toggle",      "Toggle breakpoint" },
        { "logpoint",    "Create a logpoint" },
        { "conditional", "Create a conditional breakpoint" },
        { "clear_file",  "Clear breakpoints in file" },
        { "clear_all",   "Clear all breakpoints" },
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

---@param args string[]
---@param opts vim.api.keyset.create_user_command.command_args
local function _do_command(args, opts)
    local cmd = args[1]
    if cmd == "ui" then
        debugui.toggle()
        return
    end
    manager.debug_command(cmd, args, opts)
end

---@type loop.UserCommandProvider
return {
    get_subcommands = function(args)
        return _debug_commands(args)
    end,
    dispatch = function(args, opts)
        return _do_command(args, opts)
    end,
}

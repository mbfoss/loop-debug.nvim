local M = {}


local Trackers    = require("loop.tools.Trackers")
local uitools     = require("loop.tools.uitools")
local wsinfo      = require('loop.wsinfo')
local persistence = require('loop-debug.persistence')

---@class loopdebug.SourceBreakpoint
---@field id number
---@field file string
---@field line integer
---@field column integer|nil
---@field condition string|nil
---@field hitCondition string|nil
---@field logMessage string|nil


---@class loopdebug.breakpoints.Tracker
---@field on_added fun(bp:loopdebug.SourceBreakpoint)|nil
---@field on_removed fun(bp:loopdebug.SourceBreakpoint)|nil
---@field on_all_removed fun(bpts:loopdebug.SourceBreakpoint[])|nil

local _last_breakpoint_id = 1000

---@type table<string,table<number,number>> -- file --> line --> id
local _source_breakpoints = {}

---@type table<number,loopdebug.SourceBreakpoint>
local _by_id = {} -- breakpoints by unique id

---@type loop.tools.Trackers<loopdebug.breakpoints.Tracker>
local _trackers = Trackers:new()

---@param callbacks loopdebug.breakpoints.Tracker
---@param no_snapshot boolean?
---@return loop.TrackerRef
function M.add_tracker(callbacks, no_snapshot)
    local tracker_ref = _trackers:add_tracker(callbacks)
    if not no_snapshot then
        --initial snapshot
        ---@type loopdebug.SourceBreakpoint[]
        local current = vim.tbl_values(_by_id)
        table.sort(current, function(a, b)
            if a.file ~= b.file then return a.file < b.file end
            return a.line < b.line
        end)
        if callbacks.on_added then
            for _, bp in ipairs(current) do
                callbacks.on_added(bp)
            end
        end
    end
    return tracker_ref
end

local function _norm(file)
    if not file or file == "" then return file end
    return vim.fn.fnamemodify(file, ":p")
end

--- Check if a file has a breakpoint on a specific line.
---@param file string  File path
---@param line integer  Line number
---@return number|nil
---@return loopdebug.SourceBreakpoint|nil
local function _get_source_breakpoint(file, line)
    local lines = _source_breakpoints[file]
    if not lines then return nil, nil end
    local id = lines[line]
    if not id then return nil, nil end
    return id, _by_id[id]
end

--- Check if a file has a breakpoint on a specific line.
---@param file string  File path
---@param line integer  Line number
---@return boolean has_breakpoint  True if a breakpoint exists on that line
local function _have_source_breakpoint(file, line)
    return _get_source_breakpoint(file, line) ~= nil
end

--- Remove a single breakpoint and its sign.
---@param file string File path
---@param line integer Line number
---@return boolean removed True if a breakpoint was removed
local function _remove_source_breakpoint(file, line)
    local lines = _source_breakpoints[file]
    if not lines then return false end

    local id = lines[line]
    if not id then return false end

    local bp = _by_id[id]
    if bp then
        lines[line] = nil
        _by_id[id] = nil
        _trackers:invoke("on_removed", bp)
    end
    return true
end

---@param file string File path
local function _clear_file_breakpoints(file)
    local lines = _source_breakpoints[file]

    local removed = {}

    if not lines then return end
    for _, id in pairs(lines) do
        local bp = _by_id[id]
        if bp then
            table.insert(removed, bp)
            _by_id[id] = nil
        end
    end

    _source_breakpoints[file] = nil
    for _, bp in pairs(removed) do
        _trackers:invoke("on_removed", bp)
    end
end

local function _clear_breakpoints()
    ---@type loopdebug.SourceBreakpoint[]
    local removed = vim.tbl_values(_by_id)
    _by_id = {}
    _source_breakpoints = {}
    _trackers:invoke("on_all_removed", removed)
end


--- Add a new breakpoint and display its sign.
---@param file string File path
---@param line integer Line number
---@param condition? string condition
---@param hitCondition? string Optional hit condition
---@param logMessage? string Optional log message
---@return boolean added
local function _add_source_breakpoint(file, line, condition, hitCondition, logMessage)
    if _have_source_breakpoint(file, line) then
        return false
    end
    local id = _last_breakpoint_id + 1
    _last_breakpoint_id = id

    ---@type loopdebug.SourceBreakpoint
    local bp = {
        id = id,
        file = file,
        line = line,
        condition = condition,
        hitCondition = hitCondition,
        logMessage = logMessage
    }

    _by_id[id] = bp

    _source_breakpoints[file] = _source_breakpoints[file] or {}
    local lines = _source_breakpoints[file]
    lines[line] = id

    _trackers:invoke("on_added", bp)

    return true
end

---@param file string
---@param lnum number
function M.toggle_breakpoint(file, lnum)
    file = _norm(file)
    if not _remove_source_breakpoint(file, lnum) then
        _add_source_breakpoint(file, lnum)
    end
end

---@param file string
---@param lnum number
---@return boolean
function M.add_breakpoint(file, lnum)
    file = _norm(file)
    return _add_source_breakpoint(file, lnum)
end

---@param file string
---@param lnum number
---@param message string
function M.set_logpoint(file, lnum, message)
    if type(message) == "string" and #message > 0 then
        file = _norm(file)
        _remove_source_breakpoint(file, lnum)
        _add_source_breakpoint(file, lnum, nil, nil, message)
    end
end

---@param file string
function M.clear_file_breakpoints(file)
    _clear_file_breakpoints(_norm(file))
end

--- clear all breakpoints.
function M.clear_all_breakpoints()
    _clear_breakpoints()
end

---@return loopdebug.SourceBreakpoint[]
function M.get_breakpoints()
    ---@type loopdebug.SourceBreakpoint[]
    local bpts = {}
    for _, bp in pairs(_by_id) do
        table.insert(bpts, bp)
    end
    return bpts
end

---@param breakpoints loopdebug.SourceBreakpoint[]
function _set_breakpoints(breakpoints)
    _clear_breakpoints()

    table.sort(breakpoints, function(a, b)
        if a.file ~= b.file then return a.file < b.file end
        return a.line < b.line
    end)

    for _, bp in ipairs(breakpoints) do
        local file = vim.fn.fnamemodify(bp.file, ":p")
        _add_source_breakpoint(file, bp.line, bp.condition, bp.hitCondition, bp.logMessage)
    end

    return true, nil
end

---@return boolean
function M.have_breakpoints()
    return next(_by_id) ~= nil
end

---@param handler fun(bp:loopdebug.SourceBreakpoint)
function M.for_each(handler)
    for _, bp in ipairs(_by_id) do
        handler(bp)
    end
end

---@param command nil|"toggle"|"logpoint"|"clear_file"|"clear_all"
function M.breakpoints_command(command)
    local ws_dir = wsinfo.get_ws_dir()
    if not ws_dir then
        vim.notify('No active workspace')
        return
    end
    command = command and command:match("^%s*(.-)%s*$") or ""
    if command == "" or command == "toggle" then
        local file, line = uitools.get_current_file_and_line()
        if file and line then
            M.toggle_breakpoint(file, line)
        end
    elseif command == "logpoint" then
        vim.ui.input({ prompt = "Enter log message: " }, function(message)
            if message and message ~= "" then
                local file, line = uitools.get_current_file_and_line()
                if file and line then
                    M.set_logpoint(file, line, message)
                    print("Logpoint set at " .. file .. ":" .. line)
                end
            end
        end)
    elseif command == "clear_file" then
        local bufnr = vim.api.nvim_get_current_buf()
        if vim.api.nvim_buf_is_valid(bufnr) then
            local full_path = vim.api.nvim_buf_get_name(bufnr)
            if full_path and full_path ~= "" then
                uitools.confirm_action("Clear dapbreakpoints in file", false, function(accepted)
                    if accepted == true then
                        M.clear_file_breakpoints(full_path)
                    end
                end)
            end
        end
    elseif command == "clear_all" then
        uitools.confirm_action("Clear all dapbreakpoints", false, function(accepted)
            if accepted == true then
                M.clear_all_breakpoints()
            end
        end)

        vim.notify('Invalid breakpoints subcommand: ' .. tostring(command))
    end
end

function M.init()
    if _init_done then return end
    _init_done = true

    persistence.add_tracker({
        on_ws_open = function()
            _set_breakpoints(persistence.get_config("breakpoints") or {})
        end,
        on_ws_closed = function()
        end,
        on_ws_will_save = function()
            persistence.set_config("breakpoints", M.get_breakpoints())
        end
    })
end

return M

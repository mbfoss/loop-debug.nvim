local signs             = require('loop.debug.signs')
local dapbreakpoints    = require('loop-debug.dap.breakpoints')
local Trackers          = require('loop.tools.Trackers')
local selector          = require("loop.tools.selector")
local projinfo          = require("loop.projinfo")
local uitools           = require("loop.tools.uitools")

local M                 = {}

local _setup_done       = false
local _setup_err_msg    = "setup() not called"

---@class loop.debugui.Tracker
---@field on_bp_added fun(bp:loopdebug.SourceBreakpoint, verified:boolean)|nil
---@field on_bp_removed fun(bp:loopdebug.SourceBreakpoint)|nil
---@field on_all_bp_removed fun(bpts:loopdebug.SourceBreakpoint[])|nil
---@field on_bp_state_update fun(bp:loopdebug.SourceBreakpoint, verified:boolean)

---@type loop.tools.Trackers<loop.debugui.Tracker>
local _trackers = Trackers:new()

---@class loop.debug_ui.Breakpointata
---@field breakpoint loopdebug.SourceBreakpoint
---@field states table<number,boolean>|nil

---@type table<number,loop.debug_ui.Breakpointata>
local _breakpoints_data = {}

---@param bp loopdebug.SourceBreakpoint
---@param verified boolean
---@return loop.signs.SignName
local function _get_breakpoint_sign(bp, verified)
    -- Determine the sign type based on breakpoint fields
    local sign
    if bp.logMessage then
        sign = verified and "logpoint" or "logpoint_inactive"
    elseif bp.condition or bp.hitCondition then
        sign = verified and "conditional_breakpoint" or "conditional_breakpoint_inactive"
    else
        sign = verified and "active_breakpoint" or "inactive_breakpoint"
    end
    return sign
end

---@param data loop.debug_ui.Breakpointata
---@@return boolean
local function _get_breakpoint_state(data)
    local verified = nil
    if data.states then
        for _, state in ipairs(data.states) do
            verified = verified or state
        end
    end
    if verified == nil then verified = true end
    return verified
end

---@param id number
---@param data loop.debug_ui.Breakpointata
local function _refresh_breakpoint_sign(id, data)
    local verified = _get_breakpoint_state(data)
    local sign = _get_breakpoint_sign(data.breakpoint, verified)
    signs.place_file_sign(id, data.breakpoint.file, data.breakpoint.line, "breakpoints", sign)
    _trackers:invoke("on_bp_state_update", data.breakpoint, verified)
end

---@param bp loopdebug.SourceBreakpoint
local function _on_breakpoint_added(bp)
    _breakpoints_data[bp.id] = {
        breakpoint = bp,
    }
    local sign = _get_breakpoint_sign(bp, true)
    signs.place_file_sign(bp.id, bp.file, bp.line, "breakpoints", sign)
    _trackers:invoke("on_bp_added", bp, true)
end

---@param bp loopdebug.SourceBreakpoint
local function _on_breakpoint_removed(bp)
    _breakpoints_data[bp.id] = nil
    signs.remove_file_sign(bp.id, "breakpoints")
    _trackers:invoke("on_bp_removed", bp)
end

---@param removed loopdebug.SourceBreakpoint[]
local function _on_all_breakpoints_removed(removed)
    _breakpoints_data = {}
    local files = {}
    for _, bp in ipairs(removed) do
        files[bp.file] = true
    end
    for file, _ in pairs(files) do
        signs.remove_file_signs(file, "breakpoints")
    end
    _trackers:invoke("on_all_bp_removed", removed)
end

---@param task_name string -- task name
---@return loop.job.debugjob.Tracker
function M.track_new_debugjob(task_name)
    assert(_setup_done, _setup_err_msg)
    assert(type(task_name) == "string")

    ---@type loop.job.debugjob.Tracker
    local tracker = {
        on_sess_added = function(id, name, parent_id, ctrl, providers)
            for bp_id, data in pairs(_breakpoints_data) do
                data.states = data.states or {}
                data.states[id] = false
                _refresh_breakpoint_sign(bp_id, data)
            end
        end,
        on_sess_removed = function(id, name)
            for bp_id, data in pairs(_breakpoints_data) do
                if data.states then
                    data.states[id] = nil
                    _refresh_breakpoint_sign(bp_id, data)
                end
            end
        end,
        on_breakpoint_event = function(sess_id, session_name, event)
            for _, state in ipairs(event) do
                local bp = _breakpoints_data[state.breakpoint_id]
                if bp then
                    bp.states = bp.states or {}
                    bp.states[sess_id] = state.verified
                    local data = _breakpoints_data[state.breakpoint_id]
                    if data then
                        _refresh_breakpoint_sign(state.breakpoint_id, data)
                    end
                end
            end
        end,
        on_exit = function(code) end
    }
    return tracker
end

---@param bp loopdebug.SourceBreakpoint
---@param verified boolean
local function _format_breakpoint(bp, verified)
    local symbol = verified and "●" or "○"
    if bp.logMessage and bp.logMessage ~= "" then
        symbol = "▶" -- logpoint
    end
    if bp.condition and bp.condition ~= "" then
        symbol = "◆" -- conditional
    end
    if bp.hitCondition and bp.hitCondition ~= "" then
        symbol = "▲" -- hit-condition
    end
    local file = bp.file
    local projdir = projinfo.get_proj_dir()
    if projdir then
        file = vim.fs.relpath(projdir, file) or file
    end
    local parts = { symbol }
    table.insert(parts, " ")
    table.insert(parts, file)
    table.insert(parts, ":")
    table.insert(parts, tostring(bp.line))
    -- 3. Optional qualifiers
    if bp.condition and bp.condition ~= "" then
        table.insert(parts, " | if " .. bp.condition)
    end
    if bp.hitCondition and bp.hitCondition ~= "" then
        table.insert(parts, " | hits=" .. bp.hitCondition)
    end
    if bp.logMessage and bp.logMessage ~= "" then
        table.insert(parts, " | log: " .. bp.logMessage:gsub("\n", " "))
    end
    return table.concat(parts, '')
end

function _select_breakpoint()
    local choices = {}
    for _, data in pairs(_breakpoints_data) do
        local verified = _get_breakpoint_state(data)
        local item = {
            label = _format_breakpoint(data.breakpoint, verified),
            data = data.breakpoint,
        }
        table.insert(choices, item)
    end
    selector.select("Breakpoints", choices, nil, function(bp)
        ---@cast bp loopdebug.SourceBreakpoint
        if bp and bp.file then
            uitools.smart_open_file(bp.file, bp.line, bp.column)
        end
    end)
end

local function _enable_breakpoint_sync_on_save()
    local group = vim.api.nvim_create_augroup(
        "LoopBreakpointSyncOnSave",
        { clear = true }
    )

    vim.api.nvim_create_autocmd("BufWritePre", {
        group = group,
        callback = function(ev)
            local bufnr = ev.buf
            if not vim.api.nvim_buf_is_valid(bufnr) then
                return
            end

            -- Skip non-file buffers
            if vim.bo[bufnr].buftype ~= "" then
                return
            end

            local file = vim.api.nvim_buf_get_name(bufnr)
            if file == "" then
                return
            end
            file = vim.fn.fnamemodify(file, ":p")
            -- Fetch up-to-date sign data
            local signs_by_id = signs.get_file_signs_by_id(file)

            -- Clear + resync
            dapbreakpoints.clear_file_breakpoints(file)
            -- Collect breakpoint signs only
            local breakpoints = {}
            for _, sign in pairs(signs_by_id) do
                if sign.group == "breakpoints" then
                    breakpoints[#breakpoints + 1] = sign
                end
            end
            -- Sort breakpoints by line number
            table.sort(breakpoints, function(a, b)
                return a.lnum < b.lnum
            end)
            -- Add breakpoints in order
            for _, sign in ipairs(breakpoints) do
                dapbreakpoints.add_breakpoint(file, sign.lnum)
            end
        end,
    })
end


---@param command nil|"toggle"|"logpoint"|"clear_file"|"clear_all"
function M.breakpoints_command(command)
    assert(_setup_done, _setup_err_msg)
    local proj_dir = projinfo.get_proj_dir()
    if not proj_dir then
        vim.notify('No active project')
        return
    end
    command = command and command:match("^%s*(.-)%s*$") or ""
    if command == "" or command == "toggle" then
        local file, line = uitools.get_current_file_and_line()
        if file and line then
            dapbreakpoints.toggle_breakpoint(file, line)
        end
    elseif command == "logpoint" then
        vim.ui.input({ prompt = "Enter log message: " }, function(message)
            if message and message ~= "" then
                local file, line = uitools.get_current_file_and_line()
                if file and line then
                    dapbreakpoints.set_logpoint(file, line, message)
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
                        dapbreakpoints.clear_file_breakpoints(full_path)
                    end
                end)
            end
        end
    elseif command == "clear_all" then
        uitools.confirm_action("Clear all dapbreakpoints", false, function(accepted)
            if accepted == true then
                dapbreakpoints.clear_all_breakpoints()
            end
        end)
    elseif command == "list" then
        _select_breakpoint()
    else
        vim.notify('Invalid breakpoints subcommand: ' .. tostring(command))
    end
end

--- Setup the breakpoint sign system and autocommands.
---@param _? table Optional setup options (currently unused)
function M.setup(_)
    assert(not _setup_done, "setup already done")
    _setup_done = true

    _enable_breakpoint_sync_on_save()

    require('loopdebug.breakpoints').add_tracker({
        on_added = _on_breakpoint_added,
        on_removed = _on_breakpoint_removed,
        on_all_removed = _on_all_breakpoints_removed
    })
end

return M

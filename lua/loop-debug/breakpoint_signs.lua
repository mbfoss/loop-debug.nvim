local config        = require('loop-debug.config')
local signsmgr      = require('loop-debug.tools.signsmgr')
local breakpoints   = require('loop-debug.breakpoints')
local selector      = require("loop.tools.selector")
local wsinfo        = require("loop.wsinfo")
local uitools       = require("loop.tools.uitools")

local M             = {}

local _init_done    = false
local _init_err_msg = "init() not called"

local _sign_group   = "breakpoints"

local _sign_names   = {
    active_breakpoint        = "active_breakpoint",
    inactive_breakpoint      = "inactive_breakpoint",
    logpoint                 = "logpoint",
    logpoint_inactive        = "logpoint_inactive",
    cond_breakpoint          = "cond_breakpoint",
    cond_breakpoint_inactive = "cond_breakpoint_inactive",
}


---@class loop.debug_ui.Breakpointata
---@field breakpoint loopdebug.SourceBreakpoint
---@field states table<number,boolean>|nil

---@type table<number,loop.debug_ui.Breakpointata>
local _breakpoints_data = {}

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
    local wsdir = wsinfo.get_ws_dir()
    if wsdir then
        file = vim.fs.relpath(wsdir, file) or file
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

---@param bp loopdebug.SourceBreakpoint
---@param verified boolean
---@return string
local function _get_breakpoint_sign(bp, verified)
    -- Determine the sign type based on breakpoint fields
    local sign
    if bp.logMessage then
        sign = verified and _sign_names.logpoint or _sign_names.logpoint_inactive
    elseif bp.condition or bp.hitCondition then
        sign = verified and _sign_names.cond_breakpoint or _sign_names.cond_breakpoint_inactive
    else
        sign = verified and _sign_names.active_breakpoint or _sign_names.inactive_breakpoint
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
    signsmgr.place_file_sign(id, data.breakpoint.file, data.breakpoint.line, _sign_group, sign)
end

---@param bp loopdebug.SourceBreakpoint
local function _on_breakpoint_added(bp)
    _breakpoints_data[bp.id] = {
        breakpoint = bp,
    }
    local sign = _get_breakpoint_sign(bp, true)
    signsmgr.place_file_sign(bp.id, bp.file, bp.line, _sign_group, sign)
end

---@param bp loopdebug.SourceBreakpoint
local function _on_breakpoint_removed(bp)
    _breakpoints_data[bp.id] = nil
    signsmgr.remove_file_sign(bp.id, _sign_group)
end

---@param removed loopdebug.SourceBreakpoint[]
local function _on_all_breakpoints_removed(removed)
    _breakpoints_data = {}
    local files = {}
    for _, bp in ipairs(removed) do
        files[bp.file] = true
    end
    for file, _ in pairs(files) do
        signsmgr.remove_file_signs(file, _sign_group)
    end
end

---@param task_name string -- task name
---@return loop.job.debugjob.Tracker
function _start(task_name)
    assert(_init_done, _init_err_msg)
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
            local signs_by_id = signsmgr.get_file_signs_by_id(file)

            -- Clear + resync
            breakpoints.clear_file_breakpoints(file)
            -- Collect breakpoint signs only
            local bpsigns = {}
            for _, sign in pairs(signs_by_id) do
                if sign.group == _sign_group then
                    bpsigns[#bpsigns + 1] = sign
                end
            end
            -- Sort breakpoints by line number
            table.sort(bpsigns, function(a, b)
                return a.lnum < b.lnum
            end)
            -- Add breakpoints in order
            for _, sign in ipairs(bpsigns) do
                breakpoints.add_breakpoint(file, sign.lnum)
            end
        end,
    })
end

function M.init()
    if _init_done then return end
    _init_done = true
    assert(config.current)

    local highlight = "LoopDebugBreakpoint"

    vim.api.nvim_set_hl(0, highlight, { link = "Debug" })

    local symbols = config.current.symbols

    signsmgr.define_sign_group(_sign_group, config.current.sign_priority.breakpoints or 12)
    for name, full_name in pairs(_sign_names) do
        signsmgr.define_sign(_sign_group, full_name, symbols[name], highlight)
    end

    _enable_breakpoint_sync_on_save()

    breakpoints.add_tracker({
        on_added = _on_breakpoint_added,
        on_removed = _on_breakpoint_removed,
        on_all_removed = _on_all_breakpoints_removed
    })
end

return M

local M               = {}

local persistence     = require('loop-debug.persistence')
local CompBuffer      = require('loop.buf.CompBuffer')
local VariablesComp   = require('loop-debug.comp.Variables')
local StackTraceComp  = require('loop-debug.comp.StackTrace')

local _init_done      = false

local _ui_auto_group  = vim.api.nvim_create_augroup("LoopDebugPluginUI", { clear = true })

---@type loop.comp.CompBuffer?
local _vars_compbuffer

---@type loop.comp.CompBuffer?
local _stack_compbuffer

---@type loopdebug.comp.Variables?
local _variables_comp

---@type loopdebug.comp.StackTrace?
local _stack_comp

-- Configuration and State Storage
local _default_layout = {
    width_ratio = 0.20,
    top_ratio = 0.5,
}

---@param winid number
local function _save_layout(winid)
    local total_cols = vim.o.columns
    local total_lines = vim.o.lines
    local w = vim.api.nvim_win_get_width(winid)
    local h = vim.api.nvim_win_get_height(winid)
    local is_width_valid = w < math.floor(total_cols * 0.6)
    local is_height_valid = h < math.floor(total_lines * 0.9)

    local layout = {}
    if is_width_valid then layout.width_ratio = (w / vim.o.columns) end
    if is_height_valid then layout.top_ratio = (h / vim.o.lines) end
    persistence.set_config("layout", layout)
end

local function _destroy_components()
    if _vars_compbuffer then
        _vars_compbuffer:destroy()
        _vars_compbuffer = nil
    end

    if _stack_compbuffer then
        _stack_compbuffer:destroy()
        _stack_compbuffer = nil
    end

    if _variables_comp then
        _variables_comp:dispose()
        _variables_comp = nil
    end
    if _stack_comp then
        _stack_comp:dispose()
        _stack_comp = nil
    end
end

---@param vars_winid number
---@param stack_winid number
local function _create_components(vars_winid, stack_winid)
    _destroy_components()
    assert(not _vars_compbuffer and not _stack_compbuffer)
    assert(not _variables_comp and not _stack_comp)

    _vars_compbuffer = CompBuffer:new("debugvars", "Variables")
    _stack_compbuffer = CompBuffer:new("callstack", "Call Stack")

    vim.wo[vars_winid].winfixbuf = false
    vim.api.nvim_win_set_buf(vars_winid, (_vars_compbuffer:get_or_create_buf()))
    vim.wo[vars_winid].winfixbuf = true

    vim.wo[stack_winid].winfixbuf = false
    vim.api.nvim_win_set_buf(stack_winid, (_stack_compbuffer:get_or_create_buf()))
    vim.wo[stack_winid].winfixbuf = true

    _variables_comp = VariablesComp:new("Variables")
    _stacktrace_comp = StackTraceComp:new("Call Stack")

    _variables_comp:link_to_buffer(_vars_compbuffer:make_controller())
    _stacktrace_comp:link_to_buffer(_stack_compbuffer:make_controller())
end


-- Unique keys for window variables
local KEY_MARKER = "loopdebugplugin_debugpanel"
local KEY_TYPE   = "loopdebugplugin_panel_type" -- "TOP" or "BOTTOM"

local function is_managed_window(win_id)
    if not vim.api.nvim_win_is_valid(win_id) then return false end
    local ok, is_managed = pcall(function() return vim.w[win_id][KEY_MARKER] end)
    return ok and is_managed == true
end

local function get_managed_windows()
    local found = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if is_managed_window(win) then
            table.insert(found, win)
        end
    end
    return found
end

function M.show()
    local managed = get_managed_windows()
    if #managed > 0 then
        return
    end

    assert(_init_done)

    if not persistence.is_ws_open() then
        vim.notify("loopdebug: No active worksapce", vim.log.levels.WARN)
        return
    end

    local layout = vim.tbl_deep_extend("force", _default_layout, persistence.get_config("layout") or {})

    local original_win = vim.api.nvim_get_current_win()

    -- 1. Create the Vertical container
    vim.cmd("topleft vsplit")
    local top_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(top_win, math.floor(layout.width_ratio * vim.o.columns))

    -- 2. Create the Horizontal split
    vim.cmd("below split")
    local bottom_win = vim.api.nvim_get_current_win()

    -- 3. Restore Height with validation
    local height = math.floor(vim.o.lines * layout.top_ratio)
    vim.api.nvim_win_set_height(top_win, height)

    local config_map = {
        [top_win] = "TOP",
        [bottom_win] = "BOTTOM"
    }

    for win, type_name in pairs(config_map) do
        -- Visuals
        vim.wo[win].wrap = false
        vim.wo[win].spell = false
        -- WinVars
        vim.w[win][KEY_MARKER] = true
        vim.w[win][KEY_TYPE] = type_name
        -- Constraints
        vim.wo[win].winfixbuf = true
        vim.wo[win].winfixwidth = true
        vim.wo[win].winfixheight = true
    end

    if vim.api.nvim_win_is_valid(original_win) then
        vim.api.nvim_set_current_win(original_win)
    end

    vim.api.nvim_clear_autocmds({ group = _ui_auto_group })
    vim.api.nvim_create_autocmd("WinResized", {
        group = _ui_auto_group,
        callback = function()
            -- v.event.windows contains IDs of all windows that changed size
            local targets = vim.v.event.windows
            for _, winid in ipairs(targets or {}) do
                if is_managed_window(winid) then
                    local type = vim.w[winid].loopdebugplugin_panel_type
                    if type == "TOP" then
                        _save_layout(winid)
                    end
                end
            end
        end,
    })

    _create_components(top_win, bottom_win)
end

function M.hide()
    local managed = get_managed_windows()
    vim.api.nvim_clear_autocmds({ group = _ui_auto_group })
    for _, win in ipairs(managed) do
        vim.api.nvim_win_close(win, true)
    end
    _destroy_components()
end

function M.toggle()
    local managed = get_managed_windows()
    if #managed > 0 then
        M.hide()
        return
    end
    M.show()
end

function M.init()
    if _init_done then return end
    _init_done = true
    persistence.add_tracker({
        on_ws_unload = function()
            M.hide()
        end,
    })
end

return M

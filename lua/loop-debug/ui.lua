local M                   = {}

local manager             = require('loop-debug.manager')
local CompBuffer          = require('loop.buf.CompBuffer')
local VariablesComp       = require('loop-debug.comp.Variables')
local StackTraceComp      = require('loop-debug.comp.StackTrace')

local _ui_auto_group      = vim.api.nvim_create_augroup("LoopDebugPluginUI", { clear = true })

local _manager_tracker_id = nil

-- Configuration and State Storage
_layout_config            = {
    width = math.floor(vim.o.columns / 4),
    top_height = nil, -- If nil, split is equal (50/50)
}

-- Unique keys for window variables
local KEY_MARKER          = "loopdebugplugin_debugpanel"
local KEY_TYPE            = "loopdebugplugin_panel_type" -- "TOP" or "BOTTOM"

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

function M.get_layout_config()
    return _layout_config
end

function M.set_layout_config(cfg)
    _layout_config = cfg or {}
    _layout_config.width = _layout_config.width or math.floor(vim.o.columns / 4)
end

function M.toggle()
    local managed = get_managed_windows()

    if #managed > 0 then
        vim.api.nvim_clear_autocmds({ group = _ui_auto_group })
        if _manager_tracker_id then
            manager.remove_tracker(_manager_tracker_id)
            _manager_tracker_id = nil
        end
        for _, win in ipairs(managed) do
            vim.api.nvim_win_close(win, true)
        end
        return
    end

    local original_win = vim.api.nvim_get_current_win()

    -- 1. Create the Vertical container
    vim.cmd("topleft vsplit")
    local top_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(top_win, _layout_config.width)

    -- 2. Create the Horizontal split
    vim.cmd("below split")
    local bottom_win = vim.api.nvim_get_current_win()

    -- 3. Restore Height with validation
    if _layout_config.top_height then
        -- Ensure we don't try to set a height taller than the screen - 2 (for status/cmd line)
        local safe_height = math.min(_layout_config.top_height, vim.o.lines - 3)
        if safe_height then
            vim.api.nvim_win_set_height(top_win, safe_height)
        end
    end

    local config_map = {
        [top_win] = "TOP",
        [bottom_win] = "BOTTOM"
    }

    local vars_buffer = CompBuffer:new("debugvars", "Variables")
    local stack_buffer = CompBuffer:new("callstack", "Call Stack")

    local vars_buf = vars_buffer:get_or_create_buf()
    local stack_buf = stack_buffer:get_or_create_buf()
    
    vim.api.nvim_win_set_buf(top_win, vars_buf)
    vim.api.nvim_win_set_buf(bottom_win, stack_buf)

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
                        local total_cols = vim.o.columns
                        local total_lines = vim.o.lines
                        local w = vim.api.nvim_win_get_width(winid)
                        local h = vim.api.nvim_win_get_height(winid)
                        local is_width_valid = w < math.floor(total_cols * 0.6)
                        local is_height_valid = h < math.floor(total_lines * 0.9)
                        if is_width_valid then _layout_config.width = w end
                        if is_height_valid then _layout_config.top_height = h end
                    end
                end
            end
        end,
    })

    local variables_comp = VariablesComp:new("Variables")
    local stacktrace_comp = StackTraceComp:new("Call Stack")

    if _manager_tracker_id then
        manager.remove_tracker(_manager_tracker_id)
        _manager_tracker_id = nil
    end
    _manager_tracker_id = manager.add_tracker({
        on_job_update = function(update)
            variables_comp:update_data(update.session_id, update.sess_name, update.data_providers, update.cur_frame)
            stacktrace_comp:update_data(update.data_providers, update.cur_thread_id, update.cur_thread_name)
        end
    })

    variables_comp:link_to_buffer(vars_buffer:make_controller())
    stacktrace_comp:link_to_buffer(stack_buffer:make_controller())
end

return M

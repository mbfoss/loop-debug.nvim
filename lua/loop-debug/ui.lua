local M          = {}

-- Configuration and State Storage
M.layout_config  = {
    width = math.floor(vim.o.columns / 4),
    top_height = nil, -- If nil, split is equal (50/50)
}

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

function M.toggle()
    local managed = get_managed_windows()

    if #managed > 0 then
        -- Before closing, save the current height of the TOP window
        for _, win in ipairs(managed) do
            if vim.api.nvim_win_is_valid(win) and vim.w[win][KEY_TYPE] == "TOP" then
                M.layout_config.top_height = vim.api.nvim_win_get_height(win)
                M.layout_config.width = vim.api.nvim_win_get_width(win)
            end
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
    vim.api.nvim_win_set_width(top_win, M.layout_config.width)

    -- 2. Create the Horizontal split
    vim.cmd("split")
    local bottom_win = vim.api.nvim_get_current_win()

    -- 3. Restore Height with validation
    if M.layout_config.top_height then
        -- Ensure we don't try to set a height taller than the screen - 2 (for status/cmd line)
        local safe_height = math.min(M.layout_config.top_height, vim.o.lines - 3)
        if safe_height then
            vim.api.nvim_win_set_height(top_win, safe_height)
        end
    end

    local config_map = {
        [top_win] = "TOP",
        [bottom_win] = "BOTTOM"
    }

    for win, type_name in pairs(config_map) do
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_win_set_buf(win, buf)

        -- WinVars
        vim.w[win][KEY_MARKER] = true
        vim.w[win][KEY_TYPE] = type_name

        -- Constraints
        vim.wo[win].winfixbuf = true
        vim.wo[win].winfixwidth = true
        -- Enable winfixheight so the horizontal split doesn't jump
        -- when other windows are opened/closed
        --vim.wo[win].winfixheight = true
    end

    if vim.api.nvim_win_is_valid(original_win) then
        vim.api.nvim_set_current_win(original_win)
    end

    _assign_components()
end

return M

--[[

    local variables_comp = VariablesComp:new(task_name)
    local stacktrace_comp = StackTraceComp:new(task_name)


    local vars_page = page_manager.add_page_group(_page_groups.variables, "Variables").add_page(_page_groups.variables,
        "Variables")
    local stack_page = page_manager.add_page_group(_page_groups.stack, "Call Stack").add_page(_page_groups.stack,
        "Call Stack")

    variables_comp:link_to_page(vars_page)
    stacktrace_comp:link_to_page(stack_page)
    jobdata.variables_comp:update_data(sess_id, sess_name, data_providers, frame)

    _greyout_thread_context_pages(jobdata, sess_id)

    ---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
local function _greyout_thread_context_pages(jobdata, sess_id)
    jobdata.variables_comp:greyout_content(sess_id)
    jobdata.stacktrace_comp:greyout_content()
end


    local variables_comp = VariablesComp:new(task_name)
    local stacktrace_comp = StackTraceComp:new(task_name)

    local vars_page = page_manager.add_page_group(_page_groups.variables, "Variables").add_page(_page_groups.variables,
        "Variables")
    local stack_page = page_manager.add_page_group(_page_groups.stack, "Call Stack").add_page(_page_groups.stack,
        "Call Stack")

    variables_comp:link_to_page(vars_page)
    stacktrace_comp:link_to_page(stack_page)

        variables_comp = variables_comp,
        stacktrace_comp = stacktrace_comp,

    local thread_name = sess_data.thread_names[thread_id]
    jobdata.stacktrace_comp:set_content(sess_data.data_providers, thread_id, thread_name)

    stacktrace_comp:add_frame_tracker(function(frame)
        _switch_to_frame(jobdata, frame)
    end)


function _open_split_view(group1, group2)
    if not group1 then return end
    local loop_project = require('loop.project')
    local win = vim.api.nvim_get_current_win()
    do
        vim.cmd("leftabove vsplit")
        vim.cmd("vertical resize " .. math.floor(vim.o.columns / 3))
        loop_project.open_page(group1)
    end
    if group2 then
        vim.cmd("below split")
        loop_project.open_page(group2)
    end
    vim.api.nvim_set_current_win(win)
end
    vim.schedule(function()
        _open_split_view("Variables", "Call Stack")
    end)
]]

local config          = require("loop-debug.config")
local signs           = require('loop-debug.signs')
local debugmode       = require('loop-debug.debugmode')
local filetools       = require('loop.tools.file')
local ItemListComp    = require('loop.comp.ItemList')
local OutputLinesComp = require('loop.comp.OutputLines')
local VariablesComp   = require('loop-debug.comp.Variables')
local StackTraceComp  = require('loop-debug.comp.StackTrace')
local uitools         = require('loop.tools.uitools')
local notifications   = require('loop.notifications')
local selector        = require('loop.tools.selector')
local breakpoints_ui  = require('loop-debug.bpts_ui')

local M            = {}

---@class loop.debugui.SessionData
---@field sess_name string|nil
---@field state string|nil
---@field controller loop.job.DebugJob.SessionController
---@field data_providers loopdebug.session.DataProviders
---@field paused_threads table<number,boolean>
---@field thread_names table<number,string>
---@field cur_thread_id number|nil
---@field top_frame loopdebug.proto.StackFrame|nil
---@field adapter_output_comp loop.comp.OutputLines|nil
---@field debuggee_output_comp loop.comp.OutputLines|nil

---@class loop.debugui.DebugJobData
---@field jobname string
---@field job_ended boolean|nil
---@field job_success boolean|nil
---@field page_manager loop.PageManager
---@field current_session_id number|nil
---@field session_data table<number,loop.debugui.SessionData>
---@field task_list_comp loop.comp.ItemList
---@field variables_comp loopdebug.comp.Variables
---@field stacktrace_comp loopdebug.comp.StackTrace
---@field command fun(data:loop.debugui.DebugJobData,cmd:loop.job.DebugJob.Command):boolean,(string|nil)

---@type loop.debugui.DebugJobData|nil
local _current_job_data

local _page_groups = {
    task = "task",
    variables = "vars",
    watch = "watch",
    stack = "stack",
    output = "output",
    debugger = "debugger",
}

---@param frame loopdebug.proto.StackFrame
function _jump_to_frame(frame)
    if not (frame and frame.source and frame.source.path) then return end
    if not filetools.file_exists(frame.source.path) then return end

    -- Open file and move cursor
    local _, bufnr = uitools.smart_open_file(frame.source.path, frame.line, frame.column)

    -- Highlight the current frame line (full line, buffer-local)
    debugmode.highlight_line(frame.line, "Underlined", bufnr)

    -- Place sign for current frame
    signs.place_file_sign(1, frame.source.path, frame.line, "currentframe", "currentframe")
end

---@param jobdata loop.debugui.DebugJobData
---@param frame loopdebug.proto.StackFrame
local function _switch_to_frame(jobdata, frame)
    local sess_id = jobdata.current_session_id
    if not sess_id then return end

    local session_data = jobdata.session_data[sess_id]
    if not session_data then return end
    local thread_id = session_data.cur_thread_id
    if not thread_id then return end

    ---@type loopdebug.session.DataProviders
    local data_providers = session_data.data_providers
    local sess_name = session_data.sess_name or tostring(sess_id)

    _jump_to_frame(frame)

    jobdata.variables_comp:update_data(sess_id, sess_name, data_providers, frame)
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param thread_id number
local function _switch_to_thread(jobdata, sess_id, thread_id)
    if not sess_id or not thread_id then return end

    local sess_data = jobdata.session_data[sess_id]
    if not sess_data then return end

    sess_data.cur_thread_id = thread_id
    sess_data.top_frame = nil

    local data_providers = sess_data.data_providers

    local topframe
    -- handle current frame
    data_providers.stack_provider({ threadId = thread_id, levels = 1 }, function(err, data)
        ---@type loopdebug.proto.StackFrame
        topframe = data and data.stackFrames[1] or nil
        if topframe and topframe.source and topframe.source.path then
            --- check if it did not change meanwhile
            if sess_id == jobdata.current_session_id and thread_id == sess_data.cur_thread_id then
                sess_data.top_frame = topframe
                _switch_to_frame(jobdata, topframe)
            end
        end
    end)

    local thread_name = sess_data.thread_names[thread_id]
    jobdata.stacktrace_comp:set_content(sess_data.data_providers, thread_id, thread_name)
end

---@param jobdata loop.debugui.DebugJobData
local function _refresh_task_page(jobdata)
    if jobdata.job_ended then
        --@type loop.pages.ItemListPage.Item
        local item = {
            id = 0,
            ---@class loop.debugui.TaskPageItemData
            data = {
                label = jobdata.job_success and "Task ended" or "Task failed",
                nb_paused_threads = 0,
            }
        }
        local symbols = config.current.symbols
        jobdata.task_list_comp:set_items({ item })
        jobdata.task_list_comp:set_ui_flags(jobdata.job_success and '' or symbols.failure)
        return
    end

    local session_ids = vim.tbl_keys(jobdata.session_data)
    vim.fn.sort(session_ids)

    ---@type loop.comp.ItemList.Item[]
    local list_items = {}
    local uiflags = ''

    local symbols = config.current.symbols

    for _, sess_id in ipairs(session_ids) do
        local sdata = jobdata.session_data[sess_id]
        local state = sdata.state or "starting"
        local nb_paused_threads = vim.tbl_count(sdata.paused_threads)
        if nb_paused_threads and nb_paused_threads > 0 then
            flag = symbols.paused
        else
            flag = symbols.running
        end
        --@type loop.pages.ItemListPage.Item
        local item = {
            id = sess_id,
            ---@class loop.debugui.TaskPageItemData
            data = {
                label = tostring(sess_id) .. ' ' .. tostring(sdata.sess_name) .. ' - ' .. state,
                nb_paused_threads = nb_paused_threads,
            }
        }
        uiflags = uiflags .. flag
        table.insert(list_items, item)
    end

    jobdata.task_list_comp:set_items(list_items)
    jobdata.task_list_comp:set_current_item_by_id(jobdata.current_session_id)
    jobdata.task_list_comp:set_ui_flags(uiflags)
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param thread_pause_evt? loopdebug.session.notify.ThreadsEventScope|nil
local function _switch_to_session(jobdata, sess_id, thread_pause_evt)
    local sess_data = jobdata.session_data[sess_id]
    if not sess_data then return end

    jobdata.current_session_id = sess_id

    local thread_id = thread_pause_evt and thread_pause_evt.thread_id or sess_data.cur_thread_id
    if not thread_id then return end

    if thread_pause_evt then
        if not thread_pause_evt.all_thread then
            sess_data.paused_threads[thread_pause_evt.thread_id] = true
            _refresh_task_page(jobdata)
        end
        sess_data.data_providers.threads_provider(function(err, resp)
            if err or not resp or not resp.threads then
                notifications.notify("Failed to load thread list - " .. (err or ""))
            elseif sess_id == jobdata.current_session_id then
                if thread_pause_evt.all_thread then
                    sess_data.paused_threads = {}
                    for _, thread in pairs(resp.threads) do
                        sess_data.paused_threads[thread.id] = true
                    end
                    _refresh_task_page(jobdata)
                end
                sess_data.thread_names = {}
                for _, thread in pairs(resp.threads) do
                    sess_data.thread_names[thread_id] = thread.name
                end
                _switch_to_thread(jobdata, sess_id, thread_id)
            end
        end)
    else
        _refresh_task_page(jobdata)
        _switch_to_thread(jobdata, sess_id, thread_id)
    end
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param sess_name string
---@param parent_id number|nil
---@param controller loop.job.DebugJob.SessionController
---@param data_providers loopdebug.session.DataProviders
local function _on_session_added(jobdata, sess_id, sess_name, parent_id, controller, data_providers)
    assert(not jobdata.session_data[sess_id])
    ---@type loop.debugui.SessionData
    local session_data = {
        sess_name = sess_name,
        controller = controller,
        data_providers = data_providers,
        paused_threads = {},
        thread_names = {}
    }
    jobdata.session_data[sess_id] = session_data
    _refresh_task_page(jobdata)
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param sess_name string
local function _on_session_removed(jobdata, sess_id, sess_name)
    jobdata.session_data[sess_id] = nil
    _refresh_task_page(jobdata)
end

---@param jobdata loop.debugui.DebugJobData
---@return boolean, string|nil
local function _process_continue_all_command(jobdata)
    for _, session_data in pairs(jobdata.session_data) do
        if session_data.cur_thread_id then
            session_data.controller.continue(session_data.cur_thread_id, true)
        end
    end
    return true
end

---@param jobdata loop.debugui.DebugJobData
---@return boolean, string|nil
local function _process_terminate_all_command(jobdata)
    for _, session_data in pairs(jobdata.session_data) do
        if session_data.cur_thread_id then
            session_data.controller.continue(session_data.cur_thread_id, true)
        end
    end
    return true
end

---@param jobdata loop.debugui.DebugJobData
---@return boolean, string|nil
local function _process_select_session_command(jobdata)
    local choices = {}
    for sess_id, sess_data in pairs(jobdata.session_data) do
        ---@type loop.SelectorItem
        local item = { label = sess_data.sess_name, data = sess_id }
        table.insert(choices, item)
    end
    selector.select("Select debug session", choices, nil, function(sess_id)
        if sess_id then
            _switch_to_session(jobdata, sess_id)
        end
    end)
    return true
end

---@param jobdata loop.debugui.DebugJobData
---@return boolean, string|nil
local function _process_select_thread_command(jobdata)
    local sess_id = jobdata.current_session_id

    ---@type loop.debugui.SessionData|nil
    local sess_data = sess_id and jobdata.session_data[sess_id] or nil
    if not sess_id or not sess_data then
        return false, "No active debug session"
    end

    sess_data.data_providers.threads_provider(function(err, data)
        if err or not data or not data.threads then
            notifications.notify("Failed to load thread list - " .. (err or ""))
        elseif sess_id == jobdata.current_session_id then
            local choices = {}
            for _, thread in pairs(data.threads) do
                ---@type loop.SelectorItem
                local item = { label = tostring(thread.id) .. ": " .. tostring(thread.name), data = thread.id }
                table.insert(choices, item)
            end
            selector.select("Select thread", choices, nil, function(thread_id)
                -- ensure session did not change meanwhile
                if thread_id and sess_id == jobdata.current_session_id then
                    _switch_to_thread(jobdata, sess_id, thread_id)
                end
            end)
        end
    end)
    return true
end

---@param jobdata loop.debugui.DebugJobData
---@return boolean, string|nil
local function _process_select_frame_command(jobdata)
    local sess_id = jobdata.current_session_id

    ---@type loop.debugui.SessionData|nil
    local sess_data = sess_id and jobdata.session_data[sess_id] or nil
    if not sess_id or not sess_data then
        return false, "No active debug session"
    end

    local thread_id = sess_data.cur_thread_id
    if not thread_id then
        return false, "No selected thread"
    end

    sess_data.data_providers.stack_provider({ threadId = sess_data.cur_thread_id }, function(err, data)
        if err or not data then
            notifications.notify("Failed to load call stack - " .. (err or ""))
        elseif sess_id == jobdata.current_session_id and thread_id == sess_data.cur_thread_id then
            local choices = {}
            for _, frame in pairs(data.stackFrames) do
                ---@type loop.SelectorItem
                local item = { label = tostring(frame.name), data = frame }
                table.insert(choices, item)
            end
            selector.select("Select frame", choices, nil, function(frame)
                -- ensure if's still the same session and thread
                if frame and sess_id == jobdata.current_session_id
                    and thread_id == sess_data.cur_thread_id then
                    _switch_to_frame(jobdata, frame)
                end
            end)
        end
    end)

    return true
end

---@param jobdata loop.debugui.DebugJobData
---@param command loop.job.DebugJob.Command
---@return boolean
---@return string|nil
local function _on_debug_command(jobdata, command)
    if command == 'continue_all' then
        return _process_continue_all_command(jobdata)
    end
    if command == 'terminate_all' then
        return _process_terminate_all_command(jobdata)
    end
    if command == "session" then
        return _process_select_session_command(jobdata)
    end
    if command == "thread" then
        return _process_select_thread_command(jobdata)
    end
    if command == "frame" then
        return _process_select_frame_command(jobdata)
    end

    local sess_id = jobdata.current_session_id
    ---@type loop.debugui.SessionData|nil
    local sess_data = sess_id and jobdata.session_data[sess_id] or nil
    if not sess_id or not sess_data then
        return false, "No active debug session"
    end

    if command == 'continue' then
        sess_data.controller.continue(sess_data.cur_thread_id, true)
    elseif command == "step_in" then
        sess_data.controller.step_in(sess_data.cur_thread_id)
    elseif command == "step_out" then
        sess_data.controller.step_out(sess_data.cur_thread_id)
    elseif command == "step_over" then
        sess_data.controller.step_over(sess_data.cur_thread_id)
    elseif command == "step_back" then
        sess_data.controller.step_back(sess_data.cur_thread_id)
    else
        return false, "Invalid debug command: " .. tostring(command)
    end

    return true
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
local function _greyout_thread_context_pages(jobdata, sess_id)
    jobdata.variables_comp:greyout_content(sess_id)
    jobdata.stacktrace_comp:greyout_content()
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param sess_name string
---@param data loopdebug.session.notify.StateData
local function _on_session_state_update(jobdata, sess_id, sess_name, data)
    local session_data = jobdata.session_data[sess_id]
    if not session_data then return end
    session_data.state = data.state
    if sess_id == jobdata.current_session_id and data.state == "ended" then
        signs.remove_signs("currentframe")
        _greyout_thread_context_pages(jobdata, sess_id)
    end
    _refresh_task_page(jobdata)
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param sess_name string
---@param category string
---@param output string
local function _on_session_output(jobdata, sess_id, sess_name, category, output)
    local sess_data = jobdata.session_data[sess_id]
    assert(sess_data, "missing session data")

    local level = category == "stderr" and "error" or nil

    local is_debuggee = (category == "stdout" or category == "stderr")
    local output_comp
    if is_debuggee then
        output_comp = sess_data.debuggee_output_comp
        if not output_comp then
            local page_group = jobdata.page_manager.add_page_group(_page_groups.output, "Debug Output")
            local page_ctrl = page_group.add_page(tostring(sess_id), sess_name)
            output_comp = OutputLinesComp:new()
            output_comp:link_to_page(page_ctrl)
            sess_data.debuggee_output_comp = output_comp
        end
    else
        output_comp = sess_data.adapter_output_comp
        if not output_comp then
            local page_group = jobdata.page_manager.add_page_group(_page_groups.debugger, "Debugger")
            local page_ctrl = page_group.add_page(tostring(sess_id), sess_name)
            output_comp = OutputLinesComp:new()
            output_comp:link_to_page(page_ctrl)
            sess_data.adapter_output_comp = output_comp
        end
    end

    for line in output:gmatch("([^\n]*)\n?") do
        if line ~= "" then
            output_comp:add_line(line, nil)
        end
    end
end

---@param jobdata loop.debugui.DebugJobData
---@param name string
---@param args loopdebug.proto.RunInTerminalRequestArguments
---@param cb fun(pid: number|nil, err: string|nil)
local function _on_session_new_term_req(jobdata, name, args, cb)
    ---@type loop.tools.TermProc.StartArgs
    local start_args = {
        name = name,
        command = args.args,
        env = args.env,
        cwd = args.cwd,
        on_exit_handler = function(code) end,
    }

    ---@diagnostic disable-next-line: undefined-field
    local page_id = "term." .. name .. vim.loop.hrtime()
    local page_group = jobdata.page_manager.get_page_group(_page_groups.output)
    if not page_group then
        page_group = jobdata.page_manager.add_page_group(_page_groups.output, "Debug Output")
    end
    local proc, proc_err = page_group.add_term_page(page_id, start_args)
    if proc then
        cb(proc:get_pid(), nil)
    else
        cb(nil, proc_err or "term err")
        notifications.notify("failed to started debugged process - " .. proc_err)
    end
end

---@param item loop.comp.ItemList.Item
local function _debug_session_item_formatter(item)
    local str = item.data.label
    if item.data.nb_paused_threads and item.data.nb_paused_threads > 0 then
        local s = item.data.nb_paused_threads > 1 and "s" or ""
        str = str .. (" ( %d paused thread%s)"):format(item.data.nb_paused_threads, s)
    end
    return str
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param sess_name string
---@param event_data loopdebug.session.notify.ThreadsEventScope
local function _on_session_thread_pause(jobdata, sess_id, sess_name, event_data)
    local session_data = jobdata.session_data[sess_id]
    if not session_data then
        notifications.notify("Unexpected session pause event")
        return
    end
    _switch_to_session(jobdata, sess_id, event_data)
end

---@param jobdata loop.debugui.DebugJobData
---@param sess_id number
---@param sess_name string
---@param event_data loopdebug.session.notify.ThreadsEventScope
local function _on_session_thread_continue(jobdata, sess_id, sess_name, event_data)
    local session_data = jobdata.session_data[sess_id]
    if not session_data then
        notifications.notify("Unexpected session pause event")
        return
    end

    signs.remove_signs("currentframe")
    _greyout_thread_context_pages(jobdata, sess_id)

    if event_data.all_thread then
        session_data.paused_threads = {}
    else
        session_data.paused_threads[event_data.thread_id] = nil
    end
    _refresh_task_page(jobdata)
end

---@param task_name string -- task name
---@param page_manager loop.PageManager
---@return loop.job.debugjob.Tracker
function M.track_new_debugjob(task_name, page_manager)
    assert(type(task_name) == "string")

    local tasklist_comp = ItemListComp:new({
        formatter = _debug_session_item_formatter,
        show_current_prefix = true,
    })

    local variables_comp = VariablesComp:new(task_name)
    local stacktrace_comp = StackTraceComp:new(task_name)

    local tasks_page = page_manager.add_page_group(_page_groups.task, "Debug").add_page("task", "Tasks", true)
    local vars_page = page_manager.add_page_group(_page_groups.variables, "Variables").add_page(_page_groups.variables,
        "Variables")
    local stack_page = page_manager.add_page_group(_page_groups.stack, "Call Stack").add_page(_page_groups.stack,
        "Call Stack")

    tasklist_comp:link_to_page(tasks_page)
    variables_comp:link_to_page(vars_page)
    stacktrace_comp:link_to_page(stack_page)

    ---@type loop.debugui.DebugJobData
    local jobdata = {
        jobname = task_name,
        page_manager = page_manager,
        session_data = {},
        task_list_comp = tasklist_comp,
        variables_comp = variables_comp,
        stacktrace_comp = stacktrace_comp,
        command = function(jobdata, cmd)
            return _on_debug_command(jobdata, cmd)
        end
    }

    _current_job_data = jobdata
    debugmode.command_function = function(cmd)
        jobdata:command(cmd)
    end

    tasklist_comp:add_tracker({
        on_selection = function(item)
            if item then
                _switch_to_session(jobdata, item.id)
            end
        end
    })

    stacktrace_comp:add_frame_tracker(function(frame)
        _switch_to_frame(jobdata, frame)
    end)

    ---@type loop.job.debugjob.Tracker
    local tracker = {
        on_sess_added = function(id, name, parent_id, controller, data_providers)
            _on_session_added(jobdata, id, name, parent_id, controller, data_providers)
        end,
        on_sess_removed = function(id, name)
            _on_session_removed(jobdata, id, name)
        end,
        on_sess_state = function(sess_id, name, data)
            _on_session_state_update(jobdata, sess_id, name, data)
        end,
        on_output = function(sess_id, sess_name, category, output)
            _on_session_output(jobdata, sess_id, sess_name, category, output)
        end,

        on_new_term = function(name, args, cb)
            _on_session_new_term_req(jobdata, name, args, cb)
        end,

        on_thread_pause = function(sess_id, sess_name, data)
            _on_session_thread_pause(jobdata, sess_id, sess_name, data)
        end,
        on_thread_continue = function(sess_id, sess_name, data)
            _on_session_thread_continue(jobdata, sess_id, sess_name, data)
        end,

        on_exit = function(code)
            jobdata.job_ended = true
            jobdata.job_success = (code == 0)
            _refresh_task_page(jobdata)
            _current_job_data = nil
            debugmode.command_function = nil
            debugmode.disable_debug_mode()
        end
    }
    return tracker
end

function _toggle_debug_mode()
    if debugmode.is_active() then
        debugmode.disable_debug_mode()
        return
    end
    local job = _current_job_data
    if not job then
        notifications.notify("No active debug task", vim.log.levels.WARN)
        return
    end
    ---@type loop.debugui.SessionData
    local session_data = job.session_data[job.current_session_id]
    if not session_data then
        notifications.notify("No active debug session", vim.log.levels.WARN)
        return
    end
    debugmode.enable_debug_mode()
    _switch_to_frame(job, session_data.top_frame)
end

---@param command loop.job.DebugJob.Command|nil
---@param arg1 string|nil
function M.debug_command(command, arg1)
    if command == "breakpoint" then
        breakpoints_ui.breakpoints_command(arg1)
        return
    end
    local job = _current_job_data
    if not job then
        notifications.notify("No active debug task", vim.log.levels.WARN)
        return
    end
    if not command then
        notifications.notify("Debug command missing", vim.log.levels.WARN)
        return
    end
    if command == "debug_mode" then
        _toggle_debug_mode()
        return
    end
    local ok, err = job.command(job, command)
    if not ok then
        notifications.notify(err or "Debug command failed", vim.log.levels.WARN)
    end
end

return M

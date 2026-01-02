local SessionList        = require('loop-debug.comp.SessionList')
local breakpoints        = require('loop-debug.breakpoints')
local breakpointsmonitor = require('loop-debug.breakpointsmonitor')
local daptools           = require('loop-debug.dap.daptools')
local debugevents        = require('loop-debug.debugevents')
local notifications      = require('loop.notifications')
local selector           = require('loop.tools.selector')
local floatwin           = require('loop.tools.floatwin')

local M                  = {}

-- =============================================================================
-- Type Definitions
-- =============================================================================

---@class loopdebug.mgr.Context
---@field session_ctx number The global session context counter
---@field pause_ctx number   The pause state context counter for the current session
---@field thread_ctx number  The thread selection context counter
---@field frame_ctx number   The stack frame selection context counter

---@class loopdebug.mgr.InSessionCtx
---@field pause_ctx number
---@field thread_ctx number
---@field frame_ctx number

---@class loopdebug.mgr.SessionData
---@field sess_name string|nil
---@field state "starting"|"running"|"stopped"|"ended"|nil
---@field controller loop.job.DebugJob.SessionController
---@field data_providers loopdebug.session.DataProviders
---@field context_keys loopdebug.mgr.InSessionCtx
---@field paused_threads table<number, boolean> Set of paused thread IDs
---@field thread_names table<number, string> Map of thread ID to name
---@field cur_thread_id number|nil Currently selected thread
---@field cur_frame loopdebug.proto.StackFrame|nil Currently selected stack frame
---@field repl_ctrl loop.ReplController|nil
---@field debuggee_output_ctrl loop.OutputBufferController|nil

---@alias loopdebug.mgr.JobCommandFn fun(cmd:loop.job.DebugJob.Command):boolean,(string|nil)

---@class loopdebug.mgr.DebugJobData
---@field jobname string
---@field page_manager loop.PageManager
---@field session_ctx number
---@field current_session_id number|nil
---@field session_data table<number, loopdebug.mgr.SessionData>

---@type loopdebug.mgr.DebugJobData|nil
local _current_job_data

local _page_groups       = {
    task = "task",
    variables = "vars",
    watch = "watch",
    stack = "stack",
    output = "output",
    repl = "repl",
}

-- =============================================================================
-- Context Management
-- =============================================================================

---Builds a snapshot of the current context state to validate async callbacks.
---@param job_data loopdebug.mgr.DebugJobData
---@return loopdebug.mgr.Context
local function _build_context(job_data)
    local sess_id = job_data.current_session_id
    local sess_data = sess_id and job_data.session_data[sess_id] or nil
    local sess_ctx = sess_data and sess_data.context_keys or nil
    ---@type loopdebug.mgr.Context
    local ctx = {
        session_ctx = job_data.session_ctx,
        pause_ctx = sess_ctx and sess_ctx.pause_ctx or 0,
        thread_ctx = sess_ctx and sess_ctx.thread_ctx or 0,
        frame_ctx = sess_ctx and sess_ctx.frame_ctx or 0,
    }
    return ctx
end

---Increments the context counter for a specific level, invalidating previous async requests.
---@param job_data loopdebug.mgr.DebugJobData
---@param level "session"|"pause"|"thread"|"frame"
local function _increment_context(job_data, level)
    local sess_id = job_data.current_session_id
    local sess_data = sess_id and job_data.session_data[sess_id] or nil

    if level == "session" then
        job_data.session_ctx = job_data.session_ctx + 1
    elseif sess_data then
        local ctx = sess_data.context_keys
        if level == "pause" then
            ctx.pause_ctx = ctx.pause_ctx + 1
        elseif level == "thread" then
            ctx.thread_ctx = ctx.thread_ctx + 1
        elseif level == "frame" then
            ctx.frame_ctx = ctx.frame_ctx + 1
        end
    end
end

---Checks if the context snapshot matches the current state.
---@param job_data loopdebug.mgr.DebugJobData
---@param ctx loopdebug.mgr.Context The snapshot to check
---@param level "session"|"pause"|"thread"|"frame" The level of granularity to check
---@return boolean
local function _is_current_context(job_data, ctx, level)
    local sess_id = job_data.current_session_id
    local sess_data = sess_id and job_data.session_data[sess_id] or nil
    local cur_ctx = sess_data and sess_data.context_keys or nil

    if level == "session" then
        return ctx.session_ctx == job_data.session_ctx
    end

    -- For all other levels, we need active session data
    if not cur_ctx or ctx.session_ctx ~= job_data.session_ctx then
        return false
    end

    if level == "pause" then
        return ctx.pause_ctx == cur_ctx.pause_ctx
    elseif level == "thread" then
        return ctx.pause_ctx == cur_ctx.pause_ctx
            and ctx.thread_ctx == cur_ctx.thread_ctx
    elseif level == "frame" then
        return ctx.pause_ctx == cur_ctx.pause_ctx
            and ctx.thread_ctx == cur_ctx.thread_ctx
            and ctx.frame_ctx == cur_ctx.frame_ctx
    end
    return false
end

-- =============================================================================
-- Reporting & Internal State Setters
-- =============================================================================

---Reports the full view state to the UI (debugevents).
---@param jobdata loopdebug.mgr.DebugJobData
local function _report_current_view(jobdata)
    local sess_id = jobdata.current_session_id
    local sess_data = sess_id and jobdata.session_data[sess_id] or nil

    if not sess_data then
        debugevents.report_view_update({})
        return
    end

    debugevents.report_view_update({
        session_id = sess_id,
        session_name = sess_data.sess_name,
        data_providers = sess_data.data_providers,
        thread_id = sess_data.cur_thread_id,
        thread_name = sess_data.thread_names[sess_data.cur_thread_id],
        frame = sess_data.cur_frame
    })
end

---Reports a session status update (e.g., paused/running state).
---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
local function _report_session_update(jobdata, sess_id)
    local sess_data = sess_id and jobdata.session_data[sess_id] or nil
    if not sess_data then return end

    local state = sess_data.state or "starting"
    local nb_paused_threads = vim.tbl_count(sess_data.paused_threads)

    debugevents.report_session_update(sess_id, {
        name = sess_data.sess_name,
        data_providers = sess_data.data_providers,
        state = state,
        nb_paused_threads = nb_paused_threads
    })
end

---Internal helper: Sets the current frame without triggering side effects.
---@param jobdata loopdebug.mgr.DebugJobData
---@param frame loopdebug.proto.StackFrame?
local function _set_frame_silent(jobdata, frame)
    local sess_id = jobdata.current_session_id
    local sess_data = sess_id and jobdata.session_data[sess_id]
    if not sess_data then return end

    _increment_context(jobdata, "frame")
    sess_data.cur_frame = frame
end

---Internal helper: Sets the current thread without triggering side effects.
---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
---@param thread_id number?
local function _set_thread_silent(jobdata, sess_id, thread_id)
    local sess_data = jobdata.session_data[sess_id]
    if not sess_data then return end

    _increment_context(jobdata, "thread")
    sess_data.cur_thread_id = thread_id
    -- When thread changes, the frame is inherently invalidated
    _set_frame_silent(jobdata, nil)
end

-- =============================================================================
-- Switching Logic (Refactored)
-- =============================================================================

---Switches the active frame and updates UI.
---@param jobdata loopdebug.mgr.DebugJobData
---@param frame loopdebug.proto.StackFrame?
---@param send_updates boolean If true, triggers a UI refresh
local function _switch_to_frame(jobdata, frame, send_updates)
    _set_frame_silent(jobdata, frame)
    if send_updates then _report_current_view(jobdata) end
end

---Switches the active thread, optionally fetches the stack, and updates UI.
---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
---@param thread_id number?
---@param send_updates boolean
local function _switch_to_thread(jobdata, sess_id, thread_id, send_updates)
    -- 1. Update internal state immediately
    _set_thread_silent(jobdata, sess_id, thread_id)
    local sess_data = jobdata.session_data[sess_id]

    -- 2. Report initial view (thread changed, frame empty)
    if send_updates then _report_current_view(jobdata) end

    if not thread_id or not sess_data then return end

    -- 3. Async Fetch: Get top stack frame
    local ctx = _build_context(jobdata)
    sess_data.data_providers.stack_provider({ threadId = thread_id, levels = 1 }, function(err, data)
        -- Validate context hasn't changed while we were waiting
        if _is_current_context(jobdata, ctx, "thread") then
            local topframe = data and data.stackFrames and data.stackFrames[1]
            if topframe then
                _set_frame_silent(jobdata, topframe)
                _report_current_view(jobdata)
            end
        end
    end)
end

---Switches the active session and handles thread synchronization on pause.
---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number?
---@param thread_pause_evt loopdebug.session.notify.ThreadsEventScope? If provided, syncs threads
local function _switch_to_session(jobdata, sess_id, thread_pause_evt)
    _increment_context(jobdata, "session")

    local sess_data = sess_id and jobdata.session_data[sess_id] or nil
    if not sess_id or not sess_data then
        jobdata.current_session_id = nil
        _report_current_view(jobdata)
        return
    end

    jobdata.current_session_id = sess_id

    -- Determine target thread
    local thread_id = thread_pause_evt and thread_pause_evt.thread_id or sess_data.cur_thread_id

    -- If this is a pause event, we need to sync the thread list first
    if thread_pause_evt then
        local ctx = _build_context(jobdata)
        sess_data.data_providers.threads_provider(function(err, resp)
            -- Validate pause context matches
            if not _is_current_context(jobdata, ctx, "pause") then return end

            if err or not resp or not resp.threads then
                notifications.notify("Failed to load thread list - " .. (err or ""))
            else
                -- Update thread names and paused state
                sess_data.thread_names = {}
                if thread_pause_evt.all_thread then
                    sess_data.paused_threads = {}
                end

                for _, thread in pairs(resp.threads) do
                    sess_data.thread_names[thread.id] = thread.name
                    if thread_pause_evt.all_thread then
                        sess_data.paused_threads[thread.id] = true
                    end
                end

                if not thread_pause_evt.all_thread then
                    sess_data.paused_threads[thread_pause_evt.thread_id] = true
                end

                _report_session_update(jobdata, sess_id)
                _switch_to_thread(jobdata, sess_id, thread_id, true)
            end
        end)
    else
        -- Just a session switch, simply switch to its last known thread
        _switch_to_thread(jobdata, sess_id, thread_id, true)
    end
end

-- =============================================================================
-- Event Handlers
-- =============================================================================

---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
---@param sess_name string
---@param parent_id number|nil
---@param controller loop.job.DebugJob.SessionController
---@param data_providers loopdebug.session.DataProviders
local function _on_session_added(jobdata, sess_id, sess_name, parent_id, controller, data_providers)
    assert(not jobdata.session_data[sess_id])

    debugevents.report_session_added(sess_id, {
        name = sess_name,
        data_providers = data_providers,
        state = "starting",
        nb_paused_threads = 0,
    })

    ---@type loopdebug.mgr.SessionData
    local session_data = {
        sess_name = sess_name,
        controller = controller,
        data_providers = data_providers,
        context_keys = { pause_ctx = 1, thread_ctx = 1, frame_ctx = 1 },
        paused_threads = {},
        thread_names = {}
    }
    jobdata.session_data[sess_id] = session_data

    -- If this is the first session, select it automatically
    if not jobdata.current_session_id then
        jobdata.current_session_id = sess_id
    end

    -- Setup REPL
    local repl_page_group = jobdata.page_manager.get_page_group(_page_groups.repl)
    if not repl_page_group then
        repl_page_group = jobdata.page_manager.add_page_group(_page_groups.repl, "Debug Console")
    end
    if repl_page_group then
        local page_data = repl_page_group.add_page({
            id = tostring(sess_id),
            type = "repl",
            label = sess_name,
            buftype = "repl",
            activate = false
        })
        if page_data then
            session_data.repl_ctrl = page_data.repl_buf
            session_data.repl_ctrl.set_input_handler(function(input)
                data_providers.evaluate_provider({
                    expression = input,
                    context = "repl",
                }, function(eval_err, data)
                    if not data then
                        local msg = eval_err or "Evaluation error"
                        session_data.repl_ctrl.add_output("\27[31m" .. msg .. "\27[0m")
                    else
                        session_data.repl_ctrl.add_output(tostring(data.result))
                    end
                end)
            end)
            session_data.repl_ctrl.set_completion_handler(function(input, callback)
                data_providers.completion_provider({
                    text = input,
                    column = #input + 1,
                    frameId = session_data.cur_frame and session_data.cur_frame.id or nil,
                }, function(compl_err, data)
                    if data then
                        local strs = {}
                        for _, item in ipairs(data.targets or {}) do
                            local str = item.text or item.label
                            if str then table.insert(strs, str) end
                        end
                        callback(strs)
                    else
                        callback(nil, compl_err)
                    end
                end)
            end)
        end
    end
end

---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
---@param sess_name string
local function _on_session_removed(jobdata, sess_id, sess_name)
    jobdata.session_data[sess_id] = nil
    debugevents.report_session_removed(sess_id)
    if jobdata.current_session_id == sess_id then
        _switch_to_session(jobdata, nil)
    end
end

---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
---@param sess_name string
---@param data loopdebug.session.notify.StateData
local function _on_session_state_update(jobdata, sess_id, sess_name, data)
    local session_data = jobdata.session_data[sess_id]
    if not session_data then return end

    session_data.state = data.state
    _report_session_update(jobdata, sess_id)

    if data.state == "ended" then
        session_data.cur_thread_id = nil
        session_data.cur_frame = nil
        if jobdata.current_session_id == sess_id then
            _switch_to_session(jobdata, nil)
        end
    end
end

---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
---@param sess_name string
---@param category string
---@param output string
local function _on_session_output(jobdata, sess_id, sess_name, category, output)
    local sess_data = jobdata.session_data[sess_id]
    if not sess_data then return end

    -- REPL Output
    if category ~= "stdout" and category ~= "stderr" then
        if sess_data.repl_ctrl then
            for line in output:gmatch("([^\r\n]*)\r?\n?") do
                if line ~= "" then sess_data.repl_ctrl.add_output(line) end
            end
        end
        return
    end

    -- Process Output
    local debuggee_output_ctrl = sess_data.debuggee_output_ctrl
    if not debuggee_output_ctrl then
        local page_group = jobdata.page_manager.get_page_group(_page_groups.output)
            or jobdata.page_manager.add_page_group(_page_groups.output, "Debug Output")

        local page_data = page_group.get_page(tostring(sess_id))
        if not page_data then
            page_data = page_group.add_page({
                id = tostring(sess_id),
                type = "output",
                buftype = "output",
                label = sess_name,
            })
        end
        if page_data then
            sess_data.debuggee_output_ctrl = page_data.output_buf
            debuggee_output_ctrl = sess_data.debuggee_output_ctrl
        end
    end

    if debuggee_output_ctrl then
        local highlights = (category == "stderr") and { { group = "ErrorMsg" } } or nil
        for line in output:gmatch("([^\r\n]*)\r?\n?") do
            if line ~= "" then
                debuggee_output_ctrl.add_lines(line, highlights)
            end
        end
    end
end

---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
---@param sess_name string
---@param event_data loopdebug.session.notify.ThreadsEventScope
local function _on_session_thread_pause(jobdata, sess_id, sess_name, event_data)
    if not jobdata.session_data[sess_id] then return end
    -- Switch session handles the context update, thread syncing, and reporting
    _switch_to_session(jobdata, sess_id, event_data)
end

---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
---@param sess_name string
---@param event_data loopdebug.session.notify.ThreadsEventScope
local function _on_session_thread_continue(jobdata, sess_id, sess_name, event_data)
    local sess_data = jobdata.session_data[sess_id]
    if not sess_data then return end

    if event_data.all_thread then
        _increment_context(jobdata, "pause")
        sess_data.paused_threads = {}
        _switch_to_thread(jobdata, sess_id, nil, true)
    else
        _increment_context(jobdata, "thread")
        sess_data.paused_threads[event_data.thread_id] = nil
        -- Only switch away if the CONTINUED thread was the ACTIVE thread
        if sess_data.cur_thread_id == event_data.thread_id then
            _switch_to_thread(jobdata, sess_id, nil, true)
        end
    end
    _report_session_update(jobdata, sess_id)
end

-- =============================================================================
-- Command Processors
-- =============================================================================

---@param jobdata loopdebug.mgr.DebugJobData
---@return boolean, string|nil
local function _process_continue_all_command(jobdata)
    for _, session_data in pairs(jobdata.session_data) do
        if session_data.cur_thread_id then
            session_data.controller.continue(session_data.cur_thread_id, true)
        end
    end
    return true
end

---@param jobdata loopdebug.mgr.DebugJobData
---@return boolean, string|nil
local function _process_terminate_all_command(jobdata)
    for _, session_data in pairs(jobdata.session_data) do
        session_data.controller.terminate()
    end
    return true
end

---@param jobdata loopdebug.mgr.DebugJobData
---@return boolean, string|nil
local function _process_select_session_command(jobdata)
    local choices = {}
    for sess_id, sess_data in pairs(jobdata.session_data) do
        table.insert(choices, { label = sess_data.sess_name, data = sess_id })
    end
    selector.select("Select debug session", choices, nil, function(sess_id)
        if sess_id then _switch_to_session(jobdata, sess_id) end
    end)
    return true
end

---@param jobdata loopdebug.mgr.DebugJobData
---@return boolean, string|nil
local function _process_select_thread_command(jobdata)
    local sess_id = jobdata.current_session_id
    local sess_data = sess_id and jobdata.session_data[sess_id] or nil
    if not sess_data then return false, "No active debug session" end

    local ctx = _build_context(jobdata)
    sess_data.data_providers.threads_provider(function(err, data)
        if _is_current_context(jobdata, ctx, "pause") then
            if err or not data or not data.threads then
                notifications.notify("Failed to load thread list: " .. (err or ""))
            else
                local choices = {}
                for _, thread in pairs(data.threads) do
                    table.insert(choices, {
                        label = tostring(thread.id) .. ": " .. tostring(thread.name),
                        data = thread.id
                    })
                end
                selector.select("Select thread", choices, nil, function(thread_id)
                    if thread_id and sess_id == jobdata.current_session_id then
                        _switch_to_thread(jobdata, sess_id, thread_id, true)
                    end
                end)
            end
        end
    end)
    return true
end

---@param jobdata loopdebug.mgr.DebugJobData
---@return boolean, string|nil
local function _process_select_frame_command(jobdata)
    local sess_id = jobdata.current_session_id
    local sess_data = sess_id and jobdata.session_data[sess_id] or nil
    if not sess_data then return false, "No active debug session" end

    local thread_id = sess_data.cur_thread_id
    if not thread_id then return false, "No selected thread" end

    local ctx = _build_context(jobdata)
    sess_data.data_providers.stack_provider({ threadId = thread_id }, function(err, data)
        if _is_current_context(jobdata, ctx, "thread") then
            if err or not data then
                notifications.notify("Failed to load call stack: " .. (err or ""))
            else
                local choices = {}
                for _, frame in pairs(data.stackFrames) do
                    table.insert(choices, { label = tostring(frame.name), data = frame })
                end
                selector.select("Select frame", choices, nil, function(frame)
                    if frame and sess_id == jobdata.current_session_id and thread_id == sess_data.cur_thread_id then
                        _switch_to_frame(jobdata, frame, true)
                    end
                end)
            end
        end
    end)
    return true
end

---@param jobdata loopdebug.mgr.DebugJobData
---@return boolean, string|nil
local function _process_inspect_var_command(jobdata)
    local sess_id = jobdata.current_session_id
    local sess_data = sess_id and jobdata.session_data[sess_id] or nil
    if not sess_data then return false, "No active debug session" end

    local dbgtools = require('loop-debug.tools.dbgtools')
    local expr, expr_err = dbgtools.clean_cword()
    if not expr then return false, expr_err or "No text under the cursor" end

    local frame = sess_data.cur_frame
    local ctx = _build_context(jobdata)

    sess_data.data_providers.evaluate_provider({
        expression = expr,
        context = "watch",
        frameId = frame and frame.id or nil
    }, function(err, data)
        if _is_current_context(jobdata, ctx, "frame") then
            if data and data.result then
                local title = data.type and (expr .. ' - ' .. data.type) or expr
                floatwin.show_floatwin(title, daptools.format_variable(data.result, data.presentationHint))
            else
                floatwin.show_floatwin("Error", err or "not available")
            end
        end
    end)
    return true
end

-- =============================================================================
-- Public API
-- =============================================================================

---@param task_name string
---@param page_manager loop.PageManager
---@return loop.job.debugjob.Tracker
function M.track_new_debugjob(task_name, page_manager)
    assert(not _current_job_data, "Previous debug task did not clean properly")
    assert(type(task_name) == "string")

    debugevents.report_debug_start()

    local page_data = page_manager.add_page_group(_page_groups.task, "Debug Sessions").add_page({
        id = "sessions",
        type = "comp",
        buftype = "sessions",
        label = "Debug Sessions",
        activate = true,
    })

    local sessionlist_comp = SessionList:new()
    sessionlist_comp:link_to_buffer(page_data.comp_buf)
    sessionlist_comp:set_page(page_data.page)

    ---@type loopdebug.mgr.DebugJobData
    local jobdata = {
        jobname = task_name,
        page_manager = page_manager,
        session_ctx = 1,
        session_data = {},
    }
    _current_job_data = jobdata

    ---@type loop.job.debugjob.Tracker
    return {
        on_sess_added = function(id, name, pid, ctrl, prov)
            _on_session_added(jobdata, id, name, pid, ctrl, prov)
        end,
        on_sess_removed = function(id, name)
            _on_session_removed(jobdata, id, name)
        end,
        on_sess_state = function(id, name, data)
            _on_session_state_update(jobdata, id, name, data)
        end,
        on_output = function(id, name, cat, out)
            _on_session_output(jobdata, id, name, cat, out)
        end,
        on_thread_pause = function(id, name, data)
            _on_session_thread_pause(jobdata, id, name, data)
        end,
        on_thread_continue = function(id, name, data)
            _on_session_thread_continue(jobdata, id, name, data)
        end,
        on_new_term = function(name, args, cb)
            -- Terminal logic remains same, inlined for brevity if needed or kept as original
            local start_args = { name = name, command = args.args, env = args.env, cwd = args.cwd, on_exit_handler = function() end }
            local pg = jobdata.page_manager.get_page_group(_page_groups.output)
                or jobdata.page_manager.add_page_group(_page_groups.output, "Debug Output")
            local pd, err = pg.add_page({
                id = "term." .. name .. vim.loop.hrtime(), type = "term", buftype = "term", label = "Debug Server", term_args =
            start_args, activate = true
            })
            if pd and pd.term_proc then cb(pd.term_proc:get_pid(), nil) else cb(nil, err) end
        end,
        on_exit = function(code)
            _current_job_data = nil
            debugevents.report_debug_end(code == 0)
        end
    }
end

---@param command loop.job.DebugJob.Command|nil
---@param arg1 string|nil
function M.debug_command(command, arg1)
    if command == "breakpoint" then
        if arg1 == "list" then breakpointsmonitor.select_breakpoint() else breakpoints.breakpoints_command(arg1) end
        return
    end

    local jobdata = _current_job_data
    if not jobdata then
        notifications.notify("No active debug task", vim.log.levels.WARN)
        return
    end

    if not command then return end

    -- Dispatch commands
    if command == 'continue_all' then
        _process_continue_all_command(jobdata); return
    end
    if command == 'terminate_all' then
        _process_terminate_all_command(jobdata); return
    end
    if command == "session" then
        _process_select_session_command(jobdata); return
    end
    if command == "thread" then
        _process_select_thread_command(jobdata); return
    end
    if command == "frame" then
        _process_select_frame_command(jobdata); return
    end
    if command == "inspect" then
        _process_inspect_var_command(jobdata); return
    end

    local sess_id = jobdata.current_session_id
    local sess_data = sess_id and jobdata.session_data[sess_id]
    if not sess_data then
        notifications.notify("No active debug session", vim.log.levels.WARN); return
    end

    if command == 'pause' then
        sess_data.controller.pause(sess_data.cur_thread_id or 0); return
    end

    if not sess_data.cur_thread_id then
        notifications.notify("No thread selected", vim.log.levels.WARN); return
    end

    local step_map = {
        continue = "continue",
        step_in = "step_in",
        step_out = "step_out",
        step_over = "step_over",
        step_back = "step_back"
    }
    if step_map[command] then
        -- Passing 'true' to continue usually implies reverse continue in some adapters,
        -- but strictly standard DAP uses separate reqs. Assuming loop controller handles it.
        sess_data.controller[command](sess_data.cur_thread_id, command == 'continue')
    else
        notifications.notify("Invalid debug command: " .. tostring(command), vim.log.levels.WARN)
    end
end

return M

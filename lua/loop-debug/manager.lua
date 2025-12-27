local config        = require("loop-debug.config")
local signs         = require('loop-debug.signs')
local filetools     = require('loop.tools.file')
local ItemListComp  = require('loop.comp.ItemList')
local uitools       = require('loop.tools.uitools')
local notifications = require('loop.notifications')
local selector      = require('loop.tools.selector')
local breakpoints   = require('lua.loop-debug.breakpoints')
local floatwin      = require('loop-debug.tools.floatwin')
local daptools      = require('loop-debug.dap.daptools')

local M             = {}

---@class loopdebug.mgr.Context
---@field session_ctx number
---@field pause_ctx number
---@field thread_ctx number
---@field frame_ctx number

---@class loopdebug.mgr.InSessionCtx
---@field pause_ctx number
---@field thread_ctx number
---@field frame_ctx number

---@class loopdebug.mgr.SessionData
---@field sess_name string|nil
---@field state string|nil
---@field controller loop.job.DebugJob.SessionController
---@field data_providers loopdebug.session.DataProviders
---@field context_keys loopdebug.mgr.InSessionCtx
---@field paused_threads table<number,boolean>
---@field thread_names table<number,string>
---@field cur_thread_id number|nil
---@field cur_frame loopdebug.proto.StackFrame|nil
---@field repl_ctrl loop.ReplController|nil
---@field debuggee_output_ctrl loop.OutputBufferController|nil

---@alias loopdebug.mgr.JobCommandFn fun(cmd:loop.job.DebugJob.Command):boolean,(string|nil)

---@class loopdebug.mgr.DebugJobData
---@field jobname string
---@field job_ended boolean|nil
---@field job_success boolean|nil
---@field page_manager loop.PageManager
---@field session_ctx number
---@field current_session_id number|nil
---@field session_data table<number,loopdebug.mgr.SessionData>
---@field sessionlist_comp loop.comp.ItemList
---@field sessionlist_page loop.PageController
---@field command_fn loopdebug.mgr.JobCommandFn

---@type loopdebug.mgr.DebugJobData|nil
local _current_job_data

local _page_groups  = {
    task = "task",
    variables = "vars",
    watch = "watch",
    stack = "stack",
    output = "output",
    repl = "repl",
}

local _ansi_colors  = {
    RESET = "\27[0m",
    BOLD  = "\27[1m",
    GREEN = "\27[32m",
    BLUE  = "\27[34m",
    RED   = "\27[31m",
    CYAN  = "\27[36m",
}

---@param single_target loopdebug.mgr.DebugTracker|nil
local function _send_job_udpate_event(single_target)
    local job_data = _current_job_data
    if not job_data then return end
    local sess_id = job_data.current_session_id
    local sess_data = sess_id and job_data.session_data[sess_id] or nil
    if not sess_data then return end
    ---@type loopdebug.mgr.JobUpdateEvent
    local event = {
        session_id = job_data.current_session_id,
        sess_name = sess_data.sess_name,
        cur_thread_id = sess_data.cur_thread_id,
        cur_thread_name = sess_data.thread_names[sess_data.cur_thread_id],
        cur_frame = sess_data.cur_frame,
        data_providers = vim.fn.copy(sess_data.data_providers)
    }
    if _current_job_data then
        if single_target then
            if single_target.on_job_update then
                single_target.on_job_update(event)
            end
        else
            _trackers:invoke("on_job_update", event)
        end
    end
end

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

---@param job_data loopdebug.mgr.DebugJobData
---@param level "session"|"pause"|"thread"|"frame"
local function _increment_context(job_data, level)
    local sess_id = job_data.current_session_id
    local sess_data = sess_id and job_data.session_data[sess_id] or nil
    if level == "session" then
        job_data.session_ctx = job_data.session_ctx + 1
    else
        if not sess_data then return end
        local ctx = sess_data.context_keys
        if level == "pause" then
            ctx.pause_ctx = ctx.pause_ctx + 1
        elseif level == "thread" then
            ctx.thread_ctx = ctx.thread_ctx + 1
        elseif level == "frame" then
            ctx.frame_ctx = ctx.frame_ctx + 1
        else
            assert(false)
        end
    end
end

---@param job_data loopdebug.mgr.DebugJobData
---@param ctx loopdebug.mgr.Context
---@param level "session"|"pause"|"thread"|"frame"
local function _is_current_context(job_data, ctx, level)
    local sess_id = job_data.current_session_id
    local sess_data = sess_id and job_data.session_data[sess_id] or nil
    local cur_ctx = sess_data and sess_data.context_keys or nil
    if level == "session" then
        return ctx.session_ctx == job_data.session_ctx
    elseif level == "pause" then
        return cur_ctx
            and ctx.session_ctx == job_data.session_ctx
            and ctx.pause_ctx == cur_ctx.pause_ctx
    elseif level == "thread" then
        return cur_ctx
            and ctx.session_ctx == job_data.session_ctx
            and ctx.pause_ctx == cur_ctx.pause_ctx
            and ctx.thread_ctx == cur_ctx.thread_ctx
    elseif level == "frame" then
        return cur_ctx
            and ctx.session_ctx == job_data.session_ctx
            and ctx.pause_ctx == cur_ctx.pause_ctx
            and ctx.thread_ctx == cur_ctx.thread_ctx
            and ctx.frame_ctx == cur_ctx.frame_ctx
    else
        assert(false)
    end
    return false
end

---@param frame loopdebug.proto.StackFrame
function _jump_to_frame(frame)
    if not (frame and frame.source and frame.source.path) then return end
    if not filetools.file_exists(frame.source.path) then return end
    -- Open file and move cursor
    uitools.smart_open_file(frame.source.path, frame.line, frame.column)
    -- Place sign for current frame
    signs.place_file_sign(1, frame.source.path, frame.line, "currentframe", "currentframe")
end

---@param jobdata loopdebug.mgr.DebugJobData
local function _refresh_task_page(jobdata)
    if jobdata.job_ended then
        --@type loop.pages.ItemListPage.Item
        local item = {
            id = 0,
            ---@class loopdebug.mgr.TaskPageItemData
            data = {
                label = jobdata.job_success and "Task ended" or "Task failed",
                nb_paused_threads = 0,
            }
        }
        local symbols = config.current.symbols
        jobdata.sessionlist_comp:set_items({ item })
        jobdata.sessionlist_page.set_ui_flags(jobdata.job_success and '' or symbols.failure)
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
            ---@class loopdebug.mgr.TaskPageItemData
            data = {
                label = tostring(sess_id) .. ' ' .. tostring(sdata.sess_name) .. ' - ' .. state,
                nb_paused_threads = nb_paused_threads,
            }
        }
        uiflags = uiflags .. flag
        table.insert(list_items, item)
    end

    jobdata.sessionlist_comp:set_items(list_items)
    jobdata.sessionlist_comp:set_current_item_by_id(jobdata.current_session_id)
    jobdata.sessionlist_page.set_ui_flags(uiflags)
end

---@param jobdata loopdebug.mgr.DebugJobData
---@param frame loopdebug.proto.StackFrame?
---@param send_updates boolean
local function _switch_to_frame(jobdata, frame, send_updates)
    if not frame then return end

    local sess_id = jobdata.current_session_id
    if not sess_id then return end

    local session_data = jobdata.session_data[sess_id]
    if not session_data then return end

    _increment_context(jobdata, "frame")

    if not frame then
        session_data.cur_frame = nil
        signs.remove_signs("currentframe")
        if send_updates then _send_job_udpate_event() end
        return
    end

    session_data.cur_frame = frame
    _jump_to_frame(frame)
    if send_updates then _send_job_udpate_event() end
end


---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
---@param thread_id number?
---@param send_updates boolean
local function _switch_to_thread(jobdata, sess_id, thread_id, send_updates)
    if not sess_id then return end

    local sess_data = jobdata.session_data[sess_id]
    if not sess_data then return end

    _increment_context(jobdata, "thread")

    _switch_to_frame(jobdata, nil, false)

    if not thread_id then
        sess_data.cur_thread_id = nil
        if send_updates then _send_job_udpate_event() end
        return
    end

    sess_data.cur_thread_id = thread_id
    local data_providers = sess_data.data_providers
    if send_updates then _send_job_udpate_event() end

    local ctx = _build_context(jobdata)
    local topframe

    -- request current frame
    data_providers.stack_provider({ threadId = thread_id, levels = 1 }, function(err, data)
        if _is_current_context(jobdata, ctx, "thread") then
            ---@type loopdebug.proto.StackFrame
            topframe = data and data.stackFrames[1] or nil
            sess_data.cur_frame = topframe
            _switch_to_frame(jobdata, topframe, true)
        end
    end)
end

---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number?
---@param thread_pause_evt? loopdebug.session.notify.ThreadsEventScope|nil
local function _switch_to_session(jobdata, sess_id, thread_pause_evt)
    _increment_context(jobdata, "session")

    _switch_to_thread(jobdata, jobdata.current_session_id, nil, false)

    local sess_data = sess_id and jobdata.session_data[sess_id] or nil
    if not sess_id or not sess_data then
        _send_job_udpate_event()
        _refresh_task_page(jobdata)
        return
    end

    jobdata.current_session_id = sess_id
    _send_job_udpate_event()

    local thread_id = thread_pause_evt and thread_pause_evt.thread_id or sess_data.cur_thread_id
    if not thread_id then
        _refresh_task_page(jobdata)
        return
    end

    if thread_pause_evt then
        if not thread_pause_evt.all_thread then
            sess_data.paused_threads[thread_pause_evt.thread_id] = true
            _refresh_task_page(jobdata)
        end
        local ctx = _build_context(jobdata)
        sess_data.data_providers.threads_provider(function(err, resp)
            if _is_current_context(jobdata, ctx, "pause") then
                if err or not resp or not resp.threads then
                    notifications.notify("Failed to load thread list - " .. (err or ""))
                else
                    if thread_pause_evt.all_thread then
                        sess_data.paused_threads = {}
                        for _, thread in pairs(resp.threads) do
                            sess_data.paused_threads[thread.id] = true
                        end
                        _refresh_task_page(jobdata)
                    end
                    sess_data.thread_names = {}
                    for _, thread in pairs(resp.threads) do
                        sess_data.thread_names[thread.id] = thread.name
                    end
                    _switch_to_thread(jobdata, sess_id, thread_id, true)
                end
            end
        end)
    else
        _refresh_task_page(jobdata)
        _switch_to_thread(jobdata, sess_id, thread_id, true)
    end
end

---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
---@param sess_name string
---@param parent_id number|nil
---@param controller loop.job.DebugJob.SessionController
---@param data_providers loopdebug.session.DataProviders
local function _on_session_added(jobdata, sess_id, sess_name, parent_id, controller, data_providers)
    assert(not jobdata.session_data[sess_id])
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
    if not jobdata.current_session_id then
        -- first session
        jobdata.current_session_id = sess_id
    end
    _refresh_task_page(jobdata)

    local repl_page_group = jobdata.page_manager.get_page_group(_page_groups.repl)
    if not repl_page_group then
        repl_page_group = jobdata.page_manager.add_page_group(_page_groups.repl, "Debug Console")
    end
    if repl_page_group then
        local page_data, err = repl_page_group.add_page({
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
                        local msg = eval_err and eval_err or "Evaluation error"
                        session_data.repl_ctrl.add_output(_ansi_colors.RED .. msg .. _ansi_colors.RESET)
                    else
                        session_data.repl_ctrl.add_output(tostring(data.result))
                    end
                end)
            end)
            session_data.repl_ctrl.set_completion_handler(function(input, callback)
                data_providers.completion_provider({
                    text = input,
                    column = #input + 1,
                    frameId = session_data.cur_frame and session_data.cur_frame.id or nil, --no context check needed here
                }, function(compl_err, data)
                    if data then
                        local strs = {}
                        for _, item in ipairs(data.targets or {}) do
                            local str = item.text and item.text or item.label
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
    _refresh_task_page(jobdata)
end

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
        if session_data.cur_thread_id then
            session_data.controller.terminate()
        end
    end
    return true
end

---@param jobdata loopdebug.mgr.DebugJobData
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

---@param jobdata loopdebug.mgr.DebugJobData
---@return boolean, string|nil
local function _process_select_thread_command(jobdata)
    local sess_id = jobdata.current_session_id

    ---@type loopdebug.mgr.SessionData|nil
    local sess_data = sess_id and jobdata.session_data[sess_id] or nil
    if not sess_id or not sess_data then
        return false, "No active debug session"
    end

    local ctx = _build_context(jobdata)
    sess_data.data_providers.threads_provider(function(err, data)
        if _is_current_context(jobdata, ctx, "pause") then
            if err or not data or not data.threads then
                notifications.notify("Failed to load thread list - " .. (err or ""))
            else
                local choices = {}
                for _, thread in pairs(data.threads) do
                    ---@type loop.SelectorItem
                    local item = { label = tostring(thread.id) .. ": " .. tostring(thread.name), data = thread.id }
                    table.insert(choices, item)
                end
                selector.select("Select thread", choices, nil, function(thread_id)
                    -- ensure session did not change meanwhile
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

    ---@type loopdebug.mgr.SessionData|nil
    local sess_data = sess_id and jobdata.session_data[sess_id] or nil
    if not sess_id or not sess_data then
        return false, "No active debug session"
    end

    local thread_id = sess_data.cur_thread_id
    if not thread_id then
        return false, "No selected thread"
    end

    local ctx = _build_context(jobdata)
    sess_data.data_providers.stack_provider({ threadId = sess_data.cur_thread_id }, function(err, data)
        if _is_current_context(jobdata, ctx, "thread") then
            if err or not data then
                notifications.notify("Failed to load call stack - " .. (err or ""))
            else
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
    ---@type loopdebug.mgr.SessionData|nil
    local sess_data = sess_id and jobdata.session_data[sess_id] or nil
    if not sess_id or not sess_data then
        return false, "No active debug session"
    end

    local thread_id = sess_data.cur_thread_id
    if not thread_id then
        return false, "No selected thread"
    end

    local dbgtools = require('loop-debug.tools.dbgtools')
    local expr, expr_err = dbgtools.clean_cword()
    if not expr then
        return false, expr_err or "No text under the cursor"
    end
    local frame = sess_data.cur_frame
    local ctx = _build_context(jobdata)
    sess_data.data_providers.evaluate_provider({
        expression = expr,
        context = "watch",
        frameId = frame and frame.id or nil
    }, function(err, data)
        if _is_current_context(jobdata, ctx, "frame") then
            if data and data.result then
                floatwin.open_inspect_win(expr, daptools.format_variable(data.result, data.presentationHint))
            else
                err = err or "not available"
                floatwin.open_inspect_win("Error", err)
            end
        end
    end)
    return true
end

---@param jobdata loopdebug.mgr.DebugJobData
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
    if command == "inspect" then
        return _process_inspect_var_command(jobdata)
    end

    local sess_id = jobdata.current_session_id
    ---@type loopdebug.mgr.SessionData|nil
    local sess_data = sess_id and jobdata.session_data[sess_id] or nil
    if not sess_id or not sess_data then
        return false, "No active debug session"
    end

    if command == 'pause' then
        sess_data.controller.pause(sess_data.cur_thread_id or 0)
        return true
    end

    if not sess_data.cur_thread_id then
        return false, "No thread selected"
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

---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
---@param sess_name string
---@param data loopdebug.session.notify.StateData
local function _on_session_state_update(jobdata, sess_id, sess_name, data)
    local session_data = jobdata.session_data[sess_id]
    if not session_data then return end
    session_data.state = data.state
    if data.state == "ended" then
        session_data.cur_thread_id = nil
        session_data.cur_frame = nil
        _switch_to_session(jobdata, nil)
    end
end

---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
---@param sess_name string
---@param category string
---@param output string
local function _on_session_output(jobdata, sess_id, sess_name, category, output)
    local sess_data = jobdata.session_data[sess_id]
    assert(sess_data, "missing session data")


    local is_repl = (category ~= "stdout" and category ~= "stderr")
    if is_repl then
        if sess_data.repl_ctrl then
            for line in output:gmatch("([^\r\n]*)\r?\n?") do
                if line ~= "" then
                    sess_data.repl_ctrl.add_output(line)
                end
            end
        end
        return
    end

    local debuggee_output_ctrl
    debuggee_output_ctrl = sess_data.debuggee_output_ctrl
    if not debuggee_output_ctrl then
        local page_group = jobdata.page_manager.get_page_group(_page_groups.output)
        if not page_group then
            page_group = jobdata.page_manager.add_page_group(_page_groups.output, "Debug Output")
        end
        local page_data
        if page_group then
            page_data = page_group.get_page(tostring(sess_id))
        end
        if not page_data and page_group then
            page_data = page_group.add_page({
                id = tostring(sess_id),
                type = "output",
                buftype = "output",
                label = sess_name,
            })
        end
        if page_data then
            assert(page_data.output_buf)
            sess_data.debuggee_output_ctrl = page_data.output_buf
        end
    end
    if debuggee_output_ctrl then
        ---@type loop.Highlight[]|nil
        local highlights = nil
        if category == "stderr" then
            highlights = {
                { group = "ErrorMsg" }
            }
        end
        for line in output:gmatch("([^\r\n]*)\r?\n?") do
            if line ~= "" then
                debuggee_output_ctrl.add_lines(line, highlights)
            end
        end
    end
end

---@param jobdata loopdebug.mgr.DebugJobData
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
    local page_id = "term." .. name .. string.format("%d", vim.loop.hrtime())
    local page_group = jobdata.page_manager.get_page_group(_page_groups.output)
    if not page_group then
        page_group = jobdata.page_manager.add_page_group(_page_groups.output, "Debug Output")
    end
    if not page_group then
        cb(nil, "UI not available")
        return
    end
    local page_data, err_msg = page_group.add_page({
        id = page_id,
        type = "term",
        buftype = "term",
        label = "Debug Server",
        term_args = start_args,
        activate = true,
    })
    local proc = page_data and page_data.term_proc or nil
    if proc then
        cb(proc:get_pid(), nil)
    else
        cb(nil, err_msg or "term err")
        notifications.notify("failed to started debugged process - " .. err_msg)
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

---@param jobdata loopdebug.mgr.DebugJobData
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

---@param jobdata loopdebug.mgr.DebugJobData
---@param sess_id number
---@param sess_name string
---@param event_data loopdebug.session.notify.ThreadsEventScope
local function _on_session_thread_continue(jobdata, sess_id, sess_name, event_data)
    local session_data = jobdata.session_data[sess_id]
    if not session_data then
        notifications.notify("Unexpected session pause event")
        return
    end
    session_data.cur_frame = nil
    if event_data.all_thread then
        _increment_context(jobdata, "pause")
        session_data.paused_threads = {}
        _switch_to_thread(jobdata, sess_id, nil, true)
    else
        _increment_context(jobdata, "thread")
        session_data.paused_threads[event_data.thread_id] = nil
        if session_data.cur_thread_id == event_data.thread_id then
            _switch_to_thread(jobdata, sess_id, nil, true)
        else
            _refresh_task_page(jobdata) -- for paused thread count
        end
    end
end

---@param task_name string -- task name
---@param page_manager loop.PageManager
---@return loop.job.debugjob.Tracker
function M.track_new_debugjob(task_name, page_manager)
    assert(type(task_name) == "string")

    local sessionlist_comp = ItemListComp:new({
        formatter = _debug_session_item_formatter,
        show_current_prefix = true,
    })

    local page_data = page_manager.add_page_group(_page_groups.task, "Debug Sessions").add_page({
        id = "sessions",
        type = "comp",
        buftype = "sessions",
        label = "Debug Sessions",
        activate = true,
    })
    assert(page_data)
    sessionlist_comp:link_to_buffer(page_data.comp_buf)

    ---@type loopdebug.mgr.DebugJobData
    local jobdata = {
        jobname = task_name,
        page_manager = page_manager,
        session_ctx = 1,
        session_data = {},
        sessionlist_comp = sessionlist_comp,
        sessionlist_page = page_data.page,
        command_fn = function() return false end,
    }

    jobdata.command_fn = function(cmd)
        return _on_debug_command(jobdata, cmd)
    end

    _current_job_data = jobdata

    sessionlist_comp:add_tracker({
        on_selection = function(id, data)
            if id then
                _switch_to_session(jobdata, id)
            end
        end
    })

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
        end
    }
    return tracker
end

---@param command loop.job.DebugJob.Command|nil
---@param arg1 string|nil
function M.debug_command(command, arg1)
    if command == "breakpoint" then
        breakpoints.breakpoints_command(arg1)
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
    local ok, err = job.command_fn(command)
    if not ok then
        notifications.notify(err or "Debug command failed", vim.log.levels.WARN)
    end
end

return M

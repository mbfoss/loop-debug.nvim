local class = require('loop.tools.class')
local strtools = require('loop.tools.strtools')
local daptools = require("loop-debug.dap.daptools")

local BaseSession = require("loop-debug.dap.BaseSession")
local FSM = require("loop-debug.tools.FSM")

local fsmdata = require('loop-debug.dap.fsmdata')

---@class loopdebug.Session
---@field new fun(self: loopdebug.Session, name:string) : loopdebug.Session
---@field _name string
---@field _log loopdebug.tools.Logger
---@field _args loopdebug.session.Args
---@field _capabilities table<string,string>
---@field _output_handler fun(msg_body:table)
---@field _on_exit fun(code:number)
---@field _tracker loop.session.Tracker
---@field _can_send_breakpoints boolean
---@field _source_breakpoints loopdebug.session.SourceBreakpointsData
---@field _subsession_id number
---@field _data_providers loopdebug.session.DataProviders
local Session = class()

---@param name string
function Session:init(name)
    assert(name, "session name require")

    self._name = name
    self._log = require('loop-debug.tools.Logger').create_logger("dap.session[" .. tostring(name) .. "]")

    self._started = false
    self._subsession_id = 0

    self._can_send_breakpoints = false
    self._source_breakpoints = { by_location = {}, by_usr_id = {}, by_dap_id = {}, pending_files = {} }

    self._data_providers = self:_create_data_providers()
end

---@return loopdebug.session.DataProviders
function Session:_create_data_providers()
    local is_available = function()
        return self._base_session ~= nil and self._fsm:curr_state() == 'running'
    end

    local na_msg = "not available"

    ---@type loopdebug.session.BreakpointsCommand
    local breakpoint_command = function(cmd, bp)
        if cmd == "add" then
            self:_set_source_breakpoint(bp)
        elseif cmd == "remove" then
            self:_remove_breakpoint(bp.id)
        elseif cmd == "remove_all" then
            self:_remove_all_breakpoints()
        else
            assert(false)
        end
    end

    ---@type loopdebug.session.ThreadsProvider
    local threads_provider = function(callback)
        if not is_available() then
            callback(na_msg, nil)
            return
        end
        self._base_session:request_threads(function(err, body)
            if not is_available() then
                callback(na_msg, nil)
            else
                callback(err, body)
            end
        end)
    end
    ---@type loopdebug.session.StackProvider
    local stack_provider = function(req, callback)
        if not is_available() then
            callback(na_msg, nil)
            return
        end
        self._base_session:request_stackTrace(req, function(err, body)
            if not is_available() then
                callback(na_msg, nil)
            else
                callback(err, body)
            end
        end)
    end
    ---@type loopdebug.session.ScopesProvider
    local scopes_provider = function(req, callback)
        if not is_available() then
            callback(na_msg, nil)
            return
        end
        self._base_session:request_scopes(req, function(err, body)
            if not is_available() then
                callback(na_msg, nil)
            else
                callback(err, body)
            end
        end)
    end
    ---@type loopdebug.session.VariablesProvider
    local variables_provider = function(req, callback)
        if not is_available() then
            callback(na_msg, nil)
            return
        end
        self._base_session:request_variables(req, function(err, body)
            if not is_available() then
                callback(na_msg, nil)
            else
                callback(err, body)
            end
        end)
    end
    ---@type loopdebug.session.EvaluateProvider
    local evaluate_provider = function(req, callback)
        if not is_available() then
            callback(na_msg, nil)
            return
        end
        self._base_session:request_evaluate(req, function(err, body)
            if not is_available() then
                callback(na_msg, nil)
            else
                callback(err, body)
            end
        end)
    end
    ---@type loopdebug.session.CompletionProvider
    local completion_provider = function(req, callback)
        if not is_available() then
            callback(na_msg, nil)
            return
        end
        self._base_session:request_completions(req, function(err, body)
            if not is_available() then
                callback(na_msg, nil)
            elseif not self._capabilities["supportsCompletionsRequest"] then
                callback("not supported", nil)
            else
                callback(err, body)
            end
        end)
    end

    ---@type loopdebug.session.DataProviders
    return {
        breakpoints_command = breakpoint_command,
        threads_provider = threads_provider,
        stack_provider = stack_provider,
        scopes_provider = scopes_provider,
        variables_provider = variables_provider,
        evaluate_provider = evaluate_provider,
        completion_provider = completion_provider,
    }
end

---@param args loopdebug.session.Args
---@return boolean,string|nil
function Session:start(args)
    assert(not self._started)
    self._started = true
    self._args = args

    assert(args.debug_args)
    assert(args.debug_args.adapter)

    local debuggername = args.debug_args.adapter.name or "Debugger"

    self._log:debug("Starting - args: " .. vim.inspect(args))

    local adapter = args.debug_args.adapter

    self._capabilities = {}
    self._process_ended = false
    self._tracker = args.tracker
    self._on_exit = args.exit_handler

    local stderr_handler = function(text)
        self:_trace_notification("[" .. debuggername .. "] " .. tostring(text), "error")
    end

    local exit_handler = function(code, signal)
        vim.schedule(function()
            self._process_ended = true
            self:_notify_about_state()
        end)
        if self._on_exit then
            self._on_exit(code)
        end
    end

    if adapter.type ~= "server" then
        local cmd_and_args = strtools.cmd_to_string_array(adapter.command)
        if #cmd_and_args == 0 then
            return false, "Missing DAP process command"
        end

        local dap_program = cmd_and_args[1]
        if dap_program == nil or dap_program == "" then
            return false, "Debugger command is missing"
        end

        local dap_path = vim.fn.exepath(dap_program)
        if dap_path == nil or dap_path == "" then
            return false, "Debugger program is not executable: " .. tostring(dap_program)
        end

        local dap_args = { unpack(cmd_and_args, 2) }

        self._base_session = BaseSession:new(self._name)
        self._base_session:start({
            dap_mode = "executable",
            dap_cmd = dap_path,  -- dap process
            dap_args = dap_args, -- dap args
            dap_env = adapter.env,
            dap_cwd = adapter.cwd,
            on_stderr = stderr_handler,
            on_exit = exit_handler,
        })
    else
        if not adapter.host or adapter.host == "" or not adapter.port then
            return false, "Missing remote DAP host name or port"
        end
        self._base_session = BaseSession:new(self._name)
        self._base_session:start({
            dap_mode = "server",
            dap_host = adapter.host,
            dap_port = adapter.port,
            on_stderr = stderr_handler,
            on_exit = exit_handler,
        })
    end

    if not self._base_session:running() then
        return false, "debug adapter initialization error"
    end

    ---@type loopdebug.fsmdata.StateHandlers
    local state_handlers = {
        initializing = function(_, _) self:_on_initializing_state() end,
        starting = function(_, _) self:_on_starting_state() end,
        running = function(_, _) self:_on_running_state() end,
        disconnecting = function(_, _) self:_on_disconnecting_state() end,
        ended = function(_, _) self:_on_ended_state() end,
    }
    -- start the FSM
    self._fsm = FSM:new(self._name, fsmdata.create_fsm_data(state_handlers))

    self._base_session:set_event_handler("module", function() end)
    self._base_session:set_event_handler("output", function(msg_body) self:_on_output_event(msg_body) end)
    self._base_session:set_event_handler("initialized", function(msg_body) self:_on_initialized_event(msg_body) end)
    self._base_session:set_event_handler("thread", function(msg_body) self:_on_thread_event(msg_body) end)
    self._base_session:set_event_handler("stopped", function(msg_body) self:_on_stopped_event(msg_body) end)
    self._base_session:set_event_handler("continued", function(msg_body) self:_on_continued_event(msg_body) end)
    self._base_session:set_event_handler("breakpoint", function(msg_body) self:_on_breakpoint_event(msg_body) end)
    self._base_session:set_event_handler("exited", function(msg_body) self:_on_exited_event(msg_body) end)
    self._base_session:set_event_handler("terminated", function(msg_body) self:_on_terminated_event(msg_body) end)


    self._base_session:set_reverse_request_handler("runInTerminal",
        function(req_args, on_success, on_failure)
            self:_on_runInTerminal_request(req_args, on_success, on_failure)
        end
    )

    self._base_session:set_reverse_request_handler("startDebugging",
        function(req_args, on_success, on_failure)
            self:_on_startDebugging_request(req_args, on_success, on_failure)
        end
    )

    vim.schedule(function()
        self._fsm:start()
    end)

    return true
end

function Session:terminate()
    self._fsm:trigger(fsmdata.trigger.disconnect)
end

---@return string
function Session:name()
    return self._name
end

---@return loopdebug.session.DataProviders
function Session:get_data_providers()
    return self._data_providers
end

---@param breakpoint loopdebug.SourceBreakpoint
function Session:_set_source_breakpoint(breakpoint)
    -- TODO: handle already sent breakpoints
    local data = self._source_breakpoints
    ---@type loopdebug.session.SourceBPData
    local pbdata = { user_data = breakpoint, verified = false, dap_id = nil }
    data.by_usr_id[breakpoint.id] = pbdata
    data.by_location[breakpoint.file] = data.by_location[breakpoint.file] or {}
    data.by_location[breakpoint.file][breakpoint.line] = pbdata
    data.pending_files[breakpoint.file] = true
    if self._can_send_breakpoints then
        self:_send_pending_breakpoints(function(success) end)
    end
end

---@param id number
function Session:_remove_breakpoint(id)
    local data = self._source_breakpoints
    local bp = data.by_usr_id[id]
    if bp then
        data.by_usr_id[id] = nil
        if bp.dap_id then
            data.by_dap_id[bp.dap_id] = nil
        end
        if data.by_location[bp.user_data.file] then
            local byline = data.by_location[bp.user_data.file]
            byline[bp.user_data.line] = nil
            if next(byline) == nil then
                data.by_location[bp.user_data.file] = nil
            end
        end
        data.pending_files[bp.user_data.file] = true
    end
    if self._can_send_breakpoints then
        self:_send_pending_breakpoints(function(success) end)
    end
end

function Session:_remove_all_breakpoints()
    local data = self._source_breakpoints
    for file, _ in pairs(data.by_location) do
        data.pending_files[file] = true
    end
    data.by_location = {}
    data.by_usr_id = {}
    data.by_dap_id = {}
    if self._can_send_breakpoints then
        self:_send_pending_breakpoints(function(success) end)
    end
end

---@param id number
---@return boolean|nil
function Session:get_breakpoint_state(id)
    local bp = self._source_breakpoints.by_usr_id[id]
    if bp then return bp.verified end
    return nil
end

---@param event loop.session.TrackerEvent
---@param data any
function Session:_notify_tracker(event, data)
    self._tracker(self, event, data)
end

function Session:_notify_about_state()
    local state = self._process_ended and "ended" or self._fsm:curr_state()
    ---@type loopdebug.session.notify.StateData
    local data = { state = state }
    self:_notify_tracker("state", data)
end

---@param text string
---@param level nil|"warn"|"error"
function Session:_trace_notification(text, level)
    ---@type loopdebug.session.notify.Trace
    local data = { text = text, level = level }
    self:_notify_tracker("trace", data)
end

---@return string
function Session:state()
    local state = self._process_ended and "ended" or self._fsm:curr_state()
    return state
end

---@param thread_id number
function Session:debug_pause(thread_id)
    assert(type(thread_id) == "number")
    self._base_session:request_pause({ threadId = thread_id },
        function(err, _)
            if err then
                self:_trace_notification("pause error: " .. tostring(err), "error")
            end
        end)
end

---@param thread_id number
---@param all_threads boolean
function Session:debug_continue(thread_id, all_threads)
    assert(type(thread_id) == "number")
    local single_thread = (all_threads == false)
    self._base_session:request_continue({ threadId = thread_id, singleThread = single_thread },
        function(err, _)
            if err then
                self:_trace_notification("continue error: " .. tostring(err), "error")
                return
            end
            ---@type loopdebug.session.notify.ThreadsEventScope
            local data = {
                thread_id = thread_id,
                all_thread = all_threads,
            }
            self:_notify_tracker("threads_continued", data)
        end)
end

---@param thread_id number
function Session:debug_stepIn(thread_id)
    assert(thread_id)
    self._base_session:request_stepIn({ threadId = thread_id, granularity = "line" }, function(err)
        if err then
            self:_trace_notification("stepIn error: " .. tostring(err), "error")
        end
    end)
end

---@param thread_id number
function Session:debug_stepOut(thread_id)
    assert(thread_id)
    self._base_session:request_stepOut({ threadId = thread_id, granularity = "line" }, function(err)
        if err then
            self:_trace_notification("stepOut error: " .. tostring(err), "error")
        end
    end)
end

---@param thread_id number
function Session:debug_stepOver(thread_id)
    assert(thread_id)

    self._base_session:request_next({ threadId = thread_id, granularity = "line" }, function(err)
        if err then
            self:_trace_notification("stepOver error: " .. tostring(err), "error")
        end
    end)
end

---@param thread_id number
function Session:debug_stepBack(thread_id)
    if not self._capabilities or self._capabilities["supportsStepBack"] ~= true then
        self._log:debug("step-back not supported by this debugger")
        return
    end
    assert(thread_id)
    self._base_session:request_stepBack({ threadId = thread_id, granularity = "line" }, function(err)
        if err then
            self:_trace_notification("stepBack error: " .. tostring(err), "error")
        end
    end)
end

function Session:debug_terminate()
    self._fsm:trigger(fsmdata.trigger.disconnect)
end

---@type fun(sef:loopdebug.Session, req_args:any, on_success:fun(resp_body:table), on_failure:fun(reason:string))
function Session:_on_runInTerminal_request(req_args, on_success, on_failure)
    if not req_args then
        on_failure('missing request args')
        return
    end
    ---@class loopdebug.session.notify.RunInTerminalReq
    local data = {
        ---@type loopdebug.proto.RunInTerminalRequestArguments
        args = req_args,
        on_success = function(pid) on_success({ processId = pid }) end,
        on_failure = on_failure
    }
    self:_notify_tracker("runInTerminal_request", data)
end

---@type fun(sef:loopdebug.Session, req_args: loopdebug.proto.StartDebuggingRequestArguments|nil, on_success:fun(resp_body:any), on_failure:fun(reason:string))
function Session:_on_startDebugging_request(req_args, on_success, on_failure)
    if not req_args then
        on_failure('missing request args')
        return
    end
    self._subsession_id = self._subsession_id + 1
    local name = self:name() .. ':' .. tostring(self._subsession_id)
    ---@type loopdebug.session.notify.SubsessionRequest
    local data = {
        name = name,
        debug_args = {
            adapter = vim.deepcopy(self._args.debug_args.adapter),
            request = req_args.request,
            request_args = req_args.configuration,
            initial_breakpoints = {},
        },
        on_success = on_success,
        on_failure = on_failure
    }
    for _, bp_data in pairs(self._source_breakpoints.by_usr_id) do
        ---@type loopdebug.SourceBreakpoint
        local bp = bp_data.user_data
        table.insert(data.debug_args.initial_breakpoints, bp)
    end
    self:_notify_tracker("subsession_request", data)
end

---@param event loopdebug.proto.OutputEvent|nil
function Session:_on_output_event(event)
    self:_notify_tracker("output", event)
end

function Session:_on_initialized_event(event)
    self:_send_configuration(function(success)
        if success then
            self._fsm:trigger(fsmdata.trigger.configuration_done)
        else
            self:_trace_notification("session initialization failed", "error")
            self._fsm:trigger(fsmdata.trigger.disconnect)
        end
    end)
end

---@param event loopdebug.proto.ThreadEvent|nil
function Session:_on_thread_event(event)
    if not event or not event.threadId then
        self._log:error("thread event with no data")
        return
    end
    if event.reason == "started" then
        self:_notify_tracker("thread_added", event.threadId)
    elseif event.reason == "exited" then
        self:_notify_tracker("thread_removed", event.threadId)
    end
end

---@param event loopdebug.proto.StoppedEvent|nil
function Session:_on_stopped_event(event)
    if not event then
        self._log:error("stopped event with no data")
        return
    end
    local cur_state = self._fsm:curr_state()
    if cur_state == "disconnecting" or cur_state == "ended" then
        self._log:error("unexpected stopped event")
        return
    end
    ---@type loopdebug.session.notify.ThreadsEventScope
    local data = {
        thread_id = event.threadId,
        all_thread = event.allThreadsStopped,
    }
    self:_notify_tracker("threads_paused", data)
end

---@param event loopdebug.proto.ContinuedEvent|nil
function Session:_on_continued_event(event)
    if not event then
        self._log:error("continued event with no data")
        return
    end
    if self._fsm:curr_state() ~= "running" then
        self._log:error("unexpected continued event")
    end
    ---@type loopdebug.session.notify.ThreadsEventScope
    local data = {
        thread_id = event.threadId,
        all_thread = event.allThreadsContinued,
    }
    self:_notify_tracker("threads_continued", data)
end

---@param event loopdebug.proto.BreakpointEvent|nil
function Session:_on_breakpoint_event(event)
    assert(event and event.breakpoint)
    local dapid = event.breakpoint.id
    if not dapid then return end
    local bp = self._source_breakpoints.by_dap_id[dapid]
    if bp then
        bp.verified = event.breakpoint.verified
        local removed = event.reason == "removed"
        ---@type loopdebug.session.notify.BreakpointsEvent
        local data = { { breakpoint_id = bp.user_data.id, verified = bp.verified, removed = removed } }
        self:_notify_tracker("breakpoints", data)
        if removed then
            self._source_breakpoints.by_dap_id[dapid] = nil
        end
    end
end

---@param event loopdebug.proto.ExitedEvent|nil
function Session:_on_exited_event(event)
    self:_notify_tracker("debuggee_exit", event)
end

---@param event loopdebug.proto.TerminatedEvent|nil
function Session:_on_terminated_event(event)
    if not event or event.restart ~= true then
        self._fsm:trigger(fsmdata.trigger.disconnect)
    end
end

---@param on_complete fun(success:boolean)
function Session:_send_initialize(on_complete)
    local adapter_id = self._args.debug_args.adapter.adapter_id
    if type(adapter_id) ~= "string" or adapter_id == "" then
        self:_trace_notification("Missing or invalid adapter_id in debugger configuration")
        on_complete(false)
        return
    end
    ---@type loopdebug.proto.InitializeRequestArguments
    local req_args = {
        adapterID = adapter_id,
        linesStartAt1 = true,
        columnsStartAt1 = true,
        pathFormat = "path",
        supportsStartDebuggingRequest = true,
        supportsRunInTerminalRequest = true,
        supportsArgsCanBeInterpretedByShell = false,
        supportsANSIStyling = true
    }
    self._base_session:request_initialize(req_args, function(err, resp)
        if resp then
            self._capabilities = resp
            on_complete(true)
        else
            self._log:error("initialize request error" .. tostring(err))
            on_complete(false)
        end
    end)
end

---@param on_complete fun(success:boolean)
function Session:_send_attach(on_complete)
    local target = self._args.debug_args
    assert(target)
    assert(target.request_args)
    self._log:info('attaching: ' .. vim.inspect(target.request_args))
    ---@type loopdebug.proto.AttachRequestArguments
    ---@diagnostic disable-next-line: assign-type-mismatch
    local attach_args = target.request_args
    self._base_session:request_attach(attach_args, function(err)
        if err then
            ---@type loopdebug.session.notify.Trace
            local data = { text = "attach request failed - " .. tostring(err), level = "error" }
            self:_notify_tracker("trace", data)
        end
        on_complete(err == nil)
    end)
end

---@param on_complete fun(success:boolean)
function Session:_send_launch(on_complete)
    local target = self._args.debug_args
    assert(target)
    assert(target.request_args)
    self._log:info('launching: ' .. vim.inspect(target.request_args))
    ---@type loopdebug.proto.LaunchRequestArguments
    ---@diagnostic disable-next-line: assign-type-mismatch
    local launch_args = target.request_args
    self._base_session:request_launch(launch_args, function(err)
        if err then
            ---@type loopdebug.session.notify.Trace
            local data = { text = "launch request failed - " .. tostring(err), level = "error" }
            self:_notify_tracker("trace", data)
        end
        on_complete(err == nil)
    end)
end

function Session:_on_initializing_state()
    self:_notify_about_state()

    local on_complete = function(success)
        if not success then
            self._fsm:trigger(fsmdata.trigger.initialize_resp_err)
            return
        end
        if self._args.debug_args.launch_post_configure ~= true then
            self._fsm:trigger(fsmdata.trigger.start_before_initialized)
        end
    end

    self:_send_initialize(function(success)
        on_complete(success)
    end)
end

---@param on_complete fun(success:boolean)
function Session:_send_configuration(on_complete)
    self._can_send_breakpoints = true
    self:_send_pending_breakpoints(function(bpts_ok)
        if bpts_ok then
            self:_send_configurationDone(on_complete)
        else
            on_complete(false)
        end
    end)
end

---@param on_complete fun(success:boolean)
function Session:_send_pending_breakpoints(on_complete)
    if not self._can_send_breakpoints then
        self._log:debug('cannot send breakpoints')
        on_complete(false)
        return
    end

    local nb_sources = vim.tbl_count(self._source_breakpoints.pending_files)
    local nb_replies = 0
    local nb_failures = 0

    if nb_sources == 0 then
        on_complete(true)
        return
    end

    for file, _ in pairs(self._source_breakpoints.pending_files) do
        self._source_breakpoints.pending_files[file] = nil

        ---@type loopdebug.proto.SourceBreakpoint[]
        local dap_breakpoints = {}
        ---@type loopdebug.session.SourceBPData[]
        local originals = {}
        do
            local lines = self._source_breakpoints.by_location[file]
            if lines then
                for line, bp in pairs(lines) do
                    ---@type loopdebug.proto.SourceBreakpoint
                    local dapbp = {
                        line = bp.user_data.line,
                        column = bp.user_data.column,
                        condition = bp.user_data.condition,
                        hitCondition = bp.user_data.hitCondition,
                        logMessage = bp.user_data.logMessage
                    }
                    table.insert(dap_breakpoints, dapbp)
                    table.insert(originals, bp)
                end
            end
        end

        self._log:debug('sending breakpoints for file: ' .. file .. ": " .. vim.inspect(dap_breakpoints))
        self._base_session:request_setBreakpoints({
                source = {
                    name = vim.fn.fnamemodify(file, ":t"),
                    path = file
                },
                breakpoints = dap_breakpoints
            },
            function(err, resp)
                if resp then
                    for idx, bp in ipairs(resp.breakpoints) do
                        local dap_id = bp.id or idx -- some dapters don't sent an id
                        local original = originals[idx]
                        original.verified = bp.verified
                        original.dap_id = dap_id
                        self._source_breakpoints.by_dap_id[dap_id] = original
                    end
                    ---@type loopdebug.session.notify.BreakpointsEvent
                    local data = {}
                    for _, bp in ipairs(originals) do
                        ---@type loopdebug.session.notify.BreakpointState
                        local state = { breakpoint_id = bp.user_data.id, verified = bp.verified }
                        table.insert(data, state)
                    end
                    self:_notify_tracker("breakpoints", data)
                end
                nb_replies = nb_replies + 1
                if err ~= nil or not resp then
                    nb_failures = nb_failures + 1
                    self._log:error("failed to set breakpoints")
                end
                if nb_replies == nb_sources then
                    on_complete(nb_failures == 0)
                end
            end)
    end
end

---@param on_complete fun(success:boolean)
function Session:_send_configurationDone(on_complete)
    self._base_session:request_configurationDone(function(err, _)
        on_complete(err == nil)
    end)
end

function Session:_on_starting_state()
    self:_notify_about_state()

    local target = self._args.debug_args
    assert(target)

    local on_complete = function(success)
        self._fsm:trigger(success and
            fsmdata.trigger.launch_resp_ok or
            fsmdata.trigger.launch_resp_error)
    end

    if target.request == "launch" then
        self:_send_launch(on_complete)
        return
    end

    if target.request == "attach" then
        self:_send_attach(on_complete)
        return
    end

    self._log:error("handled request type: " .. tostring(target.request))
    on_complete(false)
end

function Session:_on_running_state()
    self:_notify_about_state()
end

function Session:_on_disconnecting_state()
    local terminate_debuggee = self._args.debug_args.terminate_debuggee
    self._can_send_breakpoints = false
    self:_notify_about_state()

    --set a 3 seconds timeout to avoid hanging during stop
    local timeout_timer = vim.defer_fn(function()
            self._fsm:trigger(fsmdata.trigger.disconnect_timeout)
        end,
        3000)

    self._base_session:request_disconnect({
        terminateDebuggee = terminate_debuggee
    }, function(err, body)
        if timeout_timer:is_active() then
            timeout_timer:stop()
            timeout_timer:close()
        end
        self._fsm:trigger(err == nil and fsmdata.trigger.disconnect_resp_ok or fsmdata.trigger.disconnect_resp_err)
    end)
end

function Session:_on_ended_state()
    self._can_send_breakpoints = false
    self:_notify_about_state()
    self._base_session:terminate()
end

return Session

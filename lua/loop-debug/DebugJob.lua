local class    = require('loop.tools.class')
local Session  = require('loop-debug.dap.Session')
local Trackers = require("loop.tools.Trackers")

---@alias loop.job.DebugJob.Command
---|"session"
---|"thread"
---|"frame"
---|"continue"
---|"step_in"
---|"step_out"
---|"step_over"
---|"terminate"
---|"pause"
---|"continue_all"
---|"terminate_all"
---|"inspect"
---|"ui"

---@class loop.job.DebugJob.SessionController
---@field pause fun(thread_id: number)
---@field continue fun(thread_id: number, all_threads: boolean)
---@field step_in fun(thread_id: number)
---@field step_over fun(thread_id: number)
---@field step_back fun(thread_id: number)
---@field step_out fun(thread_id: number)
---@field terminate fun()

---@class loop.job.debugjob.Tracker
---@field on_exit fun(code : number)|nil
---@field on_sess_added fun(id:number,name:string, parent_id:number,ctrl:loop.job.DebugJob.SessionController,data:loopdebug.session.DataProviders)|nil
---@field on_sess_removed fun(id:number, name:string)|nil
---@field on_sess_state fun(id:number, name:string, data:loopdebug.session.notify.StateData)|nil
---@field on_new_term fun(name:string,args:loopdebug.proto.RunInTerminalRequestArguments,callback:fun(pid:number|nil,err:string|nil))|nil
---@field on_output fun(sess_id:number, sess_name:string, category:string, output:string)|nil
---@field on_thread_pause fun(sess_id:number, sess_name:string,data:loopdebug.session.notify.ThreadsEventScope)|nil
---@field on_thread_continue fun(sess_id:number, sess_name:string,data:loopdebug.session.notify.ThreadsEventScope)|nil
---@field on_breakpoint_event fun(sess_id:number, sess_name:string, event:loopdebug.session.notify.BreakpointsEvent)|nil

---@class loop.job.DebugJob
---@field new fun(self: loop.job.DebugJob, name:string) : loop.job.DebugJob
---@field _sessions table<number,loopdebug.Session>
---@field _last_session_id number
---@field _trackers loop.tools.Trackers<loop.job.debugjob.Tracker>
local DebugJob = class()

---Initializes the DebugJob instance.
---@param name string
function DebugJob:init(name)
    self._log = require('loop-debug.tools.Logger').create_logger("DebugJob[" .. tostring(name) .. "]")
    ---@type table<number,loopdebug.Session>
    self._sessions = {}
    self._last_session_id = 0
    self._output_pages = {}
    self._stacktrace_pages = {}
    self._trackers = Trackers:new()
end

---@param callbacks loop.job.debugjob.Tracker>
---@return number
function DebugJob:add_tracker(callbacks)
    return self._trackers:add_tracker(callbacks)
end

---@param id number
---@return boolean
function DebugJob:remove_tracker(id)
    return self._trackers:remove_tracker(id)
end

---@return boolean
function DebugJob:is_running()
    return next(self._sessions) ~= nil
end

function DebugJob:terminate()
    for _, s in pairs(self._sessions) do
        s:terminate()
    end
end

---@class loop.DebugJob.StartArgs
---@field name string
---@field debug_args loopdebug.session.DebugArgs

---Starts a new terminal job.
---@param args loop.DebugJob.StartArgs
---@return boolean, string|nil
function DebugJob:start(args)
    if #self._sessions > 0 then
        return false, "A debug job is already running"
    end
    return self:add_new_session(args.name, args.debug_args)
end

---@param name string
---@param debug_args loopdebug.session.DebugArgs
---@param parent_sess_id number|nil
---@return boolean,string|nil
function DebugJob:add_new_session(name, debug_args, parent_sess_id)
    local session_id           = self._last_session_id + 1
    self._last_session_id      = session_id

    ---@param session loopdebug.Session
    ---@param event loop.session.TrackerEvent
    ---@param event_data any
    local tracker              = function(session, event, event_data)
        self:_on_session_event(session_id, session, event, event_data)
    end

    local exit_handler         = function(code)
        -- schedule so that it does not happen before on_sess_added event
        vim.schedule(function()
            self:_session_exit_handler(session_id, code)
        end)
    end

    ---@type loopdebug.session.Args
    local session_args         = {
        debug_args = debug_args,
        tracker = tracker,
        exit_handler = exit_handler,
    }

    -- start new session
    local session              = Session:new(name)

    self._sessions[session_id] = session

    ---@type loop.job.DebugJob.SessionController
    local controller           = {
        pause = function(thread_id) session:debug_pause(thread_id) end,
        continue = function(thread_id, all_threads) session:debug_continue(thread_id, all_threads) end,
        step_in = function(thread_id) session:debug_stepIn(thread_id) end,
        step_over = function(thread_id) session:debug_stepOver(thread_id) end,
        step_back = function(thread_id) session:debug_stepBack(thread_id) end,
        step_out = function(thread_id) session:debug_stepOut(thread_id) end,
        terminate = function() session:debug_terminate() end,
    }

    local data_providers       = session:get_data_providers()

    self._trackers:invoke("on_sess_added", session_id, name, parent_sess_id, controller, data_providers)

    local started, start_err = session:start(session_args)
    if not started then
        return false, "Failed to start debug session, " .. start_err
    end

    return true, nil
end

function DebugJob:_session_exit_handler(session_id, code)
    vim.schedule(function()
        if self._sessions[session_id] then
            local session = self._sessions[session_id]
            self:add_debug_output(session_id, session:name(), "log", "Debug session ended")
            self._trackers:invoke("on_sess_removed", session_id, session:name())
            self._sessions[session_id] = nil
            if next(self._sessions) == nil then
                self._trackers:invoke("on_exit", code)
            end
        end
    end)
end

---@param sess_id number
---@param session loopdebug.Session
---@param event loop.session.TrackerEvent
---@param event_data any
function DebugJob:_on_session_event(sess_id, session, event, event_data)
    if event == "trace" then
        ---@type loopdebug.session.notify.Trace
        local trace = event_data
        local text = trace.text
        if trace.level then text = trace.level .. ": " .. trace.text end
        self:add_debug_output(sess_id, session:name(), "log", text)
        return
    end
    if event == "state" then
        ---@type loopdebug.session.notify.StateData
        local state = event_data
        self._trackers:invoke("on_sess_state", sess_id, session:name(), state)
        return
    end
    if event == "output" then
        ---@type loopdebug.proto.OutputEvent
        local output = event_data
        if output.category ~= "telemetry" then
            self:add_debug_output(sess_id, session:name(), tostring(output.category), tostring(output.output))
        end
        return
    end
    if event == "runInTerminal_request" then
        ---@type loopdebug.session.notify.RunInTerminalReq
        local request = event_data
        self:add_debug_term(session:name(), request.args, request.on_success, request.on_failure)
        return
    end
    if event == "threads_paused" then
        self:_on_session_threads_pause(sess_id, session:name(), event_data)
        return
    end
    if event == "threads_continued" then
        self._trackers:invoke("on_thread_continue", sess_id, session:name(), event_data)
        return
    end
    if event == "breakpoints" then
        ---@type loopdebug.session.notify.BreakpointsEvent
        local data = event_data
        self:_on_session_breakpoints_event(sess_id, session, data)
        return
    end
    if event == "debuggee_exit" then
        self:_on_session_debuggee_exit(sess_id, session)
        return
    end
    if event == "subsession_request" then
        ---@type loopdebug.session.notify.SubsessionRequest
        local request = event_data
        self:_on_subsession_request(sess_id, session, request)
        return
    end
    if event == "thread_added" or event == "thread_removed" then
        -- not needed for now
        return
    end
    vim.notify("LoopDebug: unhandled dap session event: " .. event)
end

---@param sess_id number
---@param sess_name string
---@param category string
---@param output string
function DebugJob:add_debug_output(sess_id, sess_name, category, output)
    self._trackers:invoke("on_output", sess_id, sess_name, category, output)
end

---@param name string
---@param args loopdebug.proto.RunInTerminalRequestArguments
---@param on_success fun(pid:number)
---@param on_failure fun(reason:string)
function DebugJob:add_debug_term(name, args, on_success, on_failure)
    --vim.notify(vim.inspect{name, args, on_success, on_failure})

    assert(type(name) == "string")
    assert(type(args) == "table")
    assert(type(on_success) == "function")
    assert(type(on_failure) == "function")

    local cb_error = function(err)
        on_failure("reversed request handler error")
        self._log:error("Error in on_new_term tracker\n" ..
            debug.traceback("Error: " .. tostring(err) .. "\n", 2))
    end

    xpcall(function()
        self._trackers:invoke("on_new_term", name, args, function(pid, err)
            if err then
                on_failure(err)
                self._log:error("Error in on_new_term handling\n" .. err)
            else
                on_success(pid)
            end
        end)
    end, cb_error)
end

---@param sess_id number
---@param sess_name string
---@param event_data loopdebug.session.notify.ThreadsEventScope
function DebugJob:_on_session_threads_pause(sess_id, sess_name, event_data)
    self._trackers:invoke("on_thread_pause", sess_id, sess_name, event_data)
end

---@param sess_id number
---@param session loopdebug.Session
---@param event loopdebug.session.notify.BreakpointsEvent
function DebugJob:_on_session_breakpoints_event(sess_id, session, event)
    self._trackers:invoke("on_breakpoint_event", sess_id, session, event, event)
end

---@param sess_id number
---@param session loopdebug.Session
function DebugJob:_on_session_debuggee_exit(sess_id, session)
end

---@param sess_id number
---@param session loopdebug.Session
---@param request loopdebug.session.notify.SubsessionRequest
function DebugJob:_on_subsession_request(sess_id, session, request)
    self._log:debug("Starting subsession via startDebugging: " .. vim.inspect(request))

    local ok, err = self:add_new_session(request.name, request.debug_args, sess_id)
    if not ok then
        return request.on_failure("failed to startup child session, " .. tostring(err))
    end

    request.on_success({})
end

return DebugJob

local Channel = require("loop-debug.dap.Channel")
local daptools = require("loop-debug.dap.daptools")

---@alias loopdebug.EventHandler fun(msg_body: table|nil)
---@alias loopdebug.ReverseRequestHandler fun(args: table|nil, on_success: fun(resp: table), on_failure: fun(reason: string))

local class = require('loop.tools.class')

---@class loopdebug.BaseSession.Opts
---@field dap_mode "executable"|"server"
---@field dap_cmd string|nil
---@field dap_args string[]|nil
---@field dap_env table<string,string>|nil
---@field dap_cwd string|nil
---@field dap_host string|nil
---@field dap_port number|nil
---@field on_stderr fun(text: string)
---@field on_exit fun(code: number, signal: number)

---@class loopdebug.BaseSession
---@field new fun(self: loopdebug.BaseSession, name): loopdebug.BaseSession
---@field log any
---@field request_seq integer
---@field callbacks table<integer, fun(response: loopdebug.proto.Response)>
---@field event_handlers table<string, loopdebug.EventHandler>
---@field reverse_request_handlers table<string, loopdebug.ReverseRequestHandler>
---@field channel loopdebug.Channel
local BaseSession = class()

---@param name string
function BaseSession:init(name)
    self._name = name
end

---@param opts loopdebug.BaseSession.Opts
function BaseSession:start(opts)
    assert(type(opts.on_stderr) == "function")
    assert(type(opts.on_exit) == "function")
    self.log = require('loop.tools.Logger').create_logger("dap.basicsession[" .. self._name .. ']')
    self.request_seq = 0
    self.callbacks = {}
    self.event_handlers = {}
    self.reverse_request_handlers = {}

    ---@type loopdebug.Channel.Opts
    local channel_opts = {
        dap_mode   = opts.dap_mode,
        dap_cmd    = opts.dap_cmd,
        dap_args   = opts.dap_args,
        dap_env    = opts.dap_env,
        dap_cwd    = opts.dap_cwd,
        dap_host   = opts.dap_host,
        dap_port   = opts.dap_port,
        on_message = vim.schedule_wrap(
        -- schedule to avoid processing in the fast event context
            function(msg)
                self:_on_message(msg)
            end),
        on_stderr  = vim.schedule_wrap(
        -- schedule to avoid processing in the fast event context
            function(text)
                vim.schedule(function()
                    opts.on_stderr(text)
                end)
            end),
        on_exit    = opts.on_exit,
    }

    self.channel = Channel:new(self._name, channel_opts)
    return self
end

---@return boolean
function BaseSession:running()
    return self.channel:running()
end

function BaseSession:kill()
    self.channel:kill()
end

---@param event_name string
---@param handler loopdebug.EventHandler
function BaseSession:set_event_handler(event_name, handler)
    assert(not self.event_handlers[event_name], "another handler exists for event " .. event_name)
    self.event_handlers[event_name] = handler
end

---@param command string
---@param handler loopdebug.ReverseRequestHandler
function BaseSession:set_reverse_request_handler(command, handler)
    assert(not self.reverse_request_handlers[command], "another handler exists for command " .. command)
    self.reverse_request_handlers[command] = handler
end

---@param msg loopdebug.proto.ProtocolMessage
function BaseSession:_on_message(msg)
    if msg.type == "event" then
        ---@cast msg loopdebug.proto.Event
        self:_handle_event(msg)
    elseif msg.type == "response" then
        ---@cast msg loopdebug.proto.Response
        self:_handle_resp(msg)
    elseif msg.type == "request" then
        ---@cast msg loopdebug.proto.Request
        self:_handle_rev_req(msg)
    else
        self.log:warn("Unknown DAP message type: " .. tostring(msg.type))
    end
end

---@param msg loopdebug.proto.Event
function BaseSession:_handle_event(msg)
    local handler = self.event_handlers[msg.event]
    if not handler then
        self.log:warn("Unhandled DAP event: " .. msg.event)
        return
    end
    local cb_error = function(err)
        self.log:error("Error in event handler for " .. msg.event ..
            debug.traceback("Error: " .. tostring(err) .. "\n", 2))
    end
    xpcall(function() handler(msg.body) end, cb_error)
end

---@param msg loopdebug.proto.Response
function BaseSession:_handle_resp(msg)
    local cb = self.callbacks[msg.request_seq]
    if not cb then
        self.log:log("Unhandled DAP response: " .. msg.command)
        return
    end
    self.callbacks[msg.request_seq] = nil

    local error_cb = function(err)
        self.log:error("Error in response handler for " .. tostring(msg.command) ..
            debug.traceback("Error: " .. tostring(err) .. "\n", 2))
    end
    xpcall(function() cb(msg) end, error_cb)
end

---@param msg loopdebug.proto.Request
function BaseSession:_handle_rev_req(msg)
    local resp_sent = false

    local send_success = function(body)
        if not resp_sent then
            self:_response(msg.command, msg.seq, true, body)
            resp_sent = true
        end
    end

    local send_failure = function(reason)
        if not resp_sent then
            self:_response(msg.command, msg.seq, false, reason)
            resp_sent = true
        end
    end

    local handler = self.reverse_request_handlers[msg.command]
    if not handler then
        send_failure("No handler registered for reverse request: " .. msg.command)
        return
    end

    local error_cb = function(err)
        self.log:error("Error in reverse request handler for " .. tostring(msg.command) ..
            debug.traceback("Error: " .. tostring(err) .. "\n", 2))
    end
    local ok = xpcall(function()
        handler(msg.arguments or {}, send_success, send_failure)
    end, error_cb)
    if not ok then
        send_failure("Error in reverse request handler")
    end
end

---@param command string
---@param arguments table|nil
---@param callback fun(response: loopdebug.proto.Response)|nil
function BaseSession:_request(command, arguments, callback)
    if arguments and next(arguments) == nil then
        arguments = vim.empty_dict() -- for correct json encoding
    end
    self.request_seq = self.request_seq + 1
    if callback then
        self.callbacks[self.request_seq] = callback
    end
    local req = {
        seq = self.request_seq,
        type = "request",
        command = command,
        arguments = arguments
    }
    self.channel:send_message(req)
end

---@param command string
---@param from_request_seq integer
---@param success boolean
---@param payload table|string|nil
function BaseSession:_response(command, from_request_seq, success, payload)
    self.request_seq = self.request_seq + 1
    local resp = {
        seq = self.request_seq,
        type = "response",
        request_seq = from_request_seq,
        command = command,
        success = success,
    }
    if success then
        resp.body = payload or {}
    else
        resp.message = tostring(payload)
    end
    self.channel:send_message(resp)
end

-- Converts DAP response into (err, body)
---@param cb fun(err: string|nil, body: any)|nil
---@return fun(resp: loopdebug.proto.Response)|nil
function BaseSession:_wrap(cb)
    if not cb then return nil end
    return function(resp)
        if not resp.success then
            local msg = resp.message or daptools.dap_error_to_string(resp.body)
            cb(msg or "Unknown error", nil)
        else
            cb(nil, resp.body)
        end
    end
end

---------------------------------------------------------------------
-- PUBLIC REQUEST API ------------------------------------------------
---------------------------------------------------------------------

-- Initialization / Launch / Attach / terminate ---------------------------------

---@param args loopdebug.proto.InitializeRequestArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.InitializeResponse|nil)|nil
function BaseSession:request_initialize(args, callback)
    self:_request("initialize", args, self:_wrap(callback))
end

---@param args loopdebug.proto.LaunchRequestArguments|nil
---@param callback fun(err: string|nil, body: any)|nil
function BaseSession:request_launch(args, callback)
    self:_request("launch", args, self:_wrap(callback))
end

---@param args loopdebug.proto.AttachRequestArguments|nil
---@param callback fun(err: string|nil, body: any)|nil
function BaseSession:request_attach(args, callback)
    self:_request("attach", args, self:_wrap(callback))
end

-- Disconnect / ConfigurationDone ------------------------------------

---@param args loopdebug.proto.DisconnectArguments|nil
---@param callback fun(err: string|nil, body: nil)|nil
function BaseSession:request_disconnect(args, callback)
    self:_request("disconnect", args or { restart = false }, self:_wrap(callback))
end

---@param callback fun(err: string|nil, body: nil)|nil
function BaseSession:request_configurationDone(callback)
    self:_request("configurationDone", nil, self:_wrap(callback))
end

---@param args loopdebug.proto.TerminateArguments|nil
---@param callback fun(err: string|nil, body: nil)|nil
function BaseSession:request_terminate(args, callback)
    self:_request("terminate", args, self:_wrap(callback))
end

-- Breakpoints --------------------------------------------------------

---@param args loopdebug.proto.SetBreakpointsArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.SetBreakpointsResponse|nil)|nil
function BaseSession:request_setBreakpoints(args, callback)
    self:_request("setBreakpoints", args, self:_wrap(callback))
end

---@param args loopdebug.proto.SetFunctionBreakpointsArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.SetFunctionBreakpointsResponse|nil)|nil
function BaseSession:request_setFunctionBreakpoints(args, callback)
    self:_request("setFunctionBreakpoints", args, self:_wrap(callback))
end

---@param args loopdebug.proto.SetExceptionBreakpointsArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.SetExceptionBreakpointsResponse|nil)|nil
function BaseSession:request_setExceptionBreakpoints(args, callback)
    self:_request("setExceptionBreakpoints", args, self:_wrap(callback))
end

-- Threads / StackTrace / Scopes / Variables --------------------------

---@param callback fun(err: string|nil, body: loopdebug.proto.ThreadsResponse|nil)|nil
function BaseSession:request_threads(callback)
    self:_request("threads", nil, self:_wrap(callback))
end

---@param args loopdebug.proto.StackTraceArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.StackTraceResponse|nil)|nil
function BaseSession:request_stackTrace(args, callback)
    self:_request("stackTrace", args, self:_wrap(callback))
end

---@param args loopdebug.proto.ScopesArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.ScopesResponse|nil)|nil
function BaseSession:request_scopes(args, callback)
    self:_request("scopes", args, self:_wrap(callback))
end

---@param args loopdebug.proto.VariablesArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.VariablesResponse|nil)|nil
function BaseSession:request_variables(args, callback)
    self:_request("variables", args, self:_wrap(callback))
end

-- Execution Control --------------------------------------------------

---@param args loopdebug.proto.ContinueArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.ContinueResponse|nil)|nil
function BaseSession:request_continue(args, callback)
    self:_request("continue", args, self:_wrap(callback))
end

---@param args loopdebug.proto.PauseArguments
---@param callback fun(err: string|nil, body: nil)|nil
function BaseSession:request_pause(args, callback)
    self:_request("pause", args, self:_wrap(callback))
end

---@param args loopdebug.proto.NextArguments
---@param callback fun(err: string|nil, body: nil)|nil
function BaseSession:request_next(args, callback)
    self:_request("next", args, self:_wrap(callback))
end

---@param args loopdebug.proto.StepInArguments
---@param callback fun(err: string|nil, body: nil)|nil
function BaseSession:request_stepIn(args, callback)
    self:_request("stepIn", args, self:_wrap(callback))
end

---@param args loopdebug.proto.StepOutArguments
---@param callback fun(err: string|nil, body: nil)|nil
function BaseSession:request_stepOut(args, callback)
    self:_request("stepOut", args, self:_wrap(callback))
end

---@param args loopdebug.proto.StepBackArguments
---@param callback fun(err: string|nil, body: nil)|nil
function BaseSession:request_stepBack(args, callback)
    self:_request("stepBack", args, self:_wrap(callback))
end

---@param args loopdebug.proto.ReverseContinueArguments
---@param callback fun(err: string|nil, body: nil)|nil
function BaseSession:request_reverseContinue(args, callback)
    self:_request("reverseContinue", args, self:_wrap(callback))
end

-- Evaluate / SetVariable / SetExpression ------------------------------

---@param args loopdebug.proto.EvaluateArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.EvaluateResponse|nil)|nil
function BaseSession:request_evaluate(args, callback)
    self:_request("evaluate", args, self:_wrap(callback))
end

---@param args loopdebug.proto.SetVariableArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.SetVariableResponse|nil)|nil
function BaseSession:request_setVariable(args, callback)
    self:_request("setVariable", args, self:_wrap(callback))
end

---@param args loopdebug.proto.SetExpressionArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.SetExpressionResponse|nil)|nil
function BaseSession:request_setExpression(args, callback)
    self:_request("setExpression", args, self:_wrap(callback))
end

-- LoadedSources / BreakpointLocations / ExceptionInfo ----------------

---@param args loopdebug.proto.LoadedSourcesArguments|nil
---@param callback fun(err: string|nil, body: loopdebug.proto.LoadedSourcesResponse|nil)|nil
function BaseSession:request_loadedSources(args, callback)
    self:_request("loadedSources", args, self:_wrap(callback))
end

---@param args loopdebug.proto.BreakpointLocationsArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.BreakpointLocationsResponse|nil)|nil
function BaseSession:request_breakpointLocations(args, callback)
    self:_request("breakpointLocations", args, self:_wrap(callback))
end

---@param args loopdebug.proto.ExceptionInfoArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.ExceptionInfoResponse|nil)|nil
function BaseSession:request_exceptionInfo(args, callback)
    self:_request("exceptionInfo", args, self:_wrap(callback))
end

-- Advanced Requests ---------------------------------------------------

---@param args loopdebug.proto.DataBreakpointInfoArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.DataBreakpointInfoResponse|nil)|nil
function BaseSession:request_dataBreakpointInfo(args, callback)
    self:_request("dataBreakpointInfo", args, self:_wrap(callback))
end

---@param args loopdebug.proto.SetDataBreakpointsArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.SetDataBreakpointsResponse|nil)|nil
function BaseSession:request_setDataBreakpoints(args, callback)
    self:_request("setDataBreakpoints", args, self:_wrap(callback))
end

---@param args loopdebug.proto.ReadMemoryArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.ReadMemoryResponse|nil)|nil
function BaseSession:request_readMemory(args, callback)
    self:_request("readMemory", args, self:_wrap(callback))
end

---@param args loopdebug.proto.WriteMemoryArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.WriteMemoryResponse|nil)|nil
function BaseSession:request_writeMemory(args, callback)
    self:_request("writeMemory", args, self:_wrap(callback))
end

---@param args loopdebug.proto.DisassembleArguments
---@param callback fun(err: string|nil, body: loopdebug.proto.DisassembleResponse|nil)|nil
function BaseSession:request_disassemble(args, callback)
    self:_request("disassemble", args, self:_wrap(callback))
end

---@param request string
---@param args any
---@param callback fun(err: string|nil, body: any)|nil
function BaseSession:request_custom(request, args, callback)
    self:_request(request, args, self:_wrap(callback))
end

return BaseSession

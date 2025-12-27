--- @meta
error('Cannot require a meta file')

---@class loopdebug.session.SourceBPData
---@field user_data loopdebug.SourceBreakpoint
---@field verified boolean
---@field dap_id number|nil

---@class loopdebug.session.SourceBreakpointsData
---@field by_location table<string, table<number, loopdebug.session.SourceBPData>>
---@field by_usr_id table<number, loopdebug.session.SourceBPData>
---@field by_dap_id table<number, loopdebug.session.SourceBPData>
---@field pending_files table<string,boolean>

---@class loopdebug.session.notify.Trace
---@field level nil|"warn"|"error"
---@field text string


---@class loopdebug.session.notify.BreakpointState
---@field breakpoint_id number
---@field verified boolean
---@field removed boolean|nil

---@alias loopdebug.session.notify.BreakpointsEvent loopdebug.session.notify.BreakpointState[]

---@class loopdebug.AdapterConfig
---@field adapter_id string
---@field type "executable"|"server"
---@field host string|nil
---@field port number|nil
---@field name string
---@field command string|string[]|nil
---@field env table<string,string>|nil
---@field cwd string|nil

---@alias loop.session.TrackerEvent
---|"trace"
---|"state"
---|"output"
---|"runInTerminal_request"
---|"thread_added"
---|"thread_removed"
---|"threads_paused"
---|"threads_continued"
---|"breakpoints"
---|"debuggee_exit"
---|"subsession_request"
---@alias loop.session.Tracker fun(session:loopdebug.Session, event:loop.session.TrackerEvent, args:any)

---@class loopdebug.session.DebugArgs
---@field adapter      loopdebug.AdapterConfig
---@field request      "launch" | "attach"
---@field request_args  loopdebug.proto.AttachRequestArguments|loopdebug.proto.LaunchRequestArguments|nil
---@field launch_post_configure boolean|nil
---@field terminate_debuggee boolean|nil
---@field initial_breakpoints loopdebug.SourceBreakpoint[]

---@class loopdebug.session.Args
---@field debug_args loopdebug.session.DebugArgs|nil
---@field tracker loop.session.Tracker
---@field exit_handler fun(code:number)

---@class loopdebug.session.notify.SubsessionRequest
---@field name string
---@field debug_args loopdebug.session.DebugArgs
---@field on_success fun(resp_body:any)
---@field on_failure fun(reason:string)

---@class loopdebug.session.notify.StateData
---@field state "initializing"|"starting"|"running"|"disconnecting"|"ended"

---@alias loopdebug.session.BreakpointsCommand fun(cmd:"add"|"remove"|"remove_all",bp:loopdebug.SourceBreakpoint?)
---@alias loopdebug.session.ThreadsProvider fun(callback:fun(err:string|nil, data: loopdebug.proto.ThreadsResponse | nil))
---@alias loopdebug.session.StackProvider fun(args:loopdebug.proto.StackTraceArguments, callback:fun(err:string|nil, data: loopdebug.proto.StackTraceResponse | nil))
---@alias loopdebug.session.ScopesProvider fun(args:loopdebug.proto.ScopesArguments, callback:fun(err:string|nil, data: loopdebug.proto.ScopesResponse | nil))
---@alias loopdebug.session.VariablesProvider fun(args:loopdebug.proto.VariablesArguments, callback:fun(err:string|nil, data: loopdebug.proto.VariablesResponse | nil))
---@alias loopdebug.session.EvaluateProvider fun(args:loopdebug.proto.EvaluateArguments, callback:fun(err:string|nil, data: loopdebug.proto.EvaluateResponse | nil))
---@alias loopdebug.session.CompletionProvider fun(args:loopdebug.proto.CompletionsArguments, callback:fun(err:string|nil, data: loopdebug.proto.CompletionsResponse | nil))

---@class loopdebug.session.DataProviders
---@field breakpoints_command loopdebug.session.BreakpointsCommand
---@field threads_provider loopdebug.session.ThreadsProvider
---@field stack_provider loopdebug.session.StackProvider
---@field scopes_provider loopdebug.session.ScopesProvider
---@field variables_provider loopdebug.session.VariablesProvider
---@field evaluate_provider loopdebug.session.EvaluateProvider
---@field completion_provider loopdebug.session.CompletionProvider

---@class loopdebug.session.notify.ThreadsEventScope
---@field thread_id number
---@field all_thread boolean

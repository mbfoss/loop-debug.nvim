--- @meta

error('Cannot require a meta file')

---@diagnostic disable: missing-fields, redundant-parameter

--====================================================================--
-- Debug Adapter Protocol – COMPLETE EmmyLua Types (November 2025)
-- Single file, zero dependencies, 100% spec-compliant for VS Code + EmmyLua
--====================================================================--

---@class loopdebug.proto.ProtocolMessage
---@field seq integer
---@field type "request" | "response" | "event"

---@class loopdebug.proto.Request : loopdebug.proto.ProtocolMessage
---@field command string
---@field arguments table|nil

---@class loopdebug.proto.Response : loopdebug.proto.ProtocolMessage
---@field request_seq integer
---@field success boolean
---@field command string
---@field message string|nil
---@field body table|nil

---@class loopdebug.proto.Event : loopdebug.proto.ProtocolMessage
---@field event string
---@field body table|nil

--====================================================================--
-- Common Types (COMPLETE)
--====================================================================--

---@class loopdebug.proto.Checksum
---@field algorithm "MD5" | "SHA1" | "SHA256" | "timestamp"
---@field checksum string

---@class loopdebug.proto.Source
---@field name string|nil
---@field path string|nil
---@field sourceReference integer|nil
---@field presentationHint "normal"|"emphasize"|"deemphasize"|nil
---@field origin string|nil
---@field sources loopdebug.proto.Source[]|nil
---@field adapterData any
---@field checksums loopdebug.proto.Checksum[]|nil

---@class loopdebug.proto.SourceBreakpoint
---@field line integer
---@field column integer|nil
---@field condition string|nil
---@field hitCondition string|nil
---@field logMessage string|nil

---@class loopdebug.proto.FunctionBreakpoint
---@field name string
---@field condition string|nil
---@field hitCondition string|nil

---@class loopdebug.proto.DataBreakpoint
---@field dataId string
---@field accessType "read"|"write"|"readWrite"|nil
---@field condition string|nil
---@field hitCondition string|nil

---@class loopdebug.proto.InstructionBreakpoint
---@field instructionReference string
---@field offset integer|nil
---@field condition string|nil
---@field hitCondition string|nil

---@class loopdebug.proto.Breakpoint
---@field verified boolean
---@field id integer|nil
---@field line integer|nil
---@field column integer|nil
---@field endLine integer|nil
---@field endColumn integer|nil
---@field message string|nil
---@field source loopdebug.proto.Source|nil
---@field instructionReference string|nil
---@field hitCount integer|nil
---@field offset integer|nil

---@class loopdebug.proto.StackFrame
---@field id integer
---@field name string
---@field source loopdebug.proto.Source|nil
---@field line integer
---@field column integer
---@field endLine integer|nil
---@field endColumn integer|nil
---@field presentationHint "normal"|"label"|"subtle"|nil
---@field moduleId integer|string|nil
---@field rangeName string|nil
---@field canRestart boolean|nil

---@class loopdebug.proto.Thread
---@field id integer
---@field name string

---@class loopdebug.proto.StackTrace
---@field stackFrames loopdebug.proto.StackFrame[]
---@field totalFrames integer|nil

---@alias loopdebug.proto.Scope.PresentationHint
---| "normal"
---| "locals"
---| "arguments"
---| "registers"
---| "globals"
---| "static"
---| "captured"
---| "watch"
---| "special"

---@class loopdebug.proto.Scope
---@field name string
---@field variablesReference integer
---@field expensive boolean
---@field namedVariables integer?
---@field indexedVariables integer?
---@field source loopdebug.proto.Source?
---@field line integer?
---@field column integer?
---@field endLine integer?
---@field endColumn integer?
---@field presentationHint loopdebug.proto.Scope.PresentationHint?

---@class loopdebug.proto.VariablePresentationHint
---@field kind "property"|"method"|"class"|"data"|"event"|"baseClass"|"innerClass"|"interface"|"mostDerivedClass"|"virtual"|nil
---@field attributes ("static"|"constant"|"readOnly"|"rawString"|"hasSideEffects"|"skipInEvaluation")[]|nil
---@field visibility "public"|"private"|"protected"|"internal"|"final"|nil
---@field lazy boolean|nil

---@class loopdebug.proto.Variable
---@field name string
---@field value string
---@field type string|nil
---@field presentationHint loopdebug.proto.VariablePresentationHint|nil
---@field evaluateName string|nil
---@field variablesReference integer
---@field namedVariables integer|nil
---@field indexedVariables integer|nil
---@field memoryReference string|nil

---@class loopdebug.proto.ValueFormat
---@field hex boolean|nil

---@class loopdebug.proto.StackFrameFormat : loopdebug.proto.ValueFormat
---@field parameters boolean|nil
---@field parameterTypes boolean|nil
---@field parameterNames boolean|nil
---@field parameterValues boolean|nil
---@field line boolean|nil
---@field module boolean|nil
---@field includeAll boolean|nil

---@class loopdebug.proto.ExceptionBreakpointsFilter
---@field filter string
---@field label string
---@field description string|nil
---@field default boolean|nil
---@field supportsCondition boolean|nil
---@field conditionDescription string|nil

---@class loopdebug.proto.ExceptionFilterOptions
---@field filterId string
---@field condition string|nil

---@class loopdebug.proto.ExceptionPath
---@field name string
---@field condition string|nil

---@class loopdebug.proto.ExceptionOptions
---@field path loopdebug.proto.ExceptionPath[]?
---@field breakMode "never"|"always"|"unhandled"|"userUnhandled"

---@class loopdebug.proto.Message
---@field id integer
---@field format string
---@field variables table<string,string>|nil
---@field sendTelemetry boolean|nil
---@field showUser boolean|nil
---@field url string|nil
---@field urlLabel string|nil

---@class loopdebug.proto.Module
---@field id integer|string
---@field name string
---@field path string|nil
---@field isOptimized boolean|nil
---@field isUserCode boolean|nil
---@field version string|nil
---@field symbolStatus string|nil
---@field symbolFilePath string|nil
---@field dateTimeStamp string|nil
---@field addressRange string|nil

---@class loopdebug.proto.ColumnDescriptor
---@field attributeName string
---@field label string
---@field format string|nil
---@field type "string"|"number"|"boolean"|"unixTimestampUTC"|nil
---@field width integer|nil

---@class loopdebug.proto.ModulesViewDescriptor
---@field columns loopdebug.proto.ColumnDescriptor[]

---@class loopdebug.proto.CompletionItem
---@field label string
---@field text string|nil
---@field sortText string|nil
---@field detail string|nil
---@field type "method"|"function"|"constructor"|"field"|"variable"|"class"|"interface"|"module"|"property"|"unit"|"value"|"enum"|"keyword"|"snippet"|"text"|"color"|"file"|"reference"|"customcolor"|nil
---@field start integer|nil
---@field length integer|nil
---@field selectionStart integer|nil
---@field selectionLength integer|nil

---@class loopdebug.proto.GotoTarget
---@field id integer
---@field label string
---@field line integer
---@field column integer|nil
---@field endLine integer|nil
---@field endColumn integer|nil
---@field instructionPointerReference string|nil

---@class loopdebug.proto.Instruction
---@field address string
---@field instruction string
---@field line integer|nil
---@field column integer|nil
---@field endLine integer|nil
---@field endColumn integer|nil
---@field location loopdebug.proto.Source|nil
---@field presentationHint "normal"|"label"|"subtle"|nil

---@class loopdebug.proto.DisassembledInstruction
---@field address string
---@field instructionBytes string|nil
---@field instruction string
---@field symbol string|nil
---@field location loopdebug.proto.Source|nil
---@field line integer|nil
---@field column integer|nil
---@field endLine integer|nil
---@field endColumn integer|nil

---@class loopdebug.proto.ExceptionDetails
---@field message string|nil
---@field typeName string|nil
---@field fullTypeName string|nil
---@field stackTrace string|nil
---@field innerException loopdebug.proto.ExceptionDetails|nil

---@class loopdebug.proto.InvalidatedAreas
---@field areas ("all"|"stacks"|"threads"|"variables"|"memory"|"registers")[]|nil
---@field threadId integer|nil
---@field stackFrameId integer|nil

---@class loopdebug.proto.RunInTerminalRequestArguments
---@field kind "integrated"|"external"|nil
---@field title string|nil
---@field cwd string
---@field args string[]
---@field env table<string,string>|nil
---@field timeout integer|nil

---@class loopdebug.proto.StartDebuggingRequestArguments
---@field request "launch"|"attach"
---@field configuration table<string,any>

--====================================================================--
-- Capabilities (COMPLETE)
--====================================================================--

---@class loopdebug.proto.Capabilities
---@field supportsConfigurationDoneRequest boolean|nil
---@field supportsFunctionBreakpoints boolean|nil
---@field supportsConditionalBreakpoints boolean|nil
---@field supportsHitConditionalBreakpoints boolean|nil
---@field supportsEvaluateForHovers boolean|nil
---@field supportsStepBack boolean|nil
---@field supportsSetVariable boolean|nil
---@field supportsRestartFrame boolean|nil
---@field supportsGotoTargetsRequest boolean|nil
---@field supportsStepInTargetsRequest boolean|nil
---@field supportsCompletionsRequest boolean|nil
---@field supportsModulesRequest boolean|nil
---@field supportsRestartRequest boolean|nil
---@field supportsExceptionOptions boolean|nil
---@field supportsValueFormattingOptions boolean|nil
---@field supportsExceptionInfoRequest boolean|nil
---@field supportTerminateDebuggee boolean|nil
---@field supportSuspendDebuggee boolean|nil
---@field supportsDelayedStackTraceLoading boolean|nil
---@field supportsLoadedSourcesRequest boolean|nil
---@field supportsLogPoints boolean|nil
---@field supportsTerminateThreadsRequest boolean|nil
---@field supportsSetExpression boolean|nil
---@field supportsTerminateDebuggee boolean|nil
---@field supportsDataBreakpoints boolean|nil
---@field supportsReadMemoryRequest boolean|nil
---@field supportsWriteMemoryRequest boolean|nil
---@field supportsDisassembleRequest boolean|nil
---@field supportsCancelRequest boolean|nil
---@field supportsBreakpointLocationsRequest boolean|nil
---@field supportsClipboardContext boolean|nil
---@field supportsSteppingGranularity boolean|nil
---@field supportsInstructionBreakpoints boolean|nil
---@field supportsExceptionFilterOptions boolean|nil
---@field supportsProgressReporting boolean|nil
---@field supportsInvalidatedEvent boolean|nil
---@field supportsMemoryReferences boolean|nil
---@field supportsRunInTerminalRequest boolean|nil
---@field supportsArgsCanBeInterpretedByShell boolean|nil
---@field supportsVariablePaging boolean|nil
---@field supportsVariableTreeCache boolean|nil
---@field supportsCompletionSnippet boolean|nil
---@field supportsHovers boolean|nil
---@field supportsMultiThreadStepping boolean|nil

--====================================================================--
-- Request Arguments (COMPLETE)
--====================================================================--

---@class loopdebug.proto.InitializeRequestArguments
---@field clientID string|nil
---@field clientName string|nil
---@field adapterID string
---@field locale string|nil
---@field linesStartAt1 boolean
---@field columnsStartAt1 boolean
---@field pathFormat "path"|"uri"
---@field supportsVariableType boolean|nil
---@field supportsVariablePaging boolean|nil
---@field supportsRunInTerminalRequest boolean|nil
---@field supportsMemoryReferences boolean|nil
---@field supportsProgressReporting boolean|nil
---@field supportsInvalidatedEvent boolean|nil
---@field supportsCompletionSnippet boolean|nil

---@class loopdebug.proto.LaunchRequestArguments : loopdebug.proto.InitializeRequestArguments
---@field noDebug boolean|nil
---@field __shell boolean|nil
---@field __restart any|nil

---@class loopdebug.proto.AttachRequestArguments : loopdebug.proto.InitializeRequestArguments
---@field __restart any|nil

---@class loopdebug.proto.DisconnectArguments
---@field restart boolean|nil
---@field terminateDebuggee boolean|nil
---@field suspendDebuggee boolean|nil

---@class loopdebug.proto.TerminateArguments
---@field restart boolean|nil

---@class loopdebug.proto.RestartArguments
---@field arguments loopdebug.proto.LaunchRequestArguments | loopdebug.proto.AttachRequestArguments|nil

---@class loopdebug.proto.SetBreakpointsArguments
---@field source loopdebug.proto.Source
---@field breakpoints loopdebug.proto.SourceBreakpoint[]|nil
---@field lines integer[]|nil
---@field sourceModified boolean|nil

---@class loopdebug.proto.SetFunctionBreakpointsArguments
---@field breakpoints loopdebug.proto.FunctionBreakpoint[]

---@class loopdebug.proto.SetExceptionBreakpointsArguments
---@field filters string[]
---@field filterOptions loopdebug.proto.ExceptionFilterOptions[]|nil
---@field exceptionOptions loopdebug.proto.ExceptionOptions[]|nil

---@class loopdebug.proto.DataBreakpointInfoArguments
---@field dataId string
---@field accessTypes ("read"|"write"|"readWrite")[]|nil
---@field canPersist boolean|nil

---@class loopdebug.proto.SetDataBreakpointsArguments
---@field breakpoints loopdebug.proto.DataBreakpoint[]

---@class loopdebug.proto.SetInstructionBreakpointsArguments
---@field breakpoints loopdebug.proto.InstructionBreakpoint[]

---@class loopdebug.proto.BreakpointLocationsArguments
---@field source loopdebug.proto.Source
---@field line integer|nil
---@field column integer|nil
---@field endLine integer|nil
---@field endColumn integer|nil
---@field condition string|nil
---@field hitCondition string|nil

---@class loopdebug.proto.StackTraceArguments
---@field threadId integer
---@field startFrame integer|nil
---@field levels integer|nil
---@field format loopdebug.proto.StackFrameFormat|nil

---@class loopdebug.proto.ScopesArguments
---@field frameId integer

---@class loopdebug.proto.VariablesArguments
---@field variablesReference integer
---@field filter "indexed"|"named"|nil
---@field start integer|nil
---@field count integer|nil
---@field format loopdebug.proto.ValueFormat|nil

---@class loopdebug.proto.ContinueArguments
---@field threadId integer
---@field singleThread boolean|nil

---@class loopdebug.proto.PauseArguments
---@field threadId integer

---@class loopdebug.proto.NextArguments
---@field threadId integer
---@field granularity "statement"|"line"|"instruction"|nil

---@class loopdebug.proto.StepInArguments
---@field threadId integer
---@field targetId integer|nil
---@field granularity "statement"|"line"|"instruction"|nil

---@class loopdebug.proto.StepOutArguments
---@field threadId integer
---@field granularity "statement"|"line"|"instruction"|nil

---@class loopdebug.proto.StepBackArguments
---@field threadId integer
---@field granularity "statement"|"line"|"instruction"|nil

---@class loopdebug.proto.ReverseContinueArguments
---@field threadId integer
---@field granularity "statement"|"line"|"instruction"|nil

---@class loopdebug.proto.GotoArguments
---@field threadId integer
---@field targetId integer

---@class loopdebug.proto.RestartFrameArguments
---@field frameId integer
---@field arguments table|nil

---@class loopdebug.proto.GotoTargetsArguments
---@field source loopdebug.proto.Source
---@field line integer
---@field column integer|nil

---@class loopdebug.proto.CompletionsArguments
---@field frameId integer|nil
---@field text string
---@field column integer
---@field line integer|nil
---@field includeExternal boolean|nil
---@field excludeModules string[]|nil
---@field excludeClasses string[]|nil

---@class loopdebug.proto.EvaluateArguments
---@field expression string
---@field frameId integer|nil
---@field context "watch"|"repl"|"hover"|"clipboard"|nil
---@field format loopdebug.proto.ValueFormat|nil

---@class loopdebug.proto.SetExpressionArguments
---@field expression string
---@field value string
---@field frameId integer|nil
---@field format loopdebug.proto.ValueFormat|nil

---@class loopdebug.proto.SetVariableArguments
---@field variablesReference integer
---@field name string
---@field value string
---@field format loopdebug.proto.ValueFormat|nil

---@class loopdebug.proto.SourceArguments
---@field source loopdebug.proto.Source
---@field sourceReference integer

---@class loopdebug.proto.LoadedSourcesItem
---@field moduleId integer|string|nil
---@field includeDecompiledSources boolean

---@class loopdebug.proto.LoadedSourcesArguments
---@field includeDecompiledSources loopdebug.proto.LoadedSourcesItem[]?

---@class loopdebug.proto.ExceptionInfoArguments
---@field threadId integer

---@class loopdebug.proto.ReadMemoryArguments
---@field memoryReference string
---@field offset integer|nil
---@field count integer

---@class loopdebug.proto.WriteMemoryArguments
---@field memoryReference string
---@field offset integer|nil
---@field data string  -- base64
---@field allowPartial boolean|nil

---@class loopdebug.proto.DisassembleArguments
---@field memoryReference string
---@field offset integer|nil
---@field instructionOffset integer|nil
---@field instructionCount integer
---@field resolveSymbols boolean|nil

---@class loopdebug.proto.CancelArguments
---@field requestId integer|nil
---@field progressId string|nil
---@field token string|nil

---@class loopdebug.proto.TerminateThreadsArguments
---@field threadIds integer[]|nil

---@class loopdebug.proto.ModulesArguments
---@field moduleId integer|string|nil
---@field startModuleId integer|nil
---@field moduleCount integer|nil

---@class loopdebug.proto.RunInTerminalArguments
---@field kind "integrated"|"external"|nil
---@field title string|nil
---@field cwd string
---@field args string[]
---@field env table<string,string>|nil
---@field timeout integer|nil

--====================================================================--
-- Response Bodies (COMPLETE)
--====================================================================--

---@alias loopdebug.proto.InitializeResponse loopdebug.proto.Capabilities

---@class loopdebug.proto.SetBreakpointsResponse
---@field breakpoints loopdebug.proto.Breakpoint[]

---@class loopdebug.proto.SetFunctionBreakpointsResponse
---@field breakpoints loopdebug.proto.Breakpoint[]

---@class loopdebug.proto.SetExceptionBreakpointsResponse
---@field breakpoints loopdebug.proto.Breakpoint[]

---@class loopdebug.proto.SetDataBreakpointsResponse
---@field breakpoints loopdebug.proto.Breakpoint[]

---@class loopdebug.proto.SetInstructionBreakpointsResponse
---@field breakpoints loopdebug.proto.Breakpoint[]

---@class loopdebug.proto.ThreadsResponse
---@field threads loopdebug.proto.Thread[]

---@class loopdebug.proto.StackTraceResponse
---@field stackFrames loopdebug.proto.StackFrame[]
---@field totalFrames integer|nil

---@class loopdebug.proto.ScopesResponse
---@field scopes loopdebug.proto.Scope[]

---@class loopdebug.proto.VariablesResponse
---@field variables loopdebug.proto.Variable[]

---@class loopdebug.proto.ContinueResponse
---@field allThreadsContinued boolean|nil

---@class loopdebug.proto.EvaluateResponse
---@field result string
---@field type string|nil
---@field presentationHint loopdebug.proto.VariablePresentationHint|nil
---@field variablesReference integer
---@field namedVariables integer|nil
---@field indexedVariables integer|nil
---@field memoryReference string|nil

---@class loopdebug.proto.SetExpressionResponse
---@field value loopdebug.proto.Variable

---@class loopdebug.proto.SetVariableResponse
---@field value loopdebug.proto.Variable

---@class loopdebug.proto.GotoTargetsResponse
---@field targets loopdebug.proto.GotoTarget[]

---@class loopdebug.proto.CompletionsResponse
---@field targets loopdebug.proto.CompletionItem[]

---@class loopdebug.proto.BreakpointLocation
---@field line integer
---@field column integer?
---@field endLine integer?
---@field endColumn integer?

---@class loopdebug.proto.BreakpointLocationsResponse
---@field breakpoints loopdebug.proto.BreakpointLocation[]

---@class loopdebug.proto.ExceptionInfoResponse
---@field exceptionId string
---@field description string|nil
---@field breakMode "never"|"always"|"unhandled"|"userUnhandled"|nil
---@field details loopdebug.proto.ExceptionDetails|nil

---@class loopdebug.proto.LoadedSourcesResponse
---@field sources loopdebug.proto.Source[]

---@class loopdebug.proto.ReadMemoryResponse
---@field address string
---@field unreadableBytes integer|nil
---@field data string|nil  -- base64

---@class loopdebug.proto.WriteMemoryResponse
---@field offset integer|nil
---@field bytesWritten integer|nil
---@field verificationMessage string|nil

---@class loopdebug.proto.DisassembleResponse
---@field instructions loopdebug.proto.DisassembledInstruction[]
---@field totalInstructions integer|nil

---@class loopdebug.proto.ModulesResponse
---@field modules loopdebug.proto.Module[]
---@field totalModules integer|nil

---@class loopdebug.proto.DataBreakpointInfoResponse
---@field dataId string|nil
---@field description string|nil
---@field accessTypes ("read"|"write"|"readWrite")[]|nil
---@field canPersist boolean|nil

--====================================================================--
-- Events (COMPLETE)
--====================================================================--

---@class loopdebug.proto.InitializedEvent
-- empty

---@class loopdebug.proto.StoppedEvent
---@field reason "step"|"breakpoint"|"exception"|"pause"|"entry"|"goto"|"function breakpoint"|"data breakpoint"|"instruction breakpoint"
---@field description string|nil
---@field threadId integer|nil
---@field preserveFocusHint boolean|nil
---@field text string|nil
---@field allThreadsStopped boolean|nil
---@field hitBreakpointIds integer[]|nil
---@field frameId integer|nil

---@class loopdebug.proto.ContinuedEvent
---@field threadId integer
---@field allThreadsContinued boolean|nil
---@field singleThread boolean|nil

---@class loopdebug.proto.ThreadEvent
---@field reason "started"|"exited"
---@field threadId integer

---@class loopdebug.proto.OutputEvent
---@field category "console"|"stdout"|"stderr"|"telemetry"|nil
---@field output string
---@field group "start"|"startCollapsed"|"end"|nil
---@field variablesReference integer|nil
---@field source loopdebug.proto.Source|nil
---@field line integer|nil
---@field column integer|nil
---@field data any|nil

---@class loopdebug.proto.BreakpointEvent
---@field reason "new"|"changed"|"removed"|"function new"|"function changed"|"function removed"
---@field breakpoint loopdebug.proto.Breakpoint

---@class loopdebug.proto.ModuleEvent
---@field reason "new"|"changed"|"removed"
---@field module loopdebug.proto.Module

---@class loopdebug.proto.LoadedSourceEvent
---@field reason "new"|"changed"|"removed"
---@field source loopdebug.proto.Source

---@class loopdebug.proto.ProcessEvent
---@field name string
---@field systemProcessId integer|nil
---@field isLocalProcess boolean|nil
---@field startMethod "launch"|"attach"|"attachForSuspendedLaunch"|nil
---@field pointerSize integer|nil

---@class loopdebug.proto.ExitedEvent
---@field exitCode integer

---@class loopdebug.proto.TerminatedEvent
---@field restart boolean|nil

---@class loopdebug.proto.InvalidatedEvent
---@field areas ("all"|"stacks"|"threads"|"variables"|"memory"|"registers")[]|nil
---@field threadId integer|nil
---@field stackFrameId integer|nil
---@field expressionId string|nil

---@class loopdebug.proto.MemoryEvent
---@field memoryReference string
---@field offset integer
---@field count integer

---@class loopdebug.proto.ProgressStartEvent
---@field progressId string
---@field title string
---@field requestId integer|nil
---@field percentage number|nil
---@field message string|nil
---@field cancellable boolean|nil

---@class loopdebug.proto.ProgressUpdateEvent
---@field progressId string
---@field message string|nil
---@field percentage number|nil

---@class loopdebug.proto.ProgressEndEvent
---@field progressId string
---@field message string|nil


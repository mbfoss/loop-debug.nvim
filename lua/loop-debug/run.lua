local M = {}

local DebugJob = require('loop-debug.DebugJob')
local debugui = require('loop-debug.ui.debugui')
local bpts_ui = require('loop-debug.ui.bpts_ui')

---@param args loop.DebugJob.StartArgs
---@param page_manager loop.PageManager
---@param startup_callback fun(job: loop.job.DebugJob|nil, err: string|nil)
---@param output_handler fun(stream: "stdout"|"stderr", data: string[])|nil
---@param exit_handler fun(code: number)
local function _start_debug_job(args, page_manager, startup_callback, output_handler, exit_handler)
    -- Final DAP type validation
    if args.debug_args.adapter.type ~= "executable" and args.debug_args.adapter.type ~= "server" then
        return startup_callback(nil,
            ("invalid adapter type '%s' — must be 'executable' or 'server'"):format(tostring(args.debug_args
                .adapter
                .type)))
    end

    --notifications.notify("Starting job:\n" .. vim.inspect(start_args))
    local job = DebugJob:new(args.name)

    -- Add trackers
    job:add_tracker(debugui.track_new_debugjob(args.name, page_manager))
    job:add_tracker(bpts_ui.track_new_debugjob(args.name))
    job:add_tracker({ on_exit = exit_handler })

    if output_handler then
        job:add_tracker({ on_stdout = function(data) output_handler("stdout", data) end })
        job:add_tracker({ on_stderr = function(data) output_handler("stderr", data) end })
    end

    -- Start the debug job
    local ok, err = job:start(args)
    if not ok then
        return startup_callback(nil, err or "failed to start debug job")
    end

    -- Success!
    startup_callback(job, nil)
end


---@type fun(task:loopdebug.Task,page_manager:loop.PageManager, on_exit:loop.TaskExitHandler):(loop.TaskControl|nil,string|nil)
function M.start_debug_task(task, page_manager, on_exit)

    -- Early validation
    if not task or type(task) ~= "table" then
        return nil, "task is required and must be a table"
    end
    if task.type ~= "debug" then
        return nil, "task.type must be 'debug'"
    end
    if task.request ~= "launch" and task.request ~= "attach" then
        return nil, "task.request must be 'launch' or 'attach'"
    end

    ---@type loopdebug.Config.Debugger
    local debugger = config.current.debuggers[task.type]
    if not debugger then
        return nil, "no debugger config found for '%s'"):format(tostring(debugger)
    end

    ---- debug adapter config ---
    ---@type loopdebug.AdapterConfig
    local adapter_config
    if type(debugger.adapter_config) == "function" then
        ---@type loop.TaskContext
        local task_context = {
            task = task,
            proj_dir = projinfo.get_proj_dir()
        }
        ---@type loopdebug.AdapterConfig
        adapter_config = debugger.adapter_config(task_context)
    else
        ---@type loopdebug.AdapterConfig
        ---@diagnostic disable-next-line: assign-type-mismatch, param-type-mismatch
        adapter_config = vim.deepcopy(debugger.adapter_config)
    end

    adapter_config.cwd = adapter_config.cwd or projinfo.get_proj_dir()
    if not adapter_config.cwd then
        return startup_callback(nil, "'cwd' is missing in task config")
    end

    -- request config
    local request_args
    if task.request == "launch" then
        request_args = debugger.launch_args or {}
    else
        request_args = debugger.attach_args or {}
    end

    if type(request_args) == "function" then
        ---@type loop.TaskContext
        local task_context = {
            task = task,
            proj_dir = projinfo.get_proj_dir()
        }
        request_args = request_args(task_context)
    else
        request_args = vim.deepcopy(request_args)
    end

    -- job args
    ---@type loop.DebugJob.StartArgs
    local start_args = {
        name = task.name,
        debug_args = {
            adapter = adapter_config,
            request = task.request,
            request_args = request_args,
            terminate_debuggee = task.terminateOnDisconnect
        },
    }

    ---@type loop.Config.Debugger.HookContext
    local hook_context = {
        task = task,
        proj_dir = projinfo.get_proj_dir(),
        adapter_config = adapter_config,
        page_manager = page_manager,
        user_data = {}
    }

    local start_job = function()
        local on_exit = function(code)
            if debugger.end_hook then
                hook_context.exit_code = code
                debugger.end_hook(hook_context, fntools.called_once(function()
                    exit_handler(code)
                end))
            else
                exit_handler(code)
            end
        end
        _start_debug_job(start_args, page_manager, startup_callback, output_handler, on_exit)
    end

    if debugger.start_hook then
        debugger.start_hook(hook_context, fntools.called_once(function(ok, err)
            if ok then
                start_job()
            else
                startup_callback(nil, err or "start_hook error")
            end
        end))
    else
        start_job()
    end
end

return M

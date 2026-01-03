local M = {}

local config = require('loop-debug.config')
local DebugJob = require('loop-debug.DebugJob')
local manager = require('loop-debug.manager')
local breakpoints = require('loop-debug.breakpoints')
local wsinfo = require('loop.wsinfo')
local fntools = require('loop.tools.fntools')
local logs = require('loop.logs')

---@param args loop.DebugJob.StartArgs
---@param page_manager loop.PageManager
---@param startup_callback fun(job: loop.job.DebugJob|nil, err: string|nil)
---@param exit_handler fun(code: number)
local function _start_debug_job(args, page_manager, startup_callback, exit_handler)
    -- Final DAP type validation
    if args.debug_args.adapter.type ~= "executable" and args.debug_args.adapter.type ~= "server" then
        return startup_callback(nil,
            ("invalid adapter type '%s' — must be 'executable' or 'server'"):format(tostring(args.debug_args
                .adapter
                .type)))
    end

    logs.log("Starting debug job:\n" .. vim.inspect(args))
    local job = DebugJob:new(args.name)

    local bpts_tracker_ref = breakpoints.add_tracker({
        on_added = function(bp) job:add_breakpoint(bp) end,
        on_removed = function(bp) job:remove_breakpoint(bp) end,
        on_all_removed = function(bpts) job:remove_all_breakpoints(bpts) end
    })

    -- Add trackers
    job:add_tracker(manager.track_new_debugjob(args.name, page_manager))
    job:add_tracker({ on_exit = exit_handler })
    job:add_tracker({ on_exit = function() bpts_tracker_ref:cancel() end })

    -- Start the debug job
    local ok, err = job:start(args)
    if not ok then
        return startup_callback(nil, err or "failed to start debug job")
    end

    require('loop-debug.ui').show()

    -- Success!
    startup_callback(job, nil)
end


---@type fun(task:loopdebug.Task,page_manager:loop.PageManager, on_exit:loop.TaskExitHandler):(loop.TaskControl|nil,string|nil)
function M.start_debug_task(task, page_manager, on_exit)
    -- Early validation
    if not task or type(task) ~= "table" then
        return nil, "task is required and must be a table"
    end
    if not task.name or type(task.name) ~= "string" or #task.name == 0 then
        return nil, "task.name must be a non-empty string"
    end
    if task.type ~= "debug" then
        return nil, "task.type must be 'debug'"
    end
    if task.request ~= "launch" and task.request ~= "attach" then
        return nil, "task.request must be 'launch' or 'attach'"
    end

    ---@type loopdebug.Config.Debugger
    local debugger = config.current.debuggers[task.debugger]
    if not debugger then
        return nil, ("no debugger config found for task.debugger '%s'"):format(tostring(task.debugger))
    end

    local ws_dir = wsinfo.get_ws_dir()
    if not ws_dir then
        return nil, "failed to read workspace dir"
    end

    ---- debug adapter config ---
    ---@type loopdebug.AdapterConfig
    local adapter_config
    if type(debugger.adapter_config) == "function" then
        ---@type loopdebug.TaskContext
        local task_context = {
            task = task,
            ws_dir = ws_dir
        }
        ---@type loopdebug.AdapterConfig
        adapter_config = debugger.adapter_config(task_context)
        if type(adapter_config) ~= "table" then
            return nil, "debugger.adapter_config function must return a table"
        end
    else
        -- deep copy because a badly coded hook may change the config
        ---@type loopdebug.AdapterConfig
        ---@diagnostic disable-next-line: assign-type-mismatch, param-type-mismatch
        adapter_config = vim.deepcopy(debugger.adapter_config)
    end

    adapter_config.cwd = adapter_config.cwd or ws_dir
    if not adapter_config.cwd then
        return nil, "'cwd' is missing in task config"
    end

    -- request config
    local request_args
    if task.request == "launch" then
        request_args = debugger.launch_args or {}
    else
        request_args = debugger.attach_args or {}
    end

    if type(request_args) == "function" then
        ---@type loopdebug.TaskContext
        local task_context = {
            task = task,
            ws_dir = ws_dir
        }
        request_args = request_args(task_context)
        if type(request_args) ~= "table" then
            return nil, "debugger.request_args function must return a table"
        end
    else
        -- deep copy because a badly coded hook may change the args
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
            terminate_debuggee = task.terminateOnDisconnect,
        },
    }

    ---@type loopdebug.Config.Debugger.HookContext
    local hook_context = {
        task = task,
        ws_dir = ws_dir,
        adapter_config = adapter_config,
        page_manager = page_manager,
        user_data = {}
    }

    local task_control_context = {
        job = nil,
        disable_control = false,
        termination_requested = false,
    }

    local start_job = function()
        ---@type fun(job: loop.job.DebugJob|nil, err: string|nil)
        local function on_job_start(job, err)
            if not job then
                task_control_context.disable_control = true
                on_exit(false, err or "initialization error")
            elseif task_control_context.termination_requested then
                if job:is_running() then
                    job:terminate()
                else
                    task_control_context.disable_control = true
                    on_exit(false, "task terminated before startup completed")
                end
            else
                task_control_context.job = job
            end
        end
        local on_job_exit = function(code)
            if debugger.end_hook then
                hook_context.exit_code = code
                debugger.end_hook(hook_context, fntools.called_once(function()
                    task_control_context.disable_control = true
                    on_exit(code == 0, "Exit code: " .. tostring(code))
                end))
            else
                task_control_context.disable_control = true
                on_exit(code == 0, "Exit code: " .. tostring(code))
            end
        end
        _start_debug_job(start_args, page_manager, on_job_start, on_job_exit)
    end

    if debugger.start_hook then
        debugger.start_hook(hook_context, fntools.called_once(function(ok, err)
            if ok then
                start_job()
            else
                task_control_context.disable_control = true
                on_exit(false, err or "start_hook error")
            end
        end))
    else
        start_job()
    end

    ---@type loop.TaskControl
    local task_control = {
        terminate = function()
            if task_control_context.disable_control then
                return
            end
            task_control_context.termination_requested = true
            if task_control_context.job then
                task_control_context.job:terminate()
            end
        end
    }
    return task_control
end

return M

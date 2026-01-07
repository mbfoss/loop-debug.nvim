local strtools = require('loop.tools.strtools')

---@class loopdebug.TaskContext
---@field task loopdebug.Task
---@field ws_dir string

---@param task loopdebug.Task
local function get_task_program(task)
    if task.program then return task.program end
    local cmdparts = strtools.cmd_to_string_array(task.command or "")
    return cmdparts[1]
end

---@param task loopdebug.Task
local function get_task_args(task)
    if task.args then return task.args end
    local cmdparts = strtools.cmd_to_string_array(task.command or "")
    local unpack_func = table.unpack or unpack
    return { unpack_func(cmdparts, 2) }
end

---@class loopdebug.Config.Debugger.HookContext
---@field task loopdebug.Task
---@field ws_dir string
---@field adapter_config loopdebug.AdapterConfig
---@field page_manager loop.PageManager
---@field exit_code number|nil
---@field user_data any

---@class loopdebug.Config.Debugger
---@field adapter_config loopdebug.AdapterConfig|fun(ctx:loopdebug.TaskContext):loopdebug.AdapterConfig
---@field launch_args nil|table|fun(ctx:loopdebug.TaskContext):table
---@field attach_args nil|table|fun(ctx:loopdebug.TaskContext):table
---@field terminate_debuggee nil|boolean|fun(ctx:loopdebug.TaskContext):boolean
---@field launch_post_configure nil|boolean|nil|fun(ctx:loopdebug.TaskContext):boolean
---@field start_hook nil|fun(ctx:loopdebug.Config.Debugger.HookContext,cb:fun(ok:boolean,err:string|nil))
---@field end_hook nil|fun(ctx:loopdebug.Config.Debugger.HookContext,cb:fun())

---@param context loopdebug.TaskContext
local function _get_task_cwd(context)
    local task = context.task
    return (task and task.cwd) or context.ws_dir
end

local function mason_bin(name)
    local ok, mason_registry = pcall(require, "mason-registry")
    if not ok then return name end

    local pkg_ok, pkg = pcall(mason_registry.get_package, name)
    if not (pkg_ok and pkg:is_installed()) then
        return name
    end

    -- Verified: pkg.spec.install_path is the raw string path
    -- where the package is located.
    local path = pkg.spec.install_path
    if not path then return name end

    local possible_bins = {
        -- Specific to codelldb (VS Code extension format)
        vim.fs.joinpath(path, "extension", "adapter", name),
        -- Standard Mason /bin folder
        vim.fs.joinpath(path, "bin", name),
        -- Root of the package
        vim.fs.joinpath(path, name),
    }

    -- Check for Windows executable if needed
    if vim.fn.has("win32") == 1 then
        local win_bins = {}
        for _, b in ipairs(possible_bins) do
            table.insert(win_bins, b .. ".exe")
        end
        possible_bins = win_bins
    end

    for _, bin in ipairs(possible_bins) do
        ---@diagnostic disable-next-line: undefined-field
        if vim.uv.fs_stat(bin) then
            return bin
        end
    end

    return name
end

---@type table<string,loopdebug.Config.Debugger>
local debuggers = {}

-- ==================================================================
-- Lua (Local/Remote)
-- ==================================================================
debuggers.lua = {
    adapter_config = {
        adapter_id = "lua",
        name = "Local Lua Debugger",
        type = "executable",
        command = {
            "node",
            vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "local-lua-debugger-vscode", "extension",
                "extension", "debugAdapter.js"),
        },
        env = {
            LUA_PATH = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "local-lua-debugger-vscode",
                "extension", "debugger", "?.lua") .. ";;"
        },
    },
    launch_args = function(context)
        return {
            type = "lua-local",
            request = "launch",
            name = "Debug",
            cwd = _get_task_cwd(context),
            program = {
                lua = vim.fn.exepath("lua"),
                file = get_task_program(context.task),
                communication = 'stdio',
            },
        }
    end,
}

debuggers["lua:remote"] = {
    adapter_config = {
        adapter_id = "lua",
        name = "Lua Remote Debugger",
        type = "server",
        host = "127.0.0.1",
        port = 0,
    },
    attach_args = function(context)
        local task = context.task
        return {
            request = "attach",
            type = "lua",
            host = task.host or "127.0.0.1",
            port = task.port or 8086,
            cwd = _get_task_cwd(context),
            stopOnEntry = false,
        }
    end,
    terminate_debuggee = false,
}

-- ==================================================================
-- C / C++ / Rust (LLDB)
-- ==================================================================
debuggers.lldb = {
    adapter_config = function()
        return {
            adapter_id = "lldb",
            name = "LLDB (via lldb-dap)",
            type = "executable",
            command = { mason_bin("lldb-dap") },
        }
    end,
    launch_args = function(context)
        local task = context.task
        return {
            program = get_task_program(task),
            args = get_task_args(task),
            cwd = _get_task_cwd(context),
            env = task.env,
            stopOnEntry = task.stopOnEntry or false,
            runInTerminal = task.runInTerminal ~= false,
            initCommands = task.initCommands,
        }
    end,
    attach_args = function(context)
        local task = context.task
        return {
            pid = tonumber(task.pid),
            program = get_task_program(task) or task.program,
        }
    end,
}

-- ==================================================================
-- C / C++ / Rust (codelldb) with Dynamic Port
-- ==================================================================
debuggers.codelldb = {
    adapter_config = function()
        return {
            adapter_id = "codelldb",
            name = "codelldb",
            type = "executable",
            command = { mason_bin("codelldb") },
        }
    end,
    launch_args = function(context)
        local task = context.task
        return {
            name = "Launch (codelldb)",
            type = "codelldb",
            request = "launch",
            program = get_task_program(task),
            args = get_task_args(task),
            cwd = _get_task_cwd(context),
            env = task.env,
            stopOnEntry = task.stopOnEntry or false,
            -- Integrated terminal is usually best for LLDB
            runInTerminal = task.runInTerminal ~= false,
            -- Enables pretty-printing for Rust/C++
            sourceLanguages = task.sourceLanguages, -- { "cpp", "rust" },
            -- This allows the debugger to find source files if paths are relative
            sourceMap = task.sourceMap,
        }
    end,
    attach_args = function(context)
        local task = context.task
        return {
            name = "Attach (codelldb)",
            type = "codelldb",
            request = "attach",
            pid = tonumber(task.pid),
            program = get_task_program(task) or task.program,
            stopOnEntry = false,
        }
    end,
}

-- ==================================================================
-- JavaScript / TypeScript (js-debug)
-- ==================================================================

debuggers["js-debug"] = {
    start_hook = function(context, callback)
        local task = context.task
        local port = (type(task.port) == "number" and task.port) or 0

        context.user_data.exit_handler = function(_)
            callback(false, "debug server stopped unexpectedly")
        end

        context.user_data.output_handler = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    local srv_port = line:match("Debug server listening at.*:(%d+)%s*$")
                    if srv_port then
                        context.adapter_config.port = tonumber(srv_port)
                        callback(true)
                        context.user_data.output_handler = nil
                        break
                    end
                end
            end
        end

        local args = {
            name = "dapDebugServer.js",
            command = {
                "node",
                vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "js-debug-adapter", "js-debug", "src",
                    "dapDebugServer.js"),
                tostring(port),
            },
            cwd = context.ws_dir,
            output_handler = function(stream, data)
                if context.user_data.output_handler then
                    context.user_data.output_handler(stream, data)
                end
            end,
            on_exit_handler = function(code)
                if context.user_data.exit_handler then
                    context.user_data.exit_handler(code)
                end
            end
        }

        local page_group = context.page_manager.add_page_group("nodejs_server", "Debug Server")
        if not page_group then return end

        local page_data = page_group.add_page({
            id = "term",
            type = "term",
            buftype = "term",
            label = "Debug Server",
            term_args = args,
            activate = true,
        })

        context.user_data.proc = page_data and page_data.term_proc or nil
    end,

    end_hook = function(context, callback)
        local proc = context.user_data.proc
        if proc and proc:is_running() then
            context.user_data.exit_handler = function() callback() end
            proc:terminate()
        else
            callback()
        end
    end,

    adapter_config = function(context)
        return {
            adapter_id = "js-debug",
            name = "js-debug",
            type = "server",
            host = "::1",
            port = tonumber(context.task.port) or 0, -- Fallback to 0 if not yet set by hook
            cwd = _get_task_cwd(context),
        }
    end,

    launch_args = function(context)
        local task = context.task
        return {
            type = "pwa-node",
            request = "launch",
            runtimeExecutable = "node",
            program = get_task_program(task) or task.program,
            args = get_task_args(task) or task.args,
            cwd = _get_task_cwd(context),
            env = task.env,
            stopOnEntry = task.stopOnEntry or false,
            sourceMaps = task.sourceMaps ~= false,
        }
    end,

    attach_args = function(context)
        local task = context.task
        return {
            type = "pwa-node",
            request = "attach",
            address = task.address or "127.0.0.1",
            port = task.port or 0,
            cwd = _get_task_cwd(context),
            restart = task.restart ~= false,
            localRoot = task.cwd or _get_task_cwd(context),
            remoteRoot = task.remoteRoot or "/app",
            skipFiles = { "<node_internals>/**", "node_modules/**" },
        }
    end,
}

-- ==================================================================
-- Python (debugpy)
-- ==================================================================
debuggers.debugpy = {
    adapter_config = {
        adapter_id = "debugpy",
        name = "debugpy",
        type = "executable",
        command = { "python3", "-m", "debugpy.adapter" },
    },
    launch_args = function(context)
        local task = context.task
        return {
            program = get_task_program(task),
            args = get_task_args(task),
            cwd = _get_task_cwd(context),
            stopOnEntry = false,
            justMyCode = task.justMyCode ~= false,
            console = "integratedTerminal",
            env = task.env,
        }
    end,
}

debuggers["debugpy:remote"] = {
    adapter_config = {
        adapter_id = "debugpy",
        name = "Python Remote Debugger",
        type = "server",
        host = "127.0.0.1",
        port = 0,
    },
    attach_args = function(context)
        local task = context.task
        return {
            justMyCode = task.justMyCode ~= nil and task.justMyCode or false,
            console = "integratedTerminal",
        }
    end,
}

-- ==================================================================
-- Go (delve)
-- ==================================================================
debuggers.go = {
    adapter_config = function()
        return {
            adapter_id = "go",
            name = "Delve (dlv)",
            type = "executable",
            command = { mason_bin("delve") },
            args = { "dap", "-l", "127.0.0.1:0" },
        }
    end,
    launch_args = function(context)
        local task = context.task
        return {
            mode = task.mode or "debug",
            program = task.cwd or _get_task_cwd(context),
            env = task.env,
            dlvToolPath = mason_bin("delve"),
        }
    end,
    attach_args = function(context)
        return {
            mode = context.task.mode or "local",
            processId = context.task.processId,
        }
    end,
}

-- ==================================================================
-- Other Languages (Chrome, Bash, PHP, Java, NetCore)
-- ==================================================================
debuggers.chrome = {
    adapter_config = function()
        return {
            adapter_id = "chrome",
            name = "Chrome",
            type = "executable",
            command = { mason_bin("chrome-debug-adapter") },
        }
    end,
    launch_args = function(context)
        local task = context.task
        return {
            type = "chrome",
            request = "launch",
            url = task.url or "http://localhost:3000",
            webRoot = task.cwd or _get_task_cwd(context),
            sourceMaps = task.sourceMaps ~= false,
            userDataDir = task.userDataDir ~= false,
        }
    end,
    attach_args = function(context)
        local task = context.task
        return {
            type = "chrome",
            request = "attach",
            port = task.port or 9222,
            webRoot = task.cwd or _get_task_cwd(context),
        }
    end,
}

debuggers.bash = {
    adapter_config = function()
        return {
            adapter_id = "bash",
            name = "bashdb",
            type = "executable",
            command = { mason_bin("bash-debug-adapter") },
        }
    end,
    launch_args = function(context)
        return {
            name = "Launch Bash Script",
            type = "bashdb",
            program = get_task_program(context.task),
            cwd = _get_task_cwd(context),
            pathBash = "bash",
            pathBashdb = mason_bin("bashdb"),
            pathCat = "cat",
            pathMkfifo = "mkfifo",
            pathPkill = "pkill",
            env = context.task.env,
            terminalKind = "integrated",
        }
    end,
}

debuggers.php = {
    adapter_config = function()
        return {
            adapter_id = "php",
            name = "PHP Debug (vscode-php-debug)",
            type = "executable",
            command = { mason_bin("php-debug") },
        }
    end,
    launch_args = function(context)
        local task = context.task
        return {
            name = "Listen for Xdebug",
            type = "php",
            request = "launch",
            port = task.port or 9003,
            pathMappings = task.pathMappings or { ["/var/www/html"] = task.cwd or _get_task_cwd(context) },
        }
    end,
}

debuggers.java = {
    adapter_config = {
        adapter_id = "java",
        name = "Java (jdtls)",
        type = "server",
        host = "127.0.0.1",
        port = 0,
    },
    attach_args = function(context)
        local task = context.task
        return {
            request = "attach",
            hostName = task.hostName or "127.0.0.1",
            port = task.port or 5005,
        }
    end,
}

debuggers.netcoredbg = {
    adapter_config = function()
        return {
            adapter_id = "netcoredbg",
            name = "netcoredbg",
            type = "executable",
            command = { mason_bin("netcoredbg") },
            args = { "--interpreter=vscode" },
        }
    end,
    launch_args = function(context)
        return {
            type = "coreclr",
            request = "launch",
            program = context.task.program,
            env = context.task.env,
        }
    end,
    attach_args = function(context)
        return {
            type = "coreclr",
            request = "attach",
            processId = tonumber(context.task.processId),
        }
    end,
}

return debuggers

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
    return { unpack(cmdparts, 2) }
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
    return task and task.cwd or context.ws_dir
end

---@type table<string,loopdebug.Config.Debugger>
local debuggers = {}

-- Helper: safely get mason bin path (works even if mason not installed yet)
local function mason_bin(name)
    local mason_registry = nil
    local ok, registry = pcall(require, "mason-registry")
    if ok then
        mason_registry = registry
    end
    if mason_registry and mason_registry.is_installed and mason_registry.is_installed(name) then
        local pkg = mason_registry.get_package(name)
        if pkg and pkg.get_install_path then
            local path = pkg:get_install_path()
            local bin = path .. "/bin/" .. name
            ---@diagnostic disable-next-line: undefined-field
            if vim.uv.fs_stat(bin) then
                return bin
            end
            -- Some packages use different binary names
            local alt = path .. "/" .. name
            if vim.uv.fs_stat(alt) then
                return alt
            end
        end
    end
    -- Fallback: assume it's in PATH (user installed manually)
    return name
end

-- ==================================================================
-- Lua (local debugging inside Neovim or standalone scripts)
-- ==================================================================
debuggers.lua = {
    adapter_config = {
        adapter_id = "lua",
        name = "Local Lua Debugger",
        type = "executable",
        command = {
            "node",
            vim.fn.stdpath("data") ..
            "/mason/packages/local-lua-debugger-vscode/extension/extension/debugAdapter.js",
        },
        env = {
            LUA_PATH = vim.fn.stdpath("data")
                .. "/mason/packages/local-lua-debugger-vscode/extension/debugger/?.lua;;"
        },
    },
    launch_args = function(context)
        local task = context.task
        return {
            type = "lua-local",
            request = "launch",
            name = "Debug",
            cwd = _get_task_cwd(context),
            program = {
                lua = vim.fn.exepath("lua"),
                file = get_task_program(task),
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
-- C / C++ / Rust / Objective-C
-- ==================================================================
debuggers.lldb = {
    adapter_config = {
        adapter_id = "lldb",
        name = "LLDB (via lldb-dap)",
        type = "executable",
        command = { mason_bin("lldb-dap") },
    },
    launch_args = function(context)
        local task = context.task
        return {
            program = get_task_program(context.task),
            args = get_task_args(context.task),
            cwd = _get_task_cwd(context),
            stopOnEntry = task.stopOnEntry or false,
            runInTerminal = task.runInTerminal ~= false,
            initCommands = {
                "command script import lldb.formatters.cpp",
                "settings set target.max-string-summary-length 1024"
            }
        }
    end,
    attach_args = function(context)
        local task = context.task
        return {
            pid = tonumber(task.pid),
            program = get_task_program(context.task) or task.program,
        }
    end,
}

-- ==================================================================
-- JavaScript / TypeScript / Node.js
-- ==================================================================
debuggers["js-debug"] = {
    start_hook = function(context, callabck)
        local task = context.task
        local port
        if task and task.port and type(task.port) == "number" then
            port = task.port
        else
            port = 0
        end
        context.user_data.exit_handler = function(code)
            callabck(false, "debug server stopped unexpectedly")
        end
        context.user_data.output_handler = function(stream, data)
            if data then
                for _, line in ipairs(data) do
                    local srv_port = line:match("Debug server listening at.*:(%d+)%s*$")
                    if srv_port then
                        context.adapter_config.port = tonumber(srv_port)
                        callabck(true)
                        context.user_data.output_handler = nil
                        break
                    end
                end
            end
        end
        ---@type loop.tools.TermProc.StartArgs
        local args = {
            name = "dapDebugServer.js",
            command = { "node",
                vim.fn.stdpath("data")
                .. "/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js",
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
        local proc = context.page_manager.add_page_group("nodejs_server", "Server").add_term_page("srv", args)
        context.user_data.proc = proc
    end,
    end_hook = function(context, callabck)
        ---@type loop.tools.TermProc
        local proc = context.user_data.proc
        if proc and proc:is_running() then
            context.user_data.exit_handler = function()
                callabck()
            end
            proc:terminate()
        else
            callabck()
        end
    end,
    adapter_config = function(context)
        local task = context.task
        ---@type loopdebug.AdapterConfig
        return {
            adapter_id = "js-debug",
            name = "js-debug",
            type = "server",
            host = "::1",
            port = tonumber(task.port),
            cwd = _get_task_cwd(context),
        }
    end,
    launch_args = function(context)
        local task = context.task
        return {
            type = "pwa-node",
            request = "launch",
            runtimeExecutable = "node",
            program = get_task_program(context.task) or task.program,
            args = get_task_args(context.task) or task.args,
            cwd = _get_task_cwd(context),
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
            localRoot = context.task.cwd or task.cwd,
            remoteRoot = task.remoteRoot or "/app",
            skipFiles = { "<node_internals>/**", "node_modules/**" },
        }
    end,
}

-- ==================================================================
-- Python
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
            program = get_task_program(context.task),
            args = get_task_args(context.task),
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
-- Go
-- ==================================================================
debuggers.go = {
    adapter_config = {
        adapter_id = "go",
        name = "Delve (dlv)",
        type = "executable",
        command = { mason_bin("delve") },
        args = { "dap", "-l", "127.0.0.1:0" },
    },
    launch_args = function(context)
        local task = context.task
        return {
            mode = task.mode or "debug",
            program = context.task.cwd or task.cwd,
            dlvToolPath = mason_bin("delve"),
        }
    end,
    attach_args = function(context)
        local task = context.task
        return {
            mode = task.mode or "local",
            processId = task.processId,
        }
    end,
}

-- ==================================================================
-- Chrome / Web
-- ==================================================================
debuggers.chrome = {
    adapter_config = {
        adapter_id = "chrome",
        name = "Chrome",
        type = "executable",
        command = { mason_bin("chrome-debug-adapter") },
    },
    launch_args = function(context)
        local task = context.task
        return {
            type = "chrome",
            request = "launch",
            url = task.url or "http://localhost:3000",
            webRoot = context.task.cwd or task.cwd,
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
            webRoot = context.task.cwd or task.cwd,
        }
    end,
}

-- ==================================================================
-- Bash
-- ==================================================================
debuggers.bash = {
    adapter_config = {
        adapter_id = "bash",
        name = "bashdb",
        type = "executable",
        command = { mason_bin("bash-debug-adapter") },
    },
    launch_args = function(context)
        local task = context.task
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

-- ==================================================================
-- PHP
-- ==================================================================
debuggers.php = {
    adapter_config = {
        adapter_id = "php",
        name = "PHP Debug (vscode-php-debug)",
        type = "executable",
        command = { mason_bin("php-debug") },
    },
    launch_args = function(context)
        local task = context.task
        return {
            name = "Listen for Xdebug",
            type = "php",
            request = "launch",
            port = task.port or 9003,
            pathMappings = task.pathMappings or { ["/var/www/html"] = context.task.cwd or task.cwd },
        }
    end,
}

-- ==================================================================
-- Java
-- ==================================================================
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

-- ==================================================================
-- C# / .NET
-- ==================================================================
debuggers.netcoredbg = { -- renamed key to match common usage (was "csharp")
    adapter_config = {
        adapter_id = "netcoredbg",
        name = "netcoredbg",
        type = "executable",
        command = { mason_bin("netcoredbg") },
        args = { "--interpreter=vscode" },
    },
    launch_args = function(context)
        local task = context.task
        return {
            type = "coreclr",
            request = "launch",
            program = task.program or function()
                return vim.fn.input("Path to dll: ", context.ws_dir .. "/bin/Debug/", "file")
            end,
        }
    end,
    attach_args = function(context)
        local task = context.task
        return {
            type = "coreclr",
            request = "attach",
            processId = tonumber(task.processId),
        }
    end,
}

return debuggers

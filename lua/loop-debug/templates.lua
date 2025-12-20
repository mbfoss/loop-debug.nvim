require('loop.task.taskdef')
---@type loop.taskTemplate[]
return {
-- ==================================================================
-- Lua
-- ==================================================================
    {
        name = "Debug current Lua file (local-lua-debugger-vscode)",
        task = {
            name = "Debug",
            type = "debug",
            command = "${file:lua}",
            cwd = "${projdir}",
            debug = {
                type = "lua",
                request = "launch",
            },
        }
    },
    {
        name = "Attach to remote Lua process",
        task = {
            name = "Attach",
            type = "debug",
            debug = {
                type = "lua:remote",
                request = "attach",
                host = "127.0.0.1",
                port = 8086,
            },
        }
    },
-- ==================================================================
-- C / C++ / Rust / Objective-C (lldb-dap)
-- ==================================================================
    {
        name = "Debug executable with LLDB (launch)",
        task = {
            name = "Debug",
            type = "debug",
            command = "${prompt:Select binary: }",
            cwd = "${projdir}",
            debug = {
                type = "lldb",
                request = "launch",
                runInTerminal = true,
                stopOnEntry = false,
            },
        }
    },
    {
        name = "Attach to running process (LLDB)",
        task = {
            name = "Attach",
            type = "debug",
            debug = {
                type = "lldb",
                request = "attach",
                pid = "${select-pid}",
            },
        }
    },
-- ==================================================================
-- Node.js / JavaScript / TypeScript
-- ==================================================================
    {
        name = "Debug Node.js script (js-debug)",
        task = {
            name = "Debug",
            type = "debug",
            command = "${file:javascript}",
            cwd = "${projdir}",
            debug = {
                type = "js-debug",
                request = "launch",
                sourceMaps = true,
                stopOnEntry = false,
            },
        }
    },
    {
        name = "Attach to Node.js process (js-debug)",
        task = {
            name = "Attach",
            type = "debug",
            debug = {
                type = "js-debug",
                request = "attach",
                address = "127.0.0.1",
                port = "${prompt:Inspector port: }",
                restart = true,
            },
        }
    },
-- ==================================================================
-- Python
-- ==================================================================
    {
        name = "Debug Python script (debugpy)",
        task = {
            name = "Debug",
            type = "debug",
            command = "${file:python}",
            cwd = "${projdir}",
            debug = {
                type = "debugpy",
                request = "launch",
                justMyCode = false,
            },
        }
    },
    {
        name = "Attach to Python debug server (debugpy)",
        task = {
            name = "Attach",
            type = "debug",
            debug = {
                type = "debugpy:remote",
                request = "attach",
                justMyCode = false,
            },
        }
    },
-- ==================================================================
-- Go
-- ==================================================================
    {
        name = "Debug Go program (delve)",
        task = {
            name = "Debug Go program (delve)",
            type = "debug",
            cwd = "${projdir}",
            debug = {
                type = "go",
                request = "launch",
                mode = "debug",
            },
        }
    },
    {
        name = "Attach to Go process (delve)",
        task = {
            name = "Attach",
            type = "debug",
            debug = {
                type = "go",
                request = "attach",
                mode = "local",
                processId = "${select-pid}",
            },
        }
    },
-- ==================================================================
-- Chrome / Web
-- ==================================================================
    {
        name = "Launch Chrome and debug",
        task = {
            name = "Launch",
            type = "debug",
            debug = {
                type = "chrome",
                request = "launch",
                url = "http://localhost:3000",
                webRoot = "${projdir}",
                userDataDir = false,
                sourceMaps = true,
            },
        }
    },
    {
        name = "Attach to running Chrome",
        task = {
            name = "Attach",
            type = "debug",
            debug = {
                type = "chrome",
                request = "attach",
                port = 9222,
                webRoot = "${projdir}",
            },
        }
    },
-- ==================================================================
-- Bash
-- ==================================================================
    {
        name = "Debug Bash script (bashdb)",
        task = {
            name = "Debug",
            type = "debug",
            command = "${file}",
            cwd = "${projdir}",
            debug = {
                type = "bash",
                request = "launch",
            },
        }
    },
-- ==================================================================
-- PHP (Xdebug)
-- ==================================================================
    {
        name = "Listen for Xdebug (PHP)",
        task = {
            name = "Listen",
            type = "debug",
            debug = {
                type = "php",
                request = "launch",
                port = 9003,
                pathMappings = { ["/var/www/html"] = "${projdir}" },
            },
        }
    },
-- ==================================================================
-- C# / .NET
-- ==================================================================
    {
        name = "Debug .NET DLL (netcoredbg)",
        task = {
            name = "Debug",
            type = "debug",
            debug = {
                type = "netcoredbg",
                request = "launch",
                program = ""
            },
        }
    },
    {
        name = "Attach to .NET process",
        task = {
            name = "Attach",
            type = "debug",
            debug = {
                type = "netcoredbg",
                request = "attach",
                processId = "${select-pid}",
            },
        }
    },
-- ==================================================================
-- Java (jdtls)
-- ==================================================================
    {
        name = "Attach to Java process (JDWP)",
        task = {
            name = "Attach",
            type = "debug",
            debug = {
                type = "java",
                request = "attach",
                hostName = "127.0.0.1",
                port = 5005,
            },
        }
    },
}
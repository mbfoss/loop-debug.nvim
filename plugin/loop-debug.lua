-- IMPORTANT: keep this module light for lazy loading


require('loop.ext').register_task_provider("debug", "loop-debug.provider")


vim.api.nvim_create_user_command("LoopDebug", function(opts)
        require("loop-debug").dispatch(opts)
    end,
    {
        nargs = "*",
        complete = function(arg_lead, cmd_line, _)
            return require("loop-debug").complete(arg_lead, cmd_line)
        end,
        desc = "Loop.nvim management commands",
    })

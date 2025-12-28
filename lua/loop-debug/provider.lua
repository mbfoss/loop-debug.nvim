local run = require('loop-debug.run')
local persistence = require('loop-debug.persistence')

---@type loop.TaskProvider
local task_provider =
{
    on_workspace_open = function(ws_dir, store)
        persistence.on_workspace_open(ws_dir, store)
    end,
    on_workspace_closed = function(ws_dir)
        persistence.on_workspace_closed()
    end,
    get_task_schema = function()
        local schema = require('loop-debug.schema')
        return schema
    end,
    get_config_order = nil,
    get_task_templates = function(_)
        local templates = require('loop-debug.templates')
        return templates
    end,
    start_one_task = run.start_debug_task
}

return task_provider

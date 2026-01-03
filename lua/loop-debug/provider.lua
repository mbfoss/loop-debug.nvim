local run = require('loop-debug.run')
local ui = require('loop-debug.ui')
local persistence = require('loop-debug.persistence')

---@type loop.TaskProvider
local task_provider =
{
    on_workspace_open = function(_, store)
        persistence.on_workspace_open(store)
    end,
    on_workspace_close = function(_)
        persistence.on_workspace_close()
    end,
    on_store_will_save = function (_, store)
        persistence.on_store_will_save(store)
    end,
    on_tasks_cleanup = function ()
        ui.hide()
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
    start_one_task = run.start_debug_task,
}

return task_provider

local run = require('loop-debug.run')
local ui = require('loop-debug.ui')
local persistence = require('loop-debug.persistence')
local jsontools = require('loop.tools.json')

---@type loop.TaskProvider
local task_provider =
{
    on_tasks_cleanup = function ()
        ui.hide()
    end,
    get_task_schema = function()
        local schema = require('loop-debug.schema')
        return schema
    end,
    get_task_templates = function()
        local templates = require('loop-debug.templates')
        return templates
    end,
    get_task_preview = function (task)
        local cpy = vim.fn.copy(task)
        local templates = require('loop-debug.templates')
        ---@diagnostic disable-next-line: undefined-field, inject-field
        cpy.__order = templates[1].task.__order
        return jsontools.to_string(cpy), "json"        
    end,
    start_one_task = run.start_debug_task,
}

return task_provider

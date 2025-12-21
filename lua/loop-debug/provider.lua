local run = require('loop-debug.run')
local breakpoints = require('loop-debug.dap.breakpoints')

---@type loop.TaskProvider
local task_provider =
{
    get_state = function()
        local state = {}
        state.breakpoints = breakpoints.get_breakpoints()
        return state
    end,
    set_state = function(state)
        if state.breakpoints then
            breakpoints.set_breakpoints(state.breakpoints)
        end
    end,
    get_config_schema = function()
        return nil
    end,
    get_config_template = function()
        return nil
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

local persistence = require('loop-debug.persistence')
local task_provider = require('loop-debug.task_provider')
local cmd_provider = require('loop-debug.cmd_provider')

---@type loop.Extension
local extension =
{
    on_workspace_load = function(_, store)
        persistence.on_workspace_load(store)
    end,
    on_workspace_unload = function(_)
        persistence.on_workspace_unload()
    end,
    on_store_will_save = function (_, store)
        persistence.on_store_will_save(store)
    end,
    get_config_order = nil,
    get_cmd_provider = function()
        return cmd_provider
    end,
    get_task_provider = function()
        return task_provider
    end,


}
return extension
local M = {}

require('loop-debug.tools.FSM')

M.trigger =
{
    --initialize_resp_ok = "initialize_resp_ok",
    initialize_resp_err = "initialize_resp_err",
    initialized = "initialized",
    start_before_initialized = "start_before_initialized",
    configuration_done = "configuration_done",
    launch_resp_ok = "launch_resp_ok",
    launch_resp_error = "launch_resp_error",
    disconnect = "disconnect",
    disconnect_resp_ok = "disconnect_resp_ok",
    disconnect_resp_err = "disconnect_resp_err",
    disconnect_timeout = "disconnect_timeout",
}

---@alias loopdebug.fsmdata.StateHandler fun(trigger:string, triggerdata:any)

---@class loopdebug.fsmdata.StateHandlers
---@field initializing loopdebug.fsmdata.StateHandler
---@field starting loopdebug.fsmdata.StateHandler
---@field running loopdebug.fsmdata.StateHandler
---@field disconnecting loopdebug.fsmdata.StateHandler
---@field ended loopdebug.fsmdata.StateHandler

---@param handlers loopdebug.fsmdata.StateHandlers
---@return loop.tools.FSMData
function M.create_fsm_data(handlers)
    ---@type loop.tools.FSMData
    return {
        initial = "initializing",
        states = {
            initializing = {
                state_handler = handlers.initializing,
                triggers = {
                    --[M.trigger.initialize_resp_ok] = "starting",
                    [M.trigger.start_before_initialized] = "starting",
                    [M.trigger.configuration_done] = "starting",
                    [M.trigger.initialize_resp_err] = "disconnecting",
                    [M.trigger.disconnect] = 'disconnecting',
                }
            },
            starting = {
                state_handler = handlers.starting,
                triggers = {
                    [M.trigger.disconnect] = "disconnecting",
                    [M.trigger.launch_resp_ok] = "running",
                    [M.trigger.launch_resp_error] = "disconnecting",
                }
            },
            running = {
                state_handler = handlers.running,
                triggers = {
                    [M.trigger.disconnect] = "disconnecting",
                }
            },
            disconnecting = {
                state_handler = handlers.disconnecting,
                triggers = {
                    [M.trigger.disconnect_resp_ok] = "ended",
                    [M.trigger.disconnect_resp_err] = "ended",
                    [M.trigger.disconnect_timeout] = "ended",
                }
            },
            ended = {
                state_handler = handlers.ended,
                triggers = {}
            },
        }
    }
end

return M

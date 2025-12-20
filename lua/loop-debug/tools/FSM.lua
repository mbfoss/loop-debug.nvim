local class = require('loop.tools.class')

---@class loop.tools.FSMState
---@field state_handler fun(trigger:string, trigger_data:any)               # Called when state becomes active.
---@field triggers table<string,string>         # Valid triggers for this state.

---@class loop.tools.FSMData
---@field initial string                    # Name of the initial state.
---@field states table<string, loop.tools.FSMState>   # Map: state name → state definition.

---@class loop.tools.FSM
---@field _log any
---@field states table<string, loop.tools.FSMState>
---@field _current string|nil
---@field _started boolean
---@field _valid_triggers table<string,boolean>
---@field new fun(self: loop.tools.FSM, name : string, fsmdata : loop.tools.FSMData) : loop.tools.FSM
local FSM = class()

--- Initialize the FSM.
---@param name string: Name used for logging.
---@param fsmdata loop.tools.FSMData: Configuration object containing initial state and state table.
function FSM:init(name, fsmdata)
    self._log = require('loop-debug.tools.Logger').create_logger("fsm." .. name)
    self.states = fsmdata.states or {}
    self._current = fsmdata.initial
    self._started = false

    self._valid_triggers = {}
    for n, s in pairs(fsmdata.states) do
        assert(s.triggers, "triggers missing in state: " .. tostring(n))
        for t, tgt in pairs(s.triggers) do
            self._valid_triggers[t] = true
            assert(self.states[tgt], "Invalid target state in trigger: " .. tostring(t) .. ', in state: ' .. tostring(n))
        end
    end

    self._log:info("FSM created. Current state: " .. (self._current or "nil"))
end

--- Start the FSM by calling the state_handler of the initial state.
-- Must not have been _started already.
function FSM:start()
    assert(self._current ~= nil, "FSM has no initial state")
    assert(self._started == false, "FSM already started")

    self._started = true
    self:_call_state_handler("", nil)
end

--- Trigger a transition asynchronously via vim.schedule().
-- This avoids recursive trigger issues inside state handlers.
---@param trigger string
---@param data any
function FSM:trigger(trigger, data)
    assert(trigger and self._valid_triggers[trigger] == true, "Invalid trigger: " .. tostring(trigger))
    vim.schedule(function()
        self:_trigger(trigger, data)
    end)
end

---@return string
function FSM:curr_state()
    return self._current
end

--- Internal trigger handler (synchronous).
-- Looks up the next state and performs the transition.
---@param trigger string
---@param trigger_data any
function FSM:_trigger(trigger, trigger_data)
    if not self._current then
        self._log:warn("FSM has no _current state")
        return
    end

    local state_data = self.states[self._current]
    if not state_data then
        self._log:error("No state data for state '" .. tostring(self._current) .. "'")
        return
    end

    local next_state = state_data.triggers and state_data.triggers[trigger]
    if next_state then
        self._log:info("State change '" ..
            tostring(self._current) .. "' -> '" .. tostring(next_state) ..
            "' (trigger: " .. tostring(trigger) .. ")")
        self:_change_state(next_state, trigger, trigger_data)
    else
        self._log:warn("Trigger '" .. trigger .. "' not valid from state '" .. self._current .. "'")
    end
end

--- Internal function: change the _current state and call the new state's handler.
---@param next_state string
---@param trigger string
---@param trigger_data any
function FSM:_change_state(next_state, trigger, trigger_data)
    assert(next_state ~= nil, "next_state cannot be nil")
    self._current = next_state
    self:_call_state_handler(trigger, trigger_data)
end

---@param trigger string
---@param trigger_data any
function FSM:_call_state_handler(trigger, trigger_data)
    local state = self._current
    local state_data = self.states[state]
    assert(state_data ~= nil, "Missing state data for '" .. tostring(state) .. "'")

    local handler = state_data.state_handler
    if not handler then
        self._log:error("No state_handler for state '" .. tostring(state) .. "'")
        return
    end

    local cb_error = function(err)
        self._log:error("In FSM callback for " ..
            (state or "?") .. "\n" ..
            debug.traceback("Error: " .. tostring(err) .. "\n", 2))
    end

    local ok = xpcall(function() handler(trigger, trigger_data) end, cb_error)
    if not ok then
        self._log:error({ "Error in state handler for ", state })
    end
end

return FSM

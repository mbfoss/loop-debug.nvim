local M                = {}

local Trackers         = require("loop.tools.Trackers")

---@class loopdebug.events.SessionInfo
---@field name string
---@field data_providers loopdebug.session.DataProviders

---@class loopdebug.events.SessionState
---@field data_providers loopdebug.session.DataProviders
---@field state string|nil
---@field nb_paused_threads number|nil
---@field cur_thread_id number|nil
---@field cur_thread_name string|nil
---@field cur_frame loopdebug.proto.StackFrame|nil

---@class loopdebug.events.Tracker
---@field on_reset fun()
---@field on_session_added fun(id:number,info:loopdebug.events.SessionInfo)
---@field on_session_removed fun(id:number)
---@field on_session_update fun(id:number, state:loopdebug.events.SessionState)
---@field on_curr_session_change fun(id:number?)

---@type loop.tools.Trackers<loopdebug.events.Tracker>
local _trackers        = Trackers:new()

---@type table<number,loopdebug.events.SessionInfo>
local _sessions        = {}

---@type table<number,loopdebug.events.SessionState>
local _states          = {}

---@type number?
local _current_sess_id = nil

function M.report_reset()
    _states = {}
    _sessions = {}
    _current_sess_id = nil
    _trackers:invoke("on_reset");
end

---@type fun(id:number,info:loopdebug.events.SessionInfo)
function M.report_session_added(id, info)
    _sessions[id] = info
    _trackers:invoke("on_session_added", id, info);
    if not _current_sess_id then
        _current_sess_id = id
        _trackers:invoke("on_curr_session_change", id);
    end
end

---@type fun(id:number)
function M.report_session_removed(id)
    if id == _current_sess_id then
        _current_sess_id = nil
        _trackers:invoke("on_curr_session_change", nil);
    end
    _sessions[id] = nil
    _states[id] = nil
    _trackers:invoke("on_session_removed", id);
end

---@type fun(id:number, state:loopdebug.events.SessionState)
function M.report_session_state(id, state)
    if state and _sessions[id] then
        _states[id] = state
        _trackers:invoke("on_session_update", id, state);
    end
end

---@param id number?
function M.report_current_session(id)
    _current_sess_id = id
    _trackers:invoke("on_curr_session_change", id);
end

---@param callbacks loopdebug.events.Tracker
---@return number
function M.add_tracker(callbacks)
    local tracker_id = _trackers:add_tracker(callbacks)
    if callbacks.on_session_added then
        for id, info in pairs(_sessions) do
            callbacks.on_session_added(id, info)
        end
    end
    if callbacks.on_session_update then
        for id, state in pairs(_states) do
            callbacks.on_session_update(id, state)
        end
    end
    if callbacks.on_curr_session_change then
        callbacks.on_curr_session_change(_current_sess_id)
    end
    return tracker_id
end

---@param id number
---@return boolean
function M.remove_tracker(id)
    return _trackers:remove_tracker(id)
end

return M

local M         = {}

local Trackers  = require("loop.tools.Trackers")

---@class loopdebug.events.SessionInfo
---@field name string
---@field data_providers loopdebug.session.DataProviders
---@field state string
---@field nb_paused_threads number

---@class loopdebug.events.CurrentViewUpdate
---@field session_id number?
---@field session_name string?
---@field data_providers loopdebug.session.DataProviders?
---@field thread_id number|nil
---@field thread_name string|nil
---@field frame loopdebug.proto.StackFrame|nil

---@class loopdebug.events.Tracker
---@field on_debug_start fun()
---@field on_debug_end fun(success:boolean)
---@field on_session_added fun(id:number,info:loopdebug.events.SessionInfo)?
---@field on_session_update fun(id:number,info:loopdebug.events.SessionInfo)?
---@field on_session_removed fun(id:number)?
---@field on_view_udpate fun(view:loopdebug.events.CurrentViewUpdate)?

---@type loop.tools.Trackers<loopdebug.events.Tracker>
local _trackers = Trackers:new()

---@type table<number,loopdebug.events.SessionInfo>
local _sessions = {}

---@type loopdebug.events.CurrentViewUpdate?
local _current_view

---@param callbacks loopdebug.events.Tracker
---@return loop.TrackerRef
function M.add_tracker(callbacks)
    local tracker_ref = _trackers:add_tracker(callbacks)
    if callbacks.on_session_added then
        for id, info in pairs(_sessions) do
            callbacks.on_session_added(id, info)
        end
    end
    if _current_view and callbacks.on_view_udpate then
        callbacks.on_view_udpate(_current_view)
    end
    return tracker_ref
end

function M.report_debug_start()
    _sessions = {}
    _current_view = nil
    _trackers:invoke("on_debug_start");
end

---@param success boolean
function M.report_debug_end(success)
    _sessions = {}
    _current_view = nil
    _trackers:invoke("on_debug_end", success);
end

---@type fun(id:number,info:loopdebug.events.SessionInfo)
function M.report_session_added(id, info)
    _sessions[id] = info
    _trackers:invoke("on_session_added", id, info);
end

---@type fun(id:number,info:loopdebug.events.SessionInfo)
function M.report_session_update(id, info)
    assert(_sessions[id])
    _sessions[id] = info
    _trackers:invoke("on_session_update", id, info);
end

---@type fun(id:number)
function M.report_session_removed(id)
    _sessions[id] = nil
    _trackers:invoke("on_session_removed", id);
end

---@type fun(view:loopdebug.events.CurrentViewUpdate)
function M.report_view_update(view)
    _current_view = view
    _trackers:invoke("on_view_udpate", view);
end

return M

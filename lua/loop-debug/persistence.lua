local M         = {}

local Trackers  = require("loop.tools.Trackers")

---@alias loopdebug.ConfigElement "layout"|"watch"|"breakpoints"

---@class loopdebug.PersistenceData
---@field ws_dir string
---@field store loop.TaskProviderStore

---@type loopdebug.PersistenceData?
local _current_data

---@class loopdebug.persistence.Tracker
---@field on_ws_open fun()
---@field on_ws_closed fun()

---@type loop.tools.Trackers<loopdebug.persistence.Tracker>
local _trackers = Trackers:new()

---@param callbacks loopdebug.persistence.Tracker
---@return loop.TrackerRef
function M.add_tracker(callbacks)
    local ref = _trackers:add_tracker(callbacks)
    if _current_data and callbacks.on_ws_open then
        callbacks.on_ws_open()
    end
    return ref
end

---@param wsdir string
---@param store loop.TaskProviderStore
function M.on_workspace_open(wsdir, store)
    _current_data = {
        ws_dir = wsdir,
        store = store
    }
    _trackers:invoke("on_ws_open")
end

function M.on_workspace_closed()
    _current_data = nil
    _trackers:invoke("on_ws_closed")
end

function M.is_ws_open()
    return _current_data ~= nil
end

---@param element loopdebug.ConfigElement
---@param data table
function M.set_config(element, data) if _current_data then _current_data.store.set_field(element, data) end end

---@param element loopdebug.ConfigElement
---@return table?
function M.get_config(element) return _current_data and _current_data.store.get_field(element) end

return M

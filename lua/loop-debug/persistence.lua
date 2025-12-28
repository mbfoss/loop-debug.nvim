local M         = {}

local Trackers  = require("loop.tools.Trackers")

---@alias loopdebug.ConfigElement "layout"|"watch"|"breakpoints"

---@class loopdebug.PersistenceData
---@field store loop.TaskProviderStore

---@type loopdebug.PersistenceData?
local _current_data

---@class loopdebug.persistence.Tracker
---@field on_ws_open fun()
---@field on_ws_closed fun()
---@field on_ws_will_save fun()

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

---@param store loop.TaskProviderStore
function M.on_workspace_open(store)
    _current_data = {
        store = store
    }
    _trackers:invoke("on_ws_open")
end

function M.on_workspace_close()
    _current_data = nil
    _trackers:invoke("on_ws_closed")
end

---@param store loop.TaskProviderStore
function M.on_store_will_save(store)
    _trackers:invoke_sync("on_ws_will_save")
end

function M.is_ws_open()
    return _current_data ~= nil
end

---@param element loopdebug.ConfigElement
---@param data table
function M.set_config(element, data) if _current_data then _current_data.store.set(element, data) end end

---@param element loopdebug.ConfigElement
---@return table?
function M.get_config(element) return _current_data and _current_data.store.get(element) end

return M

local M         = {}

local Trackers  = require("loop.tools.Trackers")

---@class loopdebug.PersistenceData
---@field breakpoints loopdebug.SourceBreakpoint[]
---@field watch_exprs string[]
---@field ui_layout {string:any}

---@type string?
local _current_ws 

---@type loopdebug.PersistenceData?
local _current_data

---@param wsdir string
---@param data loopdebug.PersistenceData
function M.on_workspace_open(wsdir, data)
    _current_ws = wsdir
    _current_data = data
end

function M.on_workspace_close()
    _current_ws = nil
    _current_data = nil
end

function M.is_ws_open()
    return _current_ws ~= nil
end

---@return loopdebug.PersistenceData?
function M.get_data()
    return _current_data
end


return M

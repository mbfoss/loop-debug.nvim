---@class loop-debug.Config.SignPriority
---@field breakpoints number
---@field currentframe number

---@class loop-debug.Config.Symbols
---@field running string
---@field paused string
---@field success string
---@field failure string
---@field active_breakpoint string
---@field inactive_breakpoint string
---@field logpoint string
---@field logpoint_inactive string
---@field cond_breakpoint string
---@field cond_breakpoint_inactive string

---@class loop-debug.Config
---@field stack_levels_limit? number
---@field sign_priority? loop-debug.Config.SignPriority
---@field symbols loop-debug.Config.Symbols
---@field debuggers table<string,loopdebug.Config.Debugger>

local M = {}

---@type loop-debug.Config|nil
M.current = nil

return M

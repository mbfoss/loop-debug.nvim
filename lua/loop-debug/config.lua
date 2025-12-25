---@class loop-debug.Config
---@field stack_levels_limit? number
---@field sign_priority? table<string,number>
---@field symbols {running:string, paused:string, success:string,failure:string}
---@field debuggers table<string,loopdebug.Config.Debugger>

local M = {}

---@type loop-debug.Config|nil
M.current = nil

return M

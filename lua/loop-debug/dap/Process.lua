-- Process.lua
local uv = require('luv')
local class = require('loop.tools.class')

---@class loopdebug.Process.Opts
---@field cmd string
---@field args string[]|nil
---@field env string[]|nil
---@field cwd string
---@field on_output fun(data:string, is_stderr:boolean)
---@field on_exit fun(code:number, signal:number)

---@class loopdebug.Process
---@field new fun(self: loopdebug.Process, name : string, opts : loopdebug.Process.Opts) : loopdebug.Process
local Process = class()

---@param name string
function Process:init(name, opts)
    assert(type(opts.cmd) == "string", "cmd is required")
    assert(opts.cwd, "cwd is required for dap process")

    self.log = require('loop-debug.tools.Logger').create_logger("dap.process[" .. name .. "]")
    self.cmd = opts.cmd
    self.args = opts.args or {}
    self.cwd = opts.cwd
    self.env = opts.env or {}

    self.env['PWD'] = self.cwd -- required for commands to use cwd in all cases

    self.on_output = opts.on_output
    self.on_exit = opts.on_exit

    self.exited = false
    self.killed = false

    self.stdin = uv.new_pipe(false)
    self.stdout = uv.new_pipe(false)
    self.stderr = uv.new_pipe(false)

    self:_spawn()
    if not self.handle then
        self:_close_all()
    end
    return self
end

-------------------------------------------------
-- Spawn and IO reading
-------------------------------------------------
function Process:_spawn()
    local opts = {
        args = self.args,
        cwd = self.cwd,
        env = self:_env_list(),
        stdio = { self.stdin, self.stdout, self.stderr },
    }

    self.log:debug("starting process: " ..
        tostring(self.cmd) .. ", opts: " .. vim.inspect(opts))

    local handle, pid = uv.spawn(self.cmd, opts, vim.schedule_wrap(function(code, signal)
        if self.exited then return end
        self.exited = true

        -- Stop reading immediately
        if self.stdout and self.stdout:is_active() then
            self.stdout:read_stop()
        end
        if self.stderr and self.stderr:is_active() then
            self.stderr:read_stop()
        end

        -- Always run on_exit, even during shutdown
        if self.on_exit then
            local ok, err = pcall(self.on_exit, code, signal)
            if not ok then
                -- Log error but don't crash
                print("Process on_exit error:", err)
            end
        end

        -- Always close everything — this MUST run
        self:_close_all()
    end))

    if not handle then
        self.on_output("failed to start debugger process: " .. tostring(self.cmd), true)
        return
    end

    self.handle = handle
    self.pid = pid

    -- Start reading stdout
    self.stdout:read_start(function(err, data)
        if err then
            vim.schedule(function() error(err) end)
            return
        end
        if data and self.on_output then
            self.on_output(data, false)
        end
    end)

    -- Start reading stderr
    self.stderr:read_start(function(err, data)
        if err then
            vim.schedule(function() error(err) end)
            return
        end
        if data and self.on_output then
            self.on_output(data, true)
        end
    end)
end

-- Convert env dict → {"KEY=value", ...}
function Process:_env_list()
    local out = {}
    for k, v in pairs(self.env) do
        table.insert(out, string.format("%s=%s", k, v))
    end
    return out
end
-- Writing to stdin
-------------------------------------------------
function Process:write(data)
    if self.exited then
        return false, "process exited"
    end
    if not self.stdin or self.stdin:is_closing() then
        return false, "stdin closed"
    end
    self.stdin:write(data)
    return true
end

function Process:running()
    return self.handle ~= nil
end

function Process:terminate(timeout)
    if self.exited or self.killed then return end
    self.killed = true

    if self.handle and not self.handle:is_closing() then
        self.handle:kill("sigterm")
    end

    local timer = uv.new_timer()
    timer:start(timeout or 800, 0, vim.schedule_wrap(function()
        timer:close()
        if not self.exited and self.handle and not self.handle:is_closing() then
            self.handle:kill("sigkill")
            -- Force cleanup even if callback never fires
            self:_close_all()
        end
    end))
end

-------------------------------------------------
-- Cleanup handles
-------------------------------------------------
function Process:_close_all()
    local function safe_close(h)
        if h and not h:is_closing() then
            h:close()
        end
    end

    safe_close(self.stdin)
    safe_close(self.stdout)
    safe_close(self.stderr)
    safe_close(self.handle)

    self.stdin = nil
    self.stdout = nil
    self.stderr = nil
    self.handle = nil
end

return Process
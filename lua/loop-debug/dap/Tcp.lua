-- loop/dap/Tcp.lua
local uv = vim.loop
local class = require('loop.tools.class')

---@class loopdebug.Tcp.Opts
---@field host string
---@field port integer
---@field on_output fun(data:string, is_stderr?:boolean)
---@field on_exit fun(code?:integer, signal?:integer)

---@class loopdebug.Tcp
---@field new fun(self: loopdebug.Tcp, name:string, opts:loopdebug.Tcp.Opts): loopdebug.Tcp
local Tcp = class()

function Tcp:init(name, opts)
    assert(type(opts.host) == "string" and opts.host ~= "", "host required")
    assert(type(opts.port) == "number" and opts.port > 0 and opts.port < 65536, "valid port required")

    self.log = require('loop.tools.Logger').create_logger("dap.tcp[" .. name .. "]")
    self.name = name
    self.host = opts.host
    self.port = opts.port
    self.on_output = opts.on_output
    self.on_exit = opts.on_exit
    self.exited = false
    self.killed = false
    self.is_connected = false
    self.write_queue = {} -- Queue for writes before connection

    self.log:debug("Creating tcp socket")
    ---@diagnostic disable-next-line: undefined-field
    self.socket = uv.new_tcp()
    self:_connect_with_resolution()
    return self
end

-- Main entry: resolve if needed, then connect
function Tcp:_connect_with_resolution()
    local host = self.host

    -- Fast path: localhost or literal IP
    if host == "127.0.0.1"
        or host == "::1"
        or host:match("^%d+%.%d+%.%d+%.%d+$")
        or host:match("^[%x]*:[%x:]+:[%x]*$") then -- better IPv6 regex
        self.log:debug("Using fast path for host: " .. host)
        self:_do_connect(host)
        return
    end

    -- Async resolve
    self.log:debug("Resolving hostname: " .. host)
    ---@diagnostic disable-next-line: undefined-field
    uv.getaddrinfo(host, nil, { family = "inet", socktype = "stream" }, function(err, res)
        if err or not res or #res == 0 then
            local msg = "Failed to resolve '" .. host .. "': " .. (err or "no address")
            self.log:error(msg)
            if self.on_output then
                vim.schedule(function()
                    self.on_output(msg .. "\n", true)
                end)
            end
            self:_terminate(1)
            return
        end

        -- Prefer IPv4, fallback to first result
        local addr = res[1].addr
        for _, r in ipairs(res) do
            if r.family == "inet" then
                addr = r.addr
                break
            end
        end

        self.log:info("Resolved " .. host .. " → " .. addr)
        vim.schedule(function()
            if not self.killed then
                self:_do_connect(addr)
            end
        end)
    end)
end

function Tcp:_do_connect(target_host)
    self.log:info("Connecting to " .. target_host .. ":" .. self.port)

    self.socket:connect(target_host, self.port, function(err)
        if err then
            local msg = "Connection failed to " .. target_host .. ":" .. self.port .. ": " .. err
            self.log:error(msg)
            if self.on_output then
                vim.schedule(function()
                    self.on_output(msg .. "\n", true)
                end)
            end
            self:_terminate(1)
            return
        end

        self.log:info("Connected successfully")
        self.is_connected = true
        self:_start_reading()
        self:_flush_queue() -- Send all queued messages now!
    end)
end

function Tcp:_start_reading()
    self.socket:read_start(function(err, chunk)
        if err then
            self.log:error("Read error: " .. err)
            self:_terminate(1)
            return
        end
        if not chunk then
            self.log:info("Connection closed by peer")
            self:_terminate(0)
            return
        end
        if self.on_output then
            self.on_output(chunk, false)
        end
    end)
end

-- Flush all queued writes
function Tcp:_flush_queue()
    if not self.is_connected or #self.write_queue == 0 then
        return
    end

    self.log:debug("Flushing " .. #self.write_queue .. " queued messages")
    for _, data in ipairs(self.write_queue) do
        local ok, err = pcall(self.socket.write, self.socket, data)
        if not ok then
            self.log:error("Failed to send queued message: " .. tostring(err))
        end
    end
    self.write_queue = {}
end

-- Public: write data (now safe to call anytime)
function Tcp:write(data)
    if self.exited or self.killed or not self.socket or self.socket:is_closing() then
        return false, "closed"
    end

    if not self.is_connected then
        self.log:debug("Queuing write (" .. #data .. " bytes) - not connected yet")
        table.insert(self.write_queue, data)
        return true -- pretend success
    end

    -- Connected: write immediately
    local ok, err = pcall(self.socket.write, self.socket, data)
    if not ok then
        self.log:error("Write failed: " .. tostring(err))
        return false, err
    end

    return true
end

-- Public: check if alive
function Tcp:running()
    return self.socket and not self.socket:is_closing() and not self.exited
end

function Tcp:kill(_)
    self:close()
end

-- Public: graceful close
function Tcp:close()
    if self.killed or self.exited then return end
    self.killed = true

    -- Clear queue on close
    self.write_queue = {}

    if self.socket and not self.socket:is_closing() then
        self.socket:shutdown(function()
            self.socket:close()
            self:_terminate(0)
        end)
    else
        self:_terminate(0)
    end
end

-- Internal: final cleanup
function Tcp:_terminate(code, signal)
    if self.exited then return end
    self.exited = true
    self.is_connected = false
    self.write_queue = {}

    if self.socket and not self.socket:is_closing() then
        self.socket:close()
    end
    self.socket = nil

    if self.on_exit then
        vim.schedule(function()
            self.on_exit(code or 0, signal or 0)
        end)
    end
end

return Tcp

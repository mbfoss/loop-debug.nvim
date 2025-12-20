
---@class loopdebug.tools.Logger
local Logger = {}
Logger.__index = Logger

------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------

local env_log_level = vim.env.NVIM_LOOP_PLUGIN_LOG_LEVEL
local log_level = env_log_level and tonumber(env_log_level) or vim.log.levels.OFF

-- Log file path
local log_file_path = vim.fs.joinpath(vim.fn.stdpath("log"), "loop-debug.log")

------------------------------------------------------------
-- INTERNALS
------------------------------------------------------------

local file_handle = nil

local LEVEL_NAMES = {
	[vim.log.levels.TRACE] = "TRACE",
	[vim.log.levels.DEBUG] = "DEBUG",
	[vim.log.levels.INFO]  = "INFO",
	[vim.log.levels.WARN]  = "WARN",
	[vim.log.levels.ERROR] = "ERROR",
}

-- Ensure log directory exists
local function ensure_dir(path)
	if vim.fn.isdirectory(path) == 0 then
		vim.fn.mkdir(path, "p")
	end
end

-- Open global log file if not already opened
local function open_log_file()
	if not file_handle then
		ensure_dir(vim.fs.dirname(log_file_path))
		file_handle = assert(io.open(log_file_path, "w"))
	end
	return file_handle
end

------------------------------------------------------------
-- REAL LOGGER CREATION
------------------------------------------------------------

local function create_real_logger(module_name, level)
	local self = setmetatable({
		module = module_name,
		log_level = level or vim.log.levels.INFO,
	}, Logger)
	return self
end

-- Fake logger (does nothing)
local fake_logger = setmetatable({
	enabled = function() return false end,
	log = function() end,
	trace = function() end,
	debug = function() end,
	info = function() end,
	warn = function() end,
	error = function() end,
}, Logger)

------------------------------------------------------------
-- CONSTRUCTOR
------------------------------------------------------------

function Logger.create_logger(module_name)
	if log_level and log_level ~= vim.log.levels.OFF then
		return create_real_logger(module_name, log_level)
	else
		return fake_logger
	end
end

------------------------------------------------------------
-- INSTANCE METHODS
------------------------------------------------------------

function Logger:enabled()
	return true
end

function Logger:log(content, level)
	level = level or vim.log.levels.INFO

	if level < log_level then
		return
	end

	local msg
	if type(content) == 'string' then
		msg = content
	elseif type(content) == 'number' then
		msg = tostring(content)
	else
		msg = vim.inspect(content)
	end

	local timestamp = os.date("%Y-%m-%d %H:%M:%S")
	local level_name = LEVEL_NAMES[level] or tostring(level)
    
    ---@diagnostic disable-next-line: undefined-field
	local line = string.format("[%s] [%s] [%s] %s\n", timestamp, level_name, self.module, msg)

	local file = open_log_file()
	file:write(line)
	file:flush()
end

function Logger:trace(content)
	self:log(content, vim.log.levels.TRACE)
end

function Logger:debug(content)
	self:log(content, vim.log.levels.DEBUG)
end

function Logger:info(content)
	self:log(content, vim.log.levels.INFO)
end

function Logger:warn(content)
	self:log(content, vim.log.levels.WARN)
end

function Logger:error(content)
	self:log(content, vim.log.levels.ERROR)
end

return Logger

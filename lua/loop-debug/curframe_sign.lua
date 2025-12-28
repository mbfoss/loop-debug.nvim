---@class loop.signs
local M           = {}

local debugevents = require('loop-debug.debugevents')
local signsmgr    = require('loop-debug.tools.signsmgr')
local config      = require("loop-debug.config")
local filetools   = require('loop.tools.file')
local uitools     = require('loop.tools.uitools')

local _sign_group = "currentframe"
local _sign_name  = "currentframe"

local _init_done  = false

function M.init()
    if _init_done then return end
    _init_done = true

    local highlight = "LoopDebugCurrentFrame"
    vim.api.nvim_set_hl(0, highlight, { link = "Todo" })

    signsmgr.define_sign_group(_sign_group, config.current and config.current.sign_priority.currentframe or 13)
    signsmgr.define_sign(_sign_group, _sign_name, "▶", highlight)

    debugevents.add_tracker({
        on_debug_start = function()

        end,
        on_debug_end = function(success)

        end,
        on_view_udpate = function(view)
            local frame = view.frame
            if not (frame and frame.source and frame.source.path) then
                signsmgr.remove_signs(_sign_group)
            else
                if not filetools.file_exists(frame.source.path) then return end
                -- Open file and move cursor
                uitools.smart_open_file(frame.source.path, frame.line, frame.column)
                -- Place sign for current frame
                signsmgr.place_file_sign(1, frame.source.path, frame.line, _sign_group, _sign_name)
            end
        end
    })
end

return M

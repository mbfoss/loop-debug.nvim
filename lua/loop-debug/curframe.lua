---@class loop.signs
local M                = {}

local signsmgr             = require('loop-debug.tools.signsmgr')
local config           = require("loop-debug.config")
local Trackers         = require('loop.tools.Trackers')



local _sign_group = "currentframe"
local _sign_name = "currentframe"

-- -------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------

-- -------------------------------------------------------------------
-- Setup
-- -------------------------------------------------------------------

function M.init()
    if _init_done then return end
    _init_done = true

    _define_sign("currentframe", "▶", "Todo")

    vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload" }, {
        callback = function(ev)
            _remove_buf_signs(ev.buf, "breakpoints")
            _remove_buf_signs(ev.buf, "currentframe")
        end,
    })

    vim.api.nvim_create_autocmd("BufReadPost", {
        callback = function(ev)
            _apply_buffer_signs(ev.buf, "breakpoints")
            _apply_buffer_signs(ev.buf, "currentframe")
        end,
    })
end

return M

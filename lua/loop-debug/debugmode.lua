local M = {}
local notifications = require('loop.notifications')

local _debug_mode_detection = vim.api.nvim_create_augroup("LoopPluginDebugModeDetect", { clear = true })
local _debug_mode_line_hl = vim.api.nvim_create_namespace("LoopPluginDebugLine")

---@type fun(cmd: loop.job.DebugJob.Command)|nil
M.command_function = nil

local _debug_mode_on
local _last_hl_bufnr
local _next_winleave_ok = false

local saved = {
    original_maps = nil, -- only h/j/k/l
    scrolloff = nil,
}

local DEBUG_KEYS = { "h", "j", "k", "l", "c", "C", "t", "T" }

local function debug_cmd(cmd)
    if not M.command_function then
        notifications.notify("No active debug session", vim.log.levels.WARN)
        return
    end
    M.command_function(cmd)
end

function M.is_active()
    return _debug_mode_on
end

---@param ok boolean
function M.next_winleave_ok(ok)
    _next_winleave_ok = ok
end

local function _clear_highlight(bufnr)
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, _debug_mode_line_hl, 0, -1)
    end
end

---@param line? number Line to highlight (1-indexed)
---@param bufnr? number Buffer number, default: current
function M.highlight_line(line, bufnr)
    if not _debug_mode_on then return end

    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local hl = "Visual"

    _clear_highlight(_last_hl_bufnr)
    _last_hl_bufnr = bufnr
    -- Place extmark for highlight
    vim.api.nvim_buf_set_extmark(bufnr, _debug_mode_line_hl, line - 1, 0, {
        hl_group = hl,
        end_line = line,
        end_col = 0,
        hl_eol = true,
    })
end

-- -------------------------------------------------------------------
-- ENABLE
-- -------------------------------------------------------------------
function M.enable_debug_mode()
    if _debug_mode_on then
        return
    end

    vim.schedule(function()
        vim.cmd.stopinsert()
    end)

    -- Save original scrolloff
    saved.scrolloff = vim.wo.scrolloff
    -- Force a nice scroll margin for debugging
    vim.wo.scrolloff = 8 -- adjust as needed

    -- Save original mappings
    saved.original_maps = {}
    for _, key in ipairs(DEBUG_KEYS) do
        local map = vim.fn.maparg(key, "n", false, true)
        if map and (map.rhs ~= "" or map.callback) then
            saved.original_maps[key] = map
        end
    end

    local opts = { noremap = true, silent = true }

    -- Override debug keys
    vim.keymap.set("n", "h", function() debug_cmd("step_out") end, opts)
    vim.keymap.set("n", "j", function() debug_cmd("step_over") end, opts)
    vim.keymap.set("n", "k", function() debug_cmd("step_back") end, opts)
    vim.keymap.set("n", "l", function() debug_cmd("step_in") end, opts)
    vim.keymap.set("n", "c", function() debug_cmd("continue") end, opts)

    -- <Esc> to exit (in all modes)
    vim.keymap.set({ "n", "i", "v", "x", "s", "o" }, "<Esc>", function()
        M.disable_debug_mode()
    end, opts)

    vim.api.nvim_create_autocmd("WinLeave", {
        group = _debug_mode_detection,
        callback = function()
            if _debug_mode_on and not _next_winleave_ok then
                M.disable_debug_mode()
            end
            _next_winleave_ok = false
        end,
    })

    vim.api.nvim_create_autocmd("ModeChanged", {
        group = _debug_mode_detection, -- assign to our group
        pattern = "n:*",  -- old mode is n, new can be anything
        callback = function()
            M.disable_debug_mode()
        end,
    })

    _debug_mode_on = true

    --local left = "%#ErrorMsg# 🐞 DEBUGGING %#Normal#"
    --local right = "%#Comment#h:Out j:Over k:Back l:In c:Cont Esc:Exit%#Normal#"
    --vim.wo.winbar = string.format(" %s %%= %s ", left, right)
end

-- -------------------------------------------------------------------
-- DISABLE
-- -------------------------------------------------------------------
function M.disable_debug_mode()
    if not _debug_mode_on then return end

    -- Remove our mappings
    for _, key in ipairs(DEBUG_KEYS) do
        pcall(vim.keymap.del, "n", key)
    end
    pcall(vim.keymap.del, { "n", "i", "v", "x", "s", "o" }, "<Esc>")

    -- Restore previous hjkl mappings
    for key, map in pairs(saved.original_maps or {}) do
        local o = {
            noremap = map.noremap == 1,
            silent  = map.silent == 1,
            nowait  = map.nowait == 1,
            expr    = map.expr == 1,
        }
        if map.callback then
            vim.keymap.set("n", key, map.callback, o)
        elseif map.rhs and map.rhs ~= "" then
            vim.api.nvim_set_keymap("n", key, map.rhs, o)
        end
    end

    if saved.scrolloff ~= nil then
        vim.wo.scrolloff = saved.scrolloff
    end

    saved.original_maps = nil
    saved.scrolloff = nil

    _clear_highlight(_last_hl_bufnr)
    vim.api.nvim_clear_autocmds({ group = _debug_mode_detection })
    --vim.wo.winbar = nil

    _debug_mode_on = nil
end

-- -------------------------------------------------------------------
-- Toggle
-- -------------------------------------------------------------------
function M.toggle_debug_mode()
    if _debug_mode_on then
        M.disable_debug_mode()
    else
        M.enable_debug_mode()
    end
end

return M

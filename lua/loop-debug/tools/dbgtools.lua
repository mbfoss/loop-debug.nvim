local M = {}

local MAX_INSPECT_BYTES = 512

--- Gets text from a visual selection or a user-command range
---@param opts vim.api.keyset.create_user_command.command_args
---@return string|nil expr
---@return string|nil err
local function _get_selection_for_inspect(opts)
    if not opts.range or opts.range <= 0 then
        return nil, nil
    end
    if opts.line1 ~= opts.line2 then
        return nil, "Multline select is not supported in inspect"
    end
    -- fallback to visual marks
    local s = vim.fn.getpos("'<")
    local e = vim.fn.getpos("'>")
    if not s or not e or s[2] == 0 or e[2] == 0 then
        return nil, "no visual selection or range"
    end

    local srow, scol = s[2] - 1, s[3] - 1
    local erow, ecol = e[2] - 1, e[3]

    -- handle line-wise visual
    if vim.fn.visualmode() == "V" then
        scol = 0
        local line = vim.fn.getline(erow + 1)
        ecol = #line
    end

    local lines = vim.api.nvim_buf_get_text(0, srow, scol, erow, ecol or -1, {})
    if #lines == 0 then
        return nil, "empty selection"
    end

    local text = table.concat(lines, "\n")
    if #text > MAX_INSPECT_BYTES then
        return nil, "selection too large to inspect"
    end
    return text, nil
end

--- Gets the expression to send to dap.evaluate()
---@param opts vim.api.keyset.create_user_command.command_args
---@return string|nil expr
---@return string|nil err
function M.get_value_for_inspect(opts)
    -- 1. Selection or range
    local text, err = _get_selection_for_inspect(opts)
    if text then
        return text, nil
    end
    if err then
        return nil, err
    end

    -- 2. Expression under cursor (fallback)
    local expr = vim.fn.expand("<cexpr>")

    if expr == "" then
        return nil, "no expression under cursor"
    elseif #expr > MAX_INSPECT_BYTES then
        return nil, "expression under cursor is too large to inspect"
    end

    return expr, nil
end

return M

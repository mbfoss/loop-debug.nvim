local M = {}

local MAX_INSPECT_BYTES = 512

local function trim_expr(expr)
    return expr
        :gsub("^%s+", "")
        :gsub("%s+$", "")
        :gsub("^[%(%{%[%<\"']+", "")
        :gsub("[%>%}%]%)\"';,]+$", "")
end

local function get_visual_selection()
    local mode = vim.fn.mode()
    if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
        return nil, nil
    end

    local s = vim.fn.getpos("'<")
    local e = vim.fn.getpos("'>")

    local srow, scol = s[2] - 1, s[3] - 1
    local erow, ecol = e[2] - 1, e[3]

    local lines = vim.api.nvim_buf_get_text(0, srow, scol, erow, ecol, {})
    if #lines == 0 then
        return nil, nil
    end

    local text = table.concat(lines, "\n")
    if #text > MAX_INSPECT_BYTES then
        return nil, "visual selection too large to inspect"
    end

    text = trim_expr(text)
    if text == "" then
        return nil, "visual selection is empty after trimming"
    end

    return text, nil
end

--- Gets the expression to send to dap.evaluate()
--- @return string|nil expr
--- @return string|nil err
function M.get_value_for_inspect()
    -- 1. Visual selection (bounded)
    local visual, err = get_visual_selection()
    if visual then
        return visual, nil
    end
    if err then
        return nil, err
    end

    -- 2. Expression under cursor (Neovim 0.10+)
    local expr = vim.fn.expand("<cexpr>")
    expr = trim_expr(expr)
    if expr == "" then
        return nil, "no expression under cursor"
    end

    if #expr > MAX_INSPECT_BYTES then
        return nil, "expression under cursor is too large to inspect"
    end

    return expr, nil
end

return M

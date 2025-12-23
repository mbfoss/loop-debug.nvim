local M = {}

--- Gets the text based on current mode (Normal/Visual)
function M.get_vetted_text()
    local mode = vim.api.nvim_get_mode().mode
    local text = ""

    if mode:find("[vV\22]") then
        -- 1. Visual Mode: Get selection
        -- Use "gv" to ensure marks are updated to current selection
        local _, start_row, start_col, _ = unpack(vim.fn.getpos("v"))
        local _, end_row, end_col, _ = unpack(vim.fn.getpos("."))

        -- Standardize start/end if user selected backwards
        if start_row > end_row or (start_row == end_row and start_col > end_col) then
            start_row, end_row = end_row, start_row
            start_col, end_col = end_col, start_col
        end

        local lines = vim.api.nvim_buf_get_text(0, start_row - 1, start_col - 1, end_row - 1, end_col, {})
        text = table.concat(lines, "\n")

        -- Limit length to 100 characters
        if #text > 100 then
            text = text:sub(1, 100)
        end
    else
        -- 2. Normal Mode: Get word and trim edge symbols
        local word = vim.fn.expand("<cword>")

        -- Pattern: ^%p* (leading symbols), (.-) (the word), %p*$ (trailing symbols)
        -- The hyphen makes the match non-greedy
        text = word:match("^%p*(.-)%p*$") or ""
    end

    return text
end

return M

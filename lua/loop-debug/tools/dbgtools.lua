local M = {}

--- Gets the text based on current mode (Normal/Visual)
function M.clean_cword()
    -- 2. Normal Mode: Get word and trim edge symbols
    local word = vim.fn.expand("<cword>")

    -- Pattern: ^%p* (leading symbols), (.-) (the word), %p*$ (trailing symbols)
    -- The hyphen makes the match non-greedy
    return word:match("^%p*(.-)%p*$") or ""
end

return M

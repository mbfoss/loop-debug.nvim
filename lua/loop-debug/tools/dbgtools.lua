local M = {}

function M.get_expression_user_cursor()
    -- 1. Check for Visual Selection first
    -- This is the "gold standard" for evaluating specific parts of a line
    local mode = vim.api.nvim_get_mode().mode
    if mode:match("^[vV]") then
        -- This helper gets the text of the last visual selection
        local _, start_row, start_col, _ = unpack(vim.fn.getpos("v"))
        local _, end_row, end_col, _ = unpack(vim.fn.getpos("."))

        -- Correct for 1-based indexing and potential backwards selection
        if start_row > end_row or (start_row == end_row and start_col > end_col) then
            start_row, end_row = end_row, start_row
            start_col, end_col = end_col, start_col
        end

        local lines = vim.api.nvim_buf_get_text(0, start_row - 1, start_col - 1, end_row - 1, end_col, {})
        return table.concat(lines, "\n")
    end

    -- 2. Try Tree-sitter (Best for Python attributes like self.name)
    local node = vim.treesitter.get_node()
    if node then
        -- We look for common "expression" types
        -- In Python: 'attribute' is self.x, 'subscript' is list[0]
        local expr_types = {
            ["attribute"] = true,
            ["subscript"] = true,
            ["identifier"] = true,
            ["call"] = true, -- eval a function call under cursor
        }

        local target = node
        while target do
            if expr_types[target:type()] then
                -- Check if parent is also an expression (to get the "fullest" path)
                local parent = target:parent()
                if parent and expr_types[parent:type()] then
                    target = parent
                else
                    break
                end
            else
                target = target:parent()
            end
        end

        if target then
            return vim.treesitter.get_node_text(target, 0)
        end
    end

    -- 3. Fallback to Word under cursor
    return vim.fn.expand("<cword>")
end

-- Example usage with nvim-dap
-- vim.keymap.set('n', '<leader>de', function()
--     require('dapui').eval(M.get_dap_expression())
-- end)

return M

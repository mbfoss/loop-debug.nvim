local M = {}

---@return string|nil expr
---@return nil|string  error
function M.get_identifier_under_cursor()
    local bufnr = vim.api.nvim_get_current_buf()

    -- 1. Ensure we have a parser and a tree
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
    if not ok or not parser then
        return nil, "treesitter parser not available"
    end

    -- 2. Force a parse to ensure the tree is up to date
    local tree = parser:parse()[1]
    if not tree then
        return nil, "treesitter parser error"
    end

    -- 3. Get node at cursor specifically
    -- We use get_node with specific buffer/pos params for better reliability
    local node = vim.treesitter.get_node({ bufnr = bufnr })

    if node then
        -- important: don't include call expressions
        local expr_types = {
            attribute           = true,
            subscript           = true,
            identifier          = true,
            field_expression    = true,
            member_expression   = true,
            property_identifier = true,
        }

        ---@type TSNode?
        local target = node

        -- Walk up the tree to find the top-most "expression" node
        while target do
            local parent = target:parent()
            if parent and expr_types[parent:type()] then
                target = parent
            else
                -- If the current target is an expression type, keep it.
                -- Otherwise, it might be a child (like a '(') of an expression.
                if not expr_types[target:type()] and parent then
                    target = parent
                end
                break
            end
        end

        if target and expr_types[target:type()] then
            local text = vim.treesitter.get_node_text(target, bufnr)
            if text and #text > 0 then
                return text
            end
        end
    end
    return nil
end

return M

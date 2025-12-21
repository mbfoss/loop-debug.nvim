local M = {}

---@type string[]
local _watch_exprs = {}

---Retrieve the list of all currently watched expressions.
---@return string[]
function M.get()
    return _watch_exprs
end

---Retrieve the list of all currently watched expressions.
---@param values string[]
function M.set(values)
    if type(values) ~= "table" then return end
    _watch_exprs = values
end

---Add a new expression to the watch list.
---Prevents duplicates from being added.
---@param expr string The expression to watch.
---@return boolean added
function M.add(expr)
    if type(expr) ~= "string" or expr == "" then return false end

    -- Check for duplicates to keep the list clean
    for _, v in ipairs(_watch_exprs) do
        if v == expr then return false end
    end

    table.insert(_watch_exprs, expr)
    return true
end

---Remove a specific expression from the watch list.
---@param expr string The expression to remove.
function M.remove(expr)
    for i, v in ipairs(_watch_exprs) do
        if v == expr then
            table.remove(_watch_exprs, i)
            break
        end
    end
end

---Remove all expressions from the watch list.
function M.clear()
    _watch_exprs = {}
end

return M

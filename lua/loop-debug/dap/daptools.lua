local M = {}

--- Format a DAP error body into a human-readable string
--- @param body table|nil  DAP response body
--- @return string|nil
function M.dap_error_to_string(body)
    if not body or type(body) ~= "table" then
        return nil
    end

    local err = body.error
    if not err or type(err) ~= "table" then
        return nil
    end

    local fmt = err.format
    if type(fmt) ~= "string" or fmt == "" then
        return nil
    end

    local vars = err.variables or {}

    -- Replace {var} with variables[var]
    local msg = fmt:gsub("{(.-)}", function(key)
        local v = vars[key]
        if v == nil then
            return "{" .. key .. "}"
        end
        return tostring(v)
    end)

    return msg
end


return M

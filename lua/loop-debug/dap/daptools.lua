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


---@param basesession loopdebug.BaseSession
---@param expiry_check fun():boolean
---@return loopdebug.session.DataProviders
function M.create_data_providers(basesession, expiry_check)
    
    local is_na = expiry_check
    local na_msg = "not available"

    ---@type loopdebug.session.ThreadsProvider
    local threads_provider = function(callback)
        if is_na() then
            callback(na_msg, nil)
            return
        end
        basesession:request_threads(function(err, body)
            if is_na() then
                callback(na_msg, nil)
            else
                callback(err, body)
            end
        end)
    end


    ---@type loopdebug.session.StackProvider
    local stack_provider = function(req, callback)
        if is_na() then
            callback(na_msg, nil)
            return
        end
        basesession:request_stackTrace(req, function(err, body)
            if is_na() then
                callback(na_msg, nil)
            else
                callback(err, body)
            end
        end)
    end

    ---@type loopdebug.session.ScopesProvider
    local scopes_provider = function(req, callback)
        if is_na() then
            callback(na_msg, nil)
            return
        end
        basesession:request_scopes(req, function(err, body)
            if is_na() then
                callback(na_msg, nil)
            else
                callback(err, body)
            end
        end)
    end

    ---@type loopdebug.session.VariablesProvider
    local variables_provider = function(req, callback)
        if is_na() then
            callback(na_msg, nil)
            return
        end
        basesession:request_variables(req, function(err, body)
            if is_na() then
                callback(na_msg, nil)
            else
                callback(err, body)
            end
        end)
    end

    ---@type loopdebug.session.EvaluateProvider
    local evaluate_provider = function(req, callback)
        if is_na() then
            callback(na_msg, nil)
            return
        end
        basesession:request_evaluate(req, function(err, body)
            if is_na() then
                callback(na_msg, nil)
            else
                callback(err, body)
            end
        end)
    end

    ---@type loopdebug.session.DataProviders
    return {
        threads_provider = threads_provider,
        stack_provider = stack_provider,
        scopes_provider = scopes_provider,
        variables_provider = variables_provider,
        evaluate_provider = evaluate_provider,
    }
end

return M

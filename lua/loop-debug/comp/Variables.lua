local class        = require('loop.tools.class')
local floatwin     = require('loop.tools.floatwin')
local ItemTreeComp = require('loop.comp.ItemTree')
local persistence  = require('loop-debug.persistence')
local daptools     = require('loop-debug.dap.daptools')
local debugevents  = require('loop-debug.debugevents')

---@alias loopdebug.comp.Variables.Item loop.comp.ItemTree.Item

---@class loopdebug.comp.Vars.DataSource
---@field sess_id number
---@field sess_name string
---@field data_providers loopdebug.session.DataProviders
---@field frame loopdebug.proto.StackFrame

---@class loopdebug.comp.Variables : loop.comp.ItemTree
---@field new fun(self: loopdebug.comp.Variables, name:string): loopdebug.comp.Variables
local Variables    = class(ItemTreeComp)

---@param parent_id any
---@param name string
---@param index number
---@return string
local function _get_semantic_id(parent_id, name, index)
    return string.format("%s::%s#%d", tostring(parent_id), name, index)
end

---@param str string
---@param max_len number
---@return string preview
---@return boolean is_different
local function _preview_string(str, max_len)
    max_len = max_len > 2 and max_len or 2
    if #str < max_len and not str:find("\n", 1, true) then
        return str, false
    end
    local preview = str:gsub("\n", "⏎")
    if #preview <= max_len then return preview, true end
    return vim.fn.trim(preview:sub(1, max_len), "", 2) .. "…"
end

---@param expr string
---@return boolean
local function _add_watch_expr(expr)
    if not persistence.is_ws_open() then return false end
    local data = persistence.get_config("watch") or {}
    ---@cast data string[]
    for _, v in ipairs(data) do if v == expr then return false end end
    table.insert(data, expr)
    persistence.set_config("watch", data)
    return true
end

---@param old string
---@param new string
---@return boolean
local function _replace_watch_expr(old, new)
    local data = persistence.get_config("watch")
    if not data then return false end
    ---@cast data string[]
    for i, v in ipairs(data) do
        if v == old then
            data[i] = new
            persistence.set_config("watch", data)
            return true
        end
    end
    return false
end

---@param expr string
---@return boolean
local function _remove_watch_expr(expr)
    local data = persistence.get_config("watch")
    if not data then return false end
    ---@cast data string[]
    for i, v in ipairs(data) do
        if v == expr then
            table.remove(data, i)
            persistence.set_config("watch", data)
            return true
        end
    end
    return false
end

---@type table<string, string>
local _var_kind_to_hl_group = {
    property   = "@property",
    method     = "@method",
    ["class"]  = "@type",
    data       = "@variable",
    event      = "@event",
    baseClass  = "@type",
    innerClass = "@type",
    interface  = "@type",
}

---@param id any
---@param data any
---@param highlights loop.Highlight[]
---@return string
local function _variable_node_formatter(id, data, highlights)
    if not data then return "" end
    if data.is_na and not data.name then
        table.insert(highlights, { group = "NonText" })
        return "not available"
    end

    local hl = data.greyout and "NonText" or nil

    if data.scopelabel then
        table.insert(highlights, { group = hl or "Directory" })
        return data.scopelabel
    end

    local name = tostring(data.name or "unknown")
    local value = daptools.format_variable(tostring(data.value or ""), data.presentationHint)
    local preview, is_different = _preview_string(value, vim.o.columns - 20)

    table.insert(highlights, { group = hl or "@symbol", start_col = 0, end_col = #name })

    local start = #name
    table.insert(highlights, { group = hl or "NonText", start_col = start, end_col = start + 2 })

    start = start + 2
    local kind = data.presentationHint and data.presentationHint.kind
    local val_hl = hl or _var_kind_to_hl_group[kind] or "@variable"
    table.insert(highlights, { group = val_hl, start_col = start, end_col = start + #preview })

    return name .. ': ' .. preview
end

function Variables:init()
    ItemTreeComp.init(self, {
        formatter = _variable_node_formatter,
        loading_char = "⧗",
        render_delay_ms = 200,
    })

    self._query_context = 0
    ---@type loopdebug.events.CurrentViewUpdate|nil
    self._current_data_source = nil
    ---@type table<string, boolean>
    self._layout_cache = {}

    self:add_tracker({
        on_toggle = function(_, data, expanded)
            self._layout_cache[data.path] = expanded
        end,
        on_open = function(_, data)
            if data.scopelabel or data.is_na then return end
            floatwin.show_floatwin(data.name or "value",
                daptools.format_variable(tostring(data.value), data.presentationHint))
        end
    })

    ---@type loop.TrackerRef?
    self._events_tracker_ref = debugevents.add_tracker({
        on_view_udpate = function(view)
            self._current_data_source = view
            self._query_context = self._query_context + 1
            self:_update_data(self._query_context)
        end
    })

    ---@type loop.TrackerRef?
    self._persistence_tracker_ref = persistence.add_tracker({
        on_ws_open = function() self:_update_data(self._query_context) end
    })
end

---@param ctx number
function Variables:_update_data(ctx)
    local items = self:get_items()
    for _, item in ipairs(items) do item.data.greyout = true end
    self:refresh_content()

    self:_load_watch_expressions(ctx)
    self:_load_session_vars(ctx)
end

---@param context number
---@param data_providers loopdebug.session.DataProviders
---@param ref number
---@param parent_id any
---@param parent_path string
---@param callback fun(items:loopdebug.comp.Variables.Item[])
function Variables:_load_variables(context, data_providers, ref, parent_id, parent_path, callback)
    data_providers.variables_provider({ variablesReference = ref }, function(_, vars_data)
        if self._query_context ~= context then return end
        local children = {}
        if vars_data and vars_data.variables then
            for idx, var in ipairs(vars_data.variables) do
                local item_id = _get_semantic_id(parent_id, var.name, idx)
                local path = parent_path .. '/' .. var.name

                ---@type loopdebug.comp.Variables.Item
                local var_item = {
                    id = item_id,
                    parent_id = parent_id,
                    expanded = self._layout_cache[path],
                    data = {
                        path = path,
                        name = var.name,
                        value = var.value,
                        presentationHint = var.presentationHint
                    },
                }

                if var.variablesReference and var.variablesReference > 0 then
                    var_item.children_callback = function(cb)
                        if var_item.data.greyout then
                            cb({})
                        else
                            self:_load_variables(context, data_providers, var.variablesReference, item_id, path, cb)
                        end
                    end
                end
                table.insert(children, var_item)
            end
        end
        callback(children)
    end)
end

---@param context number
---@param parent_id string
---@param parent_path string
---@param scopes loopdebug.proto.Scope[]
---@param data_source loopdebug.events.CurrentViewUpdate
---@param scopes_cb loop.comp.ItemTree.ChildrenCallback
function Variables:_load_scopes(context, parent_id, parent_path, scopes, data_source, scopes_cb)
    ---@type loop.comp.ItemTree.Item[]
    local scope_items = {}
    for idx, scope in ipairs(scopes) do
        local path = parent_path .. '/' .. scope.name
        local item_id = _get_semantic_id(parent_id, scope.name, idx)

        local expanded = self._layout_cache[path]
        if expanded == nil then
            expanded = not (scope.expensive or scope.presentationHint == "globals" or scope.name == "Registers")
        end

        ---@type loop.comp.ItemTree.Item
        local scope_item = {
            id = item_id,
            parent_id = parent_id,
            expanded = expanded,
            data = { path = path, scopelabel = (scope.expensive and "⏱ " or "") .. scope.name }
        }
        scope_item.children_callback = function(cb)
            self:_load_variables(context, data_source.data_providers, scope.variablesReference, item_id, path, cb)
        end
        table.insert(scope_items, scope_item)
    end
    scopes_cb(scope_items)
end

---@param context number
function Variables:_load_watch_expressions(context)
    local root_id = "w"
    local root_expanded = self._layout_cache[root_id]
    if root_expanded == nil then root_expanded = true end

    self:upsert_item({ id = root_id, expanded = root_expanded, data = { path = root_id, scopelabel = "Watch" } })

    if not persistence.is_ws_open() then return end
    local list = persistence.get_config("watch") or {}
    ---@cast list string[]
    local active_ids = {}

    for idx, expr in ipairs(list) do
        local item_id = "watch_index_" .. tostring(idx)
        active_ids[item_id] = true
        self:_load_watch_expr_value(context, expr, item_id)
    end

    for _, item in ipairs(self:get_items()) do
        if item.parent_id == root_id and not active_ids[item.id] then
            self:remove_item(item.id)
        end
    end
end

---@param context number
---@param expr string
---@param item_id any
function Variables:_load_watch_expr_value(context, expr, item_id)
    local path = "w/" .. expr

    -- Check if we already have this item to preserve existing data during greyout
    local existing = self:get_item(item_id)

    ---@type loopdebug.comp.Variables.Item
    local var_item = {
        id = item_id,
        parent_id = "w",
        expanded = self._layout_cache[path],
        data = existing and existing.data or { path = path, is_expr = true, name = expr }
    }
    -- Ensure the name is correct if it was renamed
    var_item.data.name = expr

    local ds = self._current_data_source
    if not ds or not ds.frame or not ds.data_providers then
        -- Keep existing data but ensure it is marked as greyed out
        var_item.data.greyout = true
        self:upsert_item(var_item)
        return
    end

    ds.data_providers.evaluate_provider({
        expression = expr, frameId = ds.frame.id, context = 'watch',
    }, function(err, data)
        if self._query_context ~= context then return end
        if err or not data then
            var_item.data.value, var_item.data.is_na = "not available", true
        else
            var_item.data.value = data.result
            var_item.data.presentationHint = data.presentationHint
            var_item.data.is_na = false
            var_item.data.greyout = false
            if data.variablesReference and data.variablesReference > 0 then
                var_item.children_callback = function(cb)
                    self:_load_variables(context, ds.data_providers, data.variablesReference, item_id, path, cb)
                end
            end
        end
        self:upsert_item(var_item)
    end)
end

---@param context number
function Variables:_load_session_vars(context)
    local root_id = "s"
    local root_expanded = self._layout_cache[root_id]
    if root_expanded == nil then root_expanded = true end

    ---@type loop.comp.ItemTree.Item
    local root_item = {
        id = root_id, expanded = root_expanded, data = { path = root_id, scopelabel = "Variables" }
    }

    local ds = self._current_data_source
    if ds and ds.frame then
        root_item.children_callback = function(cb)
            ds.data_providers.scopes_provider({ frameId = ds.frame.id }, function(_, scopes_data)
                if self._query_context ~= context then return end
                if scopes_data and scopes_data.scopes then
                    self:_load_scopes(context, root_id, root_id, scopes_data.scopes, ds, cb)
                else
                    cb({ { id = "na", data = { is_na = true } } })
                end
            end)
        end
    end
    self:upsert_item(root_item)
end

---@param comp loop.CompBufferController
function Variables:link_to_buffer(comp)
    ItemTreeComp.link_to_buffer(self, comp)

    ---@param item loopdebug.comp.Variables.Item|nil
    local function add_or_edit_watch(item)
        floatwin.input_at_cursor({
            default_text = item and item.data.name or "",
            on_confirm = function(expr)
                if not expr or expr == "" then return end
                if not item then
                    if _add_watch_expr(expr) then
                        -- ONLY reload watches
                        self:_load_watch_expressions(self._query_context)
                    end
                elseif expr ~= item.data.name then
                    if _replace_watch_expr(item.data.name, expr) then
                        -- ONLY reload watches
                        self:_load_watch_expressions(self._query_context)
                    end
                end
            end
        })
    end

    comp.add_keymap("i", { desc = "Add watch", callback = function() add_or_edit_watch() end })
    comp.add_keymap("c", {
        desc = "Edit watch",
        callback = function()
            local cur = self:get_cur_item(comp)
            if cur and cur.data.is_expr then add_or_edit_watch(cur) end
        end
    })
    comp.add_keymap("d", {
        desc = "Delete watch",
        callback = function()
            local cur = self:get_cur_item(comp)
            if cur and cur.data.is_expr then
                _remove_watch_expr(cur.data.name)
                self:remove_item(cur.id)
                -- ONLY reload watches to sync indices
                self:_load_watch_expressions(self._query_context)
            end
        end
    })
end

function Variables:dispose()
    ItemTreeComp.dispose(self)
    if self._events_tracker_ref then self._events_tracker_ref.cancel() end
    if self._persistence_tracker_ref then self._persistence_tracker_ref.cancel() end
end

return Variables

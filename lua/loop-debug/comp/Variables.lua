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

---@param str string
---@param max_len number
---@return string preview
---@return boolean is_different
local function _preview_string(str, max_len)
    max_len = max_len > 2 and max_len or 2
    -- check conditions for returning as-is
    if #str < max_len and not str:find("\n", 1, true) then
        return str, false
    end
    if #str < max_len then
        -- replace newlines
        preview = str:gsub("\n", "⏎")
        return preview, true
    end
    local preview = str:sub(1, max_len):gsub("\n", "⏎")
    preview = vim.fn.trim(preview, "", 2) .. "…"
    return preview, true
end

---@param expr string
---@return boolean
function _add_watch_expr(expr)
    if not persistence.is_ws_open() then return false end
    local data = persistence.get_config("watch") or {}
    ---@cast data string[]
    for _, v in ipairs(data) do
        if v == expr then return false end
    end
    table.insert(data, expr)
    persistence.set_config("watch", data)
    return true
end

---@param old string
---@param new string
---@return boolean
function _replace_watch_expr(old, new)
    local data = persistence.get_config("watch")
    if data then
        ---@cast data string[]
        for i, v in ipairs(data) do
            if v == old then
                data[i] = new
                persistence.set_config("watch", data)
                return true
            end
        end
    end
    return false
end

---@param expr string
---@return boolean
function _remove_watch_expr(expr)
    local data = persistence.get_config("watch")
    if data then
        ---@cast data string[]
        for i, v in ipairs(data) do
            if v == expr then
                table.remove(data, i)
                persistence.set_config("watch", data)
                return true
            end
        end
    end
    return false
end

local _last_node_id = 0
local function _make_node_id()
    _last_node_id = _last_node_id + 1
    return _last_node_id
end

local _var_kind_to_hl_group = {
    property         = "@property",
    method           = "@method",
    ["class"]        = "@type",
    data             = "@variable",
    event            = "@event",
    baseClass        = "@type",
    innerClass       = "@type",
    interface        = "@type",
    mostDerivedClass = "@type",
    virtual          = "@keyword",
}
---@param kind? loopdebug.proto.VariablePresentationHint.Kind
---@return string
function _get_var_highlight(kind)
    if not kind then
        return "@variable"
    end
    return _var_kind_to_hl_group[kind] or "@variable"
end

---@param id any
---@param data any
---@param highlights loop.Highlight
---@return string
local function _variable_node_formatter(id, data, highlights)
    if data.is_na and not data.name then
        table.insert(highlights, { group = "NonText" })
        return "not available"
    end

    local hl = data.greyout and "NonText" or nil

    if not data then return "" end
    if data.scopelabel then
        table.insert(highlights, { group = hl or "Directory" })
        return data.scopelabel
    end

    local hint = data.presentationHint
    local name = data.name and tostring(data.name) or "unknown"
    local value = data.value and tostring(data.value) or ""

    value = daptools.format_variable(value, hint)
    local preview, is_different = _preview_string(value, vim.o.columns)
    table.insert(highlights, { group = hl or "@symbol", start_col = 0, end_col = #name })
    if data.is_na or data.greyout then
        table.insert(highlights, { group = hl or "NonText", start_col = #name })
    else
        local start_col = #name
        local end_col = start_col + 2
        table.insert(highlights, { group = hl or "NonText", start_col = start_col, end_col = end_col })
        start_col = end_col
        end_col = start_col + #preview
        local kind = hint and hint.kind or nil
        table.insert(highlights, { group = _get_var_highlight(kind), start_col = start_col, end_col = end_col })
        if is_different then
            start_col = end_col
            end_col = start_col + 1
            table.insert(highlights, { group = hl or "NonText", start_col = start_col, end_col = end_col })
        end
    end
    return name .. ': ' .. preview
end

---@param id any
---@param data any
local function _open_value_floatwin(id, data)
    if data.is_na then
        return
    end
    if data.scopelabel then
        return
    end
    local hint = data.presentationHint
    local value = data.value and tostring(data.value) or ""
    local title = data.name or "value"
    floatwin.show_floatwin(title, daptools.format_variable(value, hint))
end

function Variables:init()
    ItemTreeComp.init(self, {
        formatter = _variable_node_formatter,
        render_delay_ms = 300,
    })

    ---@type number
    self._query_context = 0

    ---@type loopdebug.events.CurrentViewUpdate|nil
    self._current_data_source = nil

    ---@type table<any,boolean> -- id --> expanded
    self._layout_cache = {}
    self:add_tracker({
        on_toggle = function(id, data, expanded)
            self._layout_cache[data.path] = expanded
        end,
        on_open = function(id, data)
            _open_value_floatwin(id, data)
        end
    })

    ---@type loop.TrackerRef?
    self._events_tracker_ref = debugevents.add_tracker({
        on_debug_start = function()
        end,
        on_debug_end = function()
        end,
        on_session_added = function(id, info)
        end,
        on_session_removed = function(id)
        end,
        on_view_udpate = function(view)
            self._current_data_source = view
            self._query_context = self._query_context + 1
            self:_update_data(self._query_context)
        end
    })

    self._persistence_tracker_ref = persistence.add_tracker({
        on_ws_open = function()
            self:_update_data(self._query_context)
        end,
        on_ws_closed = function()
        end,
        on_ws_will_save = function()
        end
    })
end

function Variables:dispose()
    ItemTreeComp.dispose(self)
    if self._events_tracker_ref then
        self._events_tracker_ref.cancel()
    end
    if self._persistence_tracker_ref then
        self._persistence_tracker_ref.cancel()
    end
end

---@param ctx number
---@return boolean
function Variables:is_current_context(ctx)
    return ctx == self._query_context
end

function Variables:_greyout_content()
    local items = self:get_items()
    for _, item in ipairs(items) do
        item.data.greyout = true
    end
    self:refresh_content()
end

---@param ctx number
function Variables:_update_data(ctx)
    self:_greyout_content()
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
    data_providers.variables_provider({ variablesReference = ref },
        function(_, vars_data)
            if not self:is_current_context(context) then return end
            local children = {}
            if vars_data then
                for var_idx, var in ipairs(vars_data.variables) do
                    local item_id = _make_node_id()
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
            else
                ---@type loopdebug.comp.Variables.Item
                local var_item = {
                    id = _make_node_id(),
                    parent_id = parent_id,
                    data = {
                        path = '',
                        is_na = true
                    },
                }
                table.insert(children, var_item)
            end
            callback(children)
        end)
end

---@param context number
---@param parent_id string
---@param parent_path string
---@param scopes loopdebug.proto.Scope[]
---@param data_providers loopdebug.session.DataProviders
---@param scopes_cb loop.comp.ItemTree.ChildrenCallback
function Variables:_load_scopes(context, parent_id, parent_path, scopes, data_providers, scopes_cb)
    ---@type loop.comp.ItemTree.Item[]
    local scope_items = {}
    for scope_idx, scope in ipairs(scopes) do
        local item_id = _make_node_id()
        local path = parent_path .. '/' .. scope.name
        local prefix = scope.expensive and "⏱ " or ""
        local expanded = self._layout_cache[path]
        if expanded == nil then
            if scope.expensive
                or scope.presentationHint == "globals"
                or scope.name == "Globals"
                or scope.presentationHint == "registers"
            then
                expanded = false
            else
                expanded = true
            end
        end
        ---@type loop.comp.ItemTree.Item
        local scope_item = {
            id = item_id,
            parent_id = parent_id,
            expanded = expanded,
            data = { path = path, scopelabel = prefix .. scope.name }
        }
        scope_item.children_callback = function(cb)
            if scope_item.data.greyout then
                cb({})
            else
                self:_load_variables(context, data_providers, scope.variablesReference, item_id, path, cb)
            end
        end
        table.insert(scope_items, scope_item)
    end
    scopes_cb(scope_items)
end

---@param comp loop.CompBufferController
function Variables:link_to_buffer(comp)
    ItemTreeComp.link_to_buffer(self, comp)

    ---@param item loop.comp.ItemTree.Item|nil
    local function add_or_edit_watch(item)
        local win = vim.api.nvim_get_current_win()
        local cursor = vim.api.nvim_win_get_cursor(win)
        local col_offset = -cursor[2]
        local row_offset = 0
        local text
        if item and item.data then text = item.data.name end
        text = text or ""
        floatwin.input_at_cursor({
            row_offset = row_offset,
            col_offset = col_offset,
            default_width = 20,
            default_text = text,
            on_confirm = function(expr)
                if not expr then return end
                if not item then
                    if _add_watch_expr(expr) then
                        self:_load_watch_expr_value(self._query_context, expr)
                    end
                elseif item.data and item.data.name and expr ~= item.data.name then
                    if _replace_watch_expr(item.data.name, expr) then
                        item.data.name = expr
                        self:_load_watch_expr_value(self._query_context, expr, item.id)
                    end
                end
            end
        })
    end

    -- Add keymaps
    comp.add_keymap("i", {
        desc = "Add watch (inline)",
        callback = function() add_or_edit_watch(nil) end,
    })
    comp.add_keymap("c", {
        desc = "Change watch expression",
        callback = function()
            ---@type loop.comp.ItemTree.Item|nil
            local cur_item = self:get_cur_item(comp)
            if not cur_item then return end
            if not cur_item.data.is_expr then return end
            add_or_edit_watch(cur_item)
        end,
    })
    comp.add_keymap("d", {
        desc = "Delete watch",
        callback = function()
            ---@type loop.comp.ItemTree.Item|nil
            local cur_item = self:get_cur_item(comp)
            if not cur_item then return end
            if not cur_item.data.is_expr then return end
            _remove_watch_expr(cur_item.data.name)
            self._layout_cache[cur_item.id] = nil
            self:remove_item(cur_item.id)
        end,
    })
end

---@return any root_id
function Variables:_upsert_watch_root()
    if not persistence.is_ws_open() then return end
    local id = "w"
    local expanded = self._layout_cache[id]
    if expanded == nil then expanded = true end        
    ---@type loop.comp.ItemTree.Item
    local root_item = {
        id = id,
        expanded = expanded,
        data = { path = id, scopelabel = "Watch" }
    }
    self:upsert_item(root_item)
    return id
end

---@param context number
---@param expr string
function Variables:_load_watch_expr_value(context, expr, forced_id)
    if not persistence.is_ws_open() then return end
    local parent_id = self:_upsert_watch_root()
    item_id = forced_id or _make_node_id()
    local path = "w/" .. expr
    ---@type loopdebug.comp.Variables.Item
    local var_item = {
        id = item_id,
        parent_id = parent_id,
        expanded = self._layout_cache[path],
        data = { path = path, is_expr = true, name = expr }
    }

    local data_source = self._current_data_source
    if not data_source or not data_source.frame or not data_source.data_providers then
        var_item.data.value = "not available"
        var_item.data.is_na = true
        self:upsert_item(var_item)
        return
    end

    data_source.data_providers.evaluate_provider({
        expression = expr,
        frameId = data_source.frame.id,
        context = 'watch',
    }, function(err, data)
        if not self:is_current_context(context) then return end
        if err or not data then
            var_item.data.value = "not available"
            var_item.data.is_na = true
        else
            var_item.data.value = data.result
            var_item.data.presentationHint = data.presentationHint
            if data.variablesReference and data.variablesReference > 0 then
                var_item.children_callback = function(cb)
                    if var_item.data.greyout then
                        cb({})
                    else
                        self:_load_variables(context, data_source.data_providers, data.variablesReference, var_item.id, path, cb)
                    end
                end
            end
        end
        self:upsert_item(var_item)
    end)
end

---@param context number
function Variables:_load_watch_expressions(context)
    local root_id = self:_upsert_watch_root()
    self:remove_children(root_id)
    if not persistence.is_ws_open() then return end
    local list = persistence.get_config("watch")
    if not list then
        return
    end
    ---@cast list string[]
    for _, expr in ipairs(list) do
        self:_load_watch_expr_value(context, expr)
    end
end

---@param context number
function Variables:_load_session_vars(context)
    local root_id = "s"
    local expanded = self._layout_cache[root_id]
    if expanded == nil then expanded = true end
    ---@type loop.comp.ItemTree.Item
    local root_item = {
        id = root_id,
        expanded = expanded,
        data = { path = root_id, scopelabel = "Variables" }
    }
    ---@return loop.comp.ItemTree.Item
    local function make_na_item()
        return {
            id = {}, -- a unique id
            data = { path = '', is_na = true },
        }
    end
    local data_source = self._current_data_source
    if data_source then
        root_item.children_callback = function(cb)
            if not self:is_current_context(context) or not data_source.frame then
                cb({ make_na_item() })
                return
            end
            data_source.data_providers.scopes_provider({ frameId = data_source.frame.id }, function(_, scopes_data)
                if not self:is_current_context(context) then
                    return
                end
                if scopes_data and scopes_data.scopes then
                    self:_load_scopes(context, root_item.id, root_item.id, scopes_data.scopes, data_source
                        .data_providers, cb)
                else
                    cb({ make_na_item() })
                end
            end)
        end
    end
    self:upsert_item(root_item)
end

return Variables

local class        = require('loop.tools.class')
local ItemTreeComp = require('loop.comp.ItemTree')
local strtools     = require('loop.tools.strtools')
local watchexpr    = require('loop-debug.watchexpr')
local floatwin     = require('loop-debug.tools.floatwin')
local daptools     = require('loop-debug.dap.daptools')

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
    -- check conditions for returning as-is
    if #str < max_len and not str:find("\n", 1, true) then
        return str, false
    end
    -- take first 50 characters
    local preview = str:sub(1, max_len)
    -- replace newlines with literal '\n'
    preview = preview:gsub("\n", " ")
    return preview, true
end

---@param is_watch boolean
---@param sess_id? number
---@return string
local function _get_root_id(is_watch, sess_id)
    return is_watch and "w" or tostring(sess_id)
end

local function _make_node_id(parent, id)
    assert(parent ~= nil and id ~= nil)
    return parent .. strtools.special_marker1() .. id
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
---@param highlights loop.comp.ItemTree.Highlight
---@return string
local function _variable_node_formatter(id, data, highlights)
    if data.is_na and not data.name then
        table.insert(highlights, { group = "NonText" })
        return "not available"
    end

    if not data then return "" end
    if data.scopelabel then
        table.insert(highlights, { group = "Directory" })
        return data.scopelabel
    end

    local hint = data.presentationHint
    local name = data.name and tostring(data.name) or "unknown"
    local value = data.value and tostring(data.value) or ""
    value = daptools.format_variable(value, hint)
    local preview, is_different = _preview_string(value, vim.o.columns)
    if is_different then preview = vim.fn.trim(preview, "", 2) end
    local text = name .. ": " .. preview
    if is_different then text = text .. "…" end
    if data.greyout then
        table.insert(highlights, { group = "NonText" })
    else
        table.insert(highlights, { group = "@symbol", start_col = 0, end_col = #name })
        if data.is_na then
            table.insert(highlights, { group = "NonText", start_col = #name })
        else
            local start_col = #name
            local end_col = start_col + 2
            table.insert(highlights, { group = "NonText", start_col = start_col, end_col = end_col })
            start_col = end_col
            end_col = start_col + #preview
            local kind = hint and hint.kind or nil
            table.insert(highlights, { group = _get_var_highlight(kind), start_col = start_col, end_col = end_col })
            if is_different then
                start_col = end_col
                end_col = start_col + 1
                table.insert(highlights, { group = "NonText", start_col = start_col, end_col = end_col })
            end
        end
    end
    return text
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
    floatwin.open_inspect_win(title, daptools.format_variable(value, hint))
end

---@param data_providers loopdebug.session.DataProviders
---@param ref number
---@param parent_id string
---@param callback fun(items:loopdebug.comp.Variables.Item[])
function Variables:_load_variables(data_providers, ref, parent_id, callback)
    data_providers.variables_provider({ variablesReference = ref },
        function(_, vars_data)
            local children = {}
            if vars_data then
                for var_idx, var in ipairs(vars_data.variables) do
                    local item_id = _make_node_id(parent_id, var.name)
                    ---@type loopdebug.comp.Variables.Item
                    local var_item = {
                        id = item_id,
                        parent_id = parent_id,
                        expanded = self._layout_cache[item_id],
                        data = {
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
                                self:_load_variables(data_providers, var.variablesReference, item_id, cb)
                            end
                        end
                    end
                    table.insert(children, var_item)
                end
            else
                ---@type loopdebug.comp.Variables.Item
                local var_item = {
                    id = {}, -- a unique id
                    parent_id = parent_id,
                    data = {
                        is_na = true
                    },
                }
                table.insert(children, var_item)
            end
            callback(children)
        end)
end

---@param parent_id string
---@param scopes loopdebug.proto.Scope[]
---@param data_providers loopdebug.session.DataProviders
---@param scopes_cb loop.comp.ItemTree.ChildrenCallback
function Variables:_load_scopes(parent_id, scopes, data_providers, scopes_cb)
    ---@type loop.comp.ItemTree.Item[]
    local scope_items = {}
    for scope_idx, scope in ipairs(scopes) do
        local item_id = _make_node_id(parent_id, scope.name)
        local prefix = scope.expensive and "⏱ " or ""
        local expanded = self._layout_cache[item_id]
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
            data = { scopelabel = prefix .. scope.name }
        }
        scope_item.children_callback = function(cb)
            if scope_item.data.greyout then
                cb({})
            else
                self:_load_variables(data_providers, scope.variablesReference, item_id, cb)
            end
        end
        table.insert(scope_items, scope_item)
    end
    scopes_cb(scope_items)
end

function Variables:init()
    ItemTreeComp.init(self, {
        formatter = _variable_node_formatter,
        render_delay_ms = 300,
    })

    ---@type loopdebug.comp.Vars.DataSource|nil
    self._current_data_source = nil

    ---@type table<any,boolean> -- id --> expanded
    self._layout_cache = {}
    self:add_tracker({
        on_toggle = function(id, data, expanded)
            self._layout_cache[id] = expanded
        end,
        on_open = function(id, data)
            _open_value_floatwin(id, data)
        end
    })

    self:_load_watch_expressions()
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
                    local added = watchexpr.add(expr)
                    if added then
                        self:_load_watch_expr_value(expr)
                    end
                elseif item.data and item.data.name and expr ~= item.data.name then
                    watchexpr.remove(item.data.name)
                    watchexpr.add(expr)
                    item.data.name = expr
                    self:_load_watch_expr_value(expr, item.id)
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
            watchexpr.remove(cur_item.data.name)
            self._layout_cache[cur_item.id] = nil
            self:remove_item(cur_item.id)
        end,
    })
end

---@return any root_id
function Variables:_upsert_watch_root()
    local id = _get_root_id(true)
    ---@type loop.comp.ItemTree.Item
    local root_item = {
        id = id,
        expanded = true,
        data = { scopelabel = "Watch" }
    }
    self:upsert_item(root_item)
    return id
end

---@param expr string
---@param forced_id any
function Variables:_load_watch_expr_value(expr, forced_id)
    local parent_id = self:_upsert_watch_root()
    local exising_items = self:get_item_and_children(parent_id)
    local item_id = forced_id
    if not item_id then
        for _, item in ipairs(exising_items) do
            if item and item.data and expr == item.data.name then
                item_id = item.id
                break
            end
        end
    end
    item_id = item_id or {}
    ---@type loopdebug.comp.Variables.Item
    local var_item = {
        id = item_id,
        parent_id = parent_id,
        expanded = self._layout_cache[expr],
        data = { is_expr = true, name = expr }
    }

    local data_source = self._current_data_source
    if not data_source then
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
                        self:_load_variables(data_source.data_providers, data.variablesReference, var_item.id, cb)
                    end
                end
            end
        end
        self:upsert_item(var_item)
    end)
end

---@param sess_id number
---@param sess_name string
---@param data_providers loopdebug.session.DataProviders
---@param frame loopdebug.proto.StackFrame
function Variables:update_data(sess_id, sess_name, data_providers, frame)
    self._current_data_source = {
        sess_id = sess_id,
        sess_name = sess_name,
        data_providers = data_providers,
        frame = frame,
    }
    self:_upsert_watch_root() -- ensure this exists at the top
    self:_load_watch_expressions()
    self:_load_session_vars()
end

function Variables:_load_watch_expressions()
    ---@type loop.comp.ItemTree.Item[]
    for _, expr in ipairs(watchexpr.get()) do
        self:_load_watch_expr_value(expr)
    end
end

function Variables:_load_session_vars()
    local data_source = self._current_data_source
    if not data_source then return end
    ---@type loop.comp.ItemTree.Item
    local root_item = {
        id = _get_root_id(false, data_source.sess_id),
        expanded = true,
        data = { scopelabel = "Session: " .. data_source.sess_name }
    }
    root_item.children_callback = function(cb)
        data_source.data_providers.scopes_provider({ frameId = data_source.frame.id }, function(_, scopes_data)
            if scopes_data and scopes_data.scopes then
                self:_load_scopes(root_item.id, scopes_data.scopes, data_source.data_providers, cb)
            else
                ---@type loop.comp.ItemTree.Item
                local scope_item = {
                    id = {}, -- a unique id
                    data = { is_na = true },
                }
                cb({ scope_item })
            end
        end)
    end
    self:upsert_item(root_item)
end

---@param sess_id any
function Variables:greyout_content(sess_id)
    do
        local items = self:get_item_and_children(_get_root_id(true))
        for _, item in ipairs(items) do
            item.data.greyout = true
        end
    end
    do
        local items = self:get_item_and_children(_get_root_id(false, sess_id))
        for _, item in ipairs(items) do
            item.data.greyout = true
        end
    end
    self:refresh_content()
end

return Variables

local class = require('loop.tools.class')
local ItemTreeComp = require('loop.comp.ItemTree')
local strtools = require('loop.tools.strtools')

---@alias loopdebug.comp.Variables.Item loop.comp.ItemTree.Item

---@class loopdebug.comp.Variables : loop.comp.ItemTree
---@field new fun(self: loopdebug.comp.Variables, name:string): loopdebug.comp.Variables
local Variables = class(ItemTreeComp)

local _vartype_to_group = {
    -- primitives
    ["string"]     = "@string",
    ["number"]     = "@number",
    ["boolean"]    = "@boolean",
    ["null"]       = "@constant.builtin",
    ["undefined"]  = "@constant.builtin",
    -- functions
    ["function"]   = "@function",
    ["function()"] = "@function", -- seen in some DAP servers
    ["function "]  = "@function",
    ["func"]       = "@function",
    ["Function"]   = "@function",
    -- objects / tables / arrays
    ["array"]      = "@structure",
    ["list"]       = "@structure",
    ["table"]      = "@structure",
    ["object"]     = "@structure",
    ["Object"]     = "@structure",
    ["Array"]      = "@structure",
    ["Module"]     = "@module",
}

---@param vartype string
---@return string|nil
function _get_vartype_hightlight(vartype)
    if not vartype then return nil end
    vartype = tostring(vartype)
    vartype = vartype:gsub("%s+", "")
    vartype = vartype:lower()
    local hl = _vartype_to_group[vartype]
    return hl or "@variable"
end

---@param id any
---@param data any
---@param highlights loop.comp.ItemTree.Highlight
---@return string
local function _variable_node_formatter(id, data, highlights)
    if not data then return "" end
    if data.scopelabel then
        table.insert(highlights, { group = "Directory" })
        return data.scopelabel
    end
    if data.is_na then
        table.insert(highlights, { group = "NonText" })
        return "not available"
    end

    if data.greyout then
        table.insert(highlights, { group = "NonText" })
    else
        table.insert(highlights, { group = "@symbol", start_col = 0, end_col = #data.name })
        table.insert(highlights, { group = _get_vartype_hightlight(data.type), start_col = #data.name + 2 })
    end
    return tostring(data.name) .. ": " .. tostring(data.value)
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
                    local item_id = parent_id .. strtools.special_marker1() .. var.name
                    ---@type loopdebug.comp.Variables.Item
                    local var_item = {
                        id = item_id,
                        parent = parent_id,
                        expanded = self._layout_cache[item_id],
                        data = {
                            name = var.name,
                            type = var.type,
                            value = var.value
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
                    parent =
                        parent_id,
                    data = { is_na = true },
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
        local item_id = scope.name
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
        formatter = _variable_node_formatter
    })
    ---@type table<any,boolean> -- id --> expanded
    self._layout_cache = {}
end

---@param sess_id number
---@param sess_name string
---@param data_providers loopdebug.session.DataProviders
---@param frame loopdebug.proto.StackFrame
function Variables:load_variables(sess_id, sess_name, data_providers, frame)
    ---@type loop.comp.ItemTree.Item
    local root_item = {
        id = tostring(sess_id),
        expanded = true,
        data = { scopelabel = sess_name }
    }
    root_item.children_callback = function(cb)
        data_providers.scopes_provider({ frameId = frame.id }, function(_, scopes_data)
            if scopes_data and scopes_data.scopes then
                self:_load_scopes(root_item.id, scopes_data.scopes, data_providers, cb)
            end
        end)
    end
    self:upsert_item(root_item)
end

---@param sess_id any
function Variables:greyout_session(sess_id)
    self._layout_cache = {}
    local items = self:get_item_and_children(tostring(sess_id))
    for _, item in ipairs(items) do
        item.data.greyout = true
        self._layout_cache[item.id] = item.expanded
    end
    self:refresh_content()
end

return Variables

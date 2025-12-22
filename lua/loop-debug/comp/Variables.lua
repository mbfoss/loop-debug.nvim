local class        = require('loop.tools.class')
local ItemTreeComp = require('loop.comp.ItemTree')
local strtools     = require('loop.tools.strtools')
local watchexpr    = require('loop-debug.watchexpr')

---@alias loopdebug.comp.Variables.Item loop.comp.ItemTree.Item

---@class loopdebug.comp.Vars.DataSource
---@field sess_id number
---@field sess_name string
---@field data_providers loopdebug.session.DataProviders
---@field frame loopdebug.proto.StackFrame

---@class loopdebug.comp.Variables : loop.comp.ItemTree
---@field new fun(self: loopdebug.comp.Variables, name:string): loopdebug.comp.Variables
local Variables    = class(ItemTreeComp)

local function floating_input_at_cursor(opts)
    local prev_win = vim.api.nvim_get_current_win()
    -- Create scratch buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].swapfile = false
    vim.bo[buf].undolevels = -1
    -- Cursor position
    -- Floating window at current line
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "cursor",
        row = opts.row_offset,
        col = opts.col_offset,
        width = opts.width,
        height = 1,
        style = "minimal",
        border = "rounded",
    })
    vim.wo[win].winhighlight = "Normal:Normal,NormalNC:Normal,EndOfBuffer:Normal,FloatBorder:Normal"
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { opts.default })
    vim.api.nvim_win_set_cursor(win, { 1, #opts.default })
    vim.cmd("normal! q")
    vim.cmd("startinsert")
    local closed = false
    local function close(value)
        if closed then return end
        closed = true
        vim.cmd("stopinsert")
        vim.api.nvim_set_current_win(prev_win)
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        vim.schedule(function() opts.on_confirm(value) end)
    end
    -- Confirm on Enter
    vim.keymap.set("i", "<CR>", function()
        local line = vim.api.nvim_get_current_line()
        close(line ~= "" and line or nil)
    end, { buffer = buf, nowait = true })
    -- Cancel on Esc
    vim.keymap.set("i", "<Esc>", function() close(nil) end, { buffer = buf, nowait = true })
    vim.api.nvim_create_autocmd("WinLeave", {
        once = true,
        callback = function()
            close(nil)
        end,
    })
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
    ---@type loopdebug.proto.VariablePresentationHint|nil
    local hint = data.presentationHint
    if data.is_na and not data.name then
        table.insert(highlights, { group = "NonText" })
        return "not available"
    end
    local name = data.name or "unknown"
    if not data then return "" end
    if data.scopelabel then
        table.insert(highlights, { group = "Directory" })
        return data.scopelabel
    end
    if data.greyout then
        table.insert(highlights, { group = "NonText" })
    else
        table.insert(highlights, { group = "@symbol", start_col = 0, end_col = #name })
        if data.is_na then
            table.insert(highlights, { group = "NonText", start_col = #name + 2 })
        else
            local kind = hint and hint.kind or nil
            table.insert(highlights, { group = _get_var_highlight(kind), start_col = #name + 1 })
        end
    end
    local value = data.value or ""
    if hint and hint.attributes and vim.list_contains(hint.attributes, "rawString") then
        -- unwrap quotes and decode escape sequences
        value = value
            :gsub("^(['\"])(.*)%1$", "%2")
            :gsub("\\n", "\n")
            :gsub("\\t", "\t")
    end
    if value:find("\n", 1, true) then
        return name .. ":\n" .. value
    end
    return name .. ": " .. tostring(value)
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

    ---@type loop.comp.ItemTree.Item
    local root_item = {
        id = _get_root_id(true),
        expanded = true,
        data = { scopelabel = "Watch" }
    }
    self:upsert_item(root_item)

    ---@type loopdebug.comp.Vars.DataSource|nil
    self._current_data_source = nil

    ---@type table<any,boolean> -- id --> expanded
    self._layout_cache = {}
    self:add_tracker({
        on_toggle = function(id, data, expanded)
            self._layout_cache[id] = expanded
        end
    })

    self:_load_watch_expressions()
end

---@param page_ctrl loop.PageControl
function Variables:link_to_page(page_ctrl)
    ItemTreeComp.link_to_page(self, page_ctrl)

    --- Helper: edit an existing watch or add a new one
    local function add_watch()
        local win = vim.api.nvim_get_current_win()
        local cursor = vim.api.nvim_win_get_cursor(win)
        local col_offset = -cursor[2]
        local row_offset = 0
        floating_input_at_cursor({
            row_offset = row_offset,
            col_offset = col_offset,
            width = 30,
            default = "",
            on_confirm = function(expr)
                if not expr then return end
                local added = watchexpr.add(expr)
                if added then
                    self:_load_watch_expr_value(expr)
                end
            end
        })
    end

    -- Add keymaps
    page_ctrl.add_keymap("i", {
        desc = "Add watch (inline)",
        callback = function() add_watch() end,
    })

    page_ctrl.add_keymap("d", {
        desc = "Delete watch",
        callback = function()
            ---@type loop.comp.ItemTree.Item|nil
            local cur_item = self:get_cur_item(page_ctrl)
            if not cur_item then return end
            if not cur_item.data.is_expr then return end
            watchexpr.remove(cur_item.data.name)
            self._layout_cache[cur_item.id] = nil
            self:remove_item(cur_item.id)
        end,
    })
end

---@param expr string
function Variables:_load_watch_expr_value(expr)
    local parent_id = _get_root_id(true)
    ---@type loopdebug.comp.Variables.Item
    local var_item = {
        id = _make_node_id(parent_id, expr),
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

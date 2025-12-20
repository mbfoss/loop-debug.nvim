local class = require('loop.tools.class')
local ItemListPage = require('loop.pages.ItemListPage')
local config = require('loop.config')
local selector = require('loop.tools.selector')
local Trackers = require("loop.tools.Trackers")

---@class loop.pages.StackTracePage : loop.pages.ItemListPage
---@field new fun(self: loop.pages.StackTracePage, name:string): loop.pages.StackTracePage
local StackTracePage = class(ItemListPage)

---@param item loop.pages.ItemListPage.Item
---@param highlights loop.pages.ItemListPage.Highlight[]
local function _item_formatter(item, highlights)
    ---@type loop.pages.ItemListPage.Highlight[]
    local hls = {}

    local frame = item.data.frame
    if not frame then
        table.insert(highlights, item.data.greyout and "NonText" or "Directory")
        return item.data.text
    end

    local parts = {}
    local pos = 0

    -- frame ID
    local id_str = tostring(frame.id)
    table.insert(parts, id_str)
    table.insert(hls, { group = "Identifier", start_col = pos, end_col = pos + #id_str })
    pos = pos + #id_str

    -- separator ": "
    local sep1 = ": "
    table.insert(parts, sep1)
    pos = pos + #sep1

    -- function name
    local name_str = tostring(frame.name)
    table.insert(parts, name_str)
    table.insert(hls, { group = "@function", start_col = pos, end_col = pos + #name_str })
    pos = pos + #name_str

    if frame.source and frame.source.name then
        local sep2 = " - "
        table.insert(parts, sep2)
        pos = pos + #sep2

        local source_str = tostring(frame.source.name)
        table.insert(parts, source_str)
        table.insert(hls, { group = "@module", start_col = pos, end_col = pos + #source_str })
        pos = pos + #source_str

        if frame.line then
            -- colon before line number
            local sep_line = ":"
            table.insert(parts, sep_line)
            pos = pos + #sep_line

            local line_str = tostring(frame.line)
            table.insert(parts, line_str)
            table.insert(hls, { group = "@number", start_col = pos, end_col = pos + #line_str })
            pos = pos + #line_str

            if frame.column then
                -- colon before column number
                local sep_col = ":"
                table.insert(parts, sep_col)
                pos = pos + #sep_col

                local col_str = tostring(frame.column)
                table.insert(parts, col_str)
                table.insert(hls, { group = "@number", start_col = pos, end_col = pos + #col_str })
                pos = pos + #col_str
            end
        end
    end

    if item.data.greyout then
        table.insert(highlights, { group = "NonText" })
    else
        for _, hl in ipairs(hls) do
            table.insert(highlights, hl)
        end
    end

    return table.concat(parts, '')
end


---@param name string
function StackTracePage:init(name)
    ItemListPage.init(self, name, {
        formatter = _item_formatter,
    })

    self._frametrackers = Trackers:new()
    self:add_tracker({
        on_selection = function(item)
            if item and item.data then
                -- id 0 is the title line
                if item.id > 0 then
                    ---@type loopdebug.proto.StackFrame
                    local frame = item.data.frame
                    vim.schedule(function()
                        self._frametrackers:invoke("frame_selected", frame)
                    end)
                end
            end
        end
    })
end

---@param callback fun(frame:loopdebug.proto.StackFrame)
function StackTracePage:add_frame_tracker(callback)
    self._frametrackers:add_tracker({
        frame_selected = callback
    })
end

---@param data loopdebug.session.DataProviders
---@param thread_id number
function StackTracePage:set_content(data, thread_id)
    data.stack_provider({
            threadId = thread_id,
            levels = config.current.debug.stack_levels_limit or 100,
        },
        function(err, resp)
            local text = "Thread " .. tostring(thread_id)
            local items = { {
                id = 0,
                data = { text = text, thread_data = data }
            } }
            if resp then
                for idx, frame in ipairs(resp.stackFrames) do
                    ---@type loop.pages.ItemListPage.Item
                    local item = { id = idx, data = { frame = frame } }
                    table.insert(items, item)
                end
            end
            self:set_items(items)
        end)
end

function StackTracePage:clear_content()
    self:set_items({})
end

function StackTracePage:greyout_content()
    local items = self:get_items()
    for _, item in ipairs(items) do
        item.data.greyout = true
    end
    self:refresh_content()
end

return StackTracePage

local class = require('loop.tools.class')
local ItemList = require('loop.comp.ItemList')
local config = require('loop-debug.config')
local debugevents = require('loop-debug.debugevents')
local Trackers = require("loop.tools.Trackers")

---@class loopdebug.comp.SessionListComp : loop.comp.ItemList
---@field new fun(self: loopdebug.comp.SessionListComp): loopdebug.comp.SessionListComp
local SessionListComp = class(ItemList)

---@param item loop.comp.ItemList.Item
---@param highlights loop.Highlight[]
local function _item_formatter(item, highlights)
    local str = item.data.label
    if item.data.nb_paused_threads and item.data.nb_paused_threads > 0 then
        local s = item.data.nb_paused_threads > 1 and "s" or ""
        str = str .. (" ( %d paused thread%s)"):format(item.data.nb_paused_threads, s)
    end
    return str
end

function SessionListComp:init()
    ItemList.init(self, {
        formatter = _item_formatter,
        show_current_prefix = true,
    })

    ---@type table<number,loopdebug.events.SessionInfo>
    self._sessions = {}
    ---@type boolean?
    self._job_result = nil
    ---@type number?
    self._current_sess_id = nil

    ---@type loop.TrackerRef?
    self._events_tracker_ref = debugevents.add_tracker({
        on_debug_start = function()
            self._sessions = {}
            self._job_result = nil
            self:_refresh()
        end,
        on_debug_end = function(success)
            self._sessions = {}
            self._job_result = success
            self:_refresh()
        end,
        on_session_added = function(id, info)
            self._sessions[id] = info
            self:_refresh()
        end,
        on_session_update = function(id, info)
            self._sessions[id] = info
            self:_refresh()
        end,
        on_session_removed = function(id)
            self._sessions[id] = nil
            self:_refresh()
        end,
        on_view_udpate = function(view)
            self._current_sess_id = view.session_id
        end
    })
end

function SessionListComp:dispose()
    ItemList.dispose(self)
    if self._events_tracker_ref then
        self._events_tracker_ref.cancel()
    end
end

---@param page loop.PageController
function SessionListComp:set_page(page)
    self._page = page
end

---@param buf_ctrl loop.CompBufferController
function SessionListComp:link_to_buffer(buf_ctrl)
    ItemList.link_to_buffer(self, buf_ctrl)
    buf_ctrl.disable_change_events()
end

function SessionListComp:_refresh()
    if self._job_result then
        --@type loop.pages.ItemListPage.Item
        local item = {
            id = 0,
            ---@class loopdebug.mgr.TaskPageItemData
            data = {
                label = self._job_result and "Task ended" or "Task failed",
                nb_paused_threads = 0,
            }
        }
        local symbols = config.current.symbols
        self:set_items({ item })
        if self._page then
            self._page.set_ui_flags(self._job_result and '' or symbols.failure)
        end
        return
    end

    local session_ids = vim.tbl_keys(self._sessions)
    vim.fn.sort(session_ids)

    ---@type loop.comp.ItemList.Item[]
    local list_items = {}
    local uiflags = ''

    local symbols = config.current.symbols

    for _, sess_id in ipairs(session_ids) do
        local info = self._sessions[sess_id]
        local nb_paused_threads = info.nb_paused_threads
        if nb_paused_threads and nb_paused_threads > 0 then
            flag = symbols.paused
        else
            flag = symbols.running
        end
        --@type loop.pages.ItemListPage.Item
        local item = {
            id = sess_id,
            ---@class loopdebug.mgr.TaskPageItemData
            data = {
                label = tostring(sess_id) .. ' ' .. tostring(info.name) .. ' - ' .. info.state,
                nb_paused_threads = nb_paused_threads,
            }
        }
        uiflags = uiflags .. flag
        table.insert(list_items, item)
    end

    self:set_items(list_items)
    self:set_current_item_by_id(self._current_sess_id)
    if self._page then
        self._page.set_ui_flags(uiflags)
    end
end

return SessionListComp


--[[

  _refresh_task_page(jobdata)



---@param jobdata loopdebug.mgr.DebugJobData
local
    sessionlist_comp:add_tracker({
        on_selection = function(id, data)
            if id then
                _switch_to_session(jobdata, id)
            end
        end
    })

]]

local class = require('loop.tools.class')
local OutputLines = require('loop.comp.OutputLines')
local floatwin = require('loop-debug.tools.floatwin')

---@class loop.comp.ReplComp
---@field new fun(self:loop.comp.ReplComp,providers):loop.comp.ReplComp
---@field _prompt string
---@field _output loop.comp.OutputLines
---@field _buf_ctrl loop.BufferController|nil
local ReplComp = class()

function ReplComp:init()
    self._prompt = "> "
    self._output = OutputLines:new()
    ---@type loopdebug.session.DataProviders
    self._data_providers = nil
end

-- =========================================================
-- Public integration
-- =========================================================

---@param buf_ctrl loop.BufferController
---@return nil
function ReplComp:link_to_buffer(buf_ctrl)
    self._buf_ctrl = buf_ctrl

    -- Output renderer
    self._output:link_to_buffer(buf_ctrl)

    -- REPL output is passive
    buf_ctrl:disable_change_events()
    buf_ctrl:follow_last_line()

    self:_setup_keymaps(buf_ctrl)
end

-- =========================================================
-- Public output API
-- =========================================================

---@param data_providers loopdebug.session.DataProviders
function ReplComp:set_data_providers(data_providers)
    self._data_providers = data_providers
end

---@param text string
---@param highlights loop.comp.output.Highlight[]|nil
---@return nil
function ReplComp:print(text, highlights)
    self._output:add_line(text, highlights)
end

-- =========================================================
-- Input entry (floating window)
-- =========================================================

---@return nil
function ReplComp:_open_input()
    floatwin.input_at_cursor({
        default_text = "",
        on_confirm = function(text)
            if not text or text == "" then
                return
            end
            self:_handle_input(text)
        end,
    })
end

---@param text string
---@return nil
function ReplComp:_handle_input(text)
    -- Echo input into transcript
    self._output:add_line(self._prompt .. text)
    if not self._data_providers then
        self._output:add_line("Session not available", { { group = "ErrorMsg" } })
        return
    end
    self._data_providers.evaluate_provider({
        expression = text,
        context = "repl"
    }, function(err, data)
        if data then
            for _, line in ipairs(vim.fn.split(tostring(data.result), "\n", false)) do
                self._output:add_line(line)
            end
        else
            self._output:add_line(err or "error", { { group = "ErrorMsg" } })
        end
    end)
end

-- =========================================================
-- Keymaps
-- =========================================================

---@param buf_ctrl loop.BufferController
---@return nil
function ReplComp:_setup_keymaps(buf_ctrl)
    buf_ctrl.add_keymap(
        "<CR>", {
            desc = "REPL input",
            callback = function()
                self:_open_input()
            end,
        })
    buf_ctrl.add_keymap(
        "i", {
            desc = "REPL input",
            callback = function()
                self:_open_input()
            end
        })
end

return ReplComp

local M = {}

local debug_win_augroup = vim.api.nvim_create_augroup("LoopDebugPluginModalWin", { clear = true })
local _current_win = nil

---@param title string
---@param text string
function M.open_inspect_win(title, text)
    if _current_win and vim.api.nvim_win_is_valid(_current_win) then
        vim.api.nvim_win_close(_current_win, true)
    end

    local lines = vim.split(text, "\n", { trimempty = false })

    -- 1. Calculate UI Constraints
    local ui_width = vim.o.columns
    local ui_height = vim.o.lines
    local max_w = math.floor(ui_width * 0.8)
    local max_h = math.floor(ui_height * 0.8)

    -- 2. Calculate Content Dimensions
    local content_w = 20
    for _, line in ipairs(lines) do
        content_w = math.max(content_w, vim.fn.strwidth(line))
    end

    local win_width = math.min(content_w + 2, max_w)
    local win_height = math.min(#lines, max_h)

    -- 3. Determine Positioning Strategy
    -- Threshold: If height > 10 lines OR width > 50% of screen, use central layout
    local is_large = win_height > 10 or win_width > (ui_width * 0.5)

    local win_opts = {
        width = win_width,
        height = win_height,
        style = "minimal",
        border = "rounded",
        title = " " .. tostring(title) .. " ",
        title_pos = "center",
    }

    if is_large then
        -- Central Editor Layout
        win_opts.relative = "editor"
        win_opts.row = math.floor((ui_height - win_height) / 2)
        win_opts.col = math.floor((ui_width - win_width) / 2)
    else
        -- Cursor Relative Layout
        win_opts.relative = "cursor"
        win_opts.row = 1 -- One line below cursor
        win_opts.col = 0
    end

    -- 4. Create Buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "loopdebug-value"

    -- 5. Open Window
    local win = vim.api.nvim_open_win(buf, true, win_opts)
    _current_win = win

    -- 6. Window-local options
    vim.wo[win].wrap = false
    vim.wo[win].sidescrolloff = 5

    -- 7. Modal Logic
    local function close_modal()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        _current_win = nil
    end

    local opts = { buffer = buf, silent = true }
    vim.keymap.set("n", "q", close_modal, opts)
    vim.keymap.set("n", "<Esc>", close_modal, opts)

    vim.api.nvim_create_autocmd("WinLeave", {
        group = debug_win_augroup,
        buffer = buf,
        callback = close_modal,
        once = true,
    })
end

-- TODO: move this to a seperate module
function M.input_at_cursor(opts)
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
    vim.cmd("startinsert!")
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
    -- Cancel on Esc in normal mode
    vim.keymap.set("n", "<Esc>", function() close(nil) end, { buffer = buf, nowait = true })
    vim.api.nvim_create_autocmd("WinLeave", {
        once = true,
        callback = function()
            close(nil)
        end,
    })
end

return M

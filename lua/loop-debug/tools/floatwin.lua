local M = {}

local debug_win_augroup = vim.api.nvim_create_augroup("LoopDebugPluginModalWin", { clear = true })
local _current_win = nil

---@param title string
---@param text string
function M.open_central_float(title, text)
    -- 1. Close existing to prevent stacking
    if _current_win and vim.api.nvim_win_is_valid(_current_win) then
        vim.api.nvim_win_close(_current_win, true)
    end

    local lines = vim.split(text, "\n", { trimempty = false })

    -- 2. Calculate Centered Dimensions
    -- We want it large but not touching the screen edges
    local ui_width = vim.o.columns
    local ui_height = vim.o.lines

    local win_width = math.floor(ui_width * 0.7)
    local win_height = math.floor(ui_height * 0.6)

    -- Adjust height if text is short
    if #lines < win_height then
        win_height = #lines
    end

    local row = math.floor((ui_height - win_height) / 2)
    local col = math.floor((ui_width - win_width) / 2)

    -- 3. Create Buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "loopdebug-value"

    -- 4. Open and Focus Window
    -- enter = true automatically moves your cursor into the float
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = win_width,
        height = win_height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " " .. tostring(title) .. " ",
        title_pos = "center",
    })
    _current_win = win

    -- 5. Modal Logic
    local function close_modal()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        _current_win = nil
    end

    -- Keymaps inside the modal
    local opts = { buffer = buf, silent = true }
    vim.keymap.set("n", "q", close_modal, opts)
    vim.keymap.set("n", "<Esc>", close_modal, opts)

    -- Close if focus is lost (e.g. clicking away or switching splits)
    vim.api.nvim_create_autocmd("WinLeave", {
        group = debug_win_augroup,
        buffer = buf,
        callback = close_modal,
        once = true,
    })
end

return M

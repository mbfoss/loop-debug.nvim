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

function M.input_at_cursor(opts)
    local prev_win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_create_buf(false, true)
    
    -- Buffer setup
    local buf_opts = {
        buftype = "nofile",
        bufhidden = "wipe",
        swapfile = false,
        undolevels = -1
    }
    for k, v in pairs(buf_opts) do vim.bo[buf][k] = v end

    -- Initial size calculations
    local min_width = opts.default_width or 10
    local max_width = math.floor(vim.o.columns * 0.8)
    local initial_text = opts.default_text or ""
    local current_width = math.max(min_width, #initial_text + 1)
    current_width = math.min(current_width, max_width)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "cursor",
        row = opts.row_offset or 1,
        col = opts.col_offset or 0,
        width = current_width,
        height = 1,
        style = "minimal",
        border = "rounded",
    })

    vim.wo[win].winhighlight = "Normal:Normal,NormalNC:Normal,EndOfBuffer:Normal,FloatBorder:Normal"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { initial_text })
    vim.api.nvim_win_set_cursor(win, { 1, #initial_text })
    
    -- 1. AUTO-RESIZE LOGIC
    vim.api.nvim_create_autocmd("TextChangedI", {
        buffer = buf,
        callback = function()
            local line = vim.api.nvim_get_current_line()
            local new_width = math.max(min_width, vim.fn.strwidth(line) + 1)
            new_width = math.min(new_width, max_width)
            
            -- Only call API if width actually changed to save performance
            if new_width ~= current_width then
                current_width = new_width
                vim.api.nvim_win_set_config(win, { width = current_width })
            end
        end,
    })

    vim.cmd("startinsert!")

    local closed = false
    local function close(value)
        if closed then return end
        closed = true
        vim.cmd("stopinsert")
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_win_is_valid(prev_win) then
            vim.api.nvim_set_current_win(prev_win)
        end
        vim.schedule(function() opts.on_confirm(value) end)
    end

    -- Keybindings
    local kopts = { buffer = buf, nowait = true }
    vim.keymap.set("i", "<CR>", function() close(vim.api.nvim_get_current_line()) end, kopts)
    vim.keymap.set("n", "<Esc>", function() close(nil) end, kopts)
    vim.keymap.set("i", "<C-c>", function() close(nil) end, kopts)

    vim.api.nvim_create_autocmd("WinLeave", {
        once = true,
        callback = function() close(nil) end,
    })
end

return M

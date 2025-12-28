local M              = {}

---@class loop.signs.Sign
---@field id number
---@field group string
---@field name string
---@field lnum number
---@field priority number

---@alias loop.signs.ById table<number, loop.signs.Sign>        -- id → sign
---@alias loop.signs.BySignName table<string, loop.signs.ById>
---@alias loop.signs.ByFile table<string, loop.signs.BySignName>

---@class loop.signs.GroupData
---@field byfile loop.signs.ByFile
---@field id_to_file table<number, string>

---@class loop.signs.GroupInfo
---@field sign_names table<string,boolean>
---@field priority number

---@type table<string,loop.signs.GroupInfo>
local _defined_signs = {} -- group -> info

---@type table<string, loop.signs.GroupData> -- group -> data
local _signs         = {}
local _id_prefix     = "loopdebug_"

local _init_done     = false


---@param file string
---@return integer
local function _get_loaded_bufnr(file)
    local bufnr = vim.fn.bufnr(file, false)
    return (bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr)) and bufnr or -1
end

local function _remove_buf_signs(bufnr, group)
    vim.fn.sign_unplace(_id_prefix .. group, { buffer = bufnr })
end

local function _place_sign(bufnr, sign)
    vim.fn.sign_place(
        sign.id,
        _id_prefix .. sign.group,
        _id_prefix .. sign.name,
        bufnr,
        { lnum = sign.lnum, priority = sign.priority }
    )
end

local function _unplace_sign(bufnr, sign)
    vim.fn.sign_unplace(_id_prefix .. sign.group, {
        buffer = bufnr,
        id = sign.id,
    })
end

local function _apply_buffer_signs(bufnr, group)
    local file = vim.api.nvim_buf_get_name(bufnr)
    if file == "" then return end
    file = vim.fn.fnamemodify(file, ":p")

    local group_data = _signs[group]
    if not group_data then return end

    local file_data = group_data.byfile[file]
    if not file_data then return end

    for _, signs in pairs(file_data) do
        for _, sign in pairs(signs) do
            _place_sign(bufnr, sign)
        end
    end
end

-- -------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------

---@param group string
---@param priority number
function M.define_sign_group(group, priority)
    assert(group and priority)
    assert(not _defined_signs[group])
    _defined_signs[group] = {
        sign_names = {},
        priority = priority,
    }
end

---@param group string
---@param name string
---@param text string
---@param texthl string
function M.define_sign(group, name, text, texthl)
    assert(group and name and text and texthl)
    local defined_group = _defined_signs[group]
    assert(defined_group, "sign group not defined")
    assert(not defined_group.sign_names[name], "sign already in group")

    defined_group.sign_names[name] = true
    vim.fn.sign_define(_id_prefix .. name, {
        text = text,
        texthl = texthl,
    })
end

---@param id number
---@param file string
---@param line number
---@param group string
---@param name string
function M.place_file_sign(id, file, line, group, name)
    assert(_init_done)
    local defined_group = _defined_signs[group]
    assert(defined_group and defined_group.sign_names[name], "sign group/name not defined")

    file = vim.fn.fnamemodify(file, ":p")
    local bufnr = _get_loaded_bufnr(file)

    local group_data = _signs[group]
    if not group_data then
        group_data = { byfile = {}, id_to_file = {} }
        _signs[group] = group_data
    end

    -- remove this id from all sign names for this file
    local file_table = group_data.byfile[file]
    if file_table then
        for _, signs in pairs(file_table) do
            local old = signs[id]
            if old and bufnr >= 0 then
                _unplace_sign(bufnr, old)
            end
            signs[id] = nil
        end
    end

    group_data.id_to_file[id] = file
    group_data.byfile[file] = group_data.byfile[file] or {}

    local byname = group_data.byfile[file]
    byname[name] = byname[name] or {}

    local name_table = byname[name]

    -- Replace existing sign with same id
    local old = name_table[id]
    if old and bufnr >= 0 then
        _unplace_sign(bufnr, old)
    end

    local sign = {
        id = id,
        group = group,
        name = name,
        lnum = line,
        priority = defined_group.priority or 12,
    }

    name_table[id] = sign

    if bufnr > 0 then
        _place_sign(bufnr, sign)
    end
end

---@param id number
---@param group string
function M.remove_file_sign(id, group)
    assert(_init_done)
    assert(_defined_signs[group], "sign group not defined")

    local group_table = _signs[group]
    if not group_table then return end

    local file = group_table.id_to_file[id]
    if not file then return end

    group_table.id_to_file[id] = nil

    local file_table = group_table.byfile[file]
    if not file_table then return end

    local bufnr = _get_loaded_bufnr(file)

    for _, signs in pairs(file_table) do
        local sign = signs[id]
        if sign then
            if bufnr > 0 then
                _unplace_sign(bufnr, sign)
            end
            signs[id] = nil
        end
    end
end

---@param file string
---@param group string
function M.remove_file_signs(file, group)
    assert(_init_done)
    assert(_defined_signs[group], "sign group not defined")

    file = vim.fn.fnamemodify(file, ":p")
    local group_table = _signs[group]
    if not group_table then return end

    local file_table = group_table.byfile[file]
    if not file_table then return end

    for _, signs in pairs(file_table) do
        for id in pairs(signs) do
            group_table.id_to_file[id] = nil
        end
    end

    group_table.byfile[file] = nil

    if not next(group_table.byfile) then
        _signs[group] = nil
    end

    local bufnr = _get_loaded_bufnr(file)
    if bufnr > 0 then
        _remove_buf_signs(bufnr, group)
    end
end

---@param group string
function M.remove_signs(group)
    assert(_init_done)
    assert(_defined_signs[group], "sign group not defined")

    local group_table = _signs[group]
    if not group_table then return end

    for file in pairs(group_table.byfile) do
        local bufnr = _get_loaded_bufnr(file)
        if bufnr > 0 then
            _remove_buf_signs(bufnr, group)
        end
    end

    _signs[group] = nil
end

function M.clear_all()
    assert(_init_done)
    for group, group_table in pairs(_signs) do
        for file in pairs(group_table.byfile) do
            local bufnr = _get_loaded_bufnr(file)
            if bufnr > 0 then
                _remove_buf_signs(bufnr, group)
            end
        end
    end
    _signs = {}
end

---@param group string
function M.refresh_all_signs(group)
    assert(_init_done)
    assert(_defined_signs[group], "sign group not defined")

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            _remove_buf_signs(bufnr, group)
            _apply_buffer_signs(bufnr, group)
        end
    end
end

---@param file string
---@return table<number, loop.signs.Sign>
function M.get_file_signs_by_id(file)
    assert(_init_done)

    file = vim.fn.fnamemodify(file, ":p")

    ---@type table<number, loop.signs.Sign>
    local out = {}
    -- Collect stored signs first
    for group, group_table in pairs(_signs) do
        local file_table = group_table.byfile[file]
        if file_table then
            for _, signs in pairs(file_table) do
                for id, sign in pairs(signs) do
                    out[id] = sign
                end
            end
        end
    end
    -- If buffer isn't loaded, stored data is best we can do
    local bufnr = _get_loaded_bufnr(file)
    if bufnr < 0 or not next(out) then
        return out
    end
    -- Fetch live sign positions from Neovim
    for group in pairs(_signs) do
        local placed = vim.fn.sign_getplaced(
            bufnr,
            { group = _id_prefix .. group }
        )[1]

        if placed and placed.signs then
            for _, psign in ipairs(placed.signs) do
                local sign = out[psign.id]
                if sign then
                    -- Update stored state lazily
                    sign.lnum = psign.lnum
                end
            end
        end
    end
    return out
end

function M.init()
    if _init_done then return end
    _init_done = true
    local au_group = vim.api.nvim_create_augroup("loopplugin_signs", { clear = true })
    vim.api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
        group = au_group,
        callback = function(ev)
            for group_name, _ in pairs(_defined_signs) do
                _apply_buffer_signs(ev.buf, group_name)
            end
        end
    })
end

return M

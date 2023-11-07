local bookmarks = {}

local ns = vim.api.nvim_create_namespace('Bookmarks')

local sign_group = 'BookmarksSignGroup'

local augroup = nil

local ignored_filetypes = { help = true, NvimTree = true }

local function is_ignored(bufnr)
    bufnr = bufnr or 0
    return ignored_filetypes[vim.bo[bufnr].filetype] ~= nil
end

local function set_bookmark(bufnr, line)
    return vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
        sign_text = ' 󰃀',
        sign_hl_group = sign_group
    })
end

local function del_bookmark(bufnr, id)
    if id ~= nil then vim.api.nvim_buf_del_extmark(bufnr, ns, id) end
end

local function refresh_bookmark(x)
    if x.id ~= nil then
        local o = vim.api.nvim_buf_get_extmark_by_id(x.bufnr, ns, x.id, {})
        x.line = o[1] + 1
    end
end

local function refresh_bookmarks()
    for _, x in pairs(bookmarks) do refresh_bookmark(x) end
end

local function restore_bookmarks(bufnr)
    if is_ignored(bufnr) then return end

    for _, x in pairs(bookmarks) do
        if x.id == nil and vim.fn.bufnr(x.file) == bufnr then
            x.id = set_bookmark(bufnr, x.line)
            x.bufnr = bufnr
            x.text = vim.fn.trim(vim.fn.getline(x.line))
        end
    end
end

local function find_bookmark(bufnr, line)
    for _, x in pairs(bookmarks) do
        if x.id ~= nil and x.line == line and vim.fn.bufnr(x.file) == bufnr then
            return x
        end
    end
    return nil
end

local function remove_invalid_bookmarks()
    local old = bookmarks
    bookmarks = {}
    for _, x in pairs(bookmarks) do
        if x.file ~= nil then table.insert(bookmarks, x) end
    end
end

local function toggle_bookmark()
    if is_ignored() then return end

    local line = vim.fn.line('.')
    local bufnr = vim.api.nvim_get_current_buf()
    local text = vim.fn.trim(vim.api.nvim_get_current_line())

    local x = find_bookmark(bufnr, line)
    if x ~= nil then
        del_bookmark(x.bufnr, x.id)
        x.file = ""
        remove_invalid_bookmarks()
    else
        local file = vim.fn.bufname(bufnr)
        if #vim.fn.trim(file) == 0 then return end
        file = vim.fn.fnamemodify(file, ":p")
        local id = set_bookmark(bufnr, line)
        table.insert(bookmarks, {
            file = file,
            line = line,
            bufnr = bufnr,
            text = text,
            id = id
        })
    end
end

local function clear_bookmarks()
    for _, x in pairs(bookmarks) do
        -- vim.print(x)
        del_bookmark(x.bufnr, x.id)
    end
    bookmarks = {}
end

local function load_bookmarks()
    local f = io.open(vim.fn.stdpath("data") .. "/bookmarks.json", "r")
    if f ~= nil then
        local content = f:read("*all")
        f:close()
        bookmarks = vim.json.decode(content,
            { luanil = { object = true, array = true } })

        for _, x in pairs(bookmarks) do
            x.bufnr = nil
            x.id = nil
        end
    end
end

local function save_bookmarks()
    refresh_bookmarks()

    local f = assert(io.open(vim.fn.stdpath("data") .. "/bookmarks.json", "w"))
    f:write(vim.json.encode(bookmarks))
    f:close()
end

-- user commands

local function create_user_commands()
    vim.api.nvim_create_user_command('BookmarksToggle', toggle_bookmark, {})
    vim.api.nvim_create_user_command('BookmarksClear', clear_bookmarks, {})
    vim.api.nvim_create_user_command('BookmarksSave', save_bookmarks, {})
end

local function setup(opts)
    -- vim.print(opts)

    opts.ignored_filetypes = opts.ignored_filetypes or {}
    for _, v in ipairs(opts.ignored_filetypes) do ignored_filetypes[v] = true end

    load_bookmarks()

    if augroup == nil then
        augroup = vim.api
            .nvim_create_augroup("BookmarksAugroup", { clear = true })
        vim.api.nvim_create_autocmd("VimLeave", {
            pattern = '*',
            callback = function(ev) save_bookmarks() end,
            group = augroup
        })
        vim.api.nvim_create_autocmd("BufRead", {
            pattern = '*',
            callback = function(ev)
                -- vim.print(ev)
                restore_bookmarks(ev.buf)
            end,
            group = augroup
        })
    end

    create_user_commands()
end

--- telescope ---

local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local sorters = require "telescope.sorters"
local conf = require("telescope.config").values

local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"

local telescope = {}

telescope.opts = {
    layout_config = {
        prompt_position = "top"
    },
    sorting_strategy = "ascending",
    results_title = ""
}

telescope.actions = {
    del = function(prompt_bufnr)
        local picker = action_state.get_current_picker(prompt_bufnr)
        picker:delete_selection(function(entry)
            -- vim.print(entry)
            local x = entry.value
            if x.id ~= nil then
                del_bookmark(x.bufnr, x.id)
                x.file = ""
                remove_invalid_bookmarks()
            end
        end)
    end,

    clear = function(prompt_bufnr)
        clear_bookmarks()
        actions.close(prompt_bufnr)
    end
}

telescope.opts.mappings = {
    ['n'] = { ['dd'] = telescope.actions.del, ['cc'] = telescope.actions.clear }
}

telescope.setup = function(ext_config, config)
    -- vim.print(ext_config)
    -- vim.print(config)
    telescope.opts = vim.tbl_deep_extend("force", telescope.opts, ext_config)
    setup(telescope.opts)
end

local function shorten(str, n_head, n_tail)
    local j = ' .. '
    if #str <= n_head + n_tail + #j then return str end
    return str.sub(str, 1, n_head) .. j .. str.sub(str, -n_tail)
end

telescope.new_finder = function()
    refresh_bookmarks()

    local results = {}
    local seen = {}
    for _, x in pairs(bookmarks) do
        if seen[x.file] == nil then
            seen[x.file] = true
            table.insert(results, { file = x.file, line = 0 })
        end
        table.insert(results, x)
    end

    return finders.new_table({
        results = results,
        entry_maker = function(x)
            local display = string.format("%6d %s", x.line, x.text or "")
            if x.line == 0 then display = x.file end
            return {
                value = x,
                ordinal = string.format("%s\1%06d %s", x.file, x.line,
                    x.text or ""), -- for sorting and filtering; should NOT contain '\0'
                display = display,
                path = x.file,
                lnum = x.line,
                col = 0
            }
        end
    })
end

telescope.run = function(opts)
    -- vim.print(opts) -- :messages
    opts = vim.tbl_deep_extend("force", telescope.opts, opts)
    local picker = pickers.new(opts, {
        prompt_title = 'Bookmarks',
        finder = telescope.new_finder(),
        sorter = sorters.get_substr_matcher(),
        previewer = conf.grep_previewer(opts),
        attach_mappings = function(_, map)
            for mode, tbl in pairs(opts.mappings) do
                for key, action in pairs(tbl) do
                    map(mode, key, action)
                end
            end
            return true
        end
    })
    picker:find()
end

return { telescope = telescope }

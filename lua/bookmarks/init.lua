local marks = vim.split('ABCDEFGHIJKLMNOPQRSTUVWXYZ', '', {})

local sign_name = 'bookmarks_sign_name'
local sign_group = 'bookmarks_sign_group'

local augroup = nil

local ignored_filetypes = { help = true, NvimTree = true }

function is_ignored(bufnr)
  bufnr = bufnr or 0
  return ignored_filetypes[vim.bo[bufnr].filetype] ~= nil
end

function try_to_place_sign(bufnr)
  if is_ignored(bufnr) then
    return
  end

  for _, v in pairs(get_bookmarks()) do
    if vim.fn.bufnr(v.file) == bufnr then
      vim.fn.sign_place(get_id(v.mark), sign_group, sign_name, bufnr, { lnum = v.lnum })
    end
  end
end

function setup(opts)
  -- vim.print(opts)

  opts.ignored_filetypes = opts.ignored_filetypes or {}
  for _, v in ipairs(opts.ignored_filetypes) do
    ignored_filetypes[v] = true
  end

  if #vim.fn.sign_getdefined(sign_name) == 0 then
    vim.fn.sign_define(sign_name, { text = '󰃀' })
  end

  if augroup == nil then
    augroup = vim.api.nvim_create_augroup("bookmarks_augroup", { clear = true })
    vim.api.nvim_create_autocmd("BufRead", {
      pattern = '*',
      callback = function(ev)
        -- vim.print(ev)
        try_to_place_sign(ev.buf)
      end,
      group = augroup,
    })
  end

  for _, v in pairs(get_bookmarks()) do
    local bufnr = vim.fn.bufnr(v.file)
    if bufnr ~= -1 then
      vim.fn.sign_place(get_id(v.mark), sign_group, sign_name, bufnr, { lnum = v.lnum })
    end
  end
end

function get_id(c)
  return 3172 + c:byte()
end

function get_bufnr(buf)
  if type(buf) == 'number' then
    return buf
  end
  return vim.fn.bufnr(buf)
end

function set_bookmark(buf, c, line)
  vim.api.nvim_buf_set_mark(buf, c, line, 1, {})
  buf = get_bufnr(buf)
  if buf ~= -1 then
    vim.fn.sign_place(get_id(c), sign_group, sign_name, buf, { lnum = line })
  end
end

function del_bookmark(buf, c)
  vim.api.nvim_del_mark(c)
  buf = get_bufnr(buf)
  if buf ~= -1 then
    vim.fn.sign_unplace(sign_group, { id = get_id(c), buffer = buf })
  end
end

function toggle_bookmark()
  if is_ignored() then
    return
  end

  local line = vim.fn.line('.')
  local buf = vim.api.nvim_get_current_buf()

  for _, c in pairs(marks) do
    local m = vim.api.nvim_get_mark(c, {}) -- (row, col, buffer, buffername)
    if line == m[1] and buf == m[3] then
      del_bookmark(buf, c)
      return
    end
  end

  for _, c in pairs(marks) do
    if vim.deep_equal({ 0, 0, 0, '' }, vim.api.nvim_get_mark(c, {})) then
      set_bookmark(buf, c, line)
      return
    end
  end

  vim.notify(string.format('No mark available! %s:%d', vim.fn.bufname(), line), vim.log.levels.WARN)
end

function get_bookmarks()
  local bookmarks = {}
  for _, v in pairs(vim.fn.getmarklist()) do
    if v.mark >= "'A" and v.mark <= "'Z" then
      -- v.pos [bufnum, lnum, col, off]
      table.insert(bookmarks, { mark = v.mark:sub(2, 2), file = v.file, lnum = v.pos[2] })
    end
  end
  return bookmarks
end

function clear_bookmarks()
  for _, v in pairs(get_bookmarks()) do
    del_bookmark(v.file, v.mark)
  end
end

local M = {
  setup = setup,
  toggle_bookmark = toggle_bookmark,
  get_bookmarks = get_bookmarks,
  clear_bookmarks = clear_bookmarks,
  del_bookmark = function()
    vim.ui.select(get_bookmarks(), {
        prompt = 'Select one to delete: ',
        format_item = function(v)
          return string.format("%s %s:%d", v.mark, v.file, v.lnum)
        end
      },
      function(v)
        del_bookmark(v.file, v.mark)
      end)
  end
}

-- telescope

local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values

local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"

local telescope = {}

telescope.opts = {}

telescope.actions = {
  del = function(prompt_bufnr)
    local v = action_state.get_selected_entry().value
    del_bookmark(v.file, v.mark)

    local picker = action_state.get_current_picker(prompt_bufnr)
    for _, entry in ipairs(picker:get_multi_selection()) do
      v = entry.value
      -- vim.print(v)
      del_bookmark(v.file, v.mark)
    end

    picker:refresh(telescope.new_finder())
  end,

  clear = function(prompt_bufnr)
    clear_bookmarks()
    actions.close(prompt_bufnr)
  end
}

telescope.opts.mappings = {
  ['n'] = {
    ['d'] = telescope.actions.del,
    ['c'] = telescope.actions.clear
  }
}

telescope.setup = function(ext_config, config)
  -- vim.print(ext_config)
  -- vim.print(config)
  telescope.opts = vim.tbl_deep_extend("force", telescope.opts, ext_config)
  setup(telescope.opts)
end

telescope.new_finder = function ()
  return finders.new_table({
    results = get_bookmarks(),
    entry_maker = function(v)
      return {
        value = v,
        ordinal = string.format("%s\0%06d", v.file, v.lnum), -- for sorting
        display = string.format("%s %s:%d", v.mark, v.file, v.lnum),
        filename = v.file,
        lnum = v.lnum,
        col = 1,
      }
    end,
  })
end

telescope.run = function(opts)
  -- vim.print(opts) -- :messages
  opts = vim.tbl_deep_extend("force", telescope.opts, opts)
  pickers
      .new(opts, {
        prompt_title = 'Bookmarks',
        finder = telescope.new_finder(),
        sorter = conf.generic_sorter(opts),
        previewer = conf.grep_previewer(opts),
        attach_mappings = function(_, map)
          for mode, tbl in pairs(opts.mappings) do
            for key, action in pairs(tbl) do
              map(mode, key, action)
            end
          end
          return true
        end,
      })
      :find()
end

M.telescope = telescope
return M

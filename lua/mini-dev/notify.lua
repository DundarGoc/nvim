-- TODO:
--
-- Code:
-- - Auto set up for LSP progress.
--
-- Docs:
--
-- Tests:
-- - Handles width computation for empty lines inside notification.

--- *mini.notify* Show notifications
--- *MiniNotify*
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Show one or more notifications in a single floating window.
---
--- - Manage notifications (add, update, remove, clear).
---
--- - Keep history which can be accessed with |MiniNotify.get_history()|
---   and shown with |MiniNotify.show_history()|.
---
--- - |vim.notify()| wrapper generator (see |MiniNotify.make_notify()|).
---
--- - Automated show of LSP progress report.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.notify').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniNotify`
--- which you can use for scripting or manually (with `:lua MiniNotify.*`).
---
--- See |MiniNotify.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.mininotify_config` which should have same structure as
--- `MiniNotify.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'j-hui/fidget.nvim':
---     - .
---
--- - 'rcarriga/nvim-notify':
---     - .
---
--- # Highlight groups ~
---
--- * `MiniNotifyBorder` - window border.
--- * `MiniNotifyNormal` - basic foreground/background highlighting.
--- * `MiniNotifyTitle` - window title.
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling ~
---
--- To disable showing notifications, set `vim.g.mininotify_disable` (globally) or
--- `vim.b.mininotify_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.

--- # Notification specification ~
---
--- Notification is a table with the following keys:
---
--- - <msg> `(string)` - single string with notification message.
--- - <level> `(string)` - notification level as key of |vim.log.levels|.
--- - <hl_group> `(string)` - highlight group with which notification is shown.
--- - <ts_add> `(number)` - timestamp of when notification was added.
--- - <ts_update> `(number)` - timestamp of the latest notification update.
--- - <ts_remove> `(number|nil)` - timestamp of when notification was removed.
---   It is `nil` if notification was never removed and thus considered "active".
---@tag MiniNotify-specification

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
MiniNotify = {}
H = {}

--- Module setup
---
--- Calling this function creates all user commands described in |MiniDeps-actions|.
---
---@param config table|nil Module config table. See |MiniNotify.config|.
---
---@usage `require('mini.notify').setup({})` (replace `{}` with your `config` table).
MiniNotify.setup = function(config)
  -- Export module
  _G.MiniNotify = MiniNotify

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands(config)

  -- Create default highlighting
  H.create_default_hl()
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # General info ~
--- # Window ~
---
--- `config.window` defines behavior of notification window.
---
--- `config.window.config` is a table defining floating window characteristics
--- or a callable returning such table (will be called with identifier of
--- window's buffer already showing notifications). It should have the same
--- structure as in |nvim_open_win()|. It has the following default values:
--- - `width` is chosen to fit buffer content but not more than 38.2% of 'columns'.
--- - `height` is chosen to fit buffer content with enabled 'wrap'.
--- - `anchor`, `col`, and `row` are "NE", 'columns', and 0 or 1 (depending on tabline).
--- - `zindex` is 999 to be as much on top as reasonably possible.
MiniNotify.config = {
  -- Whether to set up notifications about LSP progress
  setup_lsp_progress = true,

  -- Function which orders notification array from most to least important
  -- By default orders first by level and then by update timestamp
  sort = nil,

  -- Window options
  window = {
    -- Floating window config
    config = {},

    -- Value of 'winblend' option
    winblend = 25,
  },
}
--minidoc_afterlines_end

-- Make vim.notify wrapper
--
-- Add notification and remove it after timeout.
MiniNotify.make_notify = function(opts)
  local level_names = {}
  for k, v in pairs(vim.log.levels) do
    level_names[v] = k
  end

  --stylua: ignore
  local default_opts = {
    ERROR = { timeout = 10000, hl = 'DiagnosticFloatingError' },
    WARN  = { timeout = 10000, hl = 'DiagnosticFloatingWarn'  },
    INFO  = { timeout = 10000, hl = 'DiagnosticFloatingInfo'  },
    DEBUG = { timeout = 0,     hl = 'DiagnosticFloatingHint'  },
    TRACE = { timeout = 0,     hl = 'DiagnosticFloatingOk'    },
    OFF   = { timeout = 0,     hl = 'MiniNotifyNormal'        },
  }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  for _, val in pairs(opts) do
    if type(val) ~= 'table' then H.error('Level data should be table.') end
    if type(val.timeout) ~= 'number' then H.error('`timeout` in level data should be number.') end
    if type(val.hl) ~= 'string' then H.error('`hl` in level data should be string.') end
  end

  return function(msg, level)
    level = level or vim.log.levels.INFO
    local level_name = level_names[level]
    if level_name == nil then H.error('Only valid values of `vim.log.levels` are supported.') end

    local level_data = opts[level_name]
    if level_data.timeout <= 0 then return end

    local id = MiniNotify.add(msg, level_name, level_data.hl)
    vim.defer_fn(function() MiniNotify.remove(id) end, level_data.timeout)
  end
end

---@return number Notification identifier.
MiniNotify.add = function(msg, level, hl_group)
  H.validate_msg(msg)
  level = level or 'INFO'
  H.validate_level(level)
  hl_group = hl_group or 'MiniNotifyNormal'
  H.validate_hl_group(hl_group)

  local cur_ts = vim.loop.hrtime()
  local new_notif = { msg = msg, level = level, hl_group = hl_group, ts_add = cur_ts, ts_update = cur_ts }

  local new_id = #H.history + 1
  -- NOTE: Crucial to use the same table here and later only update values
  -- inside of it in place. This makes sure that history entries are in sync.
  H.history[new_id], H.active[new_id] = new_notif, new_notif

  -- Refresh active notifications
  MiniNotify.refresh()

  return new_id
end

---@param id number Identifier of currently active notification
---   as returned by |MiniNotify.add()|.
---@param new_data table Table with data to update. Keys should be as non-timestamp
---   fields of |MiniNotify-specification|.
MiniNotify.update = function(id, new_data)
  local notif = H.active[id]
  if notif == nil then H.error('`id` is not an identifier of active notification.') end
  if type(new_data) ~= 'table' then H.error('`new_data` should be table.') end

  if new_data.msg ~= nil then H.validate_msg(new_data.msg) end
  if new_data.level ~= nil then H.validate_level(new_data.level) end
  if new_data.hl_group ~= nil then H.validate_hl_group(new_data.hl_group) end

  notif.msg = new_data.msg or notif.msg
  notif.level = new_data.level or notif.level
  notif.hl_group = new_data.hl_group or notif.hl_group
  notif.ts_update = vim.loop.hrtime()

  MiniNotify.refresh()
end

MiniNotify.remove = function(id)
  local notif = H.active[id]
  if notif == nil then return end
  notif.ts_remove = vim.loop.hrtime()
  H.active[id] = nil

  MiniNotify.refresh()
end

MiniNotify.clear = function()
  local cur_ts = vim.loop.hrtime()
  for id, _ in pairs(H.active) do
    H.active[id].ts_remove = cur_ts
  end
  H.active = {}

  MiniNotify.refresh()
end

MiniNotify.refresh = function()
  -- Prepare array of active notifications
  local notif_arr = vim.deepcopy(vim.tbl_values(H.active))
  local sort = H.get_config().sort
  if not vim.is_callable(sort) then sort = MiniNotify.default_sort end
  notif_arr = sort(notif_arr)

  if not H.is_notification_array(notif_arr) then H.error('Output of `config.sort` should be an notification array.') end
  if #notif_arr == 0 then return H.window_close() end

  -- Refresh buffer
  local buf_id = H.cache.buf_id
  if not H.is_valid_buf(buf_id) then buf_id = H.buffer_create() end
  H.buffer_refresh(buf_id, notif_arr)

  -- Refresh window
  local win_id = H.cache.win_id
  if not (H.is_valid_win(win_id) and H.is_win_in_tabpage(win_id)) then
    H.window_close()
    win_id = H.window_open(buf_id)
  else
    H.window_refresh()
  end

  -- Update cache
  H.cache.buf_id, H.cache.win_id = buf_id, win_id
end

--- Get history
---
--- In order from oldest to newest based on the creation time.
--- Content is based on the last valid update.
--- Can be used to get any notification by its id or only active notifications
--- by checking if they were removed (`ts_remove ~= nil`).
MiniNotify.get_history = function() return vim.deepcopy(H.history) end

--- Show history
---
--- Open a scratch buffer with all history.
MiniNotify.show_history = function()
  local buf_id = vim.api.nvim_create_buf(true, true)
  local notif_arr = MiniNotify.get_history()
  H.buffer_refresh(buf_id, notif_arr)
  vim.api.nvim_win_set_buf(0, buf_id)
end

MiniNotify.default_sort = function(notif_arr)
  table.sort(notif_arr, H.notif_compare)
  return notif_arr
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniNotify.config

-- Map of currently active notifications with their id as key
H.active = {}

-- History of all notifications in order they are created
H.history = {}

-- Priorities of levels
H.level_priority = { ERROR = 6, WARN = 5, INFO = 4, DEBUG = 3, TRACE = 2, OFF = 1 }

-- Namespaces
H.ns_id = {
  highlight = vim.api.nvim_create_namespace('MiniNotifyHighlight'),
}

-- Various cache
H.cache = {
  -- Notification buffer and window
  buf_id = nil,
  win_id = nil,
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  vim.validate({
    setup_lsp_progress = { config.setup_lsp_progress, 'boolean' },
    sort = { config.sort, 'function', true },
    window = { config.window, 'table' },
  })

  local is_table_or_callable = function(x) return type(x) == 'table' or vim.is_callable(x) end
  vim.validate({
    ['window.config'] = { config.window.config, is_table_or_callable, 'table or callable' },
    ['window.winblend'] = { config.window.winblend, 'number' },
  })

  return config
end

H.apply_config = function(config) MiniNotify.config = config end

H.create_autocommands = function(config)
  local augroup = vim.api.nvim_create_augroup('MiniNotify', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  au('TabEnter', '*', function() MiniNotify.refresh() end, 'Refresh in notifications in new tabpage')

  if config.setup_lsp_progress then
    -- TODO
  end
end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniNotifyBorder', { link = 'FloatBorder' })
  hi('MiniNotifyNormal', { link = 'NormalFloat' })
  hi('MiniNotifyTitle',  { link = 'FloatTitle'  })
end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniNotify.config, vim.b.mininotify_config or {}, config or {})
end

-- Buffer ---------------------------------------------------------------------
H.buffer_create = function()
  local buf_id = vim.api.nvim_create_buf(false, true)
  -- Close if this buffer becomes current
  vim.api.nvim_create_autocmd('BufEnter', { buffer = buf_id, callback = function() MiniNotify.clear() end })
  return buf_id
end

H.buffer_refresh = function(buf_id, notif_arr)
  local ns_id = H.ns_id.highlight

  -- Ensure clear buffer
  vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, true, {})

  -- Compute lines and highlight regions
  local lines, highlights = {}, {}
  for _, notif in ipairs(notif_arr) do
    local notif_lines = vim.split(notif.msg, '\n')
    for _, l in ipairs(notif_lines) do
      table.insert(lines, l)
    end
    table.insert(highlights, { group = notif.hl_group, from_line = #lines - #notif_lines + 1, to_line = #lines })
    -- Separate with empty lines
    table.insert(lines, '')
  end
  -- Don't keep last empty line
  table.remove(lines, #lines)

  -- Set lines and highlighting
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, true, lines)
  local extmark_opts = { end_col = 0, hl_eol = true, hl_mode = 'combine' }
  for _, hi_data in ipairs(highlights) do
    extmark_opts.end_row, extmark_opts.hl_group = hi_data.to_line, hi_data.group
    vim.api.nvim_buf_set_extmark(buf_id, ns_id, hi_data.from_line - 1, 0, extmark_opts)
  end
end

H.buffer_get_width = function(buf_id)
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  local res = 0
  for _, l in ipairs(lines) do
    res = math.max(res, vim.fn.strdisplaywidth(l))
  end
  return res
end

H.buffer_default_dimensions = function(buf_id)
  local line_widths = vim.tbl_map(vim.fn.strdisplaywidth, vim.api.nvim_buf_get_lines(buf_id, 0, -1, true))

  -- Compute width so as to fit all lines
  local width = 0
  for _, l_w in ipairs(line_widths) do
    width = math.max(width, l_w)
  end
  -- - Limit from above for better visuals
  width = math.min(width, math.floor(0.382 * vim.o.columns))

  -- Compute height based on the width so as to fit all lines with 'wrap' on
  local height = 0
  for _, l_w in ipairs(line_widths) do
    height = height + math.floor(math.max(l_w - 1, 0) / width) + 1
  end

  return width, height
end

-- Window ---------------------------------------------------------------------
H.window_open = function(buf_id)
  local config = H.window_compute_config(buf_id, true)
  local win_id = vim.api.nvim_open_win(buf_id, false, config)

  vim.wo[win_id].foldenable = false
  vim.wo[win_id].wrap = true
  vim.wo[win_id].winblend = H.get_config().window.winblend

  -- Neovim=0.7 doesn't support invalid highlight groups in 'winhighlight'
  vim.wo[win_id].winhighlight = 'NormalFloat:MiniNotifyNormal,FloatBorder:MiniNotifyBorder'
    .. (vim.fn.has('nvim-0.8') == 1 and ',FloatTitle:MiniNotifyTitle' or '')

  return win_id
end

H.window_refresh = function()
  local win_id = H.cache.win_id
  local buf_id = vim.api.nvim_win_get_buf(win_id)
  local new_config = H.window_compute_config(buf_id)
  vim.api.nvim_win_set_config(win_id, new_config)
end

H.window_compute_config = function(buf_id, is_for_open)
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
  local max_width = vim.o.columns

  local default_config = { relative = 'editor', style = 'minimal', noautocmd = is_for_open, zindex = 999 }
  default_config.anchor, default_config.col, default_config.row = 'NE', vim.o.columns, has_tabline and 1 or 0
  default_config.width, default_config.height = H.buffer_default_dimensions(buf_id)
  default_config.border = 'single'
  -- Make it focusable to close after it is focused (like after mouse click)
  default_config.focusable = true

  local win_config = H.get_config().window.config
  if vim.is_callable(win_config) then win_config = win_config(buf_id) end
  local config = vim.tbl_deep_extend('force', default_config, win_config or {})

  -- Tweak config values to ensure they are proper, accounting for border
  local offset = config.border == 'none' and 0 or 2
  config.height = math.min(config.height, max_height - offset)
  config.width = math.min(config.width, max_width - offset)

  return config
end

H.window_close = function()
  if H.is_valid_win(H.cache.win_id) then vim.api.nvim_win_close(H.cache.win_id, true) end
  H.cache.win_id = nil
end

-- Notifications --------------------------------------------------------------
H.validate_msg = function(x)
  if type(x) ~= 'string' then H.error('`msg` should be string.') end
end

H.validate_level = function(x)
  if vim.log.levels[x] == nil then H.error('`level` should be key of `vim.log.levels`.') end
end

H.validate_hl_group = function(x)
  if type(x) ~= 'string' then H.error('`hl_group` should be string.') end
end

H.is_notification = function(x)
  return type(x) == 'table'
    and type(x.msg) == 'string'
    and vim.log.levels[x.level] ~= nil
    and type(x.hl_group) == 'string'
    and type(x.ts_add) == 'number'
    and type(x.ts_update) == 'number'
    and (x.ts_remove == nil or type(x.ts_remove) == 'number')
end

H.is_notification_array = function(x)
  if not vim.tbl_islist(x) then return false end
  for _, y in ipairs(x) do
    if not H.is_notification(y) then return false end
  end
  return true
end

H.notif_compare = function(a, b)
  local a_priority, b_priority = H.level_priority[a.level], H.level_priority[b.level]
  return a_priority > b_priority or (a_priority == b_priority and a.ts_update > b.ts_update)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.notify) %s', msg), 0) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.is_win_in_tabpage = function(win_id) return vim.api.nvim_win_get_tabpage(win_id) == vim.api.nvim_get_current_tabpage() end

return MiniNotify
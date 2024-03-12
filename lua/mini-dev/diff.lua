-- TODO:
--
-- Code:
-- - Consider refactoring so that word diff is only done for visible line (i.e.
--   probably in decoration provider).
--
-- - Update overlay to show word/char diff highlighting for "change" hunk type.
--
-- - When moving added line upwards, extmark should not temporarily shift down.
--
-- - Think if having `vim.b.minidiff_disable` is worth it as there is
--   `MiniDiff.enable()` and `MiniDiff.disable()`.
--
-- - Consider keeping track of reference text history to allow "rollback"?
--
-- - `gen_source.file` to compare against some fixed file?
-- - `toggle_source()`?
-- - `setqflist()`.
--
-- Docs:
--
-- Tests:
-- - Updates if no redraw seemingly is done. Example for `save` source: `yyp`
--   should add green highlighting and `<C-s>` should remove it.
--
-- - Deleting last line should be visualized.
--
-- - Changing line which is already visualizing deleted (below) line should
--   result into visualizing line as "change" and not "delete".
--
-- - Word diff should work with multibyte characters.
--
-- - Git source:
--     - Manage "not in index" files by not showing diff visualization.
--     - Manage "neither in index nor on disk" (for example, after checking out
--       commit which does not yet have file created).
--     - Manage "relative can not be used outside working tree" (for example,
--       when opening file inside '.git' directory).
--     - Manage renaming file while having `git` attached, as this might
--       disable tracking due to "neither in index nor on disk" error.
--
-- - Actions:
--     - Should work for all types of hunks (add, change, delete) in all
--       relative buffer places (first lines, middle lines, last lines).
--     - Operator's dot-repeat should work in different buffer than was
--       originally applied.

--- *mini.diff* Work with diff hunks
--- *MiniDiff*
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Show "as you type" 1-way diff by visualizing diff hunks (linewise parts
---   of text that are different between current and reference versions).
---   Visualization can be with colored signs, colored line numbers, etc.
---
--- - Special toggleable view with detailed hunk information directly in text area.
---
--- - Completely configurable and extensible source of text to compare against:
---   text at latest save, file state from Git, etc.
---
--- - Manage diff hunks: navigate, apply, textobject, and more.
---
--- What it doesn't do:
---
--- - Provide functionality to work directly with Git outside of working with
---   Git-related hunks (see |MiniDiff.gen_source.git()|).
---
--- Sources with more details:
--- - |MiniDiff-overview|
--- - |MiniDiff-source-specification|
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.diff').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniDeps`
--- which you can use for scripting or manually (with `:lua MiniDeps.*`).
---
--- See |MiniDeps.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minidiff_config` which should have same structure as
--- `MiniDeps.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'lewis6991/gitsigns.nvim':
---     - Can display only Git diff hunks, while this module has extensible design.
---     - Provides more functionality to work with Git outside of hunks.
---       This module does not (by design).
---
--- # Highlight groups ~
---
--- * `MiniDiffSignAdd`     - add hunks with gutter view.
--- * `MiniDiffSignChange`  - change hunks with gutter view.
--- * `MiniDiffSignDelete`  - delete hunks with gutter view.
--- * `MiniDiffOverAdd`     - added text shown in overlay.
--- * `MiniDiffOverChange`  - changed text shown in overlay.
--- * `MiniDiffOverContext` - context text shown in overlay.
--- * `MiniDiffOverDelete`  - deleted text shown in overlay.
---
--- To change any highlight group, modify it directly with |:highlight|.

---@tag MiniDiff-overview

---@tag MiniDiff-plugin-specification

---@tag MiniDiff-events

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
-- TODO: Remove before release
MiniDiff = {}
H = {}

--- Module setup
---
--- Calling this function creates user commands described in |MiniDeps-commands|.
---
---@param config table|nil Module config table. See |MiniDeps.config|.
---
---@usage `require('mini.deps').setup({})` (replace `{}` with your `config` table).
MiniDiff.setup = function(config)
  -- Export module
  _G.MiniDiff = MiniDiff

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    H.auto_enable({ buf = buf_id })
  end

  -- Create default highlighting
  H.create_default_hl()
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniDiff.config = {
  -- Options for how hunks are visualized
  view = {
    -- Visualization style. Possible values are 'sign' and 'number'.
    style = vim.o.number and 'number' or 'sign',

    -- Signs used for hunks with 'sign' view
    signs = { add = '▒', change = '▒', delete = '▒' },

    -- Basic priority of used extmarks
    priority = 300,
  },

  -- Source for how to reference text is computed/updated/etc.
  source = nil,

  -- Delays (in ms) defining asynchronous visualization process
  delay = {
    -- How much to wait for update after every text change
    text_change = 200,
  },

  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Apply hunks inside a visual/operator region
    apply = 'gh',

    -- Reset hunks inside a visual/operator region
    reset = 'gH',

    -- Hunk range textobject
    textobject = 'gh',

    -- Go to Hunk range in corresponding direction
    goto_first = '[H',
    goto_prev = '[h',
    goto_next = ']h',
    goto_last = ']H',
  },

  -- Various options
  options = {
    -- Diff algorithm
    algorithm = 'patience',

    -- Whether to use "indent heuristic"
    indent_heuristic = true,

    -- The amount of second-stage diff to align lines (on Neovim>=0.9)
    linematch = 60,
  },
}
--minidoc_afterlines_end

--- Enable diff tracking in buffer
MiniDiff.enable = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)

  -- Don't enable more than once
  if H.is_buf_enabled(buf_id) then return end

  -- Register enabled buffer with cached data for performance
  H.cache[buf_id] = {}
  H.update_cache(buf_id)

  -- Attach source
  local attach_output = H.cache[buf_id].source.attach(buf_id)
  if attach_output == false then return MiniDiff.disable(buf_id) end

  -- Add buffer watchers
  vim.api.nvim_buf_attach(buf_id, false, {
    -- Called on every text change (`:h nvim_buf_lines_event`)
    on_lines = function(_, _, _, from_line, _, to_line)
      local buf_cache = H.cache[buf_id]
      -- Properly detach if diffing is disabled
      if buf_cache == nil then return true end
      H.schedule_diff_update(buf_id, buf_cache.config.delay.text_change)
    end,

    -- Called when buffer content is changed outside of current session
    on_reload = function() pcall(MiniDiff.refresh, buf_id) end,

    -- Called when buffer is unloaded from memory (`:h nvim_buf_detach_event`),
    -- **including** `:edit` command
    on_detach = function() MiniDiff.disable(buf_id) end,
  })

  -- Add buffer autocommands
  local augroup = vim.api.nvim_create_augroup('MiniDiffBuffer' .. buf_id, { clear = true })
  H.cache[buf_id].augroup = augroup

  local buf_update = vim.schedule_wrap(function() H.update_cache(buf_id) end)
  local bufwinenter_opts = { group = augroup, buffer = buf_id, callback = buf_update, desc = 'Update buffer cache' }
  vim.api.nvim_create_autocmd('BufWinEnter', bufwinenter_opts)

  local buf_disable = function() MiniDiff.disable(buf_id) end
  local bufdelete_opts = { group = augroup, buffer = buf_id, callback = buf_disable, desc = 'Disable on delete' }
  vim.api.nvim_create_autocmd('BufDelete', bufdelete_opts)

  local reset = function()
    MiniDiff.disable(buf_id)
    MiniDiff.enable(buf_id)
  end
  local bufnew_opts = { group = augroup, buffer = buf_id, callback = reset, desc = 'Reset on rename' }
  vim.api.nvim_create_autocmd('BufNew', bufnew_opts)

  -- Immediately process whole buffer
  H.schedule_diff_update(buf_id, 0)
end

--- Disable diff tracking in buffer
MiniDiff.disable = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)

  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then return end
  H.cache[buf_id] = nil

  pcall(vim.api.nvim_del_augroup_by_id, buf_cache.augroup)
  H.clear_all_diff(buf_id)
  pcall(buf_cache.source.detach, buf_id)
end

--- Toggle diff tracking in buffer
MiniDiff.toggle = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)
  if H.is_buf_enabled(buf_id) then return MiniDiff.disable(buf_id) end
  return MiniDiff.enable(buf_id)
end

--- Toggle visualization style in buffer
MiniDiff.toggle_overlay = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)
  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then H.error(string.format('Buffer %d is not enabled.', buf_id)) end

  buf_cache.overlay = not buf_cache.overlay
  H.update_cache(buf_id)
  H.clear_all_diff(buf_id)
  H.schedule_diff_update(buf_id, 0)
end

--- Refresh diff content in buffer
MiniDiff.refresh = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)
  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then H.error(string.format('Buffer %d is not enabled.', buf_id)) end
  buf_cache.source.refresh(buf_id)
end

-- `ref_text` can be `nil` indicating that source did not react (yet).
MiniDiff.get_buf_data = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)
  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then return nil end
  return vim.deepcopy({
    ref_text = buf_cache.ref_text,
    hunks = buf_cache.hunks,
    hunk_summary = buf_cache.hunk_summary,
    config = buf_cache.config,
  })
end

---@param buf_id number|nil Buffer identifier. Default: `nil` for current buffer (same as 0).
---@param text string|table|nil New reference text. Either a string with `\n` used to
---   separate lines or array of lines. Use empty table to unset current
---   reference text results into no hunks shown. Default: `{}`.
MiniDiff.set_ref_text = function(buf_id, text)
  buf_id = H.validate_buf_id(buf_id)
  if type(text) == 'table' then text = #text > 0 and table.concat(text, '\n') or nil end
  if not (text == nil or type(text) == 'string') then H.error('`text` should be either string or array.') end

  -- Enable if not already enabled
  if not H.is_buf_enabled(buf_id) then MiniDiff.enable(buf_id) end

  -- Appending '\n' makes more intuitive diffs at end-of-file
  if text ~= nil and string.sub(text, -1) ~= '\n' then text = text .. '\n' end
  if text == nil then
    H.clear_all_diff(buf_id)
    vim.cmd('redraw')
  end

  H.cache[buf_id].ref_text = text
  H.schedule_diff_update(buf_id, 0)
end

--- Generate builtin highlighters
---
--- This is a table with function elements. Call to actually get highlighter.
MiniDiff.gen_source = {}

MiniDiff.gen_source.git = function()
  local attach = function(buf_id)
    local path = vim.api.nvim_buf_get_name(buf_id)
    if path == '' or vim.fn.filereadable(path) ~= 1 then return end
    H.git_start_watching_index(buf_id, path)
  end

  local refresh = function(buf_id)
    if H.git_cache[buf_id] == nil then return end
    H.git_set_ref_text(buf_id)
  end

  local detach = function(buf_id)
    local cache = H.git_cache[buf_id]
    H.git_cache[buf_id] = nil
    H.git_invalidate_cache(cache)
  end

  local apply_hunks = function(buf_id, hunks)
    if H.git_cache[buf_id] == nil then H.error('Buffer is not inside Git repo.') end
    local path = vim.api.nvim_buf_get_name(buf_id)
    if path == '' then return nil end

    local path_data = H.git_get_path_data(path)
    if path_data == nil or path_data.rel_path == nil then return end
    local patch = H.git_format_patch(buf_id, hunks, path_data)
    H.git_apply_patch(path_data, patch)
  end

  -- TODO: Think about a possible abstraction that would allow to unstage
  -- already staged hunks

  return { name = 'git', attach = attach, refresh = refresh, detach = detach, apply_hunks = apply_hunks }
end

MiniDiff.gen_source.save = function()
  local augroups = {}
  local attach = function(buf_id)
    local augroup = vim.api.nvim_create_augroup('MiniDiffSourceSaveBuffer' .. buf_id, { clear = true })
    augroups[buf_id] = augroup

    local set_ref = function()
      if vim.bo[buf_id].modified then return end
      MiniDiff.set_ref_text(buf_id, vim.api.nvim_buf_get_lines(buf_id, 0, -1, false))
    end

    -- Autocommand are more effecient than file watcher as it doesn't read disk
    local au_opts = { group = augroup, buffer = buf_id, callback = set_ref, desc = 'Set reference text after save' }
    vim.api.nvim_create_autocmd({ 'BufWritePost', 'FileChangedShellPost' }, au_opts)
    set_ref()
  end

  local detach = function(buf_id) pcall(vim.api.nvim_del_augroup_by_id, augroups[buf_id]) end

  return { name = 'save', attach = attach, detach = detach }
end

MiniDiff.do_hunks = function(buf_id, action, opts)
  buf_id = H.validate_buf_id(buf_id)
  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then H.error(string.format('Buffer %d is not enabled.', buf_id)) end
  if type(buf_cache.ref_text) ~= 'string' then H.error(string.format('Buffer %d has no reference text.', buf_id)) end

  if not (action == 'apply' or action == 'reset') then H.error('`action` should be one of "apply", "reset".') end

  opts = vim.tbl_deep_extend('force', { line_start = 1, line_end = vim.api.nvim_buf_line_count(buf_id) }, opts or {})
  local line_start, line_end = H.validate_target_lines(buf_id, opts.line_start, opts.line_end)

  local hunks = H.get_hunks_in_range(buf_cache.hunks, line_start, line_end)
  if #hunks == 0 then return H.notify('No hunks to ' .. action .. '.', 'INFO') end
  local f = action == 'apply' and buf_cache.source.apply_hunks or H.reset_hunks
  f(buf_id, hunks)
end

--- Go to hunk range
---
---@param direction string One of "first", "prev", "next", "last".
---@param opts table|nil Options. A table with fields:
---   - <n_times> `(number)` - Number of times to advance. Default: |v:count1|.
---   - <line_start> `(number)` - Line number to start from for directions
---     "prev" and "next". Default: cursor line.
MiniDiff.goto_hunk = function(direction, opts)
  local buf_id = vim.api.nvim_get_current_buf()
  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then H.error(string.format('Buffer %d is not enabled.', buf_id)) end

  if not vim.tbl_contains({ 'first', 'prev', 'next', 'last' }, direction) then
    H.error('`direction` should be one of "first", "prev", "next", "last".')
  end

  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, line_start = vim.fn.line('.') }, opts or {})
  if not (type(opts.n_times) == 'number' and opts.n_times >= 1) then
    H.error('`opts.n_times` should be positive number.')
  end
  local line_start = opts.line_start
  if type(line_start) ~= 'number' then H.error('`opts.line_start` should be number.') end

  -- Prepare ranges to iterate.
  local ranges = H.get_contiguous_hunk_ranges(buf_cache.hunks)
  if #ranges == 0 then return H.notify('No hunks to go to.', 'INFO') end

  -- Compute iteration data
  local iter_dir = (direction == 'first' or direction == 'next') and 'forward' or 'backward'
  if direction == 'first' then line_start = 0 end
  if direction == 'last' then line_start = vim.api.nvim_buf_line_count(buf_id) + 1 end

  -- Iterate
  local res_line = H.iterate_hunk_ranges(ranges, iter_dir, line_start, opts.n_times)
  if res_line == nil then return H.notify('No hunk ranges in direction "' .. direction .. '".', 'INFO') end

  -- Add to jumplist
  vim.cmd([[normal! m']])

  -- Jump
  local _, col = vim.fn.getline(res_line):find('^%s*')
  vim.api.nvim_win_set_cursor(0, { res_line, col })

  -- Open just enough folds
  vim.cmd('normal! zv')
end

--- Perform action over region
---
--- Perform action over region defined by marks. Used in mappings.
---
---@param mode string One of "apply", "reset", or the ones used in |g@|.
MiniDiff.operator = function(mode)
  if H.is_disabled(0) then return '' end

  if mode == 'apply' or mode == 'reset' then
    H.operator_cache = { action = mode }
    vim.o.operatorfunc = 'v:lua.MiniDiff.operator'
    return 'g@'
  end

  -- NOTE: Using `[` / `]` marks also works in Visual mode as because it is
  -- executed as part of `g@`, which treats visual selection as a result of
  -- Operator-pending mode mechanics (for which visual selection is allowed to
  -- define motion/textobject). The downside is that it sets 'operatorfunc',
  -- but the upside is that it is "dot-repeatable" (for relative selection).
  local opts = { line_start = vim.fn.line("'["), line_end = vim.fn.line("']") }
  MiniDiff.do_hunks(vim.api.nvim_get_current_buf(), H.operator_cache.action, opts)
  return ''
end

--- Select hunk range textobject
---
--- Selects all lines adjacent to cursor line which are in any (not necessarily
--- same) hunk (if cursor line itself is in hunk). Used in default mappings.
MiniDiff.textobject = function()
  local buf_id = vim.api.nvim_get_current_buf()
  if H.is_disabled(buf_id) then return end
  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then H.error('Current buffer is not enabled.') end

  -- Get hunk range under cursor
  local cur_line = vim.fn.line('.')
  local regions, cur_region = H.get_contiguous_hunk_ranges(buf_cache.hunks), nil
  for _, r in ipairs(regions) do
    if r.from <= cur_line and cur_line <= r.to then cur_region = r end
  end
  if cur_region == nil then return H.notify('No hunk range under cursor.', 'INFO') end

  -- Select target region
  local is_visual = vim.tbl_contains({ 'v', 'V', '\22' }, vim.fn.mode())
  if is_visual then vim.cmd('normal! \27') end
  vim.cmd(string.format('normal! %dGV%dG', cur_region.from, cur_region.to))
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniDiff.config

H.default_source = MiniDiff.gen_source.git()

-- Timers
H.timer_diff_update = vim.loop.new_timer()

-- Namespaces per highlighter name
H.ns_id = {
  viz = vim.api.nvim_create_namespace('MiniDiffViz'),
}

-- Cache of buffers waiting for debounced diff update
H.bufs_to_update = {}

-- Cache per enabled buffer
H.cache = {}

-- Table tracking which buffers were already tried to auto enable
H.bufs_auto_enabled = {}

-- Cache per buffer for attached `git` source
H.git_cache = {}

-- Cache for operator
H.operator_cache = {}

-- Common extmark data for supported styles
--stylua: ignore
H.style_extmark_data = {
  sign    = { hl_group_prefix = 'MiniDiffSign', field = 'sign_hl_group' },
  number  = { hl_group_prefix = 'MiniDiffSign', field = 'number_hl_group' },
}

-- Suffix for overlay virtual lines to be highlighted as full line
H.overlay_suffix = string.rep(' ', vim.o.columns)

-- Permanent `vim.diff()` options
H.vimdiff_opts = { result_type = 'indices', ctxlen = 0, interhunkctxlen = 0 }
H.vimdiff_supports_linematch = vim.fn.has('nvim-0.9') == 1

-- Options for `vim.diff()` during word diff. Use `interhunkctxlen = 4` to
-- reduce noisiness (chosen as slightly less than everage English word length)
H.worddiff_opts = { result_type = 'indices', ctxlen = 0, interhunkctxlen = 4, indent_heuristic = false }
if H.vimdiff_supports_linematch then H.worddiff_opts.linematch = 0 end

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  vim.validate({
    view = { config.view, 'table' },
    source = { config.source, 'table', true },
    delay = { config.delay, 'table' },
    mappings = { config.mappings, 'table' },
    options = { config.options, 'table' },
  })

  vim.validate({
    ['view.style'] = { config.view.style, 'string' },
    ['view.signs'] = { config.view.signs, 'table' },
    ['view.priority'] = { config.view.priority, 'number' },

    ['delay.text_change'] = { config.delay.text_change, 'number' },

    ['mappings.apply'] = { config.mappings.apply, 'string' },
    ['mappings.reset'] = { config.mappings.reset, 'string' },
    ['mappings.textobject'] = { config.mappings.textobject, 'string' },
    ['mappings.goto_first'] = { config.mappings.goto_first, 'string' },
    ['mappings.goto_prev'] = { config.mappings.goto_prev, 'string' },
    ['mappings.goto_next'] = { config.mappings.goto_next, 'string' },
    ['mappings.goto_last'] = { config.mappings.goto_last, 'string' },

    ['options.algorithm'] = { config.options.algorithm, 'string' },
    ['options.indent_heuristic'] = { config.options.indent_heuristic, 'boolean' },
    ['options.linematch'] = { config.options.linematch, 'number' },
  })

  vim.validate({
    ['view.signs.add'] = { config.view.signs.add, 'string' },
    ['view.signs.change'] = { config.view.signs.change, 'string' },
    ['view.signs.delete'] = { config.view.signs.delete, 'string' },
  })

  return config
end

H.apply_config = function(config)
  MiniDiff.config = config

  -- Make mappings
  local mappings = config.mappings

  local rhs_apply = function() return MiniDiff.operator('apply') end
  H.map({ 'n', 'x' }, mappings.apply, rhs_apply, { expr = true, desc = 'Apply hunks' })
  local rhs_reset = function() return MiniDiff.operator('reset') end
  H.map({ 'n', 'x' }, mappings.reset, rhs_reset, { expr = true, desc = 'Reset hunks' })

  H.map('o', mappings.textobject, '<Cmd>lua MiniDiff.textobject()<CR>', { desc = 'Hunk range textobject' })

  --stylua: ignore start
  H.map({ 'n', 'x' }, mappings.goto_first,  "<Cmd>lua MiniDiff.goto_hunk('first')<CR>", { desc = 'First hunk' })
  H.map('o',          mappings.goto_first, "V<Cmd>lua MiniDiff.goto_hunk('first')<CR>", { desc = 'First hunk' })
  H.map({ 'n', 'x' }, mappings.goto_prev,   "<Cmd>lua MiniDiff.goto_hunk('prev')<CR>",  { desc = 'Previous hunk' })
  H.map('o',          mappings.goto_prev,  "V<Cmd>lua MiniDiff.goto_hunk('prev')<CR>",  { desc = 'Previous hunk' })
  H.map({ 'n', 'x' }, mappings.goto_next,   "<Cmd>lua MiniDiff.goto_hunk('next')<CR>",  { desc = 'Next hunk' })
  H.map('o',          mappings.goto_next,  "V<Cmd>lua MiniDiff.goto_hunk('next')<CR>",  { desc = 'Next hunk' })
  H.map({ 'n', 'x' }, mappings.goto_last,   "<Cmd>lua MiniDiff.goto_hunk('last')<CR>",  { desc = 'Last hunk' })
  H.map('o',          mappings.goto_last,  "V<Cmd>lua MiniDiff.goto_hunk('last')<CR>",  { desc = 'Last hunk' })
  --stylua: ignore end

  -- Register decoration provider which actually makes visualization
  local ns_id_viz = H.ns_id.viz
  local on_win = function(_, _, bufnr, top, bottom)
    local buf_cache = H.cache[bufnr]
    if buf_cache == nil then return false end

    if buf_cache.needs_clear then
      H.clear_all_diff(bufnr)
      buf_cache.needs_clear = false
    end

    local draw_lines = buf_cache.draw_lines
    for i = top + 1, bottom + 1 do
      if draw_lines[i] ~= nil then
        for _, data in ipairs(draw_lines[i]) do
          H.set_extmark(bufnr, ns_id_viz, i - 1, data.col, data.opts)
        end
        draw_lines[i] = nil
      end
    end
  end
  vim.api.nvim_set_decoration_provider(ns_id_viz, { on_win = on_win })
end

H.create_autocommands = function()
  local augroup = vim.api.nvim_create_augroup('MiniDiff', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  -- NOTE: Try auto enabling buffer only once. This is done in `BufEnter` event
  -- with additional tracking (and not in `BufNew`) to also work for when
  -- buffers are opened during startup (and `BufNew` is not triggered).
  au('BufEnter', '*', H.auto_enable, 'Enable diff')
  au('VimResized', '*', function() H.overlay_suffix = string.rep(' ', vim.o.columns) end, 'Track Neovim resizing')
end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  local has_core_diff_hl = vim.fn.has('nvim-0.10') == 1
  hi('MiniDiffSignAdd',     { link = has_core_diff_hl and 'Added' or 'diffAdded' })
  hi('MiniDiffSignChange',  { link = has_core_diff_hl and 'Changed' or 'diffChanged' })
  hi('MiniDiffSignDelete',  { link = has_core_diff_hl and 'Removed' or 'diffRemoved'  })
  hi('MiniDiffOverAdd',     { link = 'DiffAdd' })
  hi('MiniDiffOverChange',  { link = 'DiffText' })
  hi('MiniDiffOverContext', { link = 'DiffChange' })
  hi('MiniDiffOverDelete',  { link = 'DiffDelete'  })
end

H.is_disabled = function(buf_id)
  local buf_disable = H.get_buf_var(buf_id, 'minidiff_disable')
  return vim.g.minidiff_disable == true or buf_disable == true
end

H.get_config = function(config, buf_id)
  local buf_config = H.get_buf_var(buf_id, 'minidiff_config') or {}
  return vim.tbl_deep_extend('force', MiniDiff.config, buf_config, config or {})
end

H.get_buf_var = function(buf_id, name)
  if not vim.api.nvim_buf_is_valid(buf_id) then return nil end
  return vim.b[buf_id or 0][name]
end

-- Autocommands ---------------------------------------------------------------
H.auto_enable = vim.schedule_wrap(function(data)
  if H.bufs_auto_enabled[data.buf] or H.is_buf_enabled(data.buf) or H.is_disabled(data.buf) then return end
  if not vim.api.nvim_buf_is_valid(data.buf) or vim.bo[data.buf].buftype ~= '' then return end
  if not H.is_buf_text(data.buf) then return end
  H.bufs_auto_enabled[data.buf] = true
  MiniDiff.enable(data.buf)
end)

-- Validators -----------------------------------------------------------------
H.validate_buf_id = function(x)
  if x == nil or x == 0 then return vim.api.nvim_get_current_buf() end
  if not (type(x) == 'number' and vim.api.nvim_buf_is_valid(x)) then
    H.error('`buf_id` should be `nil` or valid buffer id.')
  end
  return x
end

H.validate_target_lines = function(buf_id, line_start, line_end)
  local n_lines = vim.api.nvim_buf_line_count(buf_id)

  if type(line_start) ~= 'number' then H.error('`line_start` should be number.') end
  if type(line_end) ~= 'number' then H.error('`line_end` should be number.') end

  -- Allow negative lines to count from last line
  line_start = line_start < 0 and (n_lines + line_start + 1) or line_start
  line_end = line_end < 0 and (n_lines + line_end + 1) or line_end

  -- Clamp to fit the allowed range
  line_start = math.min(math.max(line_start, 1), n_lines)
  line_end = math.min(math.max(line_end, 1), n_lines)
  if not (line_start <= line_end) then H.error('`line_start` should be less than or equal to `line_end`.') end

  return line_start, line_end
end

H.validate_callable = function(x, name)
  if vim.is_callable(x) then return x end
  H.error('`' .. name .. '` should be callable.')
end

-- Enabling -------------------------------------------------------------------
H.is_buf_enabled = function(buf_id) return H.cache[buf_id] ~= nil end

H.update_cache = function(buf_id)
  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then return end

  local buf_config = H.get_config({}, buf_id)
  buf_cache.config = buf_config
  buf_cache.extmark_data = H.convert_view_to_extmark_opts(buf_config.view)
  buf_cache.source = H.normalize_source(buf_config.source or H.default_source)

  buf_cache.hunks = buf_cache.hunks or {}
  buf_cache.hunk_summary = buf_cache.hunk_summary or {}
  buf_cache.draw_lines = buf_cache.draw_lines or {}

  H.cache[buf_id] = buf_cache
end

H.normalize_source = function(source)
  if type(source) ~= 'table' then H.error('`source` should be table.') end

  local res = { attach = source.attach }
  res.name = source.name or 'unknown'
  res.refresh = source.refresh or function(buf_id) MiniDiff.set_ref_text(buf_id, H.cache[buf_id].ref_text) end
  res.detach = source.detach or function(_) end
  res.apply_hunks = source.apply_hunks or function(_) H.error('Current source does not support applying hunks.') end

  if type(res.name) ~= 'string' then H.error('`source.name` should be string.') end
  H.validate_callable(res.attach, 'source.attach')
  H.validate_callable(res.refresh, 'source.refresh')
  H.validate_callable(res.detach, 'source.detach')
  H.validate_callable(res.apply_hunks, 'source.apply_hunks')

  return res
end

H.convert_view_to_extmark_opts = function(view)
  local extmark_data = H.style_extmark_data[view.style]
  if extmark_data == nil then H.error('Style ' .. vim.inspect(view.style) .. ' is not supported.') end

  local signs = view.style == 'sign' and view.signs or {}
  local field, hl_group_prefix = extmark_data.field, extmark_data.hl_group_prefix
  return {
    add = { [field] = hl_group_prefix .. 'Add', sign_text = signs.add, priority = view.priority },
    -- Prefer showing "change" hunks over others
    change = { [field] = hl_group_prefix .. 'Change', sign_text = signs.change, priority = view.priority + 1 },
    delete = { [field] = hl_group_prefix .. 'Delete', sign_text = signs.delete, priority = view.priority - 1 },
  }
end

-- Processing -----------------------------------------------------------------
H.schedule_diff_update = vim.schedule_wrap(function(buf_id, delay_ms)
  H.bufs_to_update[buf_id] = true
  H.timer_diff_update:stop()
  H.timer_diff_update:start(delay_ms, 0, H.process_scheduled_buffers)
end)

H.process_scheduled_buffers = vim.schedule_wrap(function()
  for buf_id, _ in pairs(H.bufs_to_update) do
    H.update_buf_diff(buf_id)
  end
  H.bufs_to_update = {}
end)

H.update_buf_diff = vim.schedule_wrap(function(buf_id)
  -- Make early returns
  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then return end
  if not vim.api.nvim_buf_is_valid(buf_id) then
    H.cache[buf_id] = nil
    return
  end
  if type(buf_cache.ref_text) ~= 'string' or H.is_disabled(buf_id) then
    buf_cache.hunks, buf_cache.hunk_summary, buf_cache.draw_lines = {}, {}, {}
    vim.b[buf_id].minidiff_summary, vim.b[buf_id].minidiff_summary_string = {}, ''
    return
  end

  -- Compute diff
  local options = buf_cache.config.options
  H.vimdiff_opts.algorithm = options.algorithm
  H.vimdiff_opts.indent_heuristic = options.indent_heuristic
  if H.vimdiff_supports_linematch then H.vimdiff_opts.linematch = options.linematch end

  -- - NOTE: Appending '\n' makes more intuitive diffs at end-of-file
  local cur_lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  local cur_text = table.concat(cur_lines, '\n') .. '\n'
  local diff = vim.diff(buf_cache.ref_text, cur_text, H.vimdiff_opts)

  -- Recompute hunks with summary and draw information
  buf_cache.hunks, buf_cache.draw_lines, buf_cache.hunk_summary = H.compute_hunk_data(diff, buf_cache, cur_lines)

  -- Set buffer-local variables with summary for easier external usage
  local hunk_summary = buf_cache.hunk_summary
  vim.b[buf_id].minidiff_summary = hunk_summary

  local summary = {}
  if hunk_summary.add > 0 then table.insert(summary, '+' .. hunk_summary.add) end
  if hunk_summary.change > 0 then table.insert(summary, '~' .. hunk_summary.change) end
  if hunk_summary.delete > 0 then table.insert(summary, '-' .. hunk_summary.delete) end
  vim.b[buf_id].minidiff_summary_string = table.concat(summary, ' ')

  -- Request highlighting clear to be done in decoration provider
  buf_cache.needs_clear = true

  -- Force redraw. NOTE: Using 'redraw' not always works (`<Cmd>update<CR>`
  -- from keymap with "save" source will not redraw) while 'redraw!' flickers.
  vim.api.nvim__buf_redraw_range(buf_id, 0, -1)

  -- Redraw statusline to have possible statusline component up to date
  vim.cmd('redrawstatus')

  -- Trigger event for users to possibly hook into
  vim.api.nvim_exec_autocmds('User', { pattern = 'MiniDiffUpdated' })
end)

H.compute_hunk_data = function(diff, buf_cache, cur_lines)
  local ref_lines = buf_cache.overlay and vim.split(buf_cache.ref_text, '\n') or nil

  local extmark_data = buf_cache.extmark_data
  local hunks, draw_lines, n_add, n_change, n_delete = {}, {}, 0, 0, 0
  for i, d in ipairs(diff) do
    -- Hunk
    local n_ref, n_cur = d[2], d[4]
    local hunk_type = n_ref == 0 and 'add' or (n_cur == 0 and 'delete' or 'change')
    local hunk = { type = hunk_type, ref_start = d[1], ref_count = n_ref, cur_start = d[3], cur_count = n_cur }
    hunks[i] = hunk

    -- Summary
    local hunk_n_change = math.min(n_ref, n_cur)
    n_add = n_add + n_cur - hunk_n_change
    n_change = n_change + hunk_n_change
    n_delete = n_delete + n_ref - hunk_n_change

    -- Register lines for draw. At least one line should visualize hunk.
    local from, n = math.max(d[3], 1), math.max(n_cur, 1)
    local draw_data = { col = 0, opts = extmark_data[hunk_type] }
    for l_num = from, from + n - 1 do
      -- Allow drawing several extmarks on one line (delete, change, overlay)
      local l_data = draw_lines[l_num] or {}
      table.insert(l_data, draw_data)
      draw_lines[l_num] = l_data
    end

    -- Add overlay extmark options
    -- TODO: Possibly refactor to populate `draw_lines` directly
    local overlay_extmarks = H.compute_overlay_extmarks(hunk, ref_lines, cur_lines, buf_cache)
    for _, overlay_data in ipairs(overlay_extmarks) do
      table.insert(draw_lines[overlay_data.l_num], overlay_data.data)
    end
  end

  return hunks, draw_lines, { add = n_add, change = n_change, delete = n_delete }
end

H.clear_all_diff = function(buf_id) H.clear_namespace(buf_id, H.ns_id.viz, 0, -1) end

-- Overlay --------------------------------------------------------------------
H.compute_overlay_extmarks = function(hunk, ref_lines, cur_lines, buf_cache)
  -- Use `nil` reference lines as indicator that there is no overlay
  if ref_lines == nil then return {} end

  local res, priority = {}, buf_cache.config.view.priority
  if hunk.type == 'add' then H.append_overlay_add(res, hunk, priority) end
  if hunk.type == 'change' then H.append_overlay_change(res, hunk, ref_lines, cur_lines, priority) end
  if hunk.type == 'delete' then H.append_overlay_delete(res, hunk, ref_lines, priority) end
  return res
end

H.append_overlay_add = function(target, hunk, priority)
  local from, to = hunk.cur_start, hunk.cur_start + hunk.cur_count - 1
  local ext_opts = { end_row = to, end_col = 0, hl_group = 'MiniDiffOverAdd', hl_eol = true, priority = priority }
  table.insert(target, { l_num = from, data = { col = 0, opts = ext_opts } })
end

H.append_overlay_change = function(target, hunk, ref_lines, cur_lines, priority)
  -- For one-to-one change, show lines separately with word diff highlighted
  -- This is usually the case when `linematch` is on
  if hunk.cur_count == hunk.ref_count then
    for i = 0, hunk.ref_count - 1 do
      local ref_l_num, cur_l_num = hunk.ref_start + i, hunk.cur_start + i
      local ref_l, cur_l = ref_lines[ref_l_num], cur_lines[cur_l_num]
      H.append_overlay_change_worddiff(target, ref_l, cur_l, cur_l_num, priority)
    end
    return
  end

  -- If not one-to-one change, show reference lines above first real one
  local changed_lines = {}
  for i = hunk.ref_start, hunk.ref_start + hunk.ref_count - 1 do
    local l = { { ref_lines[i], 'MiniDiffOverChange' }, { H.overlay_suffix, 'MiniDiffOverChange' } }
    table.insert(changed_lines, l)
  end
  local ext_opts = { virt_lines = changed_lines, virt_lines_above = true, priority = priority + 1 }
  table.insert(target, { l_num = hunk.cur_start, data = { col = 0, opts = ext_opts } })
end

H.append_overlay_change_worddiff = function(target, ref_line, cur_line, cur_l_num, priority)
  local ref_parts, cur_parts = H.compute_worddiff_changed_parts(ref_line, cur_line)

  -- Show changed parts in reference line as virtual line above
  local virt_line, index = {}, 1
  for i = 1, #ref_parts do
    local part = ref_parts[i]
    if index < part[1] then table.insert(virt_line, { ref_line:sub(index, part[1] - 1), 'MiniDiffOverContext' }) end
    table.insert(virt_line, { ref_line:sub(part[1], part[2]), 'MiniDiffOverChange' })
    index = part[2] + 1
  end
  if index <= ref_line:len() then table.insert(virt_line, { ref_line:sub(index), 'MiniDiffOverContext' }) end
  table.insert(virt_line, { H.overlay_suffix, 'MiniDiffOverContext' })
  local ext_opts = { virt_lines = { virt_line }, virt_lines_above = true, priority = priority + 1 }
  table.insert(target, { l_num = cur_l_num, data = { col = 0, opts = ext_opts } })

  -- Show changed parts in current line with separate extmarks
  for i = 1, #cur_parts do
    local part = cur_parts[i]
    local o = { end_row = cur_l_num - 1, end_col = part[2], hl_group = 'MiniDiffOverChange', priority = priority + 1 }
    table.insert(target, { l_num = cur_l_num, data = { col = part[1] - 1, opts = o } })
  end
end

H.append_overlay_delete = function(target, hunk, ref_lines, priority)
  local deleted_lines = {}
  for i = hunk.ref_start, hunk.ref_start + hunk.ref_count - 1 do
    table.insert(deleted_lines, { { ref_lines[i], 'MiniDiffOverDelete' }, { H.overlay_suffix, 'MiniDiffOverDelete' } })
  end
  local l_num, show_above = math.max(hunk.cur_start, 1), hunk.cur_start == 0
  -- NOTE: virtual lines above line 1 need manual scroll (like with `<C-b>`)
  -- See https://github.com/neovim/neovim/issues/16166
  local ext_opts = { virt_lines = deleted_lines, virt_lines_above = show_above, priority = priority - 1 }
  table.insert(target, { l_num = l_num, data = { col = 0, opts = ext_opts } })
end

H.compute_worddiff_changed_parts = function(ref_line, cur_line)
  local diff = vim.diff(ref_line:gsub('(.)', '%1\n'), cur_line:gsub('(.)', '%1\n'), H.worddiff_opts)
  local ref_ranges, cur_ranges = {}, {}
  for i = 1, #diff do
    local d = diff[i]
    if d[2] > 0 then table.insert(ref_ranges, { d[1], d[1] + d[2] - 1 }) end
    if d[4] > 0 then table.insert(cur_ranges, { d[3], d[3] + d[4] - 1 }) end
  end
  return ref_ranges, cur_ranges
end

-- Hunks ----------------------------------------------------------------------
H.get_hunk_buf_range = function(hunk)
  -- "Change" and "Add" hunks have the range `[from, from + cur_count - 1]`
  if hunk.cur_count > 0 then return hunk.cur_start, hunk.cur_start + hunk.cur_count - 1 end
  -- "Delete" hunks have `cur_count = 0` yet its range is `[from, from]`
  -- `cur_start` can be 0 for 'delete' hunk, yet range should be real lines
  local from = math.max(hunk.cur_start, 1)
  return from, from
end

H.get_hunks_in_range = function(hunks, from, to)
  local res = {}
  for _, h in ipairs(hunks) do
    local h_from, h_to = H.get_hunk_buf_range(h)

    local left, right = math.max(from, h_from), math.min(to, h_to)
    if left <= right then
      -- If any `cur` hunk part is selected, its `ref` part is used fully
      local new_h = { ref_start = h.ref_start, ref_count = h.ref_count }

      -- It should be possible to work with only hunk part inside target range
      -- Also Treat "delete" hunks differently as they represent range differently
      -- and can have `cur_start=0`
      new_h.cur_start = h.cur_count == 0 and h.cur_start or left
      new_h.cur_count = h.cur_count == 0 and 0 or (right - left + 1)

      table.insert(res, new_h)
    end
  end
  return res
end

H.reset_hunks = function(buf_id, hunks)
  -- Preserve 'modified' buffer option
  local cur_modified = vim.bo[buf_id].modified

  -- Make sure that hunks are properly ordered. Looks like not needed right now
  -- (as output of `vim.diff` is already ordered), but there is no quarantee.
  hunks = vim.deepcopy(hunks)
  table.sort(hunks, function(a, b) return a.cur_start < b.cur_start end)

  local ref_lines = vim.split(H.cache[buf_id].ref_text, '\n')
  local offset = 0
  for _, h in ipairs(hunks) do
    -- Replace current hunk lines with corresponding reference
    local new_lines = vim.list_slice(ref_lines, h.ref_start, h.ref_start + h.ref_count - 1)

    -- Compute current offset from parts: result of previous replaces, "delete"
    -- hunk offset which starts below the `cur_start` line, zero-indexing.
    local cur_offset = offset + (h.cur_count == 0 and 1 or 0) - 1
    local from, to = h.cur_start + cur_offset, h.cur_start + h.cur_count + cur_offset
    vim.api.nvim_buf_set_lines(buf_id, from, to, false, new_lines)

    -- Keep track of current hunk lines shift as a result of previous replaces
    offset = offset + (h.ref_count - h.cur_count)
  end

  -- Restore 'modified' status
  if cur_modified then return end
  if vim.fn.filereadable(vim.api.nvim_buf_get_name(buf_id)) == 1 then
    -- NOTE: Use `:write` if possible to make more impactful changes
    vim.api.nvim_buf_call(buf_id, function() vim.cmd('write') end)
  else
    vim.bo[buf_id].modified = false
  end
end

H.get_contiguous_hunk_ranges = function(hunks)
  if #hunks == 0 then return {} end
  hunks = vim.deepcopy(hunks)
  table.sort(hunks, function(a, b) return a.cur_start < b.cur_start end)

  local h1_from, h1_to = H.get_hunk_buf_range(hunks[1])
  local res = { { from = h1_from, to = h1_to } }
  for i = 2, #hunks do
    local h, cur_region = hunks[i], res[#res]
    local h_from, h_to = H.get_hunk_buf_range(h)
    if h_from <= cur_region.to + 1 then
      cur_region.to = math.max(cur_region.to, h_to)
    else
      table.insert(res, { from = h_from, to = h_to })
    end
  end
  return res
end

H.iterate_hunk_ranges = function(ranges, direction, line_start, n_times)
  local from, to, by, should_count = 1, #ranges, 1, function(r) return line_start < r.from end
  if direction == 'backward' then
    from, to, by, should_count = #ranges, 1, -1, function(r) return r.to < line_start end
  end

  local res, cur_n = nil, 0
  for i = from, to, by do
    local r = ranges[i]
    if should_count(r) then
      res, cur_n = r.from, cur_n + 1
    end
    if n_times <= cur_n then break end
  end

  return res
end

-- Git ------------------------------------------------------------------------
H.git_start_watching_index = function(buf_id, path)
  -- NOTE: Watching single 'index' file is not enough as staging by Git is done
  -- via "create fresh 'index.lock' file, apply modifications, change file name
  -- to 'index'". Hence watch the whole '.git' (first level) and react only if
  -- change was in 'index' file.
  local stdout = vim.loop.new_pipe()
  local args = { 'rev-parse', '--path-format=absolute', '--git-dir' }
  local spawn_opts = { args = args, cwd = vim.fn.fnamemodify(path, ':h'), stdio = { nil, stdout, nil } }

  local disable_buffer = vim.schedule_wrap(function() MiniDiff.disable(buf_id) end)

  local stdout_feed = {}
  local on_exit = function(exit_code)
    -- Watch index only if there was no error retrieving path to it
    if exit_code ~= 0 or stdout_feed[1] == nil then return disable_buffer() end

    -- Set up index watching
    local index_path = table.concat(stdout_feed, ''):gsub('\n+$', '')
    H.git_setup_index_watch(buf_id, index_path)

    -- Set reference text immediately
    H.git_set_ref_text(buf_id)
  end

  vim.loop.spawn('git', spawn_opts, on_exit)
  H.git_read_stream(stdout, stdout_feed)
end

H.git_setup_index_watch = function(buf_id, index_path)
  local buf_fs_event, timer = vim.loop.new_fs_event(), vim.loop.new_timer()
  local buf_git_set_ref_text = function() H.git_set_ref_text(buf_id) end

  local watch_index = function(_, filename, _)
    if filename ~= 'index' then return end
    -- Debounce to not overload during incremental staging (like in script)
    timer:stop()
    timer:start(10, 0, buf_git_set_ref_text)
  end
  buf_fs_event:start(index_path, { recursive = false }, watch_index)

  H.git_invalidate_cache(H.git_cache[buf_id])
  H.git_cache[buf_id] = { fs_event = buf_fs_event, timer = timer }
end

H.git_set_ref_text = vim.schedule_wrap(function(buf_id)
  local buf_set_ref_text = vim.schedule_wrap(function(text) pcall(MiniDiff.set_ref_text, buf_id, text) end)

  -- NOTE: Do not cache buffer's name to react to its possible rename
  local path = vim.api.nvim_buf_get_name(buf_id)
  if path == '' then return buf_set_ref_text({}) end
  local cwd, basename = vim.fn.fnamemodify(path, ':h'), vim.fn.fnamemodify(path, ':t')

  -- Set
  local stdout = vim.loop.new_pipe()
  local spawn_opts = { args = { 'show', ':0:./' .. basename }, cwd = cwd, stdio = { nil, stdout, nil } }

  local stdout_feed = {}
  local on_exit = function(exit_code)
    -- Unset reference text in case of any error. This results into not showing
    -- hunks at all. Possible reasons to do so:
    -- - 'Not in index' files (new, ignored, etc.).
    -- - 'Neither in index nor on disk' files (after checking out commit which
    --   does not yet have file created).
    -- - 'Relative can not be used outside working tree' (when opening file
    --   inside '.git' directory).
    if exit_code ~= 0 or stdout_feed[1] == nil then return buf_set_ref_text({}) end

    -- Set reference text
    local text = table.concat(stdout_feed, '')
    buf_set_ref_text(text)
  end

  vim.loop.spawn('git', spawn_opts, on_exit)
  H.git_read_stream(stdout, stdout_feed)
end)

H.git_get_path_data = function(path)
  local cwd, basename = vim.fn.fnamemodify(path, ':h'), vim.fn.fnamemodify(path, ':t')
  local stdout = vim.loop.new_pipe()
  local args = { 'ls-files', '--full-name', '--format=%(objectmode) %(path)', '--', basename }
  local spawn_opts = { args = args, cwd = cwd, stdio = { nil, stdout, nil } }

  local stdout_feed, res, did_exit = {}, { cwd = cwd }, false
  local on_exit = function(exit_code)
    did_exit = true
    if exit_code ~= 0 then return end
    -- Parse data about path
    local out = table.concat(stdout_feed, ''):gsub('\n+$', '')
    res.mode_bits, res.rel_path = string.match(out, '^(%d+) (.*)$')
  end

  vim.loop.spawn('git', spawn_opts, on_exit)
  H.git_read_stream(stdout, stdout_feed)
  vim.wait(1000, function() return did_exit end, 1)
  return res
end

H.git_format_patch = function(buf_id, hunks, path_data)
  local cur_lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  local ref_lines = vim.split(H.cache[buf_id].ref_text, '\n')

  local res = {
    string.format('diff --git a/%s b/%s', path_data.rel_path, path_data.rel_path),
    'index 000000..000000 ' .. path_data.mode_bits,
    '--- a/' .. path_data.rel_path,
    '+++ b/' .. path_data.rel_path,
  }

  -- Take into account changing target ref region as a result of previous hunks
  local offset = 0
  for _, h in ipairs(hunks) do
    -- "Add" hunks have reference line above target
    local start = h.ref_start + (h.ref_count == 0 and 1 or 0)

    table.insert(res, string.format('@@ -%d,%d +%d,%d @@', start, h.ref_count, start + offset, h.cur_count))
    for i = h.ref_start, h.ref_start + h.ref_count - 1 do
      table.insert(res, '-' .. ref_lines[i])
    end
    for i = h.cur_start, h.cur_start + h.cur_count - 1 do
      table.insert(res, '+' .. cur_lines[i])
    end
    offset = offset + (h.cur_count - h.ref_count)
  end

  return res
end

H.git_apply_patch = function(path_data, patch)
  local stdin = vim.loop.new_pipe()
  local args = { 'apply', '--whitespace=nowarn', '--cached', '--unidiff-zero', '-' }
  local spawn_opts = { args = args, cwd = path_data.cwd, stdio = { stdin, nil, nil } }
  local process = vim.loop.spawn('git', spawn_opts, function() end)

  -- Write patch, notify that writing is finished (shutdown), and close
  for _, l in ipairs(patch) do
    stdin:write(l)
    stdin:write('\n')
  end
  stdin:shutdown(function()
    stdin:close()
    process:close()
  end)
end

H.git_read_stream = function(stream, feed)
  local callback = function(err, data)
    if data ~= nil then return table.insert(feed, data) end
    if err then feed[1] = nil end
    stream:close()
  end
  stream:read_start(callback)
end

H.git_invalidate_cache = function(cache)
  if cache == nil then return end
  pcall(vim.loop.fs_event_stop, cache.fs_event)
  pcall(vim.loop.timer_stop, cache.timer)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.diff) %s', msg), 0) end

H.notify = function(msg, level_name) vim.notify('(mini.diff) ' .. msg, vim.log.levels[level_name]) end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.set_extmark = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

H.get_extmarks = function(...)
  local ok, res = pcall(vim.api.nvim_buf_get_extmarks, ...)
  if not ok then return {} end
  return res
end

H.clear_namespace = function(...) pcall(vim.api.nvim_buf_clear_namespace, ...) end

H.is_buf_text = function(buf_id)
  local n = vim.api.nvim_buf_call(buf_id, function() return vim.fn.byte2line(1024) end)
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, n, false)
  return table.concat(lines, ''):find('\0') == nil
end

return MiniDiff
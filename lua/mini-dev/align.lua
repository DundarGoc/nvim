-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- TODO:
-- Documentation:
-- - Setup similar to 'vim-easy-align'. It will use `j` modifier as `<CR>` in
--   'vim-easy-align'.
-- - Idea about ignoring rows with `row ~= xxx` filtering.
-- - Filtering by last equal sign usually can be done with `n == (N - 1)`
--   (because there is usually something to the right of it).
-- - It adds padding with spaces which might conflict with tab indentation.
-- - Visual blockwise selection works best with 'virtualedit' equal to "block"
--   or "all".
-- - Names of all main steps are synchronized with their main options.

-- Documentation ==============================================================
--- Align text.
---
--- Features:
--- - Alignment is done in three major steps:
---     - *Split* lines into parts based on Lua pattern or user-supplied rule.
---     - *Justify* parts to be same width among columns.
---     - *Merge* parts to be lines (possibly with custom delimiter).
---   Each major step can be preceded with other steps to achieve highly
---   customizable outcome. See `steps` value in |MiniAlign.config|.
--- - User can control alignment interactively by pressing customizable modifiers
---   (single characters representing how alignment steps should change).
--- - Customizable alignment steps (see |MiniAlign.align_strings()|):
---     - Justification (left, right, center).
---     - Filtering affected parts based on predicate function (like "align
---       only based on last pair").
---     - Middles to be ensured between parts (like "ensure parts are separated
---       by space").
---     - Pre and post hooks.
---
--- # Setup~
---
--- This module needs a setup with `require('mini.align').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniAlign`
--- which you can use for scripting or manually (with `:lua MiniAlign.*`).
---
--- See |MiniAlign.config| for available config settings.
---
--- You can override runtime config settings (like `config.modifiers`) locally
--- to buffer inside `vim.b.minialign_config` which should have same structure
--- as `MiniAlign.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons~
---
--- - 'junegunn/vim-easy-align':
---     - 'mini.align' doesn't distinguish splitted parts from one another.
---     - 'junegunn/vim-easy-align' implements special filtering by delimiter
---       number in a row. 'mini.align' has builtin filtering based on Lua code
---       supplied by user in modifier phase. See `MiniAlign.gen_step.filter`.
--- - 'godlygeek/tabular':
--- - `tommcdo/vim-lion`:
---
--- # Disabling~
---
--- To disable, set `g:minialign_disable` (globally) or `b:minialign_disable`
--- (for a buffer) to `v:true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag mini.align
---@tag MiniAlign

--- Glossary
---
--- - Split.
--- - Justufy.
--- - Merge.
--- - Parts.
--- - Step.
---@tag MiniAi-glossary

--- Algorithm design
---@tag MiniAlign-algorithm

---@alias __with_preview boolean|nil Whether to align with live preview.

-- Module definition ==========================================================
-- TODO: Make local before release
MiniAlign = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniAlign.config|.
---
---@usage `require('mini.align').setup({})` (replace `{}` with your `config` table)
MiniAlign.setup = function(config)
  -- Export module
  _G.MiniAlign = MiniAlign

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Options ~
MiniAlign.config = {
  mappings = {
    start = 'ga',
    start_with_preview = 'gA',
  },

  -- Each is a function that modifies ins input in place
  modifiers = {
    -- Main option modifiers
    ['s'] = function(_, opts)
      local input = H.user_input('Enter split Lua pattern')
      if input == nil then return end
      opts.split_pattern = input
    end,
    ['j'] = function(_, opts)
      -- stylua: ignore
      H.echo({
        { 'Select justify: ', 'ModeMsg' }, { 'l', 'Question' }, { 'eft, ' },
        { 'c', 'Question' }, { 'enter, ' }, { 'r', 'Question' }, { 'ight, ' },
        { 'n', 'Question' }, { 'one' }
      })
      local ok, char = pcall(vim.fn.getchar)
      if not ok or char == 27 then return end
      if type(char) == 'number' then char = vim.fn.nr2char(char) end

      local direction = ({ l = 'left', c = 'center', r = 'right', n = 'none' })[char]
      if direction == nil then return end
      opts.justify_side = direction
    end,
    ['m'] = function(_, opts)
      local input = H.user_input('Enter merge delimiter')
      if input == nil then return end
      opts.merge_delimiter = input
    end,

    -- Modifiers adding pre-steps
    ['f'] = function(steps, _)
      local input = H.user_input('Enter filter expression')
      local step = MiniAlign.gen_step.filter(input)
      if step == nil then return end
      table.insert(steps.pre_justify, step)
    end,
    ['i'] = function(steps, _) table.insert(steps.pre_split, MiniAlign.gen_step.ignore_split()) end,
    ['p'] = function(steps, _) table.insert(steps.pre_justify, MiniAlign.gen_step.pair()) end,
    ['t'] = function(steps, _) table.insert(steps.pre_justify, MiniAlign.gen_step.trim()) end,

    -- Delete last pre-step
    [vim.api.nvim_replace_termcodes('<BS>', true, true, true)] = function(steps, _)
      local has_pre = {}
      for _, pre in ipairs({ 'pre_split', 'pre_justify', 'pre_merge' }) do
        if #steps[pre] > 0 then table.insert(has_pre, pre) end
      end

      if #has_pre == 0 then return end

      if #has_pre == 1 then
        local pre = steps[has_pre[1]]
        table.remove(pre, #pre)
        return
      end

      --stylua: ignore
      H.echo({
        { 'Select pre-step to remove: ', 'ModeMsg' }, { 's', 'Question' }, { 'plit, ' },
        { 'j', 'Question' }, { 'ustify, ' }, { 'm', 'Question' }, { 'erge' },
      })
      local ok, char = pcall(vim.fn.getchar)
      if not ok or char == 27 then return end
      if type(char) == 'number' then char = vim.fn.nr2char(char) end

      if char == 's' then table.remove(steps.pre_split, #steps.pre_split) end
      if char == 'j' then table.remove(steps.pre_justify, #steps.pre_justify) end
      if char == 'm' then table.remove(steps.pre_merge, #steps.pre_merge) end
    end,

    -- Special configurations for common splits
    ['='] = function(steps, opts)
      opts.split_pattern = '%p*=+[<>~]*'
      table.insert(steps.pre_justify, MiniAlign.gen_step.trim())
      opts.merge_delimiter = ' '
    end,
    [','] = function(steps, opts)
      opts.split_pattern = ','
      table.insert(steps.pre_justify, MiniAlign.gen_step.trim())
      table.insert(steps.pre_justify, MiniAlign.gen_step.pair())
      opts.merge_delimiter = ' '
    end,
    [' '] = function(steps, opts)
      table.insert(
        steps.pre_split,
        MiniAlign.as_step('squash', function(strings)
          -- Replace all space sequences with single space (except indent)
          for i, s in ipairs(strings) do
            strings[i] = s:gsub('()(%s+)', function(n, space) return n == 1 and space or ' ' end)
          end
        end)
      )
      -- Don't use `' '` to respect indent
      opts.split_pattern = '%s+'
    end,
  },

  -- Options to be passed to every step
  options = {
    split_pattern = '',
    justify_side = 'left',
    merge_delimiter = '',
  },

  steps = {
    pre_split = {},
    split = nil,
    pre_justify = {},
    justify = nil,
    pre_merge = {},
    merge = nil,
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
---@param opts table|nil Options. To be passed to steps. Will be extended with
---   `options` of |MiniAlign.config|.
MiniAlign.align_strings = function(strings, opts, steps)
  -- Validate arguments
  if not H.is_array_of(strings, H.is_string) then
    H.error('First argument of `MiniAlign.align_strings()` should be array of strings.')
  end
  opts = H.normalize_opts(opts)
  steps = H.normalize_steps(steps, 'steps')

  -- Pre split
  for _, step in ipairs(steps.pre_split) do
    H.apply_step(step, strings, opts, 'pre_split')
  end

  -- Split
  local parts = H.apply_step(steps.split, strings, opts, 'split')
  if not H.is_parts(parts) then
    if H.can_be_parts(parts) then
      parts = MiniAlign.as_parts(parts)
    else
      H.error('Output of `split` step should be convertable to parts. See `:h MiniAlign.as_parts()`.')
    end
  end

  -- Pre justify
  for _, step in ipairs(steps.pre_justify) do
    H.apply_step(step, parts, opts, 'pre_justify')
  end

  -- Justify
  H.apply_step(steps.justify, parts, opts, 'justify')

  -- Pre merge
  for _, step in ipairs(steps.pre_merge) do
    H.apply_step(step, parts, opts, 'pre_merge')
  end

  -- Merge
  local new_strings = H.apply_step(steps.merge, parts, opts, 'merge')
  if not H.is_array_of(new_strings, H.is_string) then H.error('Output of `merge` step should be array of strings.') end
  return new_strings
end

--- Align current region with user-supplied steps
---
--- Mostly designed to be used inside mappings.
---
--- Will use |MiniAlign.align_strings()| and set the following options in `opts`:
--- - <justify_offsets>
--- - <region>
--- - <mode>
---
---@param mode string Selection mode. One of 'char', 'line', 'block'.
MiniAlign.align_user = function(mode)
  local modifiers = H.get_config().modifiers
  local with_preview = H.cache.with_preview
  local opts = H.cache.opts or H.normalize_opts()
  local steps = H.cache.steps or H.normalize_steps()

  local steps_are_from_cache = H.cache.steps ~= nil
  H.cache.region = nil

  -- Track if lines were actually set to properly undo during preview
  local lines_were_set = false

  -- Make initial process
  lines_were_set = H.process_current_region(lines_were_set, mode, opts, steps)

  -- Make early return:
  -- - If cache is present (enables dot-repeat).
  -- - If `split` is not default with no preview (no more information needed).
  if steps_are_from_cache or (not with_preview and opts.split_pattern ~= '') then return end

  -- Ask user to input modifier id until no more is needed
  local n_iter = 0
  while true do
    -- Get modifier from user
    local id = H.user_modifier(with_preview, H.make_status_msg_chunks(opts, steps))
    n_iter = n_iter + 1

    -- Stop in case user supplied inappropriate modifer id (abort)
    -- Also stop in case of too many iterations (guard from infinite cycle)
    if id == nil or n_iter > 1000 then
      if lines_were_set then H.undo() end
      if n_iter > 1000 then H.echo({ { 'Too many modifiers typed.', 'WarningMsg' } }, true) end
      break
    end

    -- Stop preview after `<CR>` (confirmation)
    if with_preview and id == '\r' then break end

    -- Apply modifier
    local mod = modifiers[id]
    if mod == nil then
      -- Use supplied identifier as split pattern
      opts.split_pattern = vim.pesc(id)
    else
      -- Modifier should change input `steps` table in place
      local ok, out = pcall(modifiers[id], steps, opts)
      if not ok then
        -- Force message to appear for 500ms because it might be overridden by
        -- helper status message
        local msg = string.format('Modifier %s should be properly callable. Reason: %s', vim.inspect(id), out)
        H.echo({ { msg, 'WarningMsg' } }, true)
        vim.cmd('redraw')
        vim.loop.sleep(500)
      end
    end

    -- Normalize steps and options while validating their correctness
    opts = H.normalize_opts(opts)
    steps = H.normalize_steps(steps, opts)

    -- Process region while tracking if lines were set at least once
    local lines_now_set = H.process_current_region(lines_were_set, mode, opts, steps)
    lines_were_set = lines_were_set or lines_now_set

    -- Stop in "no preview" mode right after `split` is defined
    if not with_preview and opts.split_pattern ~= '' then break end
  end
end

--- Perfrom action in Normal mode
---
--- Used in Normal mode mapping. No need to use it directly.
---
---@param with_preview __with_preview
MiniAlign.action_normal = function(with_preview)
  if H.is_disabled() then return end

  H.cache = { with_preview = with_preview }

  -- Set 'operatorfunc' which will be later called with appropriate marks set
  vim.cmd('set operatorfunc=v:lua.MiniAlign.align_user')
  return 'g@'
end

--- Perfrom action in Visual mode
---
--- Used in Visual mode mapping. No need to use it directly.
---
---@param with_preview __with_preview
MiniAlign.action_visual = function(with_preview)
  if H.is_disabled() then return end

  H.cache = { with_preview = with_preview }

  -- Perform action and exit Visual mode
  local mode = ({ ['v'] = 'char', ['V'] = 'line', ['\22'] = 'block' })[vim.fn.mode(1)]
  MiniAlign.align_user(mode)
  vim.cmd('normal! \27')
end

--- Convert 2d array to parts
MiniAlign.as_parts = function(arr2d)
  local ok, msg = H.can_be_parts(arr2d)
  if not ok then H.error('Input of `as_parts()` ' .. msg) end

  local parts = vim.deepcopy(arr2d)
  local methods = {}

  methods.apply = function(f)
    local res = {}
    for i, row in ipairs(parts) do
      res[i] = {}
      for j, s in ipairs(row) do
        res[i][j] = f(s, { row = i, col = j })
      end
    end
    return res
  end

  methods.apply_inplace = function(f)
    for i, row in ipairs(parts) do
      for j, s in ipairs(row) do
        local new_val = f(s, { row = i, col = j })
        if type(new_val) ~= 'string' then H.error('Input of `apply_inplace()` method should always return string.') end
        parts[i][j] = new_val
      end
    end
  end

  methods.get_dims = function()
    local n_cols = 0
    for _, row in ipairs(parts) do
      n_cols = math.max(n_cols, #row)
    end
    return { row = #parts, col = n_cols }
  end

  -- Group cells into single string based on boolean mask.
  -- Can be used for filtering separators and sticking separator to its part.
  methods.group = function(mask, direction)
    direction = direction or 'left'
    for i, row in ipairs(parts) do
      local group_tables = H.group_by_mask(row, mask[i], direction)
      parts[i] = vim.tbl_map(table.concat, group_tables)
    end
  end

  methods.pair = function(direction)
    direction = direction or 'left'

    local mask = {}
    for i, row in ipairs(parts) do
      mask[i] = {}
      for j, _ in ipairs(row) do
        -- Count from corresponding end
        local num = direction == 'left' and j or (#row - j + 1)
        mask[i][j] = num % 2 == 0
      end
    end

    parts.group(mask, direction)
  end

  -- NOTE: output might not be an array (some rows can not have input column)
  -- Use `vim.tbl_keys()` and `vim.tbl_values()`
  methods.slice_col = function(j)
    return vim.tbl_map(function(row) return row[j] end, parts)
  end

  methods.slice_row = function(i) return parts[i] or {} end

  methods.trim = function(direction, indent)
    direction = direction or 'both'
    indent = indent or 'keep'

    -- Verify arguments
    local trim_fun = H.trim_functions[direction]
    if not vim.is_callable(trim_fun) then
      local allowed = vim.tbl_map(vim.inspect, vim.tbl_keys(H.trim_functions))
      table.sort(allowed)
      H.error('`direction` should be one of ' .. table.concat(allowed, ', ') .. '.')
    end

    local indent_fun = H.indent_functions[indent]
    if not vim.is_callable(indent_fun) then
      local allowed = vim.tbl_map(vim.inspect, vim.tbl_keys(H.indent_functions))
      table.sort(allowed)
      H.error('`indent` should be one of ' .. table.concat(allowed, ', ') .. '.')
    end

    -- Compute indentation to restore later
    local row_indent = vim.tbl_map(function(row) return row[1]:match('^(%s*)') end, parts)
    row_indent = indent_fun(row_indent)

    -- Trim
    parts.apply_inplace(trim_fun)

    -- Restore indentation if it was removed
    if vim.tbl_contains({ 'both', 'left' }, direction) then
      for i, row in ipairs(parts) do
        row[1] = string.format('%s%s', row_indent[i], row[1])
      end
    end
  end

  return setmetatable(parts, { class = 'parts', __index = methods })
end

--- Create a step
MiniAlign.as_step = function(name, action)
  if type(name) ~= 'string' then H.error('Step name should be string.') end
  if not vim.is_callable(action) then H.error('Step action should be callable.') end
  return { name = name, action = action }
end

--- Generate common action steps
MiniAlign.gen_step = {}

MiniAlign.gen_step.default_split = function() return MiniAlign.as_step('split', H.default_action_split) end

--- Generate default `justify` step
---
--- Output uses following options (as part second argument, `opts` table):
--- - <justify_offsets> - array of numeric left offsets of rows. Used to adjust for
---   possible not equal indents, like in case of Visual charwise selection
---   when left edge is not on the first column. Default: array of zeros.
MiniAlign.gen_step.default_justify = function() return MiniAlign.as_step('justify', H.default_action_justify) end

MiniAlign.gen_step.default_merge = function() return MiniAlign.as_step('merge', H.default_action_merge) end

MiniAlign.gen_step.trim = function(direction, indent)
  return MiniAlign.as_step('trim', function(parts, _) parts.trim(direction, indent) end)
end

MiniAlign.gen_step.pair = function(direction)
  return MiniAlign.as_step('pair', function(parts, _) parts.pair(direction) end)
end

MiniAlign.gen_step.filter = function(expr)
  local action = H.make_filter_action(expr)
  if action == nil then return end
  return MiniAlign.as_step('filter', action)
end

MiniAlign.gen_step.ignore_split = function(patterns, exclude_comment)
  patterns = patterns or { '".-"' }
  if exclude_comment == nil then exclude_comment = true end

  -- Validate ingput
  if not H.is_array_of(patterns, H.is_string) then
    H.error('Argument `patterns` of `ignore_split()` should be array of strings.')
  end
  if type(exclude_comment) ~= 'boolean' then
    H.error('Argument `exclude_comment` of `ignore_split()` should be boolean.')
  end

  -- Make action which modifies `opts.split_exclude_patterns`
  local action = function(_, opts)
    local excl = opts.split_exclude_patterns or {}

    -- Add supplied patterns while avoiding duplication
    for _, patt in ipairs(patterns) do
      if not vim.tbl_contains(excl, patt) then table.insert(excl, patt) end
    end

    -- Possibly add current comment pattern while avoiding duplication
    if exclude_comment then
      -- In 'commentstring', `%s` denotes the comment content
      local comment_pattern = vim.pesc(vim.o.commentstring):gsub('%%%%s', '.-')
      -- Ignore to the end of the string if 'commentstring' is like "xxx%s"
      comment_pattern = comment_pattern:gsub('%.%-%s*$', '.*')
      if not vim.tbl_contains(excl, comment_pattern) then table.insert(excl, comment_pattern) end
    end

    opts.split_exclude_patterns = excl
  end

  return MiniAlign.as_step('ignore', action)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniAlign.config

-- Cache for various operations
H.cache = {}

-- Module's namespaces
H.ns_id = {
  -- Track user input
  input = vim.api.nvim_create_namespace('MiniAlignInput'),
}

-- Pad functions for supported justify directions
-- Allow to not add trailing whitespace
H.pad_functions = {
  left = function(x, n_spaces, no_trailing)
    if no_trailing or H.is_infinite(n_spaces) then return x end
    return string.format('%s%s', x, string.rep(' ', n_spaces))
  end,
  center = function(x, n_spaces, no_trailing)
    local n_left = math.floor(0.5 * n_spaces)
    return H.pad_functions.right(H.pad_functions.left(x, n_left, no_trailing), n_spaces - n_left, no_trailing)
  end,
  right = function(x, n_spaces, no_trailing)
    if (no_trailing and H.is_whitespace(x)) or H.is_infinite(n_spaces) then return x end
    return string.format('%s%s', string.rep(' ', n_spaces), x)
  end,
  none = function(x, _, _) return x end,
}

-- Trim functions
H.trim_functions = {
  both = function(x) return H.trim_functions.left(H.trim_functions.right(x)) end,
  left = function(x) return string.gsub(x, '^%s*', '') end,
  right = function(x) return string.gsub(x, '%s*$', '') end,
  none = function(x) return x end,
}

-- Indentation functions
H.indent_functions = {
  keep = function(indent_arr) return indent_arr end,
  max = function(indent_arr)
    local max_indent = indent_arr[1]
    for i = 2, #indent_arr do
      max_indent = (max_indent:len() < indent_arr[i]:len()) and indent_arr[i] or max_indent
    end
    return vim.tbl_map(function() return max_indent end, indent_arr)
  end,
  min = function(indent_arr)
    local min_indent = indent_arr[1]
    for i = 2, #indent_arr do
      min_indent = (indent_arr[i]:len() < min_indent:len()) and indent_arr[i] or min_indent
    end
    return vim.tbl_map(function() return min_indent end, indent_arr)
  end,
  remove = function(indent_arr)
    return vim.tbl_map(function() return '' end, indent_arr)
  end,
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    mappings = { config.mappings, 'table' },
    modifiers = { config.modifiers, H.is_valid_modifiers },
    steps = { config.steps, H.is_valid_steps },
    options = { config.options, 'table' },
  })

  vim.validate({
    ['mappings.start'] = { config.mappings.start, 'string' },
    ['mappings.start_with_preview'] = { config.mappings.start_with_preview, 'string' },
  })

  return config
end

H.apply_config = function(config)
  MiniAlign.config = config

  --stylua: ignore start
  H.map('n', config.mappings.start,              'v:lua.MiniAlign.action_normal(v:false)',      { expr = true, desc = 'Align' })
  H.map('x', config.mappings.start,              '<Cmd>lua MiniAlign.action_visual(false)<CR>', { desc = 'Align' })

  H.map('n', config.mappings.start_with_preview, 'v:lua.MiniAlign.action_normal(v:true)',       { expr = true, desc = 'Align with preview' })
  H.map('x', config.mappings.start_with_preview, '<Cmd>lua MiniAlign.action_visual(true)<CR>',  { desc = 'Align with preview' })
  --stylua: ignore end
end

H.is_disabled = function() return vim.g.minialign_disable == true or vim.b.minialign_disable == true end

H.get_config =
  function(config) return vim.tbl_deep_extend('force', MiniAlign.config, vim.b.minialign_config or {}, config or {}) end

-- Work with steps and options -------------------------------------------------
H.is_valid_steps = function(x, x_name)
  x_name = x_name or 'config.steps'

  if type(x) ~= 'table' then return false, string.format('`%s` should be table.', x_name) end

  -- Validators
  local is_steps_array = function(y) return H.is_array_of(y, H.is_step) end
  local steps_array_msg = 'should be array of steps (see `:h MiniAlign.as_step()`).'

  local is_maybe_step = function(y) return y == nil or H.is_step(y) end
  local step_msg = 'should be step (see `:h MiniAlign.as_step()`).'

  -- Actual checks
  if not is_steps_array(x.pre_split) then return false, H.msg_bad_steps(x_name, 'pre_split', steps_array_msg) end

  if not is_maybe_step(x.split) then return false, H.msg_bad_steps(x_name, 'split', step_msg) end

  if not is_steps_array(x.pre_justify) then return false, H.msg_bad_steps(x_name, 'pre_justify', steps_array_msg) end

  if not is_maybe_step(x.justify) then return false, H.msg_bad_steps(x_name, 'justify', step_msg) end

  if not is_steps_array(x.pre_merge) then return false, H.msg_bad_steps(x_name, 'pre_merge', steps_array_msg) end

  if not is_maybe_step(x.merge) then return false, H.msg_bad_steps(x_name, 'merge', step_msg) end

  return true
end

H.validate_steps = function(x, x_name)
  local is_valid, msg = H.is_valid_steps(x, x_name)
  if not is_valid then H.error(msg) end
end

H.normalize_steps = function(steps, steps_name)
  -- Infer all defaults from module config
  local res = vim.tbl_deep_extend('force', H.get_config().steps, steps or {})

  H.validate_steps(res, steps_name)

  -- Possibly fill in default main steps
  res.split = res.split or MiniAlign.gen_step.default_split()
  res.justify = res.justify or MiniAlign.gen_step.default_justify()
  res.merge = res.merge or MiniAlign.gen_step.default_merge()

  -- Deep copy to ensure that table values will not be affected (because if a
  -- table value is present only in one input, it is taken as is).
  return vim.deepcopy(res)
end

H.normalize_opts = function(opts)
  local res = vim.tbl_deep_extend('force', H.get_config().options, opts or {})
  return vim.deepcopy(res)
end

H.msg_bad_steps = function(steps_name, key, msg) return string.format('`%s.%s` %s', steps_name, key, msg) end

H.apply_step = function(step, arr, opts, step_container_name)
  local arr_name, predicate, suggest = 'parts', H.is_parts, ' See `:h MiniAlign.as_parts()`.'
  if not H.is_parts(arr) then
    arr_name = 'strings'
    predicate = function(x) return H.is_array_of(x, H.is_string) end
    suggest = ''
  end

  local res = step.action(arr, opts)

  if not predicate(arr) then
    --stylua: ignore
    local msg = string.format(
      'Step `%s` of `%s` should preserve structure of `%s`.%s',
      step.name, step_container_name, arr_name, suggest
    )
    H.error(msg)
  end

  return res
end

-- Work with default actions ---------------------------------------------------
H.default_action_split = function(string_array, opts)
  -- Prepare options
  local pattern = opts.split_pattern
  if not (H.is_string(pattern) or H.is_array_of(pattern, H.is_string)) then
    H.error('Option `split_pattern` should be string or array of strings.')
  end
  if type(pattern) == 'string' then pattern = { pattern } end

  local exclude_patterns = opts.split_exclude_patterns or {}
  if not H.is_array_of(exclude_patterns, H.is_string) then
    H.error('Option `split_exclude_patterns` should be array of strings.')
  end

  local capture_exclude_regions = vim.tbl_map(function(x)
    local patt = x
    patt = x:sub(1, 1) == '^' and ('^()' .. patt:sub(2)) or ('()' .. patt)
    patt = x:sub(-1, -1) == '$' and (patt:sub(1, -2) .. '()$') or (patt .. '()')
    return patt
  end, exclude_patterns)

  local forbidden_spans = {}
  local add_to_forbidden = function(l, r) table.insert(forbidden_spans, { l, r - 1 }) end
  local make_forbidden_spans = function(s)
    forbidden_spans = {}
    for _, capture_pat in ipairs(capture_exclude_regions) do
      s:gsub(capture_pat, add_to_forbidden)
    end
    return forbidden_spans
  end

  -- Make splits excluding matches inside forbidden regions
  local res = vim.tbl_map(
    function(s) return H.default_action_split_string(s, pattern, make_forbidden_spans) end,
    string_array
  )
  return MiniAlign.as_parts(res)
end

H.default_action_split_string = function(s, pattern_arr, make_forbidden_spans)
  -- Construct forbidden spans for string
  local forbidden_spans = make_forbidden_spans(s)

  -- Split by recycled `pattern_arr`
  local res = {}
  local n_total, n_latest_add, n_find = s:len(), 0, 0
  local n_pair = 1

  while true do
    local cur_split = H.slice_mod(pattern_arr, n_pair)
    local sep_left, sep_right = H.string_find(s, cur_split, n_find)

    if sep_left == nil then
      -- Avoid adding empty string because it does nothing but confuses "don't
      -- add trailspace" logic
      local rest = s:sub(n_latest_add, n_total)
      if rest ~= '' then table.insert(res, rest) end
      break
    end

    local is_good = #forbidden_spans == 0
      or not H.is_any_point_inside_any_span({ sep_left, sep_right }, forbidden_spans)
    if is_good then
      table.insert(res, s:sub(n_latest_add, sep_left - 1))
      table.insert(res, s:sub(sep_left, sep_right))
      n_latest_add = sep_right + 1
      n_pair = n_pair + 1
    end

    if (sep_right + 1) <= n_find then
      H.error(string.format('Pattern %s can not advance search.', vim.inspect(cur_split)))
    end
    n_find = sep_right + 1
  end

  return res
end

H.default_action_justify = function(parts, opts)
  -- Prepare options
  local side = opts.justify_side
  if not (H.is_justify_side(side) or H.is_array_of(side, H.is_justify_side)) then
    H.error([[Option `justify_side` should be one of 'left', 'center', 'right', 'none', or array of those.]])
  end
  if type(side) == 'string' then side = { side } end

  local offsets = opts.justify_offsets or H.tbl_repeat(0, #parts)

  -- Recycle `justify` array and precompute padding functions
  local dims = parts.get_dims()
  local pad_funs, side_arr = {}, {}
  for j = 1, dims.col do
    local s = H.slice_mod(side, j)
    side_arr[j] = s
    pad_funs[j] = H.pad_functions[s]
  end

  -- Compute cell width and maximum column widths (adjusting for offsets)
  local width_col = {}
  for j = 1, dims.col do
    width_col[j] = 0
  end

  local width = {}
  for i, row in ipairs(parts) do
    width[i] = {}
    for j, s in ipairs(row) do
      local w = vim.fn.strdisplaywidth(s)
      width[i][j] = w

      -- Compute offset
      local off = j == 1 and offsets[i] or 0

      -- Don't use last column in row to compute column width in case of left
      -- justification (it won't be padded so shouldn't contribute to column)
      if not (j == #row and side_arr[j] == 'left') then width_col[j] = math.max(off + w, width_col[j]) end
    end
  end

  -- Pad cells to have same width across columns (adjusting for offsets)
  for i, row in ipairs(parts) do
    for j, s in ipairs(row) do
      local off = j == 1 and offsets[i] or 0
      local n_space = width_col[j] - width[i][j] - off
      -- Don't add trailing whitespace for last column
      parts[i][j] = pad_funs[j](s, n_space, j == #row)
    end
  end
end

H.default_action_merge = function(parts, opts)
  -- Prepare options
  local delimiter = opts.merge_delimiter
  if not (H.is_string(delimiter) or H.is_array_of(delimiter, H.is_string)) then
    H.error('Option `merge_delimiter` should be string or array of strings.')
  end
  if type(delimiter) == 'string' then delimiter = { delimiter } end

  -- Precompute combination strings (recycle `merge` array)
  local dims = parts.get_dims()
  local delimiter_arr = {}
  for j = 1, dims.col - 1 do
    delimiter_arr[j] = H.slice_mod(delimiter, j)
  end

  -- Concat non-empty cells (empty cells at this point add only extra merge)
  return vim.tbl_map(function(row)
    local row_no_empty = vim.tbl_filter(function(s) return s ~= '' end, row)
    return H.concat_array(row_no_empty, delimiter_arr)
  end, parts)
end

-- Work with modifiers --------------------------------------------------------
H.is_valid_modifiers = function(x, x_name)
  x_name = x_name or 'config.modifiers'

  if type(x) ~= 'table' then return false, string.format('`%s` should be table.', x_name) end
  for k, v in pairs(x) do
    if not vim.is_callable(v) then
      return false, string.format('`%s[%s]` should be callable.', x_name, vim.inspect(k))
    end
  end

  return true
end

H.make_filter_action = function(expr)
  if expr == nil then return nil end
  if expr == '' then expr = 'true' end

  local is_loaded, f = pcall(function() return assert(loadstring('return ' .. expr)) end)
  if not (is_loaded and vim.is_callable(f)) then H.error(vim.inspect(expr) .. ' is not a valid filter expression.') end

  local predicate = function(data)
    local context = setmetatable(data, { __index = _G })
    debug.setfenv(f, context)
    return f()
  end

  return function(parts, _)
    local mask = {}
    local data = { ROW = #parts }
    for i, row in ipairs(parts) do
      data.row = i
      mask[i] = {}
      for j, s in ipairs(row) do
        data.col, data.COL = j, #row
        data.s = s

        -- Current and total number of pairs
        data.n = math.ceil(0.5 * j)
        data.N = math.ceil(0.5 * #row)

        mask[i][j] = predicate(data)
      end
    end

    parts.group(mask)
  end
end

-- Work with regions ----------------------------------------------------------
---@return boolean Whether some lines were actually set.
---@private
H.process_current_region = function(lines_were_set, mode, opts, steps)
  -- Cache current options and steps for dot-repeat
  H.cache.opts, H.cache.steps = opts, steps

  -- Undo previously set lines
  if lines_were_set then H.undo() end

  -- Get current region. NOTE: use cached value to ensure that the same region
  -- is processed during preview. Otherwise there might be problems with
  -- getting "current" regions in Normal mode as necessary marks (`[` and `]`)
  -- can be not valid.
  local region = H.cache.region or H.get_current_region()
  H.cache.region = region

  -- Enrich options
  opts.region = region
  opts.mode = mode
  opts.justify_offsets = H.tbl_repeat(0, region.to.line - region.from.line + 1)
  if mode == 'char' then
    -- Compute offset of first line for charwise selection
    local prefix = vim.fn.getline(region.from.line):sub(1, region.from.col - 1)
    opts.justify_offsets[1] = vim.fn.strdisplaywidth(prefix)
  end

  -- Actually process region
  local strings = H.region_get_text(region, mode)
  local strings_aligned = MiniAlign.align_strings(strings, opts, steps)
  H.region_set_text(region, mode, strings_aligned)

  -- Make sure that latest changes are shown
  vim.cmd('redraw')

  -- Confirm that lines were actually set
  return true
end

H.get_current_region = function()
  local from_expr, to_expr = "'[", "']"
  if H.is_visual_mode() then
    from_expr, to_expr = '.', 'v'
  end

  -- Add offset (*_pos[4]) to allow position go past end of line
  local from_pos = vim.fn.getpos(from_expr)
  local from = { line = from_pos[2], col = from_pos[3] + from_pos[4] }
  local to_pos = vim.fn.getpos(to_expr)
  local to = { line = to_pos[2], col = to_pos[3] + to_pos[4] }

  -- Ensure correct order
  if to.line < from.line or (to.line == from.line and to.col < from.col) then
    from, to = to, from
  end

  return { from = from, to = to }
end

H.region_get_text = function(region, mode)
  local from, to = region.from, region.to

  if mode == 'char' then
    local to_col_offset = vim.o.selection == 'exclusive' and 1 or 0
    return H.get_text(from.line - 1, from.col - 1, to.line - 1, to.col - to_col_offset)
  end

  if mode == 'line' then return H.get_lines(from.line - 1, to.line) end

  if mode == 'block' then
    -- Use virtual columns to respect multibyte characters
    local left_virtcol, right_virtcol = H.region_virtcols(region)
    local n_cols = right_virtcol - left_virtcol + 1

    return vim.tbl_map(
      -- `strcharpart()` returns empty string for out of bounds span, so no
      -- need for extra columns check
      function(l) return vim.fn.strcharpart(l, left_virtcol - 1, n_cols) end,
      H.get_lines(from.line - 1, to.line)
    )
  end
end

H.region_set_text = function(region, mode, text)
  local from, to = region.from, region.to

  if mode == 'char' then
    -- Ensure not going past last column (can happen with `$` in Visual mode)
    local to_line_n_cols = vim.fn.col({ to.line, '$' }) - 1
    local to_col = math.min(to.col, to_line_n_cols)
    local to_col_offset = vim.o.selection == 'exclusive' and 1 or 0
    H.set_text(from.line - 1, from.col - 1, to.line - 1, to_col - to_col_offset, text)
  end

  if mode == 'line' then H.set_lines(from.line - 1, to.line, text) end

  if mode == 'block' then
    if #text ~= (to.line - from.line + 1) then
      H.error('Number of replacement lines should fit the region in blockwise mode')
    end

    -- Use virtual columns to respect multibyte characters
    local left_virtcol, right_virtcol = H.region_virtcols(region)
    local lines = H.get_lines(from.line - 1, to.line)
    for i, l in ipairs(lines) do
      -- Use zero-based indexes
      local line_num = from.line + i - 2

      local n_virtcols = vim.fn.virtcol({ line_num + 1, '$' }) - 1
      -- Don't set text if all region is past end of line
      if left_virtcol <= n_virtcols then
        -- Make sure to not go past the line end
        local line_left_col, line_right_col = left_virtcol, math.min(right_virtcol, n_virtcols)

        -- Convert back to byte columns (columns are end-exclusive)
        local start_col, end_col = vim.fn.byteidx(l, line_left_col - 1), vim.fn.byteidx(l, line_right_col)
        start_col, end_col = math.max(start_col, 0), math.max(end_col, 0)

        -- vim.api.nvim_buf_set_text(0, line_num, start_col, line_num, end_col, { text[i] })
        H.set_text(line_num, start_col, line_num, end_col, { text[i] })
      end
    end
  end
end

H.region_virtcols = function(region)
  -- Account for multibyte characters and position past the line end
  local from_virtcol = H.pos_to_virtcol(region.from)
  local to_virtcol = H.pos_to_virtcol(region.to)

  local left_virtcol, right_virtcol = math.min(from_virtcol, to_virtcol), math.max(from_virtcol, to_virtcol)
  right_virtcol = right_virtcol - (vim.o.selection == 'exclusive' and 1 or 0)

  return left_virtcol, right_virtcol
end

H.pos_to_virtcol = function(pos)
  -- Account for position past line end
  local eol_col = vim.fn.col({ pos.line, '$' })
  if eol_col < pos.col then return vim.fn.virtcol({ pos.line, '$' }) + pos.col - eol_col end

  return vim.fn.virtcol({ pos.line, pos.col })
end

-- Work with user interaction --------------------------------------------------
H.user_modifier = function(with_preview, msg_chunks)
  -- Get from user single character modifier
  local needs_help_msg = true
  local delay = (H.cache.msg_shown or with_preview) and 0 or 1000
  vim.defer_fn(function()
    if not needs_help_msg then return end

    table.insert(msg_chunks, { ' Enter modifier' })
    H.echo(msg_chunks)
    H.cache.msg_shown = true
  end, delay)
  local ok, char = pcall(vim.fn.getchar)
  needs_help_msg = false

  -- Terminate if couldn't get input (like with <C-c>) or it is `<Esc>`
  if not ok or char == 27 then return nil end

  if type(char) == 'number' then char = vim.fn.nr2char(char) end
  return char
end

H.user_input = function(prompt, text)
  -- Register temporary keystroke listener to distinguish between cancel with
  -- `<Esc>` and immediate `<CR>`.
  local on_key = vim.on_key or vim.register_keystroke_callback
  local was_cancelled = false
  on_key(function(key)
    if key == '\27' then was_cancelled = true end
  end, H.ns_id.input)

  -- Ask for input
  local opts = { prompt = '(mini.align) ' .. prompt .. ': ', default = text or '' }
  vim.cmd('echohl Question')
  -- Use `pcall` to allow `<C-c>` to cancel user input
  local ok, res = pcall(vim.fn.input, opts)
  vim.cmd('echohl None | redraw')

  -- Stop key listening
  on_key(nil, H.ns_id.input)

  if not ok or was_cancelled then return end
  return res
end

H.make_status_msg_chunks = function(opts, steps)
  local single_to_string = function(pre_steps, opts_value)
    local steps_str = ''
    if #pre_steps > 0 then
      local pre_names = vim.tbl_map(function(x) return x.name end, pre_steps)
      steps_str = string.format('(%s) ', table.concat(pre_names, ', '))
    end
    return steps_str .. vim.inspect(opts_value)
  end

  return {
    { 'Split: ', 'ModeMsg' },
    { single_to_string(steps.pre_split, opts.split_pattern) },
    { ' | ', 'Question' },
    { 'Justify: ', 'ModeMsg' },
    { single_to_string(steps.pre_justify, opts.justify_side) },
    { ' | ', 'Question' },
    { 'Merge: ', 'ModeMsg' },
    { single_to_string(steps.pre_merge, opts.merge_delimiter) },
    { ' |', 'Question' },
  }
end

-- Predicates -----------------------------------------------------------------
H.is_array_of = function(x, predicate)
  if not vim.tbl_islist(x) then return false end
  for _, v in ipairs(x) do
    if not predicate(v) then return false end
  end
  return true
end

H.is_step = function(x) return type(x) == 'table' and type(x.name) == 'string' and vim.is_callable(x.action) end

H.is_string = function(v) return type(v) == 'string' end

H.is_justify_side = function(x) return x == 'left' or x == 'center' or x == 'right' or x == 'none' end

H.is_nonempty_region = function(x)
  if type(x) ~= 'table' then return false end
  local from_is_valid = type(x.from) == 'table' and type(x.from.line) == 'number' and type(x.from.col) == 'number'
  local to_is_valid = type(x.to) == 'table' and type(x.to.line) == 'number' and type(x.to.col) == 'number'
  return from_is_valid and to_is_valid
end

H.is_parts = function(x) return H.can_be_parts(x) and (getmetatable(x) or {}).class == 'parts' end

H.can_be_parts = function(x)
  if type(x) ~= 'table' then return false, 'should be table' end
  for i = 1, #x do
    if not H.is_array_of(x[i], H.is_string) then return false, 'values should be an array of strings' end
  end
  return true
end

H.is_infinite = function(x) return x == math.huge or x == -math.huge end

H.is_visual_mode = function() return vim.tbl_contains({ 'v', 'V', '\22' }, vim.fn.mode(1)) end

H.is_whitespace = function(x) return type(x) == 'string' and x:find('^%s*$') ~= nil end

-- Work with get/set text -----------------------------------------------------
--- Get text from current buffer
---
--- Needed for compatibility with Neovim<=0.6 which doesn't have
--- `vim.api.nvim_buf_get_text()`.
---@private
H.get_text = function(start_row, start_col, end_row, end_col)
  if vim.api.nvim_buf_get_text ~= nil then
    return vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
  end
  -- TODO: Remove this after Neovim<=0.6 support is dropped
  local text = H.get_lines(start_row, end_row + 1)
  if #text == 0 then return text end
  text[#text] = text[#text]:sub(1, end_col)
  text[1] = text[1]:sub(start_col + 1)
  return text
end

--- Get lines from current buffer
---
--- Added for completeness.
---@private
H.get_lines = function(start_row, end_row) return vim.api.nvim_buf_get_lines(0, start_row, end_row, true) end

--- Set text in current buffer without affecting marks
---@private
H.set_text = function(start_row, start_col, end_row, end_col, replacement)
  --stylua: ignore
  local cmd = string.format(
    'lockmarks lua vim.api.nvim_buf_set_text(0, %d, %d, %d, %d, %s)',
    start_row, start_col, end_row, end_col, vim.inspect(replacement)
  )
  vim.cmd(cmd)
end

--- Set lines in current buffer without affecting marks
---@private
H.set_lines = function(start_row, end_row, replacement)
  --stylua: ignore
  local cmd = string.format(
    'lockmarks lua vim.api.nvim_buf_set_lines(0, %d, %d, true, %s)',
    start_row, end_row, vim.inspect(replacement)
  )
  vim.cmd(cmd)
end

-- Utilities ------------------------------------------------------------------
H.echo = function(msg, add_to_history)
  -- Construct message chunks
  msg = type(msg) == 'string' and { { msg } } or msg
  table.insert(msg, 1, { '(mini.align) ', 'WarningMsg' })

  -- Avoid hit-enter-prompt
  local max_width = vim.o.columns * math.max(vim.o.cmdheight - 1, 0) + vim.v.echospace
  local chunks, tot_width = {}, 0
  for _, ch in ipairs(msg) do
    local new_ch = { vim.fn.strcharpart(ch[1], 0, max_width - tot_width), ch[2] }
    table.insert(chunks, new_ch)
    tot_width = tot_width + vim.fn.strdisplaywidth(new_ch[1])
    if tot_width >= max_width then break end
  end

  -- Echo. Force redraw to ensure that it is effective (`:h echo-redraw`)
  vim.cmd([[echo '' | redraw]])
  vim.api.nvim_echo(chunks, add_to_history, {})
end

H.error = function(msg) error(string.format('(mini.align) %s', msg), 0) end

H.map = function(mode, key, rhs, opts)
  if key == '' then return end

  opts = vim.tbl_deep_extend('force', { noremap = true, silent = true }, opts or {})

  -- Use mapping description only in Neovim>=0.7
  if vim.fn.has('nvim-0.7') == 0 then opts.desc = nil end

  vim.api.nvim_set_keymap(mode, key, rhs, opts)
end

H.slice_mod = function(x, i) return x[((i - 1) % #x) + 1] end

H.tbl_repeat = function(val, n)
  local res = {}
  for i = 1, n do
    res[i] = val
  end
  return res
end

H.group_by_mask = function(arr, mask, direction)
  local res, cur_group = {}, {}

  -- Construct actors based on direction
  local from, to, by = 1, #arr, 1
  local insert = function(t, v) table.insert(t, v) end
  if direction == 'right' then
    from, to, by = to, from, -1
    insert = function(t, v) table.insert(t, 1, v) end
  end

  -- Group
  for i = from, to, by do
    insert(cur_group, arr[i])
    if mask[i] or i == to then
      insert(res, cur_group)
      cur_group = {}
    end
  end

  return res
end

H.concat_array = function(target_arr, concat_arr)
  local ext_arr = {}
  for i = 1, #target_arr - 1 do
    table.insert(ext_arr, target_arr[i])
    table.insert(ext_arr, concat_arr[i])
  end
  table.insert(ext_arr, target_arr[#target_arr])
  return table.concat(ext_arr, '')
end

H.string_find = function(s, pattern, init)
  init = init or 1

  -- Match only start of full string if pattern says so.
  -- This is needed because `string.find()` doesn't do this.
  -- Example: `string.find('(aaa)', '^.*$', 4)` returns `4, 5`
  if pattern:sub(1, 1) == '^' and init > 1 then return nil end

  -- Treat `''` as if nothing is found (treats it as "reset split"). If not
  -- altered, results in infinite loop.
  if pattern == '' then return nil end

  return string.find(s, pattern, init)
end

H.is_any_point_inside_any_span = function(points, spans)
  for _, point in ipairs(points) do
    for _, span in ipairs(spans) do
      if span[1] <= point and point <= span[2] then return true end
    end
  end
  return false
end

H.undo = function()
  if H.is_visual_mode() then
    -- Can't use `u` in Visual mode because it makes all selection lowercase
    local cur_mode = vim.fn.mode(1)
    vim.cmd('silent! normal! \27')

    -- Undo
    vim.cmd('silent! lockmarks undo')

    -- Manually restore selection. There are issues with using restoring marks
    -- via `gv` (couldn't figure out how to reliably preserve visual mode).
    -- As this is called only if lines were set, region is cached.
    local region = H.cache.region
    vim.api.nvim_win_set_cursor(0, { region.from.line, region.from.col - 1 })
    vim.cmd('silent! normal!' .. cur_mode)
    vim.api.nvim_win_set_cursor(0, { region.to.line, region.to.col - 1 })
  else
    vim.cmd('silent! lockmarks normal! u')
  end
end

return MiniAlign

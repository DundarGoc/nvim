-- TODO:
--
-- Code:
--
-- Docs:
-- - Document official way to remap in Normal (operator and line) and Visual modes.
--
-- - Exchange:
--     - Works with most cases of intersecting regions, but not officially
--       supported.
--
-- - Replace:
--     - `[count]` in `grr` affects number of pastes.
--     - Respects [count] (in Visual, at first and in dot-repeat).
--       In Normal mode should differentiate between two counts:
--       `[count1]gr[count2]{motion}` (`[count1]` is for pasting,
--       `[count2]` is for textobject/motion).
--
-- - Sort:
--     - Example of interactive delimiter.
--     - Line mapping is charwise. Hence:
--         - No `[count]` support.
--         - Different custom line mapping (`^csg_` and not `cs_`).
--
--
-- Tests:

--- *mini.operators* Text edit operators
--- *MiniOperators*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Operators (already mapped and as functions):
---     - Evaluate text and replace with its output.
---     - Exchange regions.
---     - Multiply (duplicate) text.
---     - Sort text.
---     - Replace text with register.
---
--- - Extra mappings are automatically created for current line and Visual mode.
--- - All operators are dot-repeatable.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.operators').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniOperators`
--- which you can use for scripting or manually (with `:lua MiniOperators.*`).
---
--- See |MiniOperators.config| for available config settings.
---
--- You can override runtime config settings (but not `config.mappings`) locally
--- to buffer inside `vim.b.minioperators_config` which should have same structure
--- as `MiniOperators.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'gbprod/substitute.nvim':
---     - Has "replace" and "exchange" variants, but not others from this module.
---     - Has "replace/substitute" over range functionality, while this module
---       does not by design (similar to |:s| functionality with relatively
---       high mental complexity).
---     - "Replace" highlights pasted text, while in this module it doesn't.
---     - "Exchange" doesn't work across buffers, while in this module it does.
---
--- - 'svermeulen/vim-subversive':
---     - Main inspiration for "replace" functionality, so they are mostly similar
---       for this operator.
---     - Has "replace/substitute" over range functionality, while this module
---       does not by design.
---
--- - 'tommcdo/vim-exchange':
---     - Main inspiration for "exchange" functionality, so they are mostly
---       similar for this operator.
---     - Doesn't work across buffers, while this module does.
---
--- - 'christoomey/vim-sort-motion':
---     - Uses |:sort| for linewise sorting, while this module uses consistent
---       sorting algorithm (by default, see |MiniOperators.default_sort_func()|).
---     - Sorting algorithm can't be customized, while this module allows that
---       (see `sort.func` in |MiniOperators.config|).
---     - For charwise region uses only commas as separators, while this module
---       can also separate by semicolon or whitespace (by default,
---       see |MiniOperators.default_sort_func()|).
---
--- # Highlight groups ~
---
--- * `MiniOperatorsExchangeFrom` - region to exchange.
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling ~
---
--- To disable main functionality, set `vim.g.minioperators_disable` (globally) or
--- `vim.b.minioperators_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type

-- Module definition ==========================================================
-- TODO: Make local before release
MiniOperators = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniOperators.config|.
---
---@usage `require('mini.operators').setup({})` (replace `{}` with your `config` table).
--- **Neds to have triggers configured**.
MiniOperators.setup = function(config)
  -- Export module
  _G.MiniOperators = MiniOperators

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Create default highlighting
  H.create_default_hl()
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Evaluate ~
---
--- # Exchange ~
---
--- # Multiply ~
---
--- Advantages of using "multiply" instead of "yank" + "paste":
--- - Doesn't modify any register, while separate steps need some register to
---   hold multiplied text.
--- - In most cases separate steps would be "yank" + "move cursor" + "paste",
---   while "multiply" makes it at once.
---
--- # Replace ~
---
--- Advantages of using "replace" instead of "visually select" + "paste with |v_P|":
--- - As operator it is dot-repeatable which has cumulative gain in case of
---   multiple replacing is needed.
--- - Can automatically reindent.
---
--- # Sort ~
MiniOperators.config = {
  evaluate = {
    prefix = 'g=',
    func = nil,
  },

  exchange = {
    prefix = 'gx',
    reindent_linewise = true,
  },

  multiply = {
    prefix = 'gm',
  },

  replace = {
    prefix = 'gr',
    reindent_linewise = true,
  },

  sort = {
    prefix = 'gs',
    func = nil,
  }
}
--minidoc_afterlines_end

MiniOperators.evaluate = function(mode)
  if H.is_disabled() or not vim.bo.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.evaluate'
    return 'g@'
  end

  local evaluate_func = H.get_config().evaluate.func or MiniOperators.default_evaluate_func
  local data = H.get_region_data(mode)
  data.reindent_linewise = true
  H.apply_content_func(evaluate_func, data)
end

MiniOperators.exchange = function(mode)
  if H.is_disabled() or not vim.bo.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.exchange'
    return 'g@'
  end

  -- Depending on present cache data, perform exchange step
  if not H.exchange_has_step_one() then
    -- Store data about first region
    H.cache.exchange.step_one = H.exchange_set_region_extmark(mode, true)

    -- Temporarily remap `<C-c>` to stop the exchange
    H.exchange_set_stop_mapping()
  else
    -- Store data about second region
    H.cache.exchange.step_two = H.exchange_set_region_extmark(mode, false)

    -- Do exchange
    H.exchange_do()

    -- Stop exchange
    H.exchange_stop()
  end
end

MiniOperators.multiply = function(mode)
  if H.is_disabled() or not vim.bo.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.multiply'
    H.cache.multiply = { count = vim.v.count1 }

    -- Reset count to allow two counts: first for paste, second for textobject
    return vim.api.nvim_replace_termcodes('<Cmd>echon ""<CR>g@', true, true, true)
  end

  local count = mode == 'visual' and vim.v.count1 or H.cache.multiply.count
  local data = H.get_region_data(mode)
  local mark_from, mark_to, submode = data.mark_from, data.mark_to, data.submode

  H.with_temp_context({ marks = { '<', '>', '[', ']' }, registers = { 'x' } }, function()
    -- Yank to temporary "x" register
    local yank_keys = string.format('`%s%s`%s"xy', mark_from, submode, mark_to)
    H.cmd_normal(yank_keys, { cancel_redo = vim.o.cpoptions:find('y') ~= nil })

    -- Adjust cursor for a proper paste
    local ref_coords = H.multiply_get_ref_coords(mark_from, mark_to, submode)
    vim.api.nvim_win_set_cursor(0, ref_coords)

    -- Paste after textobject from temporary register
    H.cmd_normal(count .. '"xp', { lockmarks = false })

    -- Adjust cursor to be at start of pasted text. Not in linewise mode as it
    -- already is at first non-blank, while this moves to first column.
    if submode ~= 'V' then vim.cmd('normal! `[') end
  end)
end

MiniOperators.replace = function(mode)
  if H.is_disabled() or not vim.bo.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.replace'
    H.cache.replace = { count = vim.v.count1, register = vim.v.register }

    -- Reset count to allow two counts: first for paste, second for textobject
    return vim.api.nvim_replace_termcodes('<Cmd>echon ""<CR>g@', true, true, true)
  end

  -- Do replace
  -- - Compute `count` and `register` prior getting region data because it
  --   invalidates them for active Visual mode
  local count = mode == 'visual' and vim.v.count1 or H.cache.replace.count
  local register = mode == 'visual' and vim.v.register or H.cache.replace.register
  local data = H.get_region_data(mode)
  data.count = count
  data.register = register
  data.reindent_linewise = H.get_config().replace.reindent_linewise

  H.replace_do(data)

  return ''
end

MiniOperators.sort = function(mode)
  if H.is_disabled() or not vim.bo.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.sort'
    return 'g@'
  end

  local sort_func = H.get_config().sort.func or MiniOperators.default_sort_func
  H.apply_content_func(sort_func, H.get_region_data(mode))
end

-- Default sort function
--
-- - Pad pattern with `%s*` to include whitepsace into separator.
--   Example: line "b + a" with "%+" pattern will be sorted as " a+b " while with
--   "%s*%+%s*" pattern - "a + b".
MiniOperators.default_sort_func = function(content, opts)
  if not H.is_content(content) then H.error('`content` should be a content table.') end

  opts = vim.tbl_deep_extend('force', { compare_fun = nil, split_patterns = nil }, opts or {})

  local compare_fun = opts.compare_fun or function(a, b) return a < b end
  if not vim.is_callable(compare_fun) then H.error('`opts.compare_fun` should be callable.') end

  local split_patterns = opts.split_patterns or { '%s*,%s*', '%s*;%s*', '%s+' }
  if not vim.tbl_islist(split_patterns) then H.error('`opts.split_patterns` should be array.') end

  -- Prepare lines to sort
  local lines, submode = content.lines, content.submode

  if submode ~= 'v' then
    table.sort(lines, compare_fun)
    return lines
  end

  local parts, seps = H.sort_charwise_split(lines, split_patterns)
  table.sort(parts, compare_fun)
  return H.sort_charwise_unsplit(parts, seps)
end

-- Default evaluate function
--
-- - Blockwise is evaluated per line using only first lines of outputs.
MiniOperators.default_evaluate_func = function(content)
  if not H.is_content(content) then H.error('`content` should be a content table.') end

  local lines, submode = content.lines, content.submode

  -- In non-blockwise mode return the result of the last line
  if submode ~= H.submode_keys.block then return H.eval_lua_lines(lines) end

  -- In blockwise selection evaluate and return each line separately
  return vim.tbl_map(function(l) return H.eval_lua_lines({ l })[1] end, lines)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniOperators.config

-- Namespaces
H.ns_id = {
  exchange = vim.api.nvim_create_namespace('MiniOperatorsExchange'),
}

-- Cache for all operators
H.cache = {
  exchange = {},
  multiply = {},
  replace = {},
}

-- Submode keys for
H.submode_keys = {
  char = 'v',
  line = 'V',
  block = vim.api.nvim_replace_termcodes('<C-v>', true, true, true),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    evaluate = { config.evaluate, 'table' },
    exchange = { config.exchange, 'table' },
    multiply = { config.multiply, 'table' },
    replace = { config.replace, 'table' },
    sort = { config.sort, 'table' },
  })

  vim.validate({
    ['evaluate.prefix'] = { config.evaluate.prefix, 'string' },
    ['evaluate.func'] = { config.evaluate.func, 'function', true },

    ['exchange.prefix'] = { config.exchange.prefix, 'string' },
    ['exchange.reindent_linewise'] = { config.exchange.reindent_linewise, 'boolean' },

    ['multiply.prefix'] = { config.multiply.prefix, 'string' },

    ['replace.prefix'] = { config.replace.prefix, 'string' },
    ['replace.reindent_linewise'] = { config.replace.reindent_linewise, 'boolean' },

    ['sort.prefix'] = { config.sort.prefix, 'string' },
    ['sort.func'] = { config.sort.func, 'function', true },
  })

  return config
end

H.apply_config = function(config)
  MiniOperators.config = config

  -- Make mappings
  local map_all = function(operator_name)
    -- Map only valid LHS
    local prefix = config[operator_name].prefix
    if type(prefix) ~= 'string' or prefix == '' then return end

    local operator_desc = operator_name:sub(1, 1):upper() .. operator_name:sub(2)

    local expr_opts = { expr = true, replace_keycodes = false, desc = operator_desc .. ' operator' }
    H.map('n', prefix, string.format('v:lua.MiniOperators.%s()', operator_name), expr_opts)

    local line_lhs = prefix .. vim.fn.strcharpart(prefix, vim.fn.strchars(prefix) - 1, 1)
    local rhs = prefix .. '_'
    -- - Make `sort()` line mapping to be charwise
    if operator_name == 'sort' then rhs = '^' .. prefix .. 'g_' end
    H.map('n', line_lhs, rhs, { remap = true, desc = operator_desc .. ' line' })

    local visual_rhs = string.format([[<Cmd>lua MiniOperators.%s('visual')<CR>]], operator_name)
    H.map('x', prefix, visual_rhs, { desc = operator_desc .. ' selection' })
  end

  map_all('evaluate')
  map_all('exchange')
  map_all('multiply')
  map_all('replace')
  map_all('sort')
end

H.is_disabled = function() return vim.g.minioperators_disable == true or vim.b.minioperators_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniOperators.config, vim.b.minioperators_config or {}, config or {})
end

H.create_default_hl =
  function() vim.api.nvim_set_hl(0, 'MiniOperatorsExchangeFrom', { default = true, link = 'IncSearch' }) end

-- Evaluate -------------------------------------------------------------------
H.eval_lua_lines = function(lines)
  local n = #lines
  lines[n] = (lines[n]:find('^%s*return%s+') == nil and 'return ' or '') .. lines[n]

  local str_to_eval = table.concat(lines, '\n')

  -- Allow returning tuple with any value(s) being `nil`
  return H.inspect_objects(assert(loadstring(str_to_eval))())
end

H.inspect_objects = function(...)
  local objects = {}
  -- Not using `{...}` because it removes `nil` input
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end

  return vim.split(table.concat(objects, '\n'), '\n')
end

-- Exchange -------------------------------------------------------------------
H.exchange_do = function()
  local step_one, step_two = H.cache.exchange.step_one, H.cache.exchange.step_two

  -- Do nothing if regions are the same
  if H.exchange_is_same_steps(step_one, step_two) then return end

  -- Save temporary registers
  local reg_one, reg_two = vim.fn.getreginfo('1'), vim.fn.getreginfo('2')

  -- Put regions into registers. NOTE: do it before actual exchange to allow
  -- intersecting regions.
  local populating_register = function(step, register)
    return function()
      H.exchange_set_step_marks(step, { 'x', 'y' })

      local cmd = string.format('normal! `x"%sy%s`y', register, step.submode)
      vim.cmd(cmd)
    end
  end

  H.with_temp_context({ buf_id = step_one.buf_id, marks = { 'x', 'y' } }, populating_register(step_one, '1'))
  H.with_temp_context({ buf_id = step_two.buf_id, marks = { 'x', 'y' } }, populating_register(step_two, '2'))

  -- Sequentially replace
  local replacing = function(step, register)
    return function()
      H.exchange_set_step_marks(step, { 'x', 'y' })

      local replace_data = {
        count = 1,
        mark_from = 'x',
        mark_to = 'y',
        register = register,
        reindent_linewise = H.get_config().exchange.reindent_linewise,
        submode = step.submode,
      }
      H.replace_do(replace_data)
    end
  end

  H.with_temp_context({ buf_id = step_one.buf_id, marks = { 'x', 'y' } }, replacing(step_one, '2'))
  H.with_temp_context({ buf_id = step_two.buf_id, marks = { 'x', 'y' } }, replacing(step_two, '1'))

  -- Restore temporary registers
  vim.fn.setreg('1', reg_one)
  vim.fn.setreg('2', reg_two)
end

H.exchange_has_step_one = function()
  local step_one = H.cache.exchange.step_one
  if type(step_one) ~= 'table' then return false end

  if not vim.api.nvim_buf_is_valid(step_one.buf_id) then
    H.exchange_stop()
    return false
  end
  return true
end

H.exchange_set_region_extmark = function(mode, add_highlight)
  local ns_id = H.ns_id.exchange

  -- Compute regular marks for target region
  local region_data = H.get_region_data(mode)
  local submode = region_data.submode
  local markcoords_from, markcoords_to = H.get_mark(region_data.mark_from), H.get_mark(region_data.mark_to)

  -- Compute extmark's range for target region
  local extmark_from = { markcoords_from[1] - 1, markcoords_from[2] }
  local extmark_to = { markcoords_to[1] - 1, markcoords_to[2] + 1 }
  -- - Tweak columns for linewise marks
  if submode == 'V' then
    extmark_from[2] = 0
    extmark_to[2] = vim.fn.col({ extmark_to[1] + 1, '$' }) - 1
  end

  -- Set extmark to represent region. Add highlighting inside of it only if
  -- needed and not in blockwise submode (can't highlight that way).
  local buf_id = vim.api.nvim_get_current_buf()

  local extmark_hl_group
  if add_highlight and submode ~= H.submode_keys.block then extmark_hl_group = 'MiniOperatorsExchangeFrom' end

  local extmark_opts = {
    end_row = extmark_to[1],
    end_col = extmark_to[2],
    hl_group = extmark_hl_group,
    -- Using this gravity is better for handling empty lines in linewise mode
    end_right_gravity = mode == 'line',
  }
  local region_extmark_id = vim.api.nvim_buf_set_extmark(buf_id, ns_id, extmark_from[1], extmark_from[2], extmark_opts)

  -- - Possibly add highlighting for blockwise mode
  if add_highlight and extmark_hl_group == nil then
    -- Highlighting blockwise region needs full register type with width
    local opts = { regtype = H.exchange_get_blockwise_regtype(markcoords_from, markcoords_to) }
    vim.highlight.range(buf_id, ns_id, 'MiniOperatorsExchangeFrom', extmark_from, extmark_to, opts)
  end

  -- Return data to cache
  return { buf_id = buf_id, submode = submode, extmark_id = region_extmark_id }
end

H.exchange_get_region_extmark = function(step)
  return vim.api.nvim_buf_get_extmark_by_id(step.buf_id, H.ns_id.exchange, step.extmark_id, { details = true })
end

H.exchange_set_step_marks = function(step, mark_names)
  local extmark_details = H.exchange_get_region_extmark(step)

  H.set_mark(mark_names[1], { extmark_details[1] + 1, extmark_details[2] })
  H.set_mark(mark_names[2], { extmark_details[3].end_row + 1, extmark_details[3].end_col - 1 })
end

H.exchange_get_blockwise_regtype = function(mark_from, mark_to)
  local f = function()
    H.set_mark('x', mark_from)
    H.set_mark('y', mark_to)

    -- Move to `x` mark, yank blockwise to register `z` until `y` mark
    vim.cmd('normal! `x"zy\22`y')

    return vim.fn.getregtype('z')
  end

  return H.with_temp_context({ buf_id = 0, marks = { 'x', 'y' }, registers = { 'z' } }, f)
end

H.exchange_stop = function()
  H.exchange_del_stop_mapping()

  local cur, ns_id = H.cache.exchange, H.ns_id.exchange
  if cur.step_one ~= nil then pcall(vim.api.nvim_buf_clear_namespace, cur.step_one.buf_id, ns_id, 0, -1) end
  if cur.step_two ~= nil then pcall(vim.api.nvim_buf_clear_namespace, cur.step_two.buf_id, ns_id, 0, -1) end
  H.cache.exchange = {}
end

H.exchange_set_stop_mapping = function()
  local lhs = '<C-c>'
  H.cache.exchange.stop_restore_map_data = vim.fn.maparg(lhs, 'n', false, true)
  vim.keymap.set('n', lhs, H.exchange_stop, { desc = 'Stop exchange' })
end

H.exchange_del_stop_mapping = function()
  local map_data = H.cache.exchange.stop_restore_map_data
  if map_data == nil then return end

  -- Try restore previous mapping if it was set. NOTE: Neovim<0.8 doesn't have
  -- `mapset()`, so resort to deleting.
  if vim.tbl_count(map_data) > 0 and vim.fn.has('nvim-0.8') == 1 then
    vim.fn.mapset('n', false, map_data)
  else
    vim.keymap.del('n', map_data.lhs or '<C-c>')
  end
end

H.exchange_is_same_steps = function(step_one, step_two)
  if step_one.buf_id ~= step_two.buf_id or step_one.submode ~= step_two.submode then return false end
  -- Region's start and end should be the same
  local one, two = H.exchange_get_region_extmark(step_one), H.exchange_get_region_extmark(step_two)
  return one[1] == two[1] and one[2] == two[2] and one[3].end_row == two[3].end_row and one[3].end_col == two[3].end_col
end

-- Multiply -------------------------------------------------------------------
H.multiply_get_ref_coords = function(mark_from, mark_to, submode)
  local markcoords_from, markcoords_to = H.get_mark(mark_from), H.get_mark(mark_to)

  if submode ~= H.submode_keys.block then return markcoords_to end

  -- In blockwise selection go to top right corner (allowing for presence of
  -- multibyte characters)
  local row = math.min(markcoords_from[1], markcoords_to[1])
  if vim.fn.has('nvim-0.8') == 0 then
    -- Neovim<0.8 doesn't have `virtcol2col()`
    local col = math.max(markcoords_from[2], markcoords_to[2])
    return { row, col - 1 }
  end

  -- - "from"/"to" may not only be "top-left"/"bottom-right" but also
  --   "top-right" and "bottom-left"
  local virtcol_from = vim.fn.virtcol({ markcoords_from[1], markcoords_from[2] + 1 })
  local virtcol_to = vim.fn.virtcol({ markcoords_to[1], markcoords_to[2] + 1 })
  local virtcol = math.max(virtcol_from, virtcol_to)

  local col = vim.fn.virtcol2col(0, row, virtcol)

  return { row, col - 1 }
end
-- Replace --------------------------------------------------------------------
--- Delete region between two marks and paste from register
---
---@param data table Fields:
---   - <count> (optional) - Number of times to paste.
---   - <mark_from> - Name of "from" mark.
---   - <mark_to> - Name of "to" mark.
---   - <register> - Name of register from which to paste.
---   - <submode> - Region submode. One of 'v', 'V', '\22'.
---@private
H.replace_do = function(data)
  -- NOTE: Ideally, implementation would leverage "Visually select - press `P`"
  -- approach, but it has issues with dot-repeat. The `cancel_redo()` approach
  -- doesn't work probably because `P` implementation uses more than one
  -- dot-repeat overwrite.
  local register, submode = data.register, data.submode
  local mark_from, mark_to = data.mark_from, data.mark_to

  -- Do nothing with empty/unknown register
  local register_type = H.get_reg_type(register)
  if register_type == '' then H.error('Register ' .. vim.inspect(register) .. ' is empty or unknown.') end

  -- Determine if region is at edge which is needed for the correct paste key
  local from_line, _ = unpack(H.get_mark(mark_from))
  local to_line, to_col = unpack(H.get_mark(mark_to))

  local is_edge_line = submode == 'V' and to_line == vim.fn.line('$')
  local is_edge_col = submode ~= 'V' and to_col == (vim.fn.col({ to_line, '$' }) - 2)
  local is_edge = is_edge_line or is_edge_col

  local covers_linewise_all_buffer = is_edge_line and from_line == 1

  -- Compute current indent if needed
  local init_indent
  local should_reindent = data.reindent_linewise and data.submode == 'V' and vim.o.equalprg == ''
  if should_reindent then init_indent = H.get_region_indent(mark_from, mark_to) end

  -- Delete region to black whole register
  -- - Delete single character in blockwise submode with inclusive motion.
  --   See https://github.com/neovim/neovim/issues/24613
  local is_blockwise_single_cell = submode == H.submode_keys.block
    and vim.deep_equal(H.get_mark(mark_from), H.get_mark(mark_to))
  local forced_motion = is_blockwise_single_cell and 'v' or submode
  local delete_keys = string.format('`%s"_d%s`%s', mark_from, forced_motion, mark_to)
  H.cmd_normal(delete_keys)

  -- Paste register (ensuring same submode type as region)
  H.with_temp_context({ registers = { register } }, function()
    H.set_reg_type(register, submode)

    -- Possibly reindent
    if should_reindent then H.set_reg_indent(register, init_indent) end

    local paste_keys = string.format('%d"%s%s', data.count or 1, register, (is_edge and 'p' or 'P'))
    H.cmd_normal(paste_keys)
  end)

  -- Adjust cursor to be at start mark
  H.cmd_normal('`' .. mark_from, { cancel_redo = false })

  -- Adjust for extra empty line after pasting inside empty buffer
  if covers_linewise_all_buffer then vim.cmd('lockmarks lua vim.api.nvim_buf_set_lines(0, 0, 1, true, {})') end
end

-- Sort -----------------------------------------------------------------------
H.sort_charwise_split = function(lines, split_patterns)
  local lines_str = table.concat(lines, '\n')

  local pat
  for _, pattern in ipairs(split_patterns) do
    if lines_str:find(pattern) ~= nil then
      pat = pattern
      break
    end
  end

  if pat == nil then return lines end

  -- Split into parts and separators
  local parts, seps = {}, {}
  local init, n = 1, lines_str:len()
  while init < n do
    local sep_from, sep_to = string.find(lines_str, pat, init)
    if sep_from == nil then break end
    table.insert(parts, lines_str:sub(init, sep_from - 1))
    table.insert(seps, lines_str:sub(sep_from, sep_to))
    init = sep_to + 1
  end
  table.insert(parts, lines_str:sub(init, n))

  return parts, seps
end

H.sort_charwise_unsplit = function(parts, seps)
  local all = {}
  for i = 1, #parts do
    table.insert(all, parts[i])
    table.insert(all, seps[i] or '')
  end

  return vim.split(table.concat(all, ''), '\n')
end

-- General --------------------------------------------------------------------
H.apply_content_func = function(content_func, data)
  local mark_from, mark_to, submode = data.mark_from, data.mark_to, data.submode
  local reindent_linewise = data.reindent_linewise

  H.with_temp_context({ registers = { 'x' } }, function()
    -- Extract effective region content into "x" register.
    local yank_keys = string.format('`%s"xy%s`%s', mark_from, submode, mark_to)

    -- Make sure that `[` and `]` marks don't change after yank
    H.with_temp_context(
      { marks = { '[', ']' } },
      -- - Cancel one redo if `y` is dot-repeatable.
      function() H.cmd_normal(yank_keys, { cancel_redo = vim.o.cpoptions:find('y') ~= nil }) end
    )

    -- Apply content function to register content
    local reg_info = vim.fn.getreginfo('x')
    local content_init = { lines = reg_info.regcontents, submode = submode }
    reg_info.regcontents = content_func(content_init)
    vim.fn.setreg('x', reg_info)

    -- Replace region with new register content
    local replace_data = {
      count = 1,
      mark_from = mark_from,
      mark_to = mark_to,
      register = 'x',
      reindent_linewise = reindent_linewise,
      submode = submode,
    }
    H.replace_do(replace_data)
  end)
end

H.is_content = function(x) return type(x) == 'table' and vim.tbl_islist(x.lines) and type(x.submode) == 'string' end

-- Registers ------------------------------------------------------------------
H.get_reg_type = function(regname) return vim.fn.getregtype(regname):sub(1, 1) end

H.set_reg_type = function(regname, new_regtype)
  local reg_info = vim.fn.getreginfo(regname)
  local cur_regtype, n_lines = reg_info.regtype:sub(1, 1), #reg_info.regcontents

  -- Do nothing if already the same type
  if cur_regtype == new_regtype then return end

  reg_info.regtype = new_regtype
  vim.fn.setreg(regname, reg_info)
end

H.set_reg_indent = function(regname, new_indent)
  local reg_info = vim.fn.getreginfo(regname)
  reg_info.regcontents = H.update_indent(reg_info.regcontents, new_indent)
  vim.fn.setreg(regname, reg_info)
end

-- Marks ----------------------------------------------------------------------
H.get_region_data = function(mode)
  local submode = H.get_submode(mode)
  local selection_is_visual = mode == 'visual'

  -- Make sure that visual selection marks are relevant
  if selection_is_visual and H.is_visual_mode() then vim.cmd('normal! \27') end

  local mark_from = selection_is_visual and '<' or '['
  local mark_to = selection_is_visual and '>' or ']'

  return { submode = submode, mark_from = mark_from, mark_to = mark_to }
end

H.get_region_indent = function(mark_from, mark_to)
  local l_from, l_to = H.get_mark(mark_from)[1], H.get_mark(mark_to)[1]
  local lines = vim.api.nvim_buf_get_lines(0, l_from - 1, l_to, true)
  return H.compute_indent(lines)
end

H.get_mark = function(mark_name) return vim.api.nvim_buf_get_mark(0, mark_name) end

H.set_mark = function(mark_name, mark_data) vim.api.nvim_buf_set_mark(0, mark_name, mark_data[1], mark_data[2], {}) end

-- Indent ---------------------------------------------------------------------
H.compute_indent = function(lines)
  local res_indent, res_indent_width = nil, math.huge
  local blank_indent, blank_indent_width = nil, math.huge
  for _, l in ipairs(lines) do
    local cur_indent = l:match('^%s*')
    local cur_indent_width = cur_indent:len()
    local is_blank = cur_indent_width == l:len()
    if not is_blank and cur_indent_width < res_indent_width then
      res_indent, res_indent_width = cur_indent, cur_indent_width
    elseif is_blank and cur_indent_width < blank_indent_width then
      blank_indent, blank_indent_width = cur_indent, cur_indent_width
    end
  end

  return res_indent or blank_indent or ''
end

H.update_indent = function(lines, new_indent)
  -- Replace current indent with new indent without affecting blank lines
  local n_cur_indent = H.compute_indent(lines):len()
  return vim.tbl_map(function(l)
    if l:find('^%s*$') ~= nil then return l end
    return new_indent .. l:sub(n_cur_indent + 1)
  end, lines)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.operators) %s', msg), 0) end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.get_submode = function(mode)
  if mode == 'visual' then return H.is_visual_mode() and vim.fn.mode() or vim.fn.visualmode() end
  return H.submode_keys[mode]
end

H.is_visual_mode = function()
  local cur_mode = vim.fn.mode()
  return cur_mode == 'v' or cur_mode == 'V' or cur_mode == H.submode_keys.block
end

H.with_temp_context = function(context, f)
  local res
  vim.api.nvim_buf_call(context.buf_id or 0, function()
    -- Cache temporary data
    local marks_data = {}
    for _, mark_name in ipairs(context.marks or {}) do
      marks_data[mark_name] = H.get_mark(mark_name)
    end

    local reg_data = {}
    for _, reg_name in ipairs(context.registers or {}) do
      reg_data[reg_name] = vim.fn.getreginfo(reg_name)
    end

    -- Perform action
    res = f()

    -- Restore data
    for mark_name, data in pairs(marks_data) do
      H.set_mark(mark_name, data)
    end
    for reg_name, data in pairs(reg_data) do
      vim.fn.setreg(reg_name, data)
    end
  end)

  return res
end

-- A hack to restore previous dot-repeat action
H.cancel_redo = function() end;
(function()
  local has_ffi, ffi = pcall(require, 'ffi')
  if not has_ffi then return end
  local has_cancel_redo = pcall(ffi.cdef, 'void CancelRedo(void)')
  if not has_cancel_redo then return end
  H.cancel_redo = function() pcall(ffi.C.CancelRedo) end
end)()

H.cmd_normal = function(command, opts)
  opts = opts or {}
  local cancel_redo = opts.cancel_redo
  if cancel_redo == nil then cancel_redo = true end
  local lockmarks = opts.lockmarks
  if lockmarks == nil then lockmarks = true end

  vim.cmd('silent keepjumps ' .. (lockmarks and 'lockmarks ' or '') .. 'noautocmd normal! ' .. command)

  if cancel_redo then H.cancel_redo() end
end

return MiniOperators

local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('operators', config) end
local unload_module = function() child.mini_unload('operators') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
--stylua: ignore end

-- Custom validators
local validate_edit = function(lines_before, cursor_before, keys, lines_after, cursor_after)
  child.ensure_normal_mode()
  set_lines(lines_before)
  set_cursor(cursor_before[1], cursor_before[2])

  type_keys(keys)

  eq(get_lines(), lines_after)
  eq(get_cursor(), cursor_after)

  child.ensure_normal_mode()
end

local validate_edit1d = function(line_before, col_before, keys, line_after, col_after)
  validate_edit({ line_before }, { 1, col_before }, keys, { line_after }, { 1, col_after })
end

-- Output test set ============================================================
T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
    end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniOperators)'), 'table')

  -- Highlight groups
  local validate_hl_group = function(name, ref) expect.match(child.cmd_capture('hi ' .. name), ref) end

  validate_hl_group('MiniOperatorsExchangeFrom', 'links to IncSearch')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniOperators.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniOperators.config.' .. field), value) end

  expect_config('evaluate.prefix', 'g=')
  expect_config('evaluate.func', vim.NIL)

  expect_config('exchange.prefix', 'gx')
  expect_config('exchange.reindent_linewise', true)

  expect_config('replace.prefix', 'gr')
  expect_config('replace.reindent_linewise', true)

  expect_config('sort.prefix', 'gs')
  expect_config('sort.func', vim.NIL)
end

T['setup()']['respects `config` argument'] = function()
  reload_module({ exchange = { reindent_linewise = false } })
  eq(child.lua_get('MiniOperators.config.exchange.reindent_linewise'), false)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')

  expect_config_error({ evaluate = 'a' }, 'evaluate', 'table')
  expect_config_error({ evaluate = { prefix = 1 } }, 'evaluate.prefix', 'string')
  expect_config_error({ evaluate = { func = 'a' } }, 'evaluate.func', 'function')

  expect_config_error({ exchange = 'a' }, 'exchange', 'table')
  expect_config_error({ exchange = { prefix = 1 } }, 'exchange.prefix', 'string')
  expect_config_error({ exchange = { reindent_linewise = 'a' } }, 'exchange.reindent_linewise', 'boolean')

  expect_config_error({ replace = 'a' }, 'replace', 'table')
  expect_config_error({ replace = { prefix = 1 } }, 'replace.prefix', 'string')
  expect_config_error({ replace = { reindent_linewise = 'a' } }, 'replace.reindent_linewise', 'boolean')

  expect_config_error({ sort = 'a' }, 'sort', 'table')
  expect_config_error({ sort = { prefix = 1 } }, 'sort.prefix', 'string')
  expect_config_error({ sort = { func = 'a' } }, 'sort.func', 'function')
end

-- Integration tests ==========================================================
T['Exchange'] = new_set()

T['Exchange']['works charwise in Normal mode'] = function()
  local keys = { 'gxiw', 'w', 'gxiw' }
  validate_edit1d('a bb', 0, keys, 'bb a', 3)
  validate_edit1d('a bb ccc', 0, keys, 'bb a ccc', 3)
  validate_edit1d('a bb ccc', 3, keys, 'a ccc bb', 6)
  validate_edit1d('a bb ccc dddd', 3, keys, 'a ccc bb dddd', 6)

  -- With dot-repeat allowing multiple exchanges
  validate_edit1d('a bb', 0, { 'gxiw', 'w', '.' }, 'bb a', 3)
  validate_edit1d('a bb ccc dddd', 0, { 'gxiw', 'w', '.', 'w.w.' }, 'bb a dddd ccc', 10)

  -- Different order
  local keys_back = { 'gxiw', 'b', 'gxiw' }
  validate_edit1d('a bb', 2, keys_back, 'bb a', 0)
  validate_edit1d('a bb ccc', 2, keys_back, 'bb a ccc', 0)
  validate_edit1d('a bb ccc', 5, keys_back, 'a ccc bb', 2)
  validate_edit1d('a bb ccc dddd', 5, keys_back, 'a ccc bb dddd', 2)

  -- Over several lines
  set_lines({ 'aa bb', 'cc dd', 'ee ff', 'gg hh' })

  -- - Set marks
  set_cursor(2, 2)
  type_keys('ma')
  set_cursor(4, 2)
  type_keys('mb')

  -- - Validate
  set_cursor(1, 0)
  type_keys('gx`a', '2j', 'gx`b')
  eq(get_lines(), { 'ee ff', 'gg dd', 'aa bb', 'cc hh' })
  eq(get_cursor(), { 3, 0 })

  -- Single cell
  validate_edit1d('aa bb', 0, { 'gxl', 'w', 'gxl' }, 'ba ab', 3)
end

T['Exchange']['works linewise in Normal mode'] = function()
  local keys = { 'gx_', 'j', 'gx_' }
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, keys, { 'bb', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, keys, { 'bb', 'aa', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, keys, { 'aa', 'cc', 'bb' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cc', 'dd' }, { 2, 0 }, keys, { 'aa', 'cc', 'bb', 'dd' }, { 3, 0 })

  -- With dot-repeat allowing multiple exchanges
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'gx_', 'j', '.' }, { 'bb', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc', 'dd' }, { 1, 0 }, { 'gx_', 'j', '.', 'j.j.' }, { 'bb', 'aa', 'dd', 'cc' }, { 4, 0 })

  -- Different order
  local keys_back = { 'gx_', 'k', 'gx_' }
  validate_edit({ 'aa', 'bb' }, { 2, 0 }, keys_back, { 'bb', 'aa' }, { 1, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, keys_back, { 'bb', 'aa', 'cc' }, { 1, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 3, 0 }, keys_back, { 'aa', 'cc', 'bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc', 'dd' }, { 3, 0 }, keys_back, { 'aa', 'cc', 'bb', 'dd' }, { 2, 0 })

  -- Empty line
  validate_edit({ 'aa', '' }, { 1, 0 }, { 'gx_', 'G', 'gx_' }, { '', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', '', 'bb' }, { 1, 0 }, { 'gx_', 'G', 'gx_' }, { 'bb', '', 'aa' }, { 3, 0 })

  -- Over several lines
  validate_edit({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'gxip', 'G', 'gxip' }, { 'cc', '', 'aa', 'bb' }, { 3, 0 })

  -- Blank line(s)
  child.lua('MiniOperators.config.exchange.reindent_linewise = false')
  validate_edit({ 'aa', '  ' }, { 1, 0 }, { 'gx_', 'G', 'gx_' }, { '  ', 'aa' }, { 2, 0 })
  validate_edit({ ' ', '  ' }, { 1, 0 }, { 'gx_', 'G', 'gx_' }, { '  ', ' ' }, { 2, 0 })
end

T['Exchange']['works blockwise in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'io', function() vim.cmd('normal! \22') end)]])
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])
  child.lua([[vim.keymap.set('o', 'iE', function() vim.cmd('normal! \22jj') end)]])
  child.lua([[vim.keymap.set('o', 'il', function() vim.cmd('normal! \22jl') end)]])

  local keys = { 'gxie', 'w', 'gxil' }
  validate_edit({ 'a bb', 'c dd' }, { 1, 0 }, keys, { 'bb a', 'dd c' }, { 1, 3 })
  validate_edit({ 'a bb x', 'c dd y' }, { 1, 0 }, keys, { 'bb a x', 'dd c y' }, { 1, 3 })
  validate_edit({ 'a b xx', 'c d yy' }, { 1, 2 }, keys, { 'a xx b', 'c yy d' }, { 1, 5 })
  validate_edit({ 'a b xx u', 'c d yy v' }, { 1, 2 }, keys, { 'a xx b u', 'c yy d v' }, { 1, 5 })

  -- With dot-repeat allowing multiple exchanges
  validate_edit({ 'a bb', 'c dd' }, { 1, 0 }, { 'gxie', 'w', '.' }, { 'b ab', 'd cd' }, { 1, 2 })
  validate_edit({ 'a b x y', 'c d u v' }, { 1, 0 }, { 'gxie', 'w', '.', 'w.w.' }, { 'b a y x', 'd c v u' }, { 1, 6 })

  -- Different order
  local keys_back = { 'gxil', 'b', 'gxie' }
  validate_edit({ 'a bb', 'c dd' }, { 1, 2 }, keys_back, { 'bb a', 'dd c' }, { 1, 0 })
  validate_edit({ 'a bb x', 'c dd y' }, { 1, 2 }, keys_back, { 'bb a x', 'dd c y' }, { 1, 0 })
  validate_edit({ 'a b xx', 'c d yy' }, { 1, 4 }, keys_back, { 'a xx b', 'c yy d' }, { 1, 2 })
  validate_edit({ 'a b xx u', 'c d yy v' }, { 1, 4 }, keys_back, { 'a xx b u', 'c yy d v' }, { 1, 2 })

  -- Spanning empty/blank line
  validate_edit({ 'a b', '', 'c d' }, { 1, 0 }, { 'gxiE', 'w', 'gxiE' }, { 'b a', '  ', 'd c' }, { 1, 2 })
  validate_edit({ 'a b', '   ' }, { 1, 0 }, { 'gxie', 'w', 'gxie' }, { 'b a', '   ' }, { 1, 2 })

  -- Single cell
  validate_edit1d('aa bb', 0, { 'gxio', 'w', 'gxio' }, 'ba ab', 3)
end

T['Exchange']['works with mixed submodes in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])

  -- Charwise from - Linewise to
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'gxiw', 'j', 'gx_' }, { 'bb', 'aa', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'gx/b$<CR>', 'G', 'gx_' }, { 'ccb', 'aa', 'b' }, { 2, 0 })

  -- Charwise from - Blockwise to
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'gxiw', 'j', 'gxie' }, { 'b', 'd', 'aac', 'e' }, { 3, 0 })
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'gx/c<CR>', 'jl', 'gxie' }, { 'c', 'eaa', 'db' }, { 2, 1 })

  -- Linewise from - Charwise to
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { 'gx_', 'j', 'gxiw' }, { 'bb', 'aa bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc cc' }, { 1, 0 }, { 'gxj', '2j', 'gxiw' }, { 'cc', 'aa', 'bb cc' }, { 2, 0 })

  -- Linewise from - Blockwise to
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'gx_', 'j', 'gxie' }, { 'b', 'd', 'aac', 'e' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cd', 'ef' }, { 1, 0 }, { 'gxj', '2j', 'gxie' }, { 'c', 'e', 'aad', 'bbf' }, { 3, 0 })

  -- Blockwise from - Charwise to
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { '<C-v>gx', 'j', 'gxiw' }, { 'bba', 'a bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { '<C-v>jgx', 'jw', 'gxiw' }, { 'bba', 'b a', 'b' }, { 2, 2 })

  -- Blockwise from - Linewise to
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '<C-v>gx', 'j', 'gx_' }, { 'bba', 'a', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '<C-v>jgx', 'G', 'gx_' }, { 'cca', 'b', 'a', 'b' }, { 3, 0 })
end

T['Exchange']['works with `[count]` in Normal mode'] = function()
  validate_edit1d('aa bb cc dd ee ', 0, { '2gxaw', '2w', 'gx3aw' }, 'cc dd ee aa bb ', 9)

  -- With dot-repeat
  validate_edit1d('aa bb cc dd ', 0, { '2gxaw', '2w', '.', '0.2w.' }, 'aa bb cc dd ', 6)
end

T['Exchange']['works in Normal mode for line'] = function()
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'gxx', 'j', 'gxx' }, { 'bb', 'aa' }, { 2, 0 })

  -- With dot-repeat
  validate_edit({ 'aa', 'bb', 'cc', 'dd' }, { 1, 0 }, { 'gxx', 'j', '.', 'j.j.' }, { 'bb', 'aa', 'dd', 'cc' }, { 4, 0 })
end

T['Exchange']['works with `[count]` in Normal mode for line'] = function()
  validate_edit(
    { 'aa', 'bb', 'cc', 'dd', 'ee' },
    { 1, 0 },
    { '2gxx', '2j', '3gxx' },
    { 'cc', 'dd', 'ee', 'aa', 'bb' },
    { 4, 0 }
  )

  -- With dot-repeat
  validate_edit(
    { 'aa', 'bb', 'cc', 'dd' },
    { 1, 0 },
    { '2gxx', '2j', '.', 'gg.2j.' },
    { 'aa', 'bb', 'cc', 'dd' },
    { 3, 0 }
  )
end

T['Exchange']['works in Visual mode'] = function()
  -- Charwise from - Charwise to
  validate_edit1d('aa bb', 0, { 'viwgx', 'w', 'viwgx' }, 'bb aa', 3)
  validate_edit1d('aa bb', 3, { 'viwgx', '0', 'viwgx' }, 'bb aa', 0)

  -- Charwise from - Linewise to
  validate_edit({ 'aa x', 'bb' }, { 1, 0 }, { 'viwgx', 'j', 'Vgx' }, { 'bb x', 'aa' }, { 2, 0 })
  validate_edit({ 'aa x', 'bb' }, { 2, 0 }, { 'Vgx', 'k0', 'viwgx' }, { 'bb x', 'aa' }, { 1, 0 })

  -- Charwise from - Blockwise to
  validate_edit({ 'aa x', 'bb', 'cc' }, { 1, 0 }, { 'viwgx', 'j0', '<C-v>jgx' }, { 'b', 'c x', 'aab', 'c' }, { 3, 0 })
  validate_edit({ 'aa x', 'bb', 'cc' }, { 2, 0 }, { '<C-v>jgx', 'gg0', 'viwgx' }, { 'b', 'c x', 'aab', 'c' }, { 1, 0 })

  -- Linewise from - Charwise to
  validate_edit({ 'aa', 'bb x' }, { 1, 0 }, { 'Vgx', 'j0', 'viwgx' }, { 'bb', 'aa x' }, { 2, 0 })
  validate_edit({ 'aa', 'bb x' }, { 2, 0 }, { 'viwgx', 'k', 'Vgx' }, { 'bb', 'aa x' }, { 1, 0 })

  -- Linewise from - Linewise to
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'Vgx', 'j', 'Vgx' }, { 'bb', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', 'bb' }, { 2, 0 }, { 'Vgx', 'k', 'Vgx' }, { 'bb', 'aa' }, { 1, 0 })

  -- Linewise from - Blockwise to
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'Vgx', 'j0', '<C-v>jgx' }, { 'b', 'c', 'aab', 'c' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, { '<C-v>jgx', 'gg0', 'Vgx' }, { 'b', 'c', 'aab', 'c' }, { 1, 0 })

  -- Blockwise from - Charwise to
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '<C-v>jgx', 'G', 'viwgx' }, { 'cca', 'b', 'a', 'b' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 3, 0 }, { 'viwgx', 'gg0', '<C-v>jgx' }, { 'cca', 'b', 'a', 'b' }, { 1, 0 })

  -- Blockwise from - Linewise to
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '<C-v>jgx', 'G', 'Vgx' }, { 'cca', 'b', 'a', 'b' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 3, 0 }, { 'Vgx', 'gg0', '<C-v>jgx' }, { 'cca', 'b', 'a', 'b' }, { 1, 0 })

  -- Blockwise from - Blockwise to
  validate_edit({ 'ab', 'cd' }, { 1, 0 }, { '<C-v>jgx', 'l', '<C-v>jgx' }, { 'ba', 'dc' }, { 1, 1 })
  validate_edit({ 'ab', 'cd' }, { 1, 1 }, { '<C-v>jgx', 'h', '<C-v>jgx' }, { 'ba', 'dc' }, { 1, 0 })
end

T['Exchange']['works when regions are made in different modes'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])

  -- Normal from - Visual to
  validate_edit1d('aa bb', 0, { 'gxiw', 'w', 'viwgx' }, 'bb aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'gx_', 'j', 'Vgx' }, { 'bb', 'aa' }, { 2, 0 })
  validate_edit({ 'ab', 'cd' }, { 1, 0 }, { 'gxie', 'l', '<C-v>jgx' }, { 'ba', 'dc' }, { 1, 1 })

  -- Normal to - Visual from
  validate_edit1d('aa bb', 0, { 'viwgx', 'w', 'gxiw' }, 'bb aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'Vgx', 'j', 'gx_' }, { 'bb', 'aa' }, { 2, 0 })
  validate_edit({ 'ab', 'cd' }, { 1, 0 }, { '<C-v>jgx', 'l', 'gxie' }, { 'ba', 'dc' }, { 1, 1 })
end

T['Exchange']['correctly reindents linewise'] = function()
  -- Should exchange indents
  validate_edit({ '\taa', 'bb' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { '\tbb', 'aa' }, { 2, 0 })
  validate_edit({ '\taa', 'bb' }, { 2, 0 }, { 'gx_', 'k', 'gx_' }, { '\tbb', 'aa' }, { 1, 0 })
  validate_edit({ '\taa', '\t\tbb' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { '\tbb', '\t\taa' }, { 2, 0 })
  validate_edit({ '\taa', '\t\tbb' }, { 2, 0 }, { 'gx_', 'k', 'gx_' }, { '\tbb', '\t\taa' }, { 1, 0 })

  validate_edit({ '  aa', 'bb' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { '  bb', 'aa' }, { 2, 0 })
  validate_edit({ '  aa', 'bb' }, { 2, 0 }, { 'gx_', 'k', 'gx_' }, { '  bb', 'aa' }, { 1, 0 })
  validate_edit({ '  aa', '    bb' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { '  bb', '    aa' }, { 2, 0 })
  validate_edit({ '  aa', '    bb' }, { 2, 0 }, { 'gx_', 'k', 'gx_' }, { '  bb', '    aa' }, { 1, 0 })

  -- Should replace current region indent with new one
  validate_edit({ '\taa', '\t\tbb', 'cc' }, { 1, 0 }, { 'gxj', 'G', 'gx_' }, { '\tcc', 'aa', '\tbb' }, { 2, 0 })

  -- Should preserve tabs vs spaces
  validate_edit({ '\taa', '  bb' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { '\tbb', '  aa' }, { 2, 0 })
  validate_edit({ '\taa', '  bb' }, { 2, 0 }, { 'gx_', 'k', 'gx_' }, { '\tbb', '  aa' }, { 1, 0 })

  -- Should correctly work in presence of blank lines (compute indent and not
  -- reindent them)
  validate_edit(
    { '\t\taa', '', '\t', '\tcc' },
    { 1, 0 },
    { 'gx2j', 'G', 'gx_' },
    { '\t\tcc', '\taa', '', '\t' },
    { 2, 0 }
  )
end

T['Exchange']['respects `config.exchange.reindent_linewise`'] = function()
  child.lua('MiniOperators.config.exchange.reindent_linewise = false')
  validate_edit({ '\taa', 'bb' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { 'bb', '\taa' }, { 2, 0 })
end

T['Exchange']['highlights first step'] = new_set({ parametrize = { { 'charwise' }, { 'linewise' }, { 'blockwise' } } }, {
  test = function(mode)
    child.set_size(5, 12)
    local keys = ({ charwise = 'gxiw', linewise = 'gx_', blockwise = '<C-v>jlgx' })[mode]

    set_lines({ 'aa aa', 'bb' })
    set_cursor(1, 0)
    type_keys(keys)
    child.expect_screenshot()
  end,
})

T['Exchange']['can be canceled'] = function()
  child.set_size(5, 12)
  set_lines({ 'aa bb' })
  set_cursor(1, 0)

  type_keys('gxiw')
  child.expect_screenshot()

  -- Should reset highlighting and "exchange state"
  type_keys('<C-c>')
  child.expect_screenshot()

  type_keys('gxiw', 'w', 'gxiw')
  eq(get_lines(), { 'bb aa' })

  -- Should cleanup temporary mapping
  eq(child.fn.maparg('<C-c>'), '')
end

T['Exchange']['works for intersecting regions'] = function()
  -- Charwise
  validate_edit1d('abcd', 0, { 'gx3l', 'l', 'gx3l' }, 'bcdabc', 3)
  validate_edit1d('abcd', 0, { 'gx4l', 'l', 'gx2l' }, 'abcd', 0)
  validate_edit1d('abcd', 1, { 'gx2l', '0', 'gx4l' }, 'bc', 0)

  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'vjgx', 'vjgx' }, { 'bb', 'caa', 'bc' }, { 2, 1 })

  -- Linewise
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'Vjgx', 'Vjgx' }, { 'bb', 'cc', 'aa', 'bb' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cc', '' }, { 1, 0 }, { 'Vipgx', 'k', 'Vgx' }, { 'aa', 'bb', 'cc', '' }, { 1, 0 })
  validate_edit({ 'aa', 'bb', 'cc', '' }, { 2, 0 }, { 'Vgx', 'Vipgx' }, { 'bb', '' }, { 1, 0 })

  -- Blockwise
  validate_edit({ 'abc', 'def' }, { 1, 0 }, { '<C-v>jlgx', 'l', '<C-v>jlgx' }, { 'bcab', 'efde' }, { 1, 2 })
  validate_edit({ 'abc', 'def' }, { 1, 0 }, { '<C-v>jllgx', 'l', '<C-v>jgx' }, { 'abc', 'def' }, { 1, 0 })
  validate_edit({ 'abc', 'def' }, { 1, 1 }, { '<C-v>jgx', 'h', '<C-v>jllgx' }, { 'b', 'e' }, { 1, 0 })
end

T['Exchange']['works for regions in different buffers'] = function()
  local buf_1 = child.api.nvim_create_buf(true, false)
  local buf_2 = child.api.nvim_create_buf(true, false)

  child.api.nvim_buf_set_lines(buf_1, 0, -1, true, { 'aa', 'aa' })
  child.api.nvim_buf_set_lines(buf_2, 0, -1, true, { 'bb', 'bb' })

  child.api.nvim_set_current_buf(buf_1)
  type_keys('gx_')
  child.api.nvim_set_current_buf(buf_2)
  type_keys('gx_')

  eq(child.api.nvim_buf_get_lines(buf_1, 0, -1, true), { 'bb', 'aa' })
  eq(child.api.nvim_buf_get_lines(buf_2, 0, -1, true), { 'aa', 'bb' })
end

T['Exchange']['accounts for outdated first step buffer'] = function()
  local buf_1 = child.api.nvim_create_buf(true, false)
  local buf_2 = child.api.nvim_create_buf(true, false)

  child.api.nvim_buf_set_lines(buf_1, 0, -1, true, { 'aa', 'aa' })
  child.api.nvim_buf_set_lines(buf_2, 0, -1, true, { 'bb', 'cc' })

  child.api.nvim_set_current_buf(buf_1)
  type_keys('gx_')
  child.api.nvim_set_current_buf(buf_2)

  child.api.nvim_buf_delete(buf_1, { force = true })
  -- Should not error and restart exchange process
  type_keys('gx_')
  eq(get_lines(), { 'bb', 'cc' })

  type_keys('j', 'gx_')
  eq(get_lines(), { 'cc', 'bb' })
end

T['Exchange']['works for same region'] = function()
  -- Charwise
  validate_edit1d('aa bb cc', 4, { 'gxiw', 'gxiw' }, 'aa bb cc', 3)

  -- Linewise
  validate_edit1d('aa bb cc', 4, { 'gx_', 'gx_' }, 'aa bb cc', 0)

  -- Blockwise
  validate_edit({ 'ab', 'cd' }, { 1, 0 }, { '<C-v>jgx', '<C-v>jgx' }, { 'ab', 'cd' }, { 2, 0 })
end

T['Exchange']['does not have side effects'] = function()
  set_lines({ 'aa', 'bb', 'cc' })

  -- Marks `x`, `y` and registers `1`, `2`
  set_cursor(1, 0)
  type_keys('mx')
  type_keys('v"1y')

  set_cursor(1, 1)
  type_keys('my')
  type_keys('v"2y')

  -- Should properly manage stop mapping
  child.api.nvim_set_keymap('n', '<C-c>', ':echo 1<CR>', {})

  -- Do exchange
  set_cursor(2, 0)
  type_keys('gx_', 'j', 'gx_')

  -- Validate
  eq(child.api.nvim_buf_get_mark(0, 'x'), { 1, 0 })
  eq(child.api.nvim_buf_get_mark(0, 'y'), { 1, 1 })
  eq(child.fn.getreg('1'), 'a')
  eq(child.fn.getreg('2'), 'a')
  if child.fn.has('nvim-0.8') == 1 then eq(child.fn.maparg('<C-c>'), ':echo 1<CR>') end
end

T['Exchange']['respects `config.exchange.prefix`'] = function()
  child.api.nvim_del_keymap('n', 'gx')
  child.api.nvim_del_keymap('n', 'gxx')
  child.api.nvim_del_keymap('x', 'gx')

  load_module({ exchange = { prefix = 'cx' } })

  validate_edit1d('aa bb', 0, { 'cxiw', 'w', 'cxiw' }, 'bb aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'cxx', 'j', 'cxx' }, { 'bb', 'aa' }, { 2, 0 })
  validate_edit1d('aa bb', 0, { 'viwcx', 'w', 'viwcx' }, 'bb aa', 3)
end

T['Exchange']['allows custom mappings'] = function()
  child.api.nvim_del_keymap('n', 'gx')
  child.api.nvim_del_keymap('n', 'gxx')
  child.api.nvim_del_keymap('x', 'gx')

  load_module({ exchange = { prefix = '' } })

  child.lua([[
    vim.keymap.set('n', 'cx', 'v:lua.MiniOperators.exchange()', { expr = true, replace_keycodes = false, desc = 'Exchange' })
    vim.keymap.set('n', 'cxx', 'cx_', { remap = true, desc = 'Exchange line' })
    vim.keymap.set('x', 'cx', '<Cmd>lua MiniOperators.exchange("visual")<CR>', { desc = 'Exchange selection' })
  ]])

  validate_edit1d('aa bb', 0, { 'cxiw', 'w', 'cxiw' }, 'bb aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'cxx', 'j', 'cxx' }, { 'bb', 'aa' }, { 2, 0 })
  validate_edit1d('aa bb', 0, { 'viwcx', 'w', 'viwcx' }, 'bb aa', 3)
end

T['Exchange']['respects `selection=exclusive`'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])
  child.o.selection = 'exclusive'

  validate_edit1d('aaa bbb x', 0, { 'gxiw', 'w', 'gxiw' }, 'bbb aaa x', 4)
  validate_edit({ 'aa', 'bb', 'x' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { 'bb', 'aa', 'x' }, { 2, 0 })
  validate_edit({ 'a b c', 'a b c' }, { 1, 0 }, { 'gxie', 'w', 'gxie' }, { 'b a c', 'b a c' }, { 1, 2 })
end

T['Exchange']["respects 'nomodifiable'"] = function()
  set_lines({ 'aa bb' })
  set_cursor(1, 0)
  child.bo.modifiable = false
  type_keys('gxe', 'w', 'gx$')
  eq(get_lines(), { 'aa bb' })
  eq(get_cursor(), { 1, 4 })
end

T['Exchange']['respects `vim.{g,b}.minioperators_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minioperators_disable = true
    validate_edit1d('aa bb', 0, { 'gxiw' }, 'waa bb', 1)
  end,
})

T['Exchange']['respects `vim.b.minioperators_config`'] = function()
  child.b.minioperators_config = { exchange = { reindent_linewise = false } }

  validate_edit(
    { '\taa', '\tbb', 'cc', 'dd' },
    { 2, 0 },
    { 'gx_', 'G', 'gx_' },
    { '\taa', 'dd', 'cc', '\tbb' },
    { 4, 0 }
  )
end

T['Replace'] = new_set()

T['Replace']['works charwise in Normal mode'] = function()
  validate_edit1d('aa bb cc', 0, { 'yiw', 'w', 'graW' }, 'aa aacc', 3)

  -- With dot-repeat
  validate_edit1d('aa bb cc', 0, { 'yiw', 'w', 'graW', '.' }, 'aaaa', 2)

  -- Over several lines
  set_lines({ 'aa bb', 'cc dd' })

  -- - Set mark
  set_cursor(2, 2)
  type_keys('ma')

  -- - Validate
  set_cursor(1, 0)
  type_keys('yiw', 'w', 'gr`a')
  eq(get_lines(), { 'aa aa dd' })
  eq(get_cursor(), { 1, 3 })

  -- Single cell
  validate_edit1d('aa bb', 0, { 'yl', 'w', 'grl' }, 'aa ab', 3)
end

T['Replace']['works linewise in Normal mode'] = function()
  local lines = { 'aa', '', 'bb', 'cc', '', 'dd', 'ee' }
  validate_edit(lines, { 1, 0 }, { 'yy', '2j', 'grip' }, { 'aa', '', 'aa', '', 'dd', 'ee' }, { 3, 0 })

  -- - With dot-repeat
  validate_edit(lines, { 1, 0 }, { 'yy', '2j', 'grip', '2j', '.' }, { 'aa', '', 'aa', '', 'aa' }, { 5, 0 })
end

T['Replace']['works blockwise in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'io', function() vim.cmd('normal! \22') end)]])
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])

  validate_edit({ 'a b c', 'a b c' }, { 1, 0 }, { 'y<C-v>j', 'w', 'grie' }, { 'a a c', 'a a c' }, { 1, 2 })

  -- With dot-repeat
  validate_edit({ 'a b c', 'a b c' }, { 1, 0 }, { 'y<C-v>j', 'w', 'grie', 'w', '.' }, { 'a a a', 'a a a' }, { 1, 4 })

  -- Single cell
  validate_edit1d('aa bb', 0, { '<C-v>y', 'w', 'grio' }, 'aa ab', 3)
end

T['Replace']['works with mixed submodes in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])

  -- Charwise paste - Linewise region
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'yiw', 'j', 'gr_' }, { 'aa', 'aa', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'y/b$<CR>', 'j', 'gr_' }, { 'aa', 'aa', 'b', 'cc' }, { 2, 0 })

  -- Charwise paste - Blockwise region
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'yiw', 'j', 'grie' }, { 'aa', 'aac', 'e' }, { 2, 0 })
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'y/c<CR>', 'j', 'grie' }, { 'aa', 'aac', 'b e' }, { 2, 0 })

  -- Linewise paste - Charwise region
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { 'yy', 'j', 'griw' }, { 'aa', 'aa bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc cc' }, { 1, 0 }, { 'yj', '2j', 'griw' }, { 'aa', 'bb', 'aa', 'bb cc' }, { 3, 0 })

  -- Linewise paste - Blockwise region
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'yy', 'j', 'grie' }, { 'aa', 'aac', 'e' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cd', 'ef' }, { 1, 0 }, { 'yj', '2j', 'grie' }, { 'aa', 'bb', 'aad', 'bbf' }, { 3, 0 })

  -- Blockwise paste - Charwise region
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { '<C-v>y', 'j', 'griw' }, { 'aa', 'a bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { 'y<C-v>j', 'j', 'griw' }, { 'aa', 'a', 'b bb' }, { 2, 0 })

  -- Blockwise paste - Linewise region
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '<C-v>y', 'j', 'gr_' }, { 'aa', 'a', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'y<C-v>j', 'j', 'gr_' }, { 'aa', 'a', 'b', 'cc' }, { 2, 0 })
end

T['Replace']['works with two types of `[count]` in Normal mode'] = function()
  -- First `[count]` for paste with dot-repeat
  validate_edit1d('aa bb cc dd', 0, { 'yiw', 'w', '2graW' }, 'aa aaaacc dd', 3)
  validate_edit1d('aa bb cc dd', 0, { 'yiw', 'w', '2graW', 'w', '.' }, 'aa aaaaccaaaa', 9)

  -- Second `[count]` for textobject with dot-repeat
  validate_edit1d('aa bb cc dd ee', 0, { 'yiw', 'w', 'gr2aW' }, 'aa aadd ee', 3)
  validate_edit1d('aa bb cc dd ee', 0, { 'yiw', 'w', 'gr2aW', '.' }, 'aaaa', 2)

  -- Both `[count]`s with dot-repeat
  validate_edit1d('aa bb cc dd ee', 0, { 'yiw', 'w', '2gr2aW' }, 'aa aaaadd ee', 3)
  validate_edit1d('aa bb cc dd ee', 0, { 'yiw', 'w', '2gr2aW', '.' }, 'aaaaaa', 2)
end

T['Replace']['works in Normal mode for line'] = function()
  validate_edit({ 'aa', 'bb' }, { 1, 1 }, { 'yy', 'j', 'grr' }, { 'aa', 'aa' }, { 2, 0 })

  -- With dot-repeat
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 1 }, { 'yy', 'j', 'grr', 'j', '.' }, { 'aa', 'aa', 'aa' }, { 3, 0 })
end

T['Replace']['works with `[count]` in Normal mode for line'] = function()
  validate_edit({ 'aa', 'bb' }, { 1, 1 }, { 'yy', 'j', '2grr' }, { 'aa', 'aa', 'aa' }, { 2, 0 })

  -- With dot-repeat
  validate_edit(
    { 'aa', 'bb', 'cc' },
    { 1, 1 },
    { 'yy', 'j', '2grr', '2j', '.' },
    { 'aa', 'aa', 'aa', 'aa', 'aa' },
    { 4, 0 }
  )
end

local validate_replace_visual = function(lines_before, cursor_before, keys_without_replace)
  -- Get reference lines and cursor position assuming replacing in Visual mode
  -- should be the same as using `P`
  set_lines(lines_before)
  set_cursor(unpack(cursor_before))
  type_keys(keys_without_replace, 'P')

  local lines_after, cursor_after = get_lines(), get_cursor()

  -- Validate
  validate_edit(lines_before, cursor_before, { keys_without_replace, 'gr' }, lines_after, cursor_after)
end

T['Replace']['works in Visual mode'] = function()
  -- Charwise selection
  validate_replace_visual({ 'aa bb' }, { 1, 0 }, { 'yiw', 'w', 'viw' })
  validate_replace_visual({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'viw' })
  validate_replace_visual({ 'aa', 'bb' }, { 1, 0 }, { 'y<C-v>j', 'viw' })

  -- Linewise selection
  validate_replace_visual({ 'aa', 'bb' }, { 1, 0 }, { 'yiw', 'j', 'V' })
  validate_replace_visual({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'V' })
  validate_replace_visual({ 'aa', 'bb' }, { 1, 0 }, { 'y<C-v>j', 'j', 'V' })

  -- Blockwise selection
  validate_replace_visual({ 'a b', 'a b' }, { 1, 0 }, { 'yiw', 'w', '<C-v>j' })
  validate_replace_visual({ 'a b', 'a b' }, { 1, 0 }, { 'yy', 'w', '<C-v>j' })
  validate_replace_visual({ 'a b', 'a b' }, { 1, 0 }, { 'y<C-v>j', 'w', '<C-v>j' })
end

T['Replace']['works with `[count]` in Visual mode'] =
  function() validate_edit1d('aa bb', 0, { 'yiw', 'w', 'viw', '2gr' }, 'aa aaaa', 6) end

T['Replace']['correctly reindents linewise'] = function()
  -- Should use indent from text being replaced
  validate_edit({ '\taa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { '\taa', 'aa' }, { 2, 0 })
  validate_edit({ '\taa', 'bb' }, { 2, 0 }, { 'yy', 'k', 'gr_' }, { '\tbb', 'bb' }, { 1, 0 })
  validate_edit({ '\taa', '\t\tbb' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { '\taa', '\t\taa' }, { 2, 0 })
  validate_edit({ '\taa', '\t\tbb' }, { 2, 0 }, { 'yy', 'k', 'gr_' }, { '\tbb', '\t\tbb' }, { 1, 0 })

  validate_edit({ '  aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { '  aa', 'aa' }, { 2, 0 })
  validate_edit({ '  aa', 'bb' }, { 2, 0 }, { 'yy', 'k', 'gr_' }, { '  bb', 'bb' }, { 1, 0 })
  validate_edit({ '  aa', '    bb' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { '  aa', '    aa' }, { 2, 0 })
  validate_edit({ '  aa', '    bb' }, { 2, 0 }, { 'yy', 'k', 'gr_' }, { '  bb', '    bb' }, { 1, 0 })

  -- Should replace current region indent with new one
  validate_edit(
    { '\taa', '\t\tbb', 'cc' },
    { 1, 0 },
    { 'yj', 'G', 'gr_' },
    { '\taa', '\t\tbb', 'aa', '\tbb' },
    { 3, 0 }
  )

  -- Should preserve tabs vs spaces
  validate_edit({ '\taa', '  bb' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { '\taa', '  aa' }, { 2, 0 })
  validate_edit({ '\taa', '  bb' }, { 2, 0 }, { 'yy', 'k', 'gr_' }, { '\tbb', '  bb' }, { 1, 0 })

  -- Should correctly work in presence of blank lines (compute indent and not
  -- reindent them)
  validate_edit(
    { '\t\taa', '', '\t', '\tcc' },
    { 1, 0 },
    { 'y2j', 'G', 'gr_' },
    { '\t\taa', '', '\t', '\taa', '', '\t' },
    { 4, 0 }
  )
end

T['Replace']['respects `config.replace.reindent_linewise`'] = function()
  child.lua('MiniOperators.config.replace.reindent_linewise = false')
  validate_edit({ '\taa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { '\taa', '\taa' }, { 2, 0 })
end

T['Replace']['works with `[register]`'] = function()
  -- Normal mode
  validate_edit1d('aa bb cc', 0, { '"xyiw', 'w', 'yiw', 'w', '"xgriw' }, 'aa bb aa', 6)

  -- Visual mode
  validate_edit1d('aa bb cc', 0, { '"xyiw', 'w', 'yiw', 'w', 'viw', '"xgr' }, 'aa bb aa', 7)
end

T['Replace']['validatees `[register]` content'] = function()
  child.o.cmdheight = 10
  set_lines({ 'aa bb' })
  type_keys('yiw', 'w')

  expect.error(function() type_keys('"agriw') end, 'Register "a".*empty')
  expect.error(function() type_keys('"Agriw') end, 'Register "A".*unknown')
end

T['Replace']['works in edge cases'] = function()
  -- Start of line
  validate_edit1d('aa bb', 3, { 'yiw', '0', 'griw' }, 'bb bb', 0)

  -- End of line
  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'griw' }, 'aa aa', 3)

  -- First line
  validate_edit({ 'aa', 'bb' }, { 2, 0 }, { 'yy', 'k', 'grr' }, { 'bb', 'bb' }, { 1, 0 })

  -- Last line
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'yy', 'G', 'grr' }, { 'aa', 'bb', 'aa' }, { 3, 0 })
end

T['Replace']['can replace whole buffer'] = function()
  set_lines({ 'aa' })
  type_keys('yy')

  validate_edit({ 'bb', 'cc' }, { 1, 0 }, { 'grip' }, { 'aa' }, { 1, 0 })
end

T['Replace']['does not have side effects'] = function()
  -- Register type should not change
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'griw' }, { 'aa', 'aa' }, { 2, 0 })
  eq(child.fn.getregtype('"'), 'V')
end

T['Replace']['respects `config.replace.prefix`'] = function()
  child.api.nvim_del_keymap('n', 'gr')
  child.api.nvim_del_keymap('n', 'grr')
  child.api.nvim_del_keymap('x', 'gr')

  load_module({ replace = { prefix = 'cr' } })

  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'criw' }, 'aa aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'crr' }, { 'aa', 'aa' }, { 2, 0 })
  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'viw', 'cr' }, 'aa aa', 4)
end

T['Replace']['allows custom mappings'] = function()
  child.api.nvim_del_keymap('n', 'gr')
  child.api.nvim_del_keymap('n', 'grr')
  child.api.nvim_del_keymap('x', 'gr')

  load_module({ replace = { prefix = '' } })

  child.lua([[
    vim.keymap.set('n', 'cr', 'v:lua.MiniOperators.replace()', { expr = true, replace_keycodes = false, desc = 'Replace' })
    vim.keymap.set('n', 'crr', 'cr_', { remap = true, desc = 'Replace line' })
    vim.keymap.set('x', 'cr', '<Cmd>lua MiniOperators.replace("visual")<CR>', { desc = 'Replace selection' })
  ]])

  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'criw' }, 'aa aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'crr' }, { 'aa', 'aa' }, { 2, 0 })
  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'viw', 'cr' }, 'aa aa', 4)
end

T['Replace']['respects `selection=exclusive`'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])
  child.o.selection = 'exclusive'

  validate_edit1d('aaa bbb x', 0, { 'yiw', 'w', 'griw' }, 'aaa aaa x', 4)
  validate_edit({ 'aa', 'bb', 'x' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { 'aa', 'aa', 'x' }, { 2, 0 })
  validate_edit({ 'a b c', 'a b c' }, { 1, 0 }, { 'y<C-v>j', 'w', 'grie' }, { 'a a c', 'a a c' }, { 1, 2 })
end

T['Replace']["respects 'nomodifiable'"] = function()
  set_lines({ 'aa bb' })
  set_cursor(1, 0)
  child.bo.modifiable = false
  type_keys('yiw', 'w', 'gr$')
  eq(get_lines(), { 'aa bb' })
  eq(get_cursor(), { 1, 4 })
end

T['Replace']['respects `vim.{g,b}.minioperators_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minioperators_disable = true
    validate_edit1d('aa bb', 0, { 'yiw', 'w', 'griw' }, 'aa wbb', 4)
  end,
})

T['Replace']['respects `vim.b.minioperators_config`'] = function()
  child.b.minioperators_config = { replace = { reindent_linewise = false } }

  validate_edit(
    { '\taa', '\tbb', 'cc', 'dd' },
    { 2, 0 },
    { 'yy', 'G', 'gr_' },
    { '\taa', '\tbb', 'cc', '\tbb' },
    { 4, 0 }
  )
end

return T

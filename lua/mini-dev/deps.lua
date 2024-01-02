-- TODO:
--
-- Code:
--
-- - Do not forget about stashing changes before `checkout()`.
--
-- - Make sure that `checkout()` does not create many snapshots in 'rollback'
--   after every call to `create()` (as is the case for initial config setup).
--   Either don't create those files during `create()` at all or think about if
--   there is a need for 'rollback' directory.
--
-- Docs:
-- - Add examples of user commands in |MiniDeps-actions|.
--
-- Tests:

--- *mini.deps* Plugin manager
--- *MiniDeps*
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Manage plugins utilizing Git and built-in |packages| with these actions:
---     - Add / create.
---     - Update / fetch.
---     - Snapshot / checkout.
---     - Remove / clean.
---     All these actions are available both as Lua functions and user commands
---     (see |MiniDeps.setup()).
---
--- - Minimal yet flexible plugin specification:
---     - Mandatory plugin source.
---     - Name of target plugin directory.
---     - Checkout target: branch, commit, tag, etc.
---     - Dependencies to be set up prior to the target plugin.
---     - Hooks to call before/after plugin is created/changed/deleted.
---
--- - Automated show and save of fetch results to review.
---
--- - Automated save of current snapshot prior to checkout for easier rollback in
---   case something does not work as expected.
---
--- - Helpers to implement two-stage startup: |MiniDeps.now()| and |MiniDeps.later()|.
---   See |MiniDeps-examples| for how to implement basic lazy loading with them.
---
--- What it doesn't do:
---
--- - Manage plugins which are developed without Git. The suggested approach is
---   to create a separate package (see |packages|).
---
--- Sources with more details:
--- - |MiniDeps-examples|.
--- - |MiniDeps-plugin-specification|.
---
--- # Dependencies ~
---
--- For most of its functionality this plugin relies on `git` CLI tool.
--- See https://git-scm.com/ for more information about how to install it.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.deps').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniDeps`
--- which you can use for scripting or manually (with `:lua MiniDeps.*`).
---
--- See |MiniDeps.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minideps_config` which should have same structure as
--- `MiniDeps.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'folke/lazy.nvim':
---
--- - 'savq/paq-nvim':
---     - Main inspiration.
---
--- - 'lewis6991/pckr.nvim' :
---

--- # Directory structure ~
---
--- All module's data is stored in `config.path.package` directory inside
--- "pack/deps" subdirectory. It itself has the following subdirectories:
---
--- - `opt` with optional plugins (sourced after |:packadd|).
---   |MiniDeps.create()| uses this directory.
---
--- - `start` with non-optional plugins (sourced at start unconditionally).
---   All its subdirectories are recognized as plugins and can be updated,
---   removed, etc. To actually use it, move installed plugin from `opt` directory.
---
--- - `fetch` with history of the new data after |MiniDeps.fetch()|.
---   Each file contains a log of fetched changes for later review.
---
--- - `rollback` with history of automated snapshots. Each file is created
---   automatically before every run of |MiniDeps.checkout()|.
---   This can be used together with |MiniDeps.checkout()| to roll back after
---   unfortunate update.
---@tag MiniDeps-directory-structure

--- # Plugin specification ~
---
--- Each plugin dependency is managed based on its specification (a.k.a. "spec").
--- See |MiniDeps-examples| for how it is suggested to be used inside user config.
---
--- Mandatory:
--- - <source> `(string)` - field with URI of plugin source.
---   Can be anything allowed by `git clone`.
---   Note: as the most common case, URI of the format "user/repo" is transformed
---   into "https://github.com/user/repo". For relative path use "./user/repo".
---
--- Optional:
--- - <name> `(string|nil)` - directory basename of where to put plugin source.
---   It is put in "pack/deps/opt" subdirectory of `config.path.package`.
---   Default: basename of a <source>.
---
--- - <checkout> `(string|boolean|nil)` - Git checkout target to be used
---   in |MiniDeps.create()| and |MiniDeps.checkout| when called without arguments.
---   Can be anything supported by `git checkout` - branch, commit, tag, etc.
---   Can also be boolean:
---     - `true` to checkout to latest default branch (`main` / `master` / etc.)
---     - `false` to not perform `git checkout` at all.
---   Default: `true`.
---
--- - <depends> `(table|nil)` - array of strings with plugin sources. Each plugin
---   will be set up prior to the target.
---   Note: for more configuration of dependencies, set them up separately.
---   Default: `{}`.
---
--- - <hooks> `(table|nil)` - table with callable hooks to call on certain events.
---   Each hook is executed without arguments. Possible hook names:
---     - <pre_create>  - before creating plugin directory.
---     - <post_create> - after  creating plugin directory.
---     - <pre_change>  - before making change in plugin directory.
---     - <post_change> - after  making change in plugin directory.
---     - <pre_delete>  - before deleting plugin directory.
---     - <post_delete> - after  deleting plugin directory.
---   Default: empty table for no hooks.
---@tag MiniDeps-plugin-specification

--- # User commands ~
---                                                                       *:DepsAdd*
---                                                                    *:DepsCreate*
---                                                                    *:DepsUpdate*
---                                                                     *:DepsFetch*
---                                                                  *:DepsSnapshot*
---                                                                  *:DepsCheckout*
---                                                                    *:DepsRemove*
---                                                                     *:DepsClean*
---@tag MiniDeps-commands

--- # Usage examples ~
---
--- Make sure that `git` CLI tool is installed.
---
--- ## In config (functional style) ~
---
--- Recommended approach to organize config: >
---
---   -- Make sure that code from 'mini.deps' can be executed
---   vim.cmd('packadd mini.nvim') -- or 'packadd mini.deps' if using standalone
---
---   local deps = require('mini.deps')
---   local add, now, later = deps.add, deps.now, deps.later
---
---   -- Tweak setup to your liking
---   deps.setup()
---
---   -- Run code safely with `now()`
---   now(function() vim.cmd('colorscheme randomhue') end)
---   now(function() require('mini.statusline').setup() end)
---   now(function() require('mini.tabline').setup() end)
---
---   -- Delay code execution safely with `later()`
---   later(function()
---     require('mini.pick').setup()
---     vim.ui.select = MiniPick.ui_select
---   end)
---
---   -- Use external plugins
---   now(function()
---     -- If doesn't exist, will create from supplied URI
---     add('nvim-tree/nvim-web-devicons')
---     require('nvim-web-devicons').setup()
---   end)
---
---   later(function()
---     local is_010 = vim.fn.has('nvim-0.10') == 1
---     add(
---       'nvim-treesitter/nvim-treesitter',
---       {
---         checkout = is_010 and 'main' or 'master',
---         hooks = { post_change = function() vim.cmd('TSUpdate') end },
---       }
---     )
---
---     -- Run any code related to plugin's config
---     local parsers = { 'bash', 'python', 'r' }
---     if is_010 then
---       require('nvim-treesitter').setup({ ensure_install = parsers })
---     else
---       require('nvim-treesitter.configs').setup({ ensure_installed = parsers })
---     end
---   end)
--- <
--- ## Plugin management ~
---
--- `:DepsAdd user/repo` adds plugin from https://github.com/user/repo to the
--- current session (also creates it, if it is not present). See |:DepsAdd|.
--- To add plugin in every session, see previous section.
---
--- `:DepsCreate user/repo` creates plugin without adding it to current session.
---
--- `:DepsUpdate` updates all plugins with new changes from their sources.
--- See |:DepsUpdate|.
--- Alternatively: `:DepsFetch` followed by `:DepsCheckout`.
---
--- `:DepsSnapshot` creates snapshot file in default location (by default,
--- "deps-snapshot" file in config directory). See |:DepsSnapshot|.
---
--- `:DepsCheckout path/to/snapshot` makes present plugins have state from the
--- snapshot file. See |:DepsCheckout|.
---
--- `:DepsRemove repo` removes plugin with name "repo". Do not forget to
--- update config to not add same plugin in next session. See |:DepsRemove|.
--- Alternatively: `:DepsClean` removes all plugins which are not loaded in
--- current session. See |:DepsClean|.
--- Alternatively: manually delete plugin directory (if no hooks are set up).
---@tag MiniDeps-examples

---@alias __deps_source string Plugin's source. See |MiniDeps-plugin-specification|.
---@alias __deps_spec_opts table|nil Optional spec fields. See |MiniDeps-plugin-specification|.
---@alias __deps_names table Array of plugin names present in `config.path.package`.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
MiniDeps = {}
H = {}

--- Module setup
---
--- Calling this function creates all user commands described in |MiniDeps-actions|.
---
---@param config table|nil Module config table. See |MiniDeps.config|.
---
---@usage `require('mini.deps').setup({})` (replace `{}` with your `config` table).
MiniDeps.setup = function(config)
  -- Export module
  _G.MiniDeps = MiniDeps

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_user_commands(config)
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniDeps.config = {
  -- Parameters of CLI jobs
  job = {
    -- Number of parallel threads to use. Default: 80% of all available.
    n_threads = nil,

    -- Timeout (in ms) which each job should take on average
    timeout = 60000,
  },

  -- Paths describing where to store data
  path = {
    -- Directory for built-in package.
    -- All data is actually stored in the 'pack/deps' subdirectory.
    package = vim.fn.stdpath('data') .. '/site',

    -- Default file path for a snapshot
    snapshot = vim.fn.stdpath('config') .. '/deps-snapshot',
  },

  -- Whether to disable showing non-error feedback
  silent = false,
}
--minidoc_afterlines_end

--- Add plugin
---
--- - Call |MiniDeps.create()|.
--- - Register plugin's spec in current session.
--- - Make sure it can be used in current session (see |:packadd|).
---
---@param source __deps_source
---@param opts __deps_spec_opts
MiniDeps.add = function(source, opts)
  local spec = H.normalize_spec(source, opts)

  -- Decide whether to create plugin
  local _, is_present = H.get_plugin_path(spec.name)
  if not is_present then MiniDeps.create(source, opts) end

  -- Register plugin's spec in current session
  table.insert(H.session, spec)

  -- Add plugin to current session
  vim.cmd('packadd ' .. spec.name)
end

--- Create plugin
---
--- - If there is no directory present with `spec.name`:
---     - Execute `spec.hooks.pre_create`.
---     - Use `git clone` to clone plugin from its source URI into "pack/deps/opt".
---     - Execute `spec.hooks.post_create`.
---     - Run |MiniDeps.checkout()| with plugin's name.
---
---@param source __deps_source
---@param opts __deps_spec_opts
MiniDeps.create = function(source, opts)
  local spec = H.normalize_spec(source, opts)

  -- Do not override already existing plugin
  local path, is_present = H.get_plugin_path(spec.name)
  if is_present then return H.notify('Plugin ' .. vim.inspect(spec.name) .. ' already exists.', 'WARN') end

  -- Create
  H.maybe_exec(spec.hooks.pre_create)

  local command = H.git_commands.clone(spec.source, path)
  local exit_msg = 'Done creating ' .. vim.inspect(spec.name)
  local job = H.cli_new_job(command, vim.fn.getcwd(), exit_msg)

  H.notify('(0/1) Start creating ' .. vim.inspect(spec.name) .. '.')
  H.cli_run({ job })

  -- - Stop if there were errors
  if #job.err > 0 then
    local msg = string.format('There were errors during creation of %s.\n%s', table.concat(job.err))
    H.notify(msg, 'ERROR')
    return
  end

  H.maybe_exec(spec.hooks.post_create)

  -- Checkout. Don't use `MiniDeps.checkout` to skip rollback making and hooks.
  local target_arr = { { name = spec.name, checkout = spec.checkout, path = path } }
  H.infer_default_checkout(target_arr)
  H.do_checkout(target_arr)
end

--- Update plugins
---
--- - Use |MiniDeps.fetch()| to get new data from source URI.
--- - Use |MiniDeps.checkout()| to checkout according to plugin specification.
---   Note: if plugin is not added to current session, it is not checked out.
---
---@param names __deps_names
MiniDeps.update = function(names)
  -- TODO
end

--- Fetch new data of plugins
---
--- - Use `git fetch` to fetch data from source URI.
--- - Use `git log` to get newly fetched data and save output to the file in
---   fetch history.
--- - Create and show scratch buffer with the log.
---
--- Notes:
--- - This function is executed asynchronously.
--- - This does not affect actual plugin code. Run |MiniDeps.checkout()| for that.
---
---@param names __deps_names
MiniDeps.fetch = function(names)
  -- TODO
  -- Outline:
  -- - Get value of `FETCH_HEAD`.
  -- - Set `origin` to `source` from session spec.
  -- - `git fetch --all --write-fetch-head`.
  -- - Get log as `git log <prev_FETCH_HEAD>..FETCH_HEAD`.
end

--- Create snapshot file
---
--- - Get current commit of every plugin directory in `config.path.package`.
--- - Create a snapshot: table with plugin names as keys and commits as values.
--- - Write the table to `path` file in the form of a Lua code ready for |dofile()|.
---
---@param path string|nil A valid path on disk where to write snapshot file.
---   Default: `config.path.snapshot`.
MiniDeps.snapshot = function(path)
  -- TODO
end

--- Checkout plugins
---
--- - If table input, treat it as a map of checkout targets for plugin names.
---   Fields are plugin names and values are checkout targets as
---   in |MiniDeps-plugin-specification|.
---   Notes:
---   - Only present on disk plugins are checked out. That is, plugin names
---     which are not present on disk are ignored.
---
---   Example of checkout target: >
---     { plugin_1 = true, plugin_2 = false, plugin_3 = 'main' }
--- <
--- - If string input, treat as snapshot file path (as after |MiniDeps.snapshot()|).
---   Source the file expecting returned table and apply previous step.
---
--- - If no input, checkout all plugins added to current session
---   (with |MiniDeps.add()|) according to their specs.
---   See |MiniDeps.get_session()|.
---
---@param target table|string|nil A checkout target. Default: `nil`.
MiniDeps.checkout = function(target)
  -- Normalize to be an array
  local target_arr = H.normalize_checkout_target(target)

  -- Infer default checkout targets early to properly call `*_change` hooks
  H.infer_default_checkout(target_arr)
  target_arr = vim.tbl_filter(function(x) return type(x.checkout) == 'string' end, target_arr)

  if #target_arr == 0 then return end

  -- TODO: Create rollback snapshot

  -- TODO: Get and execute both hooks from current session and `target_arr`

  add_to_log('checkout target', target_arr)
  H.do_checkout(target_arr)

  -- TODO
end

--- Remove plugins
---
--- - If there is directory present with `spec.name`:
---     - Execute `spec.hooks.pre_delete`.
---     - Delete plugin directory.
---     - Execute `spec.hooks.post_delete`.
---
---@param names __deps_names
MiniDeps.remove = function(names)
  -- TODO
end

--- Clean plugins
---
--- - Delete plugin directories which are currently not present in 'runtimpath'.
MiniDeps.clean = function()
  local package_opt_path = H.get_package_path() .. '/pack/deps/opt'
  -- TODO
end

--- Get session data
MiniDeps.get_session = function()
  -- Normalize `H.session`. Prefere spec (entirely) which was added earlier.
  local session, present_names = {}, {}
  for _, spec in ipairs(H.session) do
    if not present_names[spec.name] then
      table.insert(session, spec)
      present_names[spec.name] = true
    end
  end
  H.session = session

  -- Return copy to not allow modification in place
  return vim.deepcopy(session)
end

MiniDeps.now = function(f)
  local ok, err = pcall(f)
  if not ok then table.insert(H.cache.exec_errors, err) end
  H.schedule_finish()
end

MiniDeps.later = function(f)
  table.insert(H.cache.later_callback_queue, f)
  H.schedule_finish()
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniDeps.config

-- Array of current session plugin specs. NOTE: Having it as array allows to
-- respect order in which plugins were added (at cost of later normalization).
H.session = {}

-- Various cache
H.cache = {
  -- Whether finish of `now()` or `later()` is already scheduled
  finish_is_scheduled = false,

  -- Callback queue for `later()`
  later_callback_queue = {},

  -- Errors during execution of `now()` or `later()`
  exec_errors = {},
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  vim.validate({
    job = { config.job, 'table' },
    path = { config.path, 'table' },
    silent = { config.silent, 'boolean' },
  })

  vim.validate({
    ['job.n_threads'] = { config.job.n_threads, 'number', true },
    ['job.timeout'] = { config.job.timeout, 'number' },
    ['path.package'] = { config.path.package, 'string' },
    ['path.snapshot'] = { config.path.snapshot, 'string' },
  })

  return config
end

H.apply_config = function(config)
  MiniDeps.config = config

  -- Add target package path to 'packpath'
  local pack_path = H.full_path(config.path.package)
  if not string.find(vim.o.packpath, vim.pesc(pack_path)) then vim.o.packpath = vim.o.packpath .. ',' .. pack_path end
end

H.create_user_commands = function(config)
  -- TODO
end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniDeps.config, vim.b.minideps_config or {}, config or {})
end

-- Git commands ---------------------------------------------------------------
H.git_commands = {
  clone = function(source, path)
    --stylua: ignore
    return {
      'git', 'clone',
      '--quiet', '--filter=blob:none',
      '--recurse-submodules', '--also-filter-submodules',
      '--origin', 'origin',
      source, path,
    }
  end,
  stash = {},
  checkout = function(target)
    if type(target) ~= 'string' then return {} end
    return { 'git', 'checkout', '--quiet', target }
  end,
  get_default_checkout = { 'git', 'rev-parse', '--abbrev-ref', 'origin/HEAD' },
  fetch = { 'git', 'fetch', '--quiet', '--recurse-submodules=yes', 'origin' },
  -- { 'git', 'log', '--format=%h - %ai - %an%n  %s%n', 'main~~..main' }, -- log after fetch
  -- { 'git', 'rev-parse', 'HEAD'}, -- snapshot
}

-- Plugin specification -------------------------------------------------------
H.normalize_spec = function(source, opts)
  local spec = {}

  if type(source) ~= 'string' then H.error('Plugin source should be string.') end
  -- Allow 'user/repo' as source
  if source:find('^[^/]+/[^/]+$') ~= nil then source = 'https://github.com/' .. source end
  spec.source = source

  opts = opts or {}
  if type(opts) ~= 'table' then H.error([[Plugin's optional spec should be table.]]) end

  spec.name = opts.name or vim.fn.fnamemodify(source, ':t')
  if type(spec.name) ~= 'string' then H.error('`name` in plugin spec should be string.') end

  spec.checkout = opts.checkout
  if spec.checkout == nil then spec.checkout = true end
  if not (type(spec.checkout) == 'string' or type(spec.checkout) == 'boolean') then
    H.error('`checkout` in plugin spec should be string or boolean.')
  end

  spec.hooks = opts.hooks or {}
  if type(spec.hooks) ~= 'table' then H.error('`hooks` in plugin spec should be table.') end
  local hook_names = { 'pre_create', 'post_create', 'pre_change', 'post_change', 'pre_delete', 'post_delete' }
  for _, hook_name in ipairs(hook_names) do
    if not (spec[hook_name] == nil or vim.is_callable(spec[hook_name])) then
      H.error('`hooks.' .. hook_name .. '` in plugin spec should be callable.')
    end
  end

  return spec
end

-- File system ----------------------------------------------------------------
H.get_plugin_path = function(name, package_path)
  if type(name) ~= 'string' then return end
  package_path = package_path or H.get_package_path()

  -- First check for the most common case of name present in 'pack/deps/opt'
  local opt_path = string.format('%s/pack/deps/opt/%s', package_path, name)
  local is_opt_present = vim.loop.fs_stat(opt_path) ~= nil
  if is_opt_present then return opt_path, true end

  -- Allow processing 'pack/deps/start'
  local start_path = string.format('%s/pack/deps/start/%s', package_path, name)
  local is_start_present = vim.loop.fs_stat(start_path) ~= nil

  -- Use 'opt' directory by default
  local path = is_start_present and start_path or opt_path
  return path, is_start_present or is_opt_present
end

H.get_package_path = function() return H.full_path(H.get_config().path.package) end

-- Checkout/Snapshot ----------------------------------------------------------
H.normalize_checkout_target = function(x)
  -- Convert to array which includes only present plugins
  local res, ok = {}, nil
  local package_path = H.get_package_path()

  -- Use session specs by default
  if x == nil then
    for _, spec in ipairs(MiniDeps.get_session()) do
      local path = H.get_plugin_path(spec.name, package_path)
      table.insert(res, { name = spec.name, checkout = spec.checkout, path = path })
    end
    return res
  end

  -- Treat string input as path to snapshot file
  if type(x) == 'string' then
    ok, x = pcall(dofile, vim.fn.fnamemodify(x, ':p'))
    if not ok then H.error('Checkout target is not a path to proper snapshot.') end
  end

  -- Input should be a map from plugin names to checkout target
  if type(x) ~= 'table' then H.error('Checkout target should be table.') end

  for key, value in pairs(x) do
    local path, is_present = H.get_plugin_path(key, package_path)
    local should_add = is_present and (type(value) == 'string' or type(value) == 'boolean')
    if should_add then table.insert(res, { name = key, checkout = value, path = path }) end
  end

  return res
end

H.do_checkout = function(target_arr)
  local jobs = {}
  for i, target in ipairs(target_arr) do
    local command = H.git_commands.checkout(target.checkout)
    local exit_msg = string.format('Checkout out %s in %s', vim.inspect(target.checkout), vim.inspect(target.name))
    jobs[i] = H.cli_new_job(command, target.path, exit_msg)
  end

  H.cli_run(jobs)

  -- TODO: Show errors
end

H.infer_default_checkout = function(target_arr)
  local targets_to_infer, jobs = {}, {}
  for _, target in ipairs(target_arr) do
    if target.checkout == true then
      -- NOTE: Add table as is to later modify in place
      table.insert(targets_to_infer, target)
      table.insert(jobs, H.cli_new_job(H.git_commands.get_default_checkout, target.path))
    end
  end

  H.cli_run(jobs)

  for i, target in ipairs(targets_to_infer) do
    local job_out = jobs[i].out[1] or ''
    jobs[i].out = {}

    local def_checkout = string.match(job_out, '^origin/(%S+)')
    target.checkout = def_checkout
    if def_checkout == nil then
      local name = vim.fn.fnamemodify(target.path, ':t')
      local msg = 'Could not find default branch for ' .. name .. '.'
      H.notify(msg, 'WARN')
    end
  end
end

-- CLI ------------------------------------------------------------------------
H.cli_run = function(jobs)
  local config_job = H.get_config().job
  local n_threads = config_job.n_threads or math.floor(0.8 * #vim.loop.cpu_info())
  local timeout = config_job.timeout or 60000

  local n_total, id_started, n_finished = #jobs, 0, 0
  if n_total == 0 then return end

  local run_next
  run_next = function()
    if n_total <= id_started then return end
    id_started = id_started + 1

    local job = jobs[id_started]
    local command, cwd, exit_msg = job.command or {}, job.cwd, job.exit_msg

    -- Allow reusing job structure. Do nothing if previously there were errors.
    if not (#job.err == 0 and #command > 0) then
      n_finished = n_finished + 1
      return run_next()
    end

    -- Prepare data for `vim.loop.spawn`
    local executable, args = command[1], vim.list_slice(command, 2, #command)
    local process, stdout, stderr = nil, vim.loop.new_pipe(), vim.loop.new_pipe()
    local spawn_opts = { args = args, cwd = cwd, stdio = { nil, stdout, stderr } }

    -- Register job finish and start a new one from the queue
    local on_exit = function(code)
      if code ~= 0 then table.insert(job.err, 1, 'PROCESS EXITED WITH ERROR CODE ' .. code .. '\n') end
      process:close()
      n_finished = n_finished + 1
      if type(exit_msg) == 'string' then H.notify(string.format('(%d/%d) %s.', n_finished, n_total, exit_msg)) end
      run_next()
    end

    process = vim.loop.spawn(executable, spawn_opts, on_exit)
    H.cli_read_stream(stdout, job.out)
    H.cli_read_stream(stderr, job.err)
  end

  for _ = 1, math.max(n_threads, 1) do
    run_next()
  end

  vim.wait(timeout * n_total, function() return n_total <= n_finished end, 1)
end

H.cli_read_stream = function(stream, feed)
  local callback = function(err, data)
    if err then return table.insert(feed, 1, 'ERROR: ' .. err) end
    if data ~= nil then return table.insert(feed, data) end
    stream:close()
  end
  stream:read_start(callback)
end

H.cli_new_job = function(command, cwd, exit_msg)
  return { command = command, cwd = cwd, exit_msg = exit_msg, out = {}, err = {} }
end

-- vim.fn.delete('clones', 'rf')
-- vim.fn.mkdir('clones', 'p')

_G.repos = {
  'mini.nvim',
  'mini.ai',
  'mini.align',
  -- 'mini.animate',
  -- 'mini.base16',
  -- 'mini.basics',
  -- 'mini.bracketed',
  -- 'mini.bufremove',
  -- 'mini.clue',
  -- 'mini.colors',
  -- 'mini.comment',
  -- 'mini.completion',
  -- 'mini.cursorword',
  -- 'mini.doc',
  -- 'mini.extra',
  -- 'mini.files',
  -- 'mini.fuzzy',
  -- 'mini.hipatterns',
  -- 'mini.hues',
  -- 'mini.indentscope',
  -- 'mini.jump',
  -- 'mini.jump2d',
  -- 'mini.map',
  -- 'mini.misc',
  -- 'mini.move',
  -- 'mini.operators',
  -- 'mini.pairs',
  -- 'mini.pick',
  -- 'mini.sessions',
  -- 'mini.splitjoin',
  -- 'mini.starter',
  -- 'mini.statusline',
  -- 'mini.surround',
  -- 'mini.tabline',
  -- 'mini.test',
  -- 'mini.trailspace',
  -- 'mini.visits',
}

_G.test_jobs = {}
--stylua: ignore
for _, repo in ipairs(repos) do
  local name = repo:sub(6)
  local job = H.cli_new_job(
    { 'git', '-C', 'clones', 'clone', '--quiet', '--filter=blob:none', 'https://github.com/echasnovski/' .. repo, name }, -- create
    -- { 'git', '-C', 'clones/' .. name, 'fetch', '--quiet', 'origin', 'main' }, -- fetch
    -- { 'git', '-C', 'clones/' .. name, 'log', '--format=%h - %ai - %an%n  %s%n', 'main~~..main' }, -- log after fetch
    -- { 'git', '-C', 'clones/' .. name, 'checkout', '--quiet', 'HEAD~' }, -- checkout
    -- { 'git', '-C', 'clones/' .. name, 'checkout', '--quiet', 'main' }, -- checkout
    -- { 'git', '-C', 'clones/' .. name, 'checkout', '--quiet', 'v0.10.0' }, -- checkout
    -- { 'git', '-C', 'clones/' .. name, 'rev-parse', '--abbrev-ref', 'origin/HEAD'}, -- checkout default
    -- { 'git', '-C', 'clones/' .. name, 'rev-parse', 'HEAD'}, -- snapshot

    'Done with ' .. vim.inspect(name)
  )
  table.insert(_G.test_jobs, job)
end

-- vim.fn.writefile({}, 'worklog')
-- _G.test_commands = {}
-- for i = 1, 18 do
--   table.insert(_G.test_commands, { './date-and-sleep.sh', tostring(i) })
-- end

-- Two-stage execution --------------------------------------------------------
H.schedule_finish = function()
  if H.cache.finish_is_scheduled then return end
  vim.schedule(H.finish)
  H.cache.finish_is_scheduled = true
end

H.finish = function()
  local timer, step_delay = vim.loop.new_timer(), 1
  local f = nil
  f = vim.schedule_wrap(function()
    local callback = H.cache.later_callback_queue[1]
    if callback == nil then
      H.cache.finish_is_scheduled, H.cache.later_callback_queue = false, {}
      H.report_errors()
      return
    end

    table.remove(H.cache.later_callback_queue, 1)
    MiniDeps.now(callback)
    timer:start(step_delay, 0, f)
  end)
  timer:start(step_delay, 0, f)
end

H.report_errors = function()
  if #H.cache.exec_errors == 0 then return end
  local msg_lines = {
    { '(mini.deps) ', 'WarningMsg' },
    { 'There were errors during two-stage execution:\n\n', 'MoreMsg' },
    { table.concat(H.cache.exec_errors, '\n\n'), 'ErrorMsg' },
  }
  H.cache.exec_errors = {}
  vim.api.nvim_echo(msg_lines, true, {})
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.deps) %s', msg), 0) end

H.notify = vim.schedule_wrap(function(msg, level)
  level = level or 'INFO'
  if H.get_config().silent and level ~= 'ERROR' and level ~= 'WARN' then return end
  if type(msg) == 'table' then msg = table.concat(msg, '\n') end
  vim.notify(string.format('(mini.deps) %s', msg), vim.log.levels[level])
  vim.cmd('redraw')
end)

H.to_lines = function(arr)
  local s = table.concat(arr):gsub('\n+$', '')
  return vim.split(s, '\n')
end

H.maybe_exec = function(f, ...)
  if vim.is_callable() then f(...) end
end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('\\', '/'):gsub('/+', '/'):gsub('(.)/$', '%1')) end

H.short_path = function(path, cwd)
  cwd = cwd or vim.fn.getcwd()
  if not vim.startswith(path, cwd) then return vim.fn.fnamemodify(path, ':~') end
  local res = path:sub(cwd:len() + 1):gsub('^/+', ''):gsub('/+$', '')
  return res
end

return MiniDeps

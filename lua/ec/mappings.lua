-- Russian keyboard mappings
-- stylua: ignore start
local langmap_keys = {
  'ёЁ;`~', '№;#',
  'йЙ;qQ', 'цЦ;wW', 'уУ;eE', 'кК;rR', 'еЕ;tT', 'нН;yY', 'гГ;uU', 'шШ;iI', 'щЩ;oO', 'зЗ;pP', 'хХ;[{', 'ъЪ;]}',
  'фФ;aA', 'ыЫ;sS', 'вВ;dD', 'аА;fF', 'пП;gG', 'рР;hH', 'оО;jJ', 'лЛ;kK', 'дД;lL', [[жЖ;\;:]], [[эЭ;'\"]],
  'яЯ;zZ', 'чЧ;xX', 'сС;cC', 'мМ;vV', 'иИ;bB', 'тТ;nN', 'ьЬ;mM', [[бБ;\,<]], 'юЮ;.>',
}
vim.opt.langmap = table.concat(langmap_keys, ',')
-- stylua: ignore end

-- Helper function
local default_opts = {
  noremap = true,
  silent = true,
  expr = false,
  nowait = false,
  script = false,
  unique = false,
}

local keymap = function(mode, keys, cmd, opts)
  local o = vim.tbl_deep_extend('force', default_opts, opts or {})
  vim.api.nvim_set_keymap(mode, keys, cmd, o)
end

-- Disable `s` shortcut (use `cl` instead) for safer usage of 'mini.surround'
keymap('n', [[s]], [[<Nop>]])
keymap('x', [[s]], [[<Nop>]])

-- Move by visible lines (don't map in Operator-pending mode because it
-- severely changes behavior; like `dj` on non-wrapped line will not delete it)
keymap('n', 'j', 'gj')
keymap('x', 'j', 'gj')
keymap('n', 'k', 'gk')
keymap('x', 'k', 'gk')

-- Alternative way to save
keymap('n', [[<C-s>]], [[<Cmd>silent w<CR>]])
keymap('i', [[<C-s>]], [[<Esc><Cmd>silent w<CR>]])
keymap('v', [[<C-s>]], [[<Esc><Cmd>silent w<CR>]])

-- Copy/paste with system clipboard
keymap('n', [[gy]], [["+y]])
keymap('x', [[gy]], [["+y]])
keymap('n', [[gp]], [["+p]])
keymap('x', [[gp]], [["+P]])

-- Move with <Alt-hjkl> in non-normal mode. Don't `noremap` in insert mode to
-- have these keybindings behave exactly like arrows (crucial inside
-- TelescopePrompt)
keymap('i', [[<M-h>]], [[<Left>]], { noremap = false })
keymap('i', [[<M-j>]], [[<Down>]], { noremap = false })
keymap('i', [[<M-k>]], [[<Up>]], { noremap = false })
keymap('i', [[<M-l>]], [[<Right>]], { noremap = false })
keymap('t', [[<M-h>]], [[<Left>]])
keymap('t', [[<M-j>]], [[<Down>]])
keymap('t', [[<M-k>]], [[<Up>]])
keymap('t', [[<M-l>]], [[<Right>]])
-- Move only sideways in command mode. Using `silent = false` makes movements
-- to be immediately shown.
keymap('c', [[<M-h>]], [[<Left>]], { silent = false })
keymap('c', [[<M-l>]], [[<Right>]], { silent = false })

-- Simpler window navigation
keymap('n', [[<C-h>]], [[<C-w>h]])
keymap('n', [[<C-j>]], [[<C-w>j]])
keymap('n', [[<C-k>]], [[<C-w>k]])
keymap('n', [[<C-l>]], [[<C-w>l]])

keymap('t', [[<C-w>]], [[<C-\><C-N><C-w>]])
-- When in terminal, use this to go to Normal mode
keymap('t', [[<C-h>]], [[<C-\><C-N><C-w>h]])

-- Use ctrl + arrows to resize windows
keymap('n', [[<C-Left>]], [[<Cmd>vertical resize -1<CR>]])
keymap('n', [[<C-Down>]], [[<Cmd>resize -1<CR>]])
keymap('n', [[<C-Up>]], [[<Cmd>resize +1<CR>]])
keymap('n', [[<C-Right>]], [[<Cmd>vertical resize +1<CR>]])

-- Move inside completion list with <TAB>
keymap('i', [[<Tab>]], [[pumvisible() ? "\<C-n>" : "\<Tab>"]], { expr = true })
keymap('i', [[<S-Tab>]], [[pumvisible() ? "\<C-p>" : "\<S-Tab>"]], { expr = true })

-- Correct latest misspelled word by taking first suggestion. Use `<C-g>u` to
-- mark this as separate undoable action.
-- Source: https://stackoverflow.com/a/16481737
keymap('i', '<C-f>', [[<C-g>u<Esc>[s1z=`]a<C-g>u]])

-- Reselect latest changed, put or yanked text
keymap('n', [[gV]], '`[v`]')

-- Join lines without moving cursor (set context mark, execute `J` respecting
-- count, go back to context mark)
-- Maybe don't do it? Try observing what is more convenient.
keymap('n', 'J', [['mz' . v:count1 . 'J`z']], { expr = true })

-- Make `q:` do nothing instead of opening command-line-window, because it is
-- often hit by accident
-- Use c_CTRL-F or Telescope
keymap('n', [[q:]], [[<Nop>]])

-- Search visually selected text (slightly better than builtins in Neovim>=0.8)
keymap('x', '*', [[y/\V<C-R>=escape(@", '/\')<CR><CR>]])
keymap('x', '#', [[y?\V<C-R>=escape(@", '?\')<CR><CR>]])

-- Search inside visually highlighted text
keymap('x', 'g/', '<esc>/\\%V', { silent = false })

-- Delete selection in Select mode (helpful when editing snippet placeholders)
keymap('s', [[<BS>]], [[<BS>i]])

-- Stop highlighting of search results. NOTE: this can be done with default
-- `<C-l>` but this solution deliberately uses `:` instead of `<Cmd>` to go
-- into Command mode and back which updates 'mini.map'.
keymap('n', [[\h]], ':let v:hlsearch = 1 - v:hlsearch | diffupdate<CR>')

-- Move visually selected region. Breakdown of common moving logic:
-- - Cut to `z` register (`"zx`).
-- - Move cursor `v:count1` times in certain direction (`h`, `j`, `k`, or `l`).
-- - Paste back from `z` register (`"zP`).
-- - Go to start of recent paste (``[`).
-- - Reselect previous visual selection at cursor.
-- - Special handling of linewise visual mode:
--     - For horizontal movement use `<` / `>` indention with reselect (`gv`).
--     - For vertical movement it is common to add formatting with `=` command.
--       However, this is not stable as it relies on `equalprg` option being
--       empty. To support this, append with `. (mode()==#'V' ? '=gv' : '')`.
--
-- NOTEs:
-- - More popular vertical movement:
--   keymap('x', 'J', [[":move '>+" . v:count1     . "<CR>gv=gv"]], { expr = true })
--   keymap('x', 'K', [[":move '<-" . (v:count1+1) . "<CR>gv=gv"]], { expr = true })
-- - Works only with 'selection' set to "inclusive" (default).
-- - Doesn't work at movement edges (first line for `K`, etc.).
--   See https://github.com/vim/vim/issues/11786
--   It can be made *slightly* better for `L` and `J` (use `p` instead of `P`),
--   but it complicates mappings.
keymap('x', 'H', [[mode()==#'V' ? '<gv' : ('"zx' . v:count1 . 'h"zP`[1v')]], { expr = true })
keymap('x', 'L', [[mode()==#'V' ? '>gv' : ('"zx' . v:count1 . 'l"zP`[1v')]], { expr = true })

keymap('x', 'J', [['"zx' . v:count1 . 'j"zP`[1v']], { expr = true })
keymap('x', 'K', [['"zx' . v:count1 . 'k"zP`[1v']], { expr = true })

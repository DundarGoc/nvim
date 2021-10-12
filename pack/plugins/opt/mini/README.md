# mini.nvim

Collection of minimal, independent, and fast Lua modules dedicated to improve [Neovim](https://github.com/neovim/neovim) (version 0.5 and higher) experience. Each module can be considered as a separate sub-plugin.

## Table of contents

- [Installation](#installation)
- [General principles](#general-principles)
- [Plugin colorscheme](#plugin-colorscheme)
- [Modules](#modules)
    - [mini.base16](#minibase16)
    - [mini.bufremove](#minibufremove)
    - [mini.comment](#minicomment)
    - [mini.completion](#minicompletion)
    - [mini.cursorword](#minicursorword)
    - [mini.fuzzy](#minifuzzy)
    - [mini.misc](#minimisc)
    - [mini.pairs](#minipairs)
    - [mini.statusline](#ministatusline)
    - [mini.surround](#minisurround)
    - [mini.tabline](#minitabline)
    - [mini.trailspace](#minitrailspace)
- [Planned modules](#planned-modules)

## Installation

- Using [wbthomason/packer.nvim](https://github.com/wbthomason/packer.nvim):

    ```
    use 'echasnovski/mini.nvim'
    ```

- Using [junegunn/vim-plug](https://github.com/junegunn/vim-plug):

    ```
    Plug 'echasnovski/mini.nvim'
    ```

- Each module is independent and implemented within single file. You can copy corresponding file from 'lua/mini/' directory to your '.config/nvim/lua' directory and use it from there.

Don't forget to call module's `setup()` (if required) to enable its functionality.

## General principles

- **Design**. Each module is designed to solve a particular problem targeting balance between feature-richness (handling as many edge-cases as possible) and simplicity of implementation/support. Granted, not all of them ended up with the same balance, but it is the goal nevertheless.
- **Independence**. Modules are independent of each other and can be run without external dependencies. Although some of them may need dependencies for full experience.
- **Structure**. Each module is a submodule for a placeholder "mini" module. So, for example, "surround" module should be referred to as "mini.surround".  As later will be explained, this plugin can also be referred to as "MiniSurround".
- **Setup**:
    - Each module (if needed) should be setup separately with `require(<name of module>).setup({})` (possibly replace {} with your config table or omit to use defaults).  You can supply only values which differ from defaults, which will be used for the rest ones.
    - Call to module's `setup()` always creates a global Lua object with coherent camel-case name: `require('mini.suround').setup()` creates `_G.MiniSurround`. This allows for a simpler usage of plugin functionality: instead of `require('mini.surround')` use `MiniSurround`; available from `v:lua` like `v:lua.MiniSurround`.  Considering this, "module" and "Lua object" names can be used interchangeably: 'mini.surround' and 'MiniSurround' will mean the same thing.
    - Each supplied `config` table (aft) is stored in `config` field of global object. Like `MiniSurround.config`.
    - Values of `config`, which affect runtime activity, can be changed on the fly to have effect. For example, `MiniSurround.config.n_lines` can be changed during runtime; but changing `MiniSurround.config.mappings` won't have any effect (as mappings are created once during `setup()`).
- **Disabling**. Each module's core functionality can be disabled globally or buffer-locally by creating appropriate global or buffer-scoped variables with `v:true` value. For example:
    - To disable `MiniSurround` globally run `:let g:minisurround_disable=v:true`.
    - To disable `MiniSurround` for current buffer run `:let b:minisurround_disable=v:true`.
    - To toggle `MiniSurround` globally (disable if enabled, enable if disabled) use of Lua is more appropriate: `:lua vim.g.minisurround_disable = not vim.g.minisurround_disable`.
- **Highlight groups**. Appearance of module's output is controlled by certain highlight group (see `:h highlight-groups`). To customize them, use `highlight` command. **Note**: currently not many Neovim themes support this plugin's highlight groups; fixing this situation is highly appreciated.  To see a more calibrated look, use MiniBase16 or plugin's colorscheme `minischeme`.
- **Stability**. Each module upon release is considered to be relatively stable: both in terms of setup and functionality. Any non-bugfix backward-incompatible change will be released gradually as much as possible.

## Plugin colorscheme

This plugin comes with an official colorscheme named `minischeme`. This is a MiniBase16 theme created with faster version of the following Lua code: `require('mini.base16').setup({palette = palette, name = 'minischeme', use_cterm = true})` where `palette` is:
- For dark 'background': `require('mini.base16').mini_palette('#112641', '#e2e98f', 75)`
- For light 'background': `require('mini.base16').mini_palette('#e2e5ca', '#002a83', 75)`

Activate it as a regular `colorscheme`.

All examples use this colorscheme.

## Modules

### mini.base16

Fast implementation of [chriskempson/base16](https://github.com/chriskempson/base16) theme for manually supplied palette. Has unique palette generator which needs only background and foreground colors.

<img src="https://raw.githubusercontent.com/echasnovski/nvim/misc/mini-readme-demo/master/demo-base16_dark.png" width="450em"/>
<img src="https://raw.githubusercontent.com/echasnovski/nvim/misc/mini-readme-demo/master/demo-base16_light.png" width="450em"/>

Default `config`:

```lua
{
  -- Table with names from `base00` to `base0F` and values being strings of HEX
  -- colors with format "#RRGGBB". NOTE: this should be explicitly supplied in
  -- `setup()`.
  palette = nil,

  -- Name of applied theme (stored in `g:colors_name`)
  name = 'base16-custom',

 -- Whether to support cterm colors. Can be boolean, `nil` (same as `false`),
 -- or table with cterm colors. See `setup()` documentation for more
 -- information.
  use_cterm = nil,
}
```

For more information, read 'mini.base16' section of [help file](doc/mini.txt).

Plugins with similar functionality:

- [chriskempson/base16-vim](https://github.com/chriskempson/base16-vim)

### mini.bufremove

Buffer removing (unshow, delete, wipeout) while saving window layout.

<img src="https://raw.githubusercontent.com/echasnovski/nvim/misc/mini-readme-demo/master/demo-bufremove.gif"/>

Default `config`:

```lua
{
  -- Whether to set Vim's settings for buffers (allow hidden buffers)
  set_vim_settings = true,
}
```

For more information, read 'mini.bufremove' section of [help file](doc/mini.txt).

Plugins with similar functionality:

- [mhinz/vim-sayonara](https://github.com/mhinz/vim-sayonara)
- [moll/vim-bbye](https://github.com/moll/vim-bbye)

### mini.comment

Fast and familiar per-line code commenting.

<img src="https://raw.githubusercontent.com/echasnovski/nvim/misc/mini-readme-demo/master/demo-comment.gif"/>

Default `config`:

```lua
{
  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Toggle comment (like `gcip` - comment inner paragraph) for both
    -- Normal and Visual modes
    comment = 'gc',

    -- Toggle comment on current line
    comment_line = 'gcc',

    -- Define 'comment' textobject (like `dgc` - delete whole comment block)
    textobject = 'gc',
  }
}
```

For more information, read 'mini.comment' section of [help file](doc/mini.txt).

Plugins with similar functionality:

- [tpope/vim-commentary](https://github.com/tpope/vim-commentary)
- [preservim/nerdcommenter](https://github.com/preservim/nerdcommenter)
- [b3nj5m1n/kommentary](https://github.com/b3nj5m1n/kommentary)
- [numToStr/Comment.nvim](https://github.com/numToStr/Comment.nvim)

### mini.completion

Async (with customizable 'debounce' delay) 'two-stage chain completion': first builtin LSP, then configurable fallback. Also has functionality for completion item info and function signature (both in floating window appearing after customizable delay).

<img src="https://raw.githubusercontent.com/echasnovski/nvim/misc/mini-readme-demo/master/demo-completion.gif"/>

Default `config`:

```lua
{
  -- Delay (debounce type, in ms) between certain Neovim event and action.
  -- This can be used to (virtually) disable certain automatic actions by
  -- setting very high delay time (like 10^7).
  delay = {completion = 100, info = 100, signature = 50},

  -- Maximum dimensions of floating windows for certain actions. Action entry
  -- should be a table with 'height' and 'width' fields.
  window_dimensions = {
    info = {height = 25, width = 80},
    signature = {height = 25, width = 80}
  },

  -- Way of how module does LSP completion:
  -- - `source_func` should be one of 'completefunc' or 'omnifunc'.
  -- - `auto_setup` should be boolean indicating if LSP completion is set up on
  --   every `BufEnter` event.
  -- - `process_items` should be a function which takes LSP
  --   'textDocument/completion' response items and word to complete. Its
  --   output should be a table of the same nature as input items. The most
  --   common use-cases are custom filtering and sorting. You can use
  --   default `process_items` as `MiniCompletion.default_process_items()`.
  lsp_completion = {
    source_func = 'completefunc',
    auto_setup = true,
    process_items = --<function: filters 'not snippets' by prefix and sorts by LSP specification>,
  },

  -- Fallback action. It will always be run in Insert mode. To use Neovim's
  -- built-in completion (see `:h ins-completion`), supply its mapping as
  -- string. For example, to use 'whole lines' completion, supply '<C-x><C-l>'.
  fallback_action = --<function equivalent to '<C-n>' completion>,

  -- Module mappings. Use `''` (empty string) to disable one. Some of them
  -- might conflict with system mappings.
  mappings = {
    force_twostep  = '<C-Space>', -- Force two-step completion
    force_fallback = '<A-Space>'  -- Force fallback completion
  }

  -- Whether to set Vim's settings for better experience (modifies
  -- `shortmess` and `completeopt`)
  set_vim_settings = true
}
```

For more information, read 'mini.completion' section of [help file](doc/mini.txt).

Plugins with similar functionality:

- [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- [Shougo/ddc.vim](https://github.com/Shougo/ddc.vim)

### mini.cursorword

Automatic highlighting of word under cursor (displayed after customizable delay).

<img src="https://raw.githubusercontent.com/echasnovski/nvim/misc/mini-readme-demo/master/demo-cursorword.gif"/>

Default `config`:

```lua
{
 -- Delay (in ms) between when cursor moved and when highlighting appeared
 delay = 100,
}
```

For more information, read 'mini.cursorword' section of [help file](doc/mini.txt).

Plugins with similar functionality:

- [itchyny/vim-cursorword](https://github.com/itchyny/vim-cursorword)

### mini.fuzzy

Functions for fast and simple fuzzy matching. It has not only functions to perform fuzzy matching of one string to others, but also a sorter for [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).

![](media/demo-fuzzy.gif)

Default `config`:

```lua
{
  -- Maximum allowed value of match features (width and first match). All
  -- feature values greater than cutoff can be considered "equally bad".
  cutoff = 100,
}
```

For more information, read 'mini.fuzzy' section of [help file](doc/mini.txt).

### mini.misc

Collection of miscellaneous useful functions. Like `put()` and `put_text()` which print Lua objects to command line and current buffer respectively.

<img src="https://raw.githubusercontent.com/echasnovski/nvim/misc/mini-readme-demo/master/demo-misc.gif"/>

Default `config`:

```lua
{
  -- List of fields to make global (to be used as independent variables)
  make_global = { 'put', 'put_text' },
}
```

For more information, read 'mini.misc' section of [help file](doc/mini.txt).

### mini.pairs

Autopairs plugin which has minimal defaults and functionality to do per-key expression mappings.

<img src="https://raw.githubusercontent.com/echasnovski/nvim/misc/mini-readme-demo/master/demo-pairs.gif"/>

Default `config`:

```lua
{
  -- In which modes mappings should be created
  modes = {insert = true, command = false, terminal = false}
}
```

For more information, read 'mini.pairs' section of [help file](doc/mini.txt).

Plugins with similar functionality:

- [jiangmiao/auto-pairs](https://github.com/jiangmiao/auto-pairs)
- [windwp/nvim-autopairs](https://github.com/windwp/nvim-autopairs)

### mini.statusline

Minimal and fast statusline. Has ability to use custom content supplied with concise function (using module's provided section functions) along with builtin default. For full experience needs [Nerd font](https://www.nerdfonts.com/), [lewis6991/gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) plugin, and [kyazdani42/nvim-web-devicons](https://github.com/kyazdani42/nvim-web-devicons) plugin (but works without any them).

<img src="https://raw.githubusercontent.com/echasnovski/nvim/misc/mini-readme-demo/master/demo-statusline.gif"/>

Default `config`:

```lua
{
  -- Content of statusline as functions which return statusline string. See `:h
  -- statusline` and code of default contents (used when `nil` is supplied).
  content = {
    -- Content for active window
    active = nil,

    -- Content for inactive window(s)
    inactive = nil,
  },

  -- Whether to set Vim's settings for statusline (make it always shown)
  set_vim_settings = true,
}
```

For more information, read 'mini.statusline' section of [help file](doc/mini.txt).

Plugins with similar functionality:

- [hoob3rt/lualine.nvim](https://github.com/hoob3rt/lualine.nvim)
- [NTBBloodbath/galaxyline.nvim](https://github.com/NTBBloodbath/galaxyline.nvim)
- [famiu/feline.nvim](https://github.com/famiu/feline.nvim)

### mini.surround

Fast surround plugin. Add, delete, replace, find, highlight surrounding (like pair of parenthesis, quotes, etc.). Has special "function call", "tag", and "interactive" surroundings. Supports dot-repeatability, textobject, motions.

<img src="https://raw.githubusercontent.com/echasnovski/nvim/misc/mini-readme-demo/master/demo-surround.gif"/>

Default `config`:

```lua
{
  -- Number of lines within which surrounding is searched
  n_lines = 20,

  -- Duration (in ms) of highlight when calling `MiniSurround.highlight()`
  highlight_duration = 500,

  -- Pattern to match function name in 'function call' surrounding
  -- By default it is a string of letters, '_' or '.'
  funname_pattern = '[%w_%.]+',

  -- Mappings. Use `''` (empty string) to disable one.
  mappings = {
    add = 'sa',           -- Add surrounding
    delete = 'sd',        -- Delete surrounding
    find = 'sf',          -- Find surrounding (to the right)
    find_left = 'sF',     -- Find surrounding (to the left)
    highlight = 'sh',     -- Highlight surrounding
    replace = 'sr',       -- Replace surrounding
    update_n_lines = 'sn' -- Update `n_lines`
  }
}
```

For more information, read 'mini.surround' section of [help file](doc/mini.txt).

Plugins with similar functionality:

- [tpope/vim-surround](https://github.com/tpope/vim-surround)
- [machakann/vim-sandwich](https://github.com/machakann/vim-sandwich)

### mini.tabline

Minimal tabline which shows listed (see `:h buflisted`) buffers in case of one tab and falls back to default otherwise. For full experience needs [kyazdani42/nvim-web-devicons](https://github.com/kyazdani42/nvim-web-devicons).

<img src="https://raw.githubusercontent.com/echasnovski/nvim/misc/mini-readme-demo/master/demo-tabline.gif"/>

Default `config`:

```lua
{
  -- Whether to show file icons (requires 'kyazdani42/nvim-web-devicons')
  show_icons = true,

  -- Whether to set Vim's settings for tabline (make it always shown and
  -- allow hidden buffers)
  set_vim_settings = true
}
```

For more information, read 'mini.tabline' section of [help file](doc/mini.txt).

Plugins with similar functionality:

- [akinsho/bufferline.nvim](https://github.com/akinsho/bufferline.nvim)
- [ap/vim-buftabline](https://github.com/ap/vim-buftabline)

### mini.trailspace

Automatic highlighting of trailing whitespace with functionality to remove it.

<img src="https://raw.githubusercontent.com/echasnovski/nvim/misc/mini-readme-demo/master/demo-trailspace.gif"/>

Default `config`:

```lua
{} -- (currently nothing to configure)
```

For more information, read 'mini.trailspace' section of [help file](doc/mini.txt).

Plugins with similar functionality:

- [ntpeters/vim-better-whitespace](https://github.com/ntpeters/vim-better-whitespace)

## Planned modules

This is the list of modules I currently intend to implement eventually (as my free time and dedication will allow):

- 'mini.startscreen' (or 'mini.starter', or 'mini.menu') - fast and configurable startscreen with some unique features. Something like start screen of [mhinz/vim-startify](https://github.com/mhinz/vim-startify).
- 'mini.sessions' - work with sessions (save, load, delete, persistent sessions). Something like session management of [mhinz/vim-startify](https://github.com/mhinz/vim-startify).
- 'mini.terminal' (or 'mini.repl') - coherently manage terminal windows and send text from buffers to terminal windows. Something like [kassio/neoterm](https://github.com/kassio/neoterm).
- 'mini.exchange' (or 'mini.swap') - exchange two regions of text. Something like [tommcdo/vim-exchange](https://github.com/tommcdo/vim-exchange).
- 'mini.align' - fast text alignment. Something like [tommcdo/vim-lion](https://github.com/tommcdo/vim-lion).
- 'mini.arguments' - work with listed arguments. Something like [FooSoft/vim-argwrap](https://github.com/FooSoft/vim-argwrap) and [AndrewRadev/sideways.vim](https://github.com/AndrewRadev/sideways.vim).
- 'mini.tree' - file tree explorer. Truncated version of [kyazdani42/nvim-tree](https://github.com/kyazdani42/nvim-tree.lua).

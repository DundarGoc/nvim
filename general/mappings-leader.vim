" Leader key
let mapleader = "\<Space>"

" Map leader to which_key
nnoremap <silent> <Leader> :silent <c-u> :silent WhichKey '<Space>'<CR>
vnoremap <silent> <Leader> :silent <c-u> :silent WhichKeyVisual '<Space>'<CR>

" Create map to add keys to
let g:which_key_map =  {}

" Single letter mappings
"" Execute in jupyter current line and go down by one line
nmap <silent> <Leader>j  <Plug>(IPy-Run)j
"" Execute in jupyter selection and go down by one line after the end of
"" selection
vmap <silent> <Leader>j  <Plug>(IPy-Run)'>j
let g:which_key_map['j'] = 'jupyter run'

" Send text to neoterm buffer
nnoremap <Leader>s <cmd>TREPLSendLine<CR>j
"" In simple visual mode send text and move to the last character in selection
"" and move to the right.
"" Otherwise (like in line or block visual mode) send text and move one
"" line down from bottom of selection.
xnoremap <silent> <expr> <Leader>s  mode() ==# "v" ? ":TREPLSendSelection<CR>`>l" : ":TREPLSendSelection<CR>'>j"
let g:which_key_map['s'] = 'send to terminal'

" b is for 'buffer'
let g:which_key_map.b = {
  \ 'name' : '+buffer' ,
  \ 'a' : [':b#'            , 'alternate'],
  \ 'd' : [':Bclose'        , 'delete'],
  \ 'D' : [':Bclose!'       , 'delete!'],
  \ 's' : [':call Scratch()', 'scratch'],
  \ }

" e is for 'explore'
nnoremap <silent> <Leader>en <cmd>TroubleToggle todo<CR>
nnoremap <silent> <Leader>eP <cmd>TroubleToggle lsp_document_diagnostics<CR>
nnoremap <silent> <Leader>ep <cmd>TroubleToggle lsp_workspace_diagnostics<CR>
let g:which_key_map.e = {
  \ 'name' : '+explore' ,
  \ 'P' : 'problems (troubles) document',
  \ 'f' : [':RnvimrToggle'  , 'files'],
  \ 'n' : 'notes (todo, etc.)',
  \ 'p' : 'problems (troubles) workspace',
  \ 't' : [':NvimTreeToggle', 'tree'],
  \ 'u' : [':UndotreeToggle', 'undo-tree'],
  \ }

" f is for both 'fzf' and 'find'
let g:which_key_map.f = {
  \ 'name' : '+fzf' ,
  \ '/' : [':History/'        , '"/" history'],
  \ ';' : [':Commands'        , 'commands'],
  \ 'b' : [':Buffers'         , 'open buffers'],
  \ 'C' : [':BCommits'        , 'buffer commits'],
  \ 'c' : [':Commits'         , 'commits'],
  \ 'f' : [':Files'           , 'files'],
  \ 'F' : [':GFiles --others' , 'files untracked'],
  \ 'g' : [':GFiles'          , 'git files'],
  \ 'G' : [':GFiles?'         , 'modified git files'],
  \ 'H' : [':History:'        , 'command history'],
  \ 'h' : [':History'         , 'file history'],
  \ 'L' : [':BLines'          , 'lines (current buffer)'],
  \ 'l' : [':Lines'           , 'lines (all buffers)'],
  \ 'M' : [':Maps'            , 'normal maps'],
  \ 'm' : [':Marks'           , 'marks'],
  \ 'p' : [':Helptags'        , 'help tags'],
  \ 'r' : [':Rg'              , 'text Rg'],
  \ 'S' : [':Colors'          , 'color schemes'],
  \ 's' : [':Snippets'        , 'snippets'],
  \ 'T' : [':BTags'           , 'buffer tags'],
  \ 't' : [':Tags'            , 'project tags'],
  \ 'w' : [':Windows'         , 'search windows'],
  \ 'y' : [':Filetypes'       , 'file types'],
  \ 'z' : [':FZF'             , 'FZF'],
  \ }

" g is for git
let g:which_key_map.g = {
  \ 'name' : '+git' ,
  \ 'A' :                                    'add buffer',
  \ 'a' :                                    'add (stage) hunk',
  \ 'B' : [':Git blame'                    , 'blame buffer'],
  \ 'b' :                                    'blame line',
  \ 'D' : [':tab Gvdiffsplit'              , 'diff split'],
  \ 'd' : [':Git diff'                     , 'diff'],
  \ 'g' : [':Git'                          , 'git window'],
  \ 'h' : [':diffget //2'                  , 'merge from left (our)'],
  \ 'j' :                                    'next hunk',
  \ 'k' :                                    'prev hunk',
  \ 'l' : [':diffget //3'                  , 'merge from right (their)'],
  \ 'p' :                                    'preview hunk',
  \ 'q' :                                    'quickfix hunks',
  \ 't' : [':GitGutterLineHighlightsToggle', 'toggle highlight'],
  \ 'u' :                                    'undo stage hunk',
  \ 'U' : [':Git reset %'                  , 'undo stage buffer'],
  \ 'V' : [':GV!'                          , 'view buffer commits'],
  \ 'v' : [':GV'                           , 'view commits'],
  \ 'x' :                                    'discard (reset) hunk',
  \ 'X' :                                    'discard (reset) buffer'
  \ }

" i is for IPython
"" Qt Console connection.
""" **To create working connection, execute both keybindings** (second after
""" console is created).
""" **Note**: Qt Console is opened with Python interpreter that is used in
""" terminal when opened NeoVim (i.e. output of `which python`). As a
""" consequence, if that Python interpreter doesn't have 'jupyter' or
""" 'qtconsole' installed, Qt Console will not be created.
""" `CreateQtConsole()` is defined in 'plug-config/nvim-ipy.vim'.
nmap <silent> <Leader>iq <cmd>call CreateQtConsole()<CR>
nmap <silent> <Leader>ik <cmd>IPython<Space>--existing<Space>--no-window<CR>

"" Execution
nmap <silent> <Leader>ic  <Plug>(IPy-RunCell)
nmap <silent> <Leader>ia  <Plug>(IPy-RunAll)

""" One can also setup a completion connection (generate a completion list
""" inside NeoVim but options taken from IPython session), but it seems to be
""" a bad practice methodologically.
"" imap <silent> <C-k> <cmd>call IPyComplete()<CR>
""   " This one should be used only when inside Insert mode after <C-o>
"" nmap <silent> <Leader>io <cmd>call IPyComplete()<CR>

let g:which_key_map.i = {
  \ 'name' : '+IPython',
  \ 'a' : 'run all',
  \ 'c' : 'run cell',
  \ 'k' : 'connect',
  \ 'q' : 'Qt Console',
  \ }

" l is for 'LSP' (Language Server Protocol)
nnoremap <silent> <Leader>lf <cmd>Neoformat<CR>
"" Actual commands are defined in settings for 'nvim-lspconfig'
let g:which_key_map.l = {
  \ 'name' : '+LSP' ,
  \ 'F' : 'format selected',
  \ 'R' : 'references',
  \ 'a' : 'arguments popup',
  \ 'd' : 'diagnostics popup',
  \ 'f' : 'format',
  \ 'i' : 'information',
  \ 'j' : 'next diagnostic',
  \ 'k' : 'prev diagnostic',
  \ 'r' : 'rename',
  \ 's' : 'source definition',
  \ }

" o is for 'other'
nnoremap <Leader>oC <cmd>lua MiniCursorword.toggle()<CR>
nnoremap <Leader>oT <cmd>lua MiniTrailspace.toggle()<CR>
nnoremap <Leader>ot <cmd>lua MiniTrailspace.trim()<CR>
let g:which_key_map.o = {
  \ 'name' : '+other' ,
  \ 'a' : [':ArgWrap'                     , 'arguments split'],
  \ 'C' :                                   'cursor word hl toggle',
  \ 'd' : [':DogeGenerate'                , 'document'],
  \ 'h' : [':SidewaysLeft'                , 'move arg left'],
  \ 'H' : [':TSBufToggle highlight'       , 'highlight toggle'],
  \ 'l' : [':SidewaysRight'               , 'move arg right'],
  \ 'r' : [':call ResizeToColorColumn()'  , 'resize to colorcolumn'],
  \ 'S' : [':call SpellCompletionToggle()', 'spell completion toggle'],
  \ 's' : [':setlocal spell!'             , 'spell toggle'],
  \ 't' :                                   'trim trailspace',
  \ 'T' :                                   'trailspace hl toggle',
  \ 'w' : [':call ToggleWrap()'           , 'wrap toggle'],
  \ 'z' : [':call Zoom()'                 , 'zoom'],
  \ }

" r is for 'R'
"" These mappings send commands to current neoterm buffer, so some sort of R
"" interpreter should already run there
nnoremap <silent> <Leader>rc <cmd>T devtools::check()<CR>
nnoremap <silent> <Leader>rC <cmd>T devtools::test_coverage()<CR>
nnoremap <silent> <Leader>rd <cmd>T devtools::document()<CR>
nnoremap <silent> <Leader>ri <cmd>T devtools::install(keep_source=TRUE)<CR>
nnoremap <silent> <Leader>rk <cmd>T rmarkdown::render("%")<CR>
nnoremap <silent> <Leader>rl <cmd>T devtools::load_all()<CR>
nnoremap <silent> <Leader>rT <cmd>T devtools::test_file("%")<CR>
nnoremap <silent> <Leader>rt <cmd>T devtools::test()<CR>
" Copy to clipboard and make reprex (which itself is loaded to clipboard)
vnoremap <silent> <Leader>rx "+y :T reprex::reprex()<CR>

"" These mapping execute something from Vim
"" `SplitFunSeq()` is defined in 'general/functions.vim'
nnoremap <silent> <Leader>rp <cmd>call SplitFunSeq("%>%", v:true)<CR>

let g:which_key_map.r = {
  \ 'name' : '+R',
  \ 'c' : 'check',
  \ 'C' : 'coverage',
  \ 'd' : 'document',
  \ 'i' : 'install',
  \ 'k' : 'knit file',
  \ 'l' : 'load all',
  \ 'p' : 'pipe split',
  \ 'T' : 'test file',
  \ 't' : 'test',
  \ 'x' : 'reprex selection',
  \ }

" t is for 'terminal' (uses 'neoterm')
"" `ShowActiveNeotermREPL()` is defined in 'general/functions.vim'
nnoremap <silent> <Leader>ta <cmd>call ShowActiveNeotermREPL()<CR>
nnoremap <silent> <Leader>tc :<c-u>exec v:count."Tclose\!"<CR>
nnoremap <silent> <Leader>tf :<c-u>exec "TREPLSetTerm ".v:count<CR>
nnoremap <silent> <Leader>tl <cmd>call neoterm#list_ids()<CR>

let g:which_key_map.t = {
  \ 'name' : '+terminal' ,
  \ 'a' :                        'echo active REPL id',
  \ 'C' : [':TcloseAll!'     , 'close all terminals'],
  \ 'c' :                        'close term (prepend by id)',
  \ 'f' :                        'focus term (prepend by id)',
  \ 'l' :                        'list terminals',
  \ 's' : [':belowright Tnew', 'split terminal'],
  \ 'v' : [':vertical Tnew'  , 'vsplit terminal'],
  \ }

" T is for 'test'
let g:which_key_map.T = {
  \ 'name' : '+test' ,
  \ 'F' : [':TestFile -strategy=make | copen'   , 'file (quickfix)'],
  \ 'f' : [':TestFile'                          , 'file'],
  \ 'L' : [':TestLast -strategy=make | copen'   , 'last (quickfix)'],
  \ 'l' : [':TestLast'                          , 'last'],
  \ 'N' : [':TestNearest -strategy=make | copen', 'nearest (quickfix)'],
  \ 'n' : [':TestNearest'                       , 'nearest'],
  \ 'S' : [':TestSuite -strategy=make | copen'  , 'suite (quickfix)'],
  \ 's' : [':TestSuite'                         , 'suite'],
  \ }

" Register 'which-key' mappings
call which_key#register('<Space>', "g:which_key_map")

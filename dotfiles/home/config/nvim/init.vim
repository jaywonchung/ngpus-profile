" Ansible managed

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Sections:
"    -> Neovim specific
"    -> Plugins
"    -> General
"    -> VIM user interface
"    -> Colors and Fonts
"    -> Files and backups
"    -> Text, tab and indent related
"    -> Visual mode related
"    -> Moving around, tabs and buffers
"    -> Status line
"    -> Editing mappings
"    -> vimgrep searching and cope displaying
"    -> Spell checking
"    -> Misc
"    -> Helper functions
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Neovim specific
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
if has('nvim')
    " Force to use system python internally which has python-neovim installed
    if exists("$VIRTUAL_ENV") || exists("$CONDA_PREFIX")
        let g:python3_host_prog=substitute(system("which -a python3 | head -n2 | tail -n1"), "\n", '', 'g')
    else
        let g:python3_host_prog=substitute(system("which python3"), "\n", '', 'g')
    endif
    " Disable python2
    let g:loaded_python_provider=1
    let g:python_host_skip_check=1
    " Use true colors
    set termguicolors
    " Load Archlinux specific vimfiles
    set runtimepath^=/usr/share/vim/vimfiles
    " ESC for exit terminal mode
    tnoremap <Esc> <C-\><C-n>
    " Window navigation in terminal mode
    tnoremap <C-h> <C-\><C-n><C-w>h
    tnoremap <C-j> <C-\><C-n><C-w>j
    tnoremap <C-k> <C-\><C-n><C-w>k
    tnoremap <C-l> <C-\><C-n><C-w>l
    " ShaDa
    set shada='1000,f1,<500,:100,/100,h,%
    " Turn off list mode in terminal
    autocmd TermOpen * setlocal nolist
    " Live command preview
    set inccommand=split
endif


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Plugins
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Load plugins early so we can use them.

" Automatically download vim-plug
let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" Activate plugin Manager vim-plug
silent! call plug#begin(stdpath('data') . '/plugged')

" vim colorscheme with neovim in mind
Plug 'freeo/vim-kalisi'

" Transparent background
Plug 'miyakogi/seiya.vim'

" Rust language support
Plug 'rust-lang/rust.vim'

" TOML language
Plug 'cespare/vim-toml'

" CtrlP for fuzzy finder
Plug 'ctrlpvim/ctrlp.vim'

" Git gutter
Plug 'airblade/vim-gitgutter'

" Highlight yank region
Plug 'machakann/vim-highlightedyank'

" Anyfold for smart indent based folding
Plug 'pseewald/vim-anyfold'

" Fold cycling with one key
Plug 'arecarn/vim-fold-cycle'

" Indent text object
Plug 'michaeljsmith/vim-indent-object'

" Undo history visualizer
Plug 'mbbill/undotree'

" NERD Tree with git status
Plug 'scrooloose/nerdtree'
Plug 'Xuyuanp/nerdtree-git-plugin'

" Surroound
Plug 'tpope/vim-surround'

" NERD Commenter
Plug 'scrooloose/nerdcommenter'

" Auto close braces
Plug 'spf13/vim-autoclose'

" Word jumping with vim-snipe
Plug 'yangmillstheory/vim-snipe'

if !has('nvim')
    " Bracketed pasting mode: http://cirw.in/blog/bracketed-paste
    " natively supported in neovim
    Plug 'ConradIrwin/vim-bracketed-paste'
endif

" Language server based auto completion
Plug 'neoclide/coc.nvim', {'branch': 'release'}

" vim-airline for neovim, which can't use powerline
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
let g:airline_detect_modified=1
let g:airline_detect_paste=1
let g:airline_detect_crypt=1
let g:airline_detect_spell=1
let g:airline_detect_iminsert=0
let g:airline_inactive_collapse=1
let g:airline_theme='kalisi'
let g:airline_powerline_fonts=1
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#show_tabs = 0
let g:airline#extensions#tabline#buffers_label = 'Buffers'
let g:airline#extensions#tmuxline#enabled = 0

" Tmuxline
Plug 'edkolev/tmuxline.vim'
" let g:tmuxline_preset='full'
let g:tmuxline_preset = {
      \'a'    : '#S',
      \'win'  : ['#I', '#W'],
      \'cwin'  : ['#I', '#W', '#F'],
      \'y'    : '#H',
      \'z'    : '%H:%M:%S'}

Plug 'yangmillstheory/vim-snipe'

" Initialize plugin system
call plug#end()

" Settings for coc.vim
let g:coc_global_extensions = ['coc-json', 'coc-git', 'coc-rust-analyzer', 'coc-pyright', 'coc-clangd']
" press `tab` to pring up auto completion at a part of words
inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Settings for CtrlP
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlP'
let g:ctrlp_working_path_mode = 'ra'

" Settings for Seiya.vim
let g:seiya_target_groups = has('nvim') ? ['guibg'] : ['ctermbg']
let g:seiya_auto_enable=1 " this is disabled in ginit.vim for neovim-qt, which doesn't have transparent bg

" Settings for anyfold
autocmd Filetype * AnyFoldActivate
set foldlevel=1
set foldminlines=3
"" unfolds the line in which the cursor is located when opening a file
autocmd User anyfoldLoaded normal zv

" NERD Tree configuration
map <C-n> :NERDTreeToggle<CR>

autocmd StdinReadPre * let s:std_in=1
"" open NERDTree if vim starts up on opening a directory
autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists("s:std_in") | exe 'NERDTree' argv()[0] | wincmd p | ene | endif
"" close vim if the only window left open is a NERDTree
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif

" Auto close
let g:autoclose_vim_commentmode=1

" NERD Commenter configuration
"" Add spaces after comment delimiters by default
let g:NERDSpaceDelims = 1

"" Use compact syntax for prettified multi-line comments
let g:NERDCompactSexyComs = 1

"" Align line-wise comment delimiters flush left instead of following code indentation
let g:NERDDefaultAlign = 'left'

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => General
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Sets how many lines of history VIM has to remember
set history=700

" Enable filetype plugins
filetype plugin on
filetype indent on

" Set to auto read when a file is changed from the outside
set autoread

" With a map leader it's possible to do extra key combinations
" like <leader>w saves the current file
let mapleader = "\\"
let g:mapleader = "\\"

" Fast saving
nmap <leader>w :w!<cr>

" :W sudo saves the file
command W w !sudo tee % > /dev/null


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => VIM user interface
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Change cursor style between modes. This works for GUI in vim, and also for terminal in nvim
set guicursor=n-v-c:block-Cursor/lCursor-blinkon0,i-ci:ver25-Cursor/lCursor,r-cr:hor20-Cursor/lCursor
if has('nvim-0.2.0') && !has('nvim-0.2.1')
    " There's bug in 0.2.0 that flipping blinkon0 and blinkon1 on Konsole
    set guicursor=n-v-c:block-Cursor/lCursor-blinkon1,i-ci:ver25-Cursor/lCursor-blinkon1,r-cr:hor20-Cursor/lCursor-blinkon1
endif
" For vim, extra escape sequence is needed for cursor change in terminal
if !has('nvim')
    let &t_SI = "\<Esc>]50;CursorShape=1\x7"
    let &t_SR = "\<Esc>]50;CursorShape=2\x7"
    let &t_EI = "\<Esc>]50;CUrsorShape=0\x7"
endif

" Show hybrid line numbers.
set relativenumber
set number

" Set 3 lines to the cursor - when moving vertically using j/k
set so=3

" Turn on the WiLd menu
set wildmenu

" Ignore compiled files
set wildignore=*.o,*~,*.pyc,*/.git/*,*/.hg/*,*/.svn/*,*/.DS_Store

"Always show current position
set ruler

" Height of the command bar
set cmdheight=1

" A buffer becomes hidden when it is abandoned
set hid

" Configure backspace so it acts as it should act
set backspace=eol,start,indent
set whichwrap+=<,>,h,l

" Ignore case when searching
set ignorecase

" When searching try to be smart about cases
set smartcase

" Highlight search results
set hlsearch

" Makes search act like search in modern browsers
set incsearch

" Don't redraw while executing macros (good performance config)
set lazyredraw

" For regular expressions turn magic on
set magic

" Show matching brackets when text indicator is over them
set showmatch
" How many tenths of a second to blink when matching brackets
set mat=2

" No annoying sound on errors
set noerrorbells
set novisualbell
set t_vb=
set tm=500

" Add a bit extra margin to the left
set foldcolumn=1

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Colors and Fonts
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Enable syntax highlighting
syntax enable

silent! colorscheme kalisi
set background=dark
set t_Co=256
let &t_AB="\e[48;5;%dm"
let &t_AF="\e[38;5;%dm"

" kalisi doesn't provide the terminal color palette for neovim
if has('nvim')
    " Soft black palette from Konsole
    let g:terminal_color_0  = '#3f3f3f'
    let g:terminal_color_1  = '#705050'
    let g:terminal_color_2  = '#60b48a'
    let g:terminal_color_3  = '#dfaf8f'
    let g:terminal_color_4  = '#9ab8d7'
    let g:terminal_color_5  = '#dc8cc3'
    let g:terminal_color_6  = '#8cd0d3'
    let g:terminal_color_7  = '#dcdccc'
    let g:terminal_color_8  = '#709080'
    let g:terminal_color_9  = '#dca3a3'
    let g:terminal_color_10 = '#72d5a3'
    let g:terminal_color_11 = '#f0dfaf'
    let g:terminal_color_12 = '#94bff3'
    let g:terminal_color_13 = '#ec93d3'
    let g:terminal_color_14 = '#93e0e3'
    let g:terminal_color_15 = '#ffffff'
endif

" Set extra options when running in GUI mode
if has("gui_running")
    set guioptions-=T
    set guioptions+=e
    set guitablabel=%M\ %t
endif

" Set utf8 as standard encoding and en_US as the standard language
set encoding=utf8

" For multi-byte character support (CJK support, for example)
set fileencodings=ucs-bom,utf-8,cp936,big5,euc-jp,euc-kr,gb18030,latin1

" Use Unix as the standard file type
set ffs=unix,dos,mac


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Files, backups and undo
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Turn backup off, since most stuff is in SVN, git et.c anyway...
set nobackup
set nowb
set noswapfile

" Toggle Undotree window
map <leader>u :UndotreeToggle<cr>

" Enable persistent undo
if has("persistent_undo")
    set undodir=~/.vim/undo
    set undofile
endif

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Text, tab and indent related
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Use spaces instead of tabs
set expandtab

" Be smart when using tabs ;)
set smarttab

" 1 tab == 4 spaces
set shiftwidth=4
set tabstop=4

" Linebreak on 500 characters
set lbr
set tw=500

set ai "Auto indent
set si "Smart indent
set wrap "Wrap lines

" Show tabs, trailing space and nbsp
set list
set listchars=tab:➪\ ,trail:␣,nbsp:☠


""""""""""""""""""""""""""""""
" => Visual mode related
""""""""""""""""""""""""""""""
" Visual mode pressing * or # searches for the current selection
" Super useful! From an idea by Michael Naumann
vnoremap <silent> * :call VisualSelection('f')<CR>
vnoremap <silent> # :call VisualSelection('b')<CR>


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Moving around, tabs, windows and buffers
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Treat long lines as break lines (useful when moving around in them)
map j gj
map k gk

" Map <Space> to / (search) and Ctrl-<Space> to ? (backwards search)
map <space> /
map <c-space> ?

" Disable highlight when <leader><cr> is pressed
map <silent> <leader><cr> :noh<cr>

" Smart way to move between windows
map <C-j> <C-W>j
map <C-k> <C-W>k
map <C-h> <C-W>h
map <C-l> <C-W>l

" Close the current buffer
map <leader>bd :Bclose<cr>

" Close all the buffers
map <leader>ba :bufdo bd<cr>

" Move between buffers
map <A-h> :bprevious<cr>
map <A-l> :bnext<cr>

" Opens a new buffer with the current buffer's path
" Super useful when editing files in the same directory
map <leader>te :edit <c-r>=expand("%:p:h")<cr>/

" Switch CWD to the directory of the open buffer
map <leader>cd :cd %:p:h<cr>:pwd<cr>

" Specify the behavior when switching between buffers
try
  set switchbuf=useopen,usetab,newtab
  set stal=2
catch
endtry

" Return to last edit position when opening files (You want this!)
autocmd BufReadPost *
     \ if line("'\"") > 0 && line("'\"") <= line("$") |
     \   exe "normal! g`\"" |
     \ endif

" Remember info about open buffers on close
set viminfo^=%


""""""""""""""""""""""""""""""
" => Status line
""""""""""""""""""""""""""""""

" Always show the status line
set laststatus=2

" Hide the default mode text (e.g. -- INSERT -- ), which is provided by powerline
set noshowmode

" Show (partial) command in status line.
set showcmd

" Press space to clear search highlighting and any message already displayed
nnoremap <silent> <Space> :silent noh<Bar>echo<CR>


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Editing mappings
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Remap VIM 0 to first non-blank character
map 0 ^

" Move a line of text using ALT+[jk] or Comamnd+[jk] on mac
nmap <M-j> mz:m+<cr>`z
nmap <M-k> mz:m-2<cr>`z
vmap <M-j> :m'>+<cr>`<my`>mzgv`yo`z
vmap <M-k> :m'<-2<cr>`>my`<mzgv`yo`z

if has("mac") || has("macunix")
  nmap <D-j> <M-j>
  nmap <D-k> <M-k>
  vmap <D-j> <M-j>
  vmap <D-k> <M-k>
endif

" Delete trailing white space on save, useful for Python and CoffeeScript ;)
func! DeleteTrailingWS()
  exe "normal mz"
  %s/\s\+$//ge
  exe "normal `z"
endfunc
autocmd BufWrite *.py :call DeleteTrailingWS()
autocmd BufWrite *.coffee :call DeleteTrailingWS()


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => vimgrep searching and cope displaying
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" When you press gv you vimgrep after the selected text
vnoremap <silent> gv :call VisualSelection('gv')<CR>

" Open vimgrep and put the cursor in the right position
map <leader>g :vimgrep // **/*.<left><left><left><left><left><left><left>

" Vimgreps in the current file
map <leader><space> :vimgrep // <C-R>%<C-A><right><right><right><right><right><right><right><right><right>

" When you press <leader>r you can search and replace the selected text
vnoremap <silent> <leader>r :call VisualSelection('replace')<CR>

" Do :help cope if you are unsure what cope is. It's super useful!
"
" When you search with vimgrep, display your results in cope by doing:
"   <leader>cc
"
" To go to the next search result do:
"   <leader>n
"
" To go to the previous search results do:
"   <leader>p
"
map <leader>cc :botright cope<cr>
map <leader>co ggVGy:tabnew<cr>:set syntax=qf<cr>pgg
map <leader>n :cn<cr>
map <leader>p :cp<cr>


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Spell checking
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Pressing ,ss will toggle and untoggle spell checking
map <leader>ss :setlocal spell!<cr>

" Shortcuts using <leader>
map <leader>sn ]s
map <leader>sp [s
map <leader>sa zg
map <leader>s? z=


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Misc
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Remove the Windows ^M - when the encodings gets messed up
noremap <Leader>m mmHmt:%s/<C-V><cr>//ge<cr>'tzt'm

" Quickly open a buffer for scripbble
map <leader>q :e /tmp/workspace<cr>

" Toggle paste mode on and off
map <leader>pp :setlocal paste!<cr>


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Helper functions
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! CmdLine(str)
    exe "menu Foo.Bar :" . a:str
    emenu Foo.Bar
    unmenu Foo
endfunction

function! VisualSelection(direction) range
    let l:saved_reg = @"
    execute "normal! vgvy"

    let l:pattern = escape(@", '\\/.*$^~[]')
    let l:pattern = substitute(l:pattern, "\n$", "", "")

    if a:direction == 'b'
        execute "normal ?" . l:pattern . "^M"
    elseif a:direction == 'gv'
        call CmdLine("vimgrep " . '/'. l:pattern . '/' . ' **/*.')
    elseif a:direction == 'replace'
        call CmdLine("%s" . '/'. l:pattern . '/')
    elseif a:direction == 'f'
        execute "normal /" . l:pattern . "^M"
    endif

    let @/ = l:pattern
    let @" = l:saved_reg
endfunction


" Returns true if paste mode is enabled
function! HasPaste()
    if &paste
        return 'PASTE MODE  '
    en
    return ''
endfunction

" Don't close window, when deleting a buffer
command! Bclose call <SID>BufcloseCloseIt()
function! <SID>BufcloseCloseIt()
   let l:currentBufNum = bufnr("%")
   let l:alternateBufNum = bufnr("#")

   if buflisted(l:alternateBufNum)
     buffer #
   else
     bnext
   endif

   if bufnr("%") == l:currentBufNum
     new
   endif

   if buflisted(l:currentBufNum)
     execute("bdelete! ".l:currentBufNum)
   endif
endfunction

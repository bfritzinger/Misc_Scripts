"===============================================================================
" .vimrc - Vim Configuration
"===============================================================================

"-------------------------------------------------------------------------------
" General Settings
"-------------------------------------------------------------------------------
set nocompatible              " Use Vim settings, not Vi
filetype plugin indent on     " Enable file type detection
syntax enable                 " Enable syntax highlighting

set encoding=utf-8            " Use UTF-8 encoding
set fileencoding=utf-8
set termencoding=utf-8

set hidden                    " Allow switching buffers without saving
set autoread                  " Reload files changed outside vim
set backspace=indent,eol,start " Make backspace work as expected

"-------------------------------------------------------------------------------
" UI Settings
"-------------------------------------------------------------------------------
set number                    " Show line numbers
set relativenumber            " Relative line numbers
set cursorline                " Highlight current line
set showcmd                   " Show command in bottom bar
set showmode                  " Show current mode
set wildmenu                  " Visual autocomplete for command menu
set wildmode=longest:full,full
set lazyredraw                " Don't redraw during macros
set showmatch                 " Highlight matching brackets
set scrolloff=8               " Keep 8 lines above/below cursor
set sidescrolloff=8           " Keep 8 columns left/right of cursor
set signcolumn=yes            " Always show sign column
set colorcolumn=80,120        " Show column markers

" Colors
set background=dark
set t_Co=256

" Status line
set laststatus=2
set statusline=
set statusline+=%#PmenuSel#
set statusline+=\ %f          " File path
set statusline+=%m            " Modified flag
set statusline+=%r            " Readonly flag
set statusline+=%=            " Right align
set statusline+=\ %y          " File type
set statusline+=\ %{&fileencoding?&fileencoding:&encoding}
set statusline+=\ [%{&fileformat}]
set statusline+=\ %l:%c       " Line:Column
set statusline+=\ %p%%        " Percentage through file
set statusline+=\ 

"-------------------------------------------------------------------------------
" Indentation
"-------------------------------------------------------------------------------
set autoindent                " Copy indent from current line
set smartindent               " Smart autoindenting
set expandtab                 " Use spaces instead of tabs
set shiftwidth=4              " Spaces for autoindent
set tabstop=4                 " Spaces per tab
set softtabstop=4             " Spaces per tab in insert mode
set shiftround                " Round indent to multiple of shiftwidth

"-------------------------------------------------------------------------------
" Search
"-------------------------------------------------------------------------------
set incsearch                 " Search as you type
set hlsearch                  " Highlight search results
set ignorecase                " Case insensitive search
set smartcase                 " Case sensitive if uppercase present

" Clear search highlighting with Escape
nnoremap <Esc> :nohlsearch<CR>

"-------------------------------------------------------------------------------
" Files and Backup
"-------------------------------------------------------------------------------
set nobackup                  " Don't create backup files
set nowritebackup
set noswapfile                " Don't create swap files
set undofile                  " Persistent undo
set undodir=~/.vim/undodir    " Undo file location

"-------------------------------------------------------------------------------
" Key Mappings
"-------------------------------------------------------------------------------
" Set leader key to space
let mapleader = " "

" Quick save
nnoremap <leader>w :w<CR>

" Quick quit
nnoremap <leader>q :q<CR>

" Quick save and quit
nnoremap <leader>x :x<CR>

" Split navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Resize splits
nnoremap <C-Up> :resize +2<CR>
nnoremap <C-Down> :resize -2<CR>
nnoremap <C-Left> :vertical resize -2<CR>
nnoremap <C-Right> :vertical resize +2<CR>

" Buffer navigation
nnoremap <leader>bn :bnext<CR>
nnoremap <leader>bp :bprevious<CR>
nnoremap <leader>bd :bdelete<CR>
nnoremap <leader>bl :ls<CR>

" Tab navigation
nnoremap <leader>tn :tabnew<CR>
nnoremap <leader>tc :tabclose<CR>
nnoremap <Tab> :tabnext<CR>
nnoremap <S-Tab> :tabprevious<CR>

" Move lines up/down
nnoremap <A-j> :m .+1<CR>==
nnoremap <A-k> :m .-2<CR>==
vnoremap <A-j> :m '>+1<CR>gv=gv
vnoremap <A-k> :m '<-2<CR>gv=gv

" Keep visual selection when indenting
vnoremap < <gv
vnoremap > >gv

" Yank to end of line (like D and C)
nnoremap Y y$

" Center screen after movements
nnoremap n nzzzv
nnoremap N Nzzzv
nnoremap <C-d> <C-d>zz
nnoremap <C-u> <C-u>zz

" Quick access to config
nnoremap <leader>ve :edit $MYVIMRC<CR>
nnoremap <leader>vr :source $MYVIMRC<CR>

" Toggle line numbers
nnoremap <leader>ln :set number! relativenumber!<CR>

" Toggle paste mode
set pastetoggle=<F2>

"-------------------------------------------------------------------------------
" File Type Settings
"-------------------------------------------------------------------------------
" YAML
autocmd FileType yaml setlocal ts=2 sw=2 sts=2 expandtab

" Python
autocmd FileType python setlocal ts=4 sw=4 sts=4 expandtab
autocmd FileType python setlocal colorcolumn=88

" JavaScript/TypeScript
autocmd FileType javascript,typescript,json setlocal ts=2 sw=2 sts=2 expandtab

" Markdown
autocmd FileType markdown setlocal wrap linebreak spell

" Makefile (use tabs)
autocmd FileType make setlocal noexpandtab

" Shell scripts
autocmd FileType sh,bash setlocal ts=4 sw=4 sts=4 expandtab

"-------------------------------------------------------------------------------
" Plugins (vim-plug)
"-------------------------------------------------------------------------------
" Install vim-plug if not found
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
endif

" Run PlugInstall if there are missing plugins
autocmd VimEnter * if len(filter(values(g:plugs), '!isdirectory(v:val.dir)'))
  \| PlugInstall --sync | source $MYVIMRC
\| endif

call plug#begin('~/.vim/plugged')

" Essential plugins
Plug 'tpope/vim-sensible'        " Sensible defaults
Plug 'tpope/vim-commentary'      " Easy commenting (gcc)
Plug 'tpope/vim-surround'        " Surround text objects
Plug 'tpope/vim-fugitive'        " Git integration
Plug 'airblade/vim-gitgutter'    " Git diff in gutter

" File navigation
Plug 'preservim/nerdtree'        " File tree
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'          " Fuzzy finder

" Appearance
Plug 'morhetz/gruvbox'           " Color scheme
Plug 'vim-airline/vim-airline'   " Status line

" Language support
Plug 'sheerun/vim-polyglot'      " Language pack

call plug#end()

"-------------------------------------------------------------------------------
" Plugin Configuration
"-------------------------------------------------------------------------------
" NERDTree
nnoremap <leader>n :NERDTreeToggle<CR>
nnoremap <leader>nf :NERDTreeFind<CR>
let NERDTreeShowHidden=1
let NERDTreeIgnore=['\.git$', '\.pyc$', '__pycache__', 'node_modules']

" FZF
nnoremap <leader>ff :Files<CR>
nnoremap <leader>fg :GFiles<CR>
nnoremap <leader>fb :Buffers<CR>
nnoremap <leader>fs :Rg<CR>
nnoremap <leader>fh :History<CR>

" Gruvbox
silent! colorscheme gruvbox

" Airline
let g:airline#extensions#tabline#enabled = 1
let g:airline_powerline_fonts = 0

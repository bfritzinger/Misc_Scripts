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

set scrolloff=8
set sidescrolloff=8

set mouse=a
"-------------------------------------------------------------------------------
" UI Settings
"-------------------------------------------------------------------------------
set number                    " Show line numbers
set cursorline                " Highlight current line
set showcmd                   " Show command in bottom bar
set showmode                  " Show current mode
set wildmenu                  " Visual autocomplete for command menu
set wildmode=longest:full,full
set lazyredraw                " Don't redraw during macros
set showmatch                 " Highlight matching brackets
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

"-------------------------------------------------------------------------------
" Files and Backup
"-------------------------------------------------------------------------------
set nobackup                  " Don't create backup files
set nowritebackup
set noswapfile                " Don't create swap files

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

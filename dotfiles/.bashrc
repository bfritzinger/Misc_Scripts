#===============================================================================
# .bashrc - Bash Configuration
#===============================================================================
# shellcheck shell=bash

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

#-------------------------------------------------------------------------------
# History Configuration
#-------------------------------------------------------------------------------
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=100000
HISTFILESIZE=200000
HISTTIMEFORMAT="%F %T  "
HISTIGNORE='ls:ll:la:cd:pwd:exit:clear:c:q:h:bg:fg:history'
shopt -s histappend
# Share history across concurrent shells: append after each command, then
# pull in entries written by other shells. Preserves any existing PROMPT_COMMAND.
PROMPT_COMMAND="history -a; history -n;${PROMPT_COMMAND:+ $PROMPT_COMMAND}"

#-------------------------------------------------------------------------------
# Shell Options
#-------------------------------------------------------------------------------
shopt -s checkwinsize   # Update window size after each command
shopt -s globstar       # ** matches all files and directories recursively
shopt -s cdspell        # Autocorrect typos in cd
shopt -s dirspell       # Autocorrect directory names
shopt -s autocd         # Type directory name to cd into it
shopt -s cmdhist        # Save multi-line commands as one history entry
shopt -s checkjobs      # Warn about running jobs on exit
shopt -s nocaseglob 2>/dev/null  # Case-insensitive globs (bash >=4)

#-------------------------------------------------------------------------------
# Environment Variables
#-------------------------------------------------------------------------------
export EDITOR=vim
export VISUAL=vim
export PAGER=less
export LESS='-R -F -X'

# PATH additions, idempotent (re-sourcing won't duplicate entries).
_path_prepend() {
    [ -d "$1" ] && [[ ":$PATH:" != *":$1:"* ]] && PATH="$1:$PATH"
}
_path_append() {
    [ -d "$1" ] && [[ ":$PATH:" != *":$1:"* ]] && PATH="$PATH:$1"
}

_path_prepend "$HOME/.local/bin"
_path_prepend "$HOME/bin"

# Go
if [ -d "/usr/local/go" ]; then
    export GOPATH="$HOME/go"
    _path_append "/usr/local/go/bin"
    _path_append "$GOPATH/bin"
fi

# Rust
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

# Kubernetes — $HOME/.kube/config is already kubectl's default. Only override
# here if you want multiple configs merged, e.g.:
#   export KUBECONFIG="$HOME/.kube/config:$HOME/.kube/work-config"

# Python: don't write .pyc files (keeps source trees tidy).
export PYTHONDONTWRITEBYTECODE=1

unset -f _path_prepend _path_append

#-------------------------------------------------------------------------------
# Prompt Configuration
#-------------------------------------------------------------------------------
# Colors
RED='\[\033[0;31m\]'
GREEN='\[\033[0;32m\]'
YELLOW='\[\033[0;33m\]'
BLUE='\[\033[0;34m\]'
PURPLE='\[\033[0;35m\]'
CYAN='\[\033[0;36m\]'
WHITE='\[\033[0;37m\]'
BOLD='\[\033[1m\]'
RESET='\[\033[0m\]'

# Git branch in prompt. Uses symbolic-ref (fast, no fork to sed) and falls
# back to a short SHA when in detached HEAD. Stays silent outside a repo.
parse_git_branch() {
    local b
    b=$(git symbolic-ref --short HEAD 2>/dev/null) || \
        b=$(git rev-parse --short HEAD 2>/dev/null) || return
    printf ' (%s)' "$b"
}

# Optional kube context in prompt — disabled by default (forks kubectl on every
# prompt redraw, which is noticeable). Add $(parse_kube_context) to PS1 below
# if you want it.
# parse_kube_context() {
#     command -v kubectl &>/dev/null || return
#     local ctx; ctx=$(kubectl config current-context 2>/dev/null) || return
#     printf ' [k8s:%s]' "$ctx"
# }

# Set prompt based on user
if [ "$EUID" -eq 0 ]; then
    PS1="${RED}\u${RESET}@${CYAN}\h${RESET}:${BLUE}\w${RESET}${YELLOW}\$(parse_git_branch)${RESET}\n# "
else
    PS1="${GREEN}\u${RESET}@${CYAN}\h${RESET}:${BLUE}\w${RESET}${YELLOW}\$(parse_git_branch)${RESET}\n\$ "
fi

#-------------------------------------------------------------------------------
# Completion
#-------------------------------------------------------------------------------
# Enable programmable completion
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# kubectl completion
if command -v kubectl &>/dev/null; then
    source <(kubectl completion bash)
    complete -o default -F __start_kubectl k
fi

# Helm completion
if command -v helm &>/dev/null; then
    source <(helm completion bash)
fi

# Docker completion
if command -v docker &>/dev/null && [ -f /usr/share/bash-completion/completions/docker ]; then
    . /usr/share/bash-completion/completions/docker
fi

#-------------------------------------------------------------------------------
# Load Additional Configs
#-------------------------------------------------------------------------------
# Load aliases
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# Load local/private config (not in git)
if [ -f ~/.bashrc.local ]; then
    . ~/.bashrc.local
fi

# Load work-specific config
if [ -f ~/.bashrc.work ]; then
    . ~/.bashrc.work
fi

#-------------------------------------------------------------------------------
# Useful Functions
#-------------------------------------------------------------------------------

# Create directory and cd into it
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Extract various archive formats
extract() {
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.tar.xz)    tar xJf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar x "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *)           echo "'$1' cannot be extracted" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Quick backup of a file
backup() {
    cp "$1"{,.bak.$(date +%Y%m%d_%H%M%S)}
}

# Find process by name
psgrep() {
    ps aux | grep -v grep | grep -i "$1"
}

# `myip` lives in .bash_aliases (as an alias) — defining it here as a function
# was unreachable since aliases win over functions on lookup.

# Quick HTTP server
serve() {
    local port="${1:-8000}"
    python3 -m http.server "$port"
}

# Docker cleanup
docker-cleanup() {
    echo "Removing stopped containers..."
    docker container prune -f
    echo "Removing unused images..."
    docker image prune -f
    echo "Removing unused volumes..."
    docker volume prune -f
    echo "Removing unused networks..."
    docker network prune -f
    echo "Done!"
}

# Weather
weather() {
    curl -s "wttr.in/${1:-}"
}

#-------------------------------------------------------------------------------
# Welcome Message (optional)
#-------------------------------------------------------------------------------
# Uncomment to show system info on login
# echo ""
# echo "  Host: $(hostname)"
# echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
# echo "  Kernel: $(uname -r)"
# echo "  Uptime: $(uptime -p)"
# echo ""

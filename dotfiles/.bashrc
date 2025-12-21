#===============================================================================
# .bashrc - Bash Configuration
#===============================================================================

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

#-------------------------------------------------------------------------------
# History Configuration
#-------------------------------------------------------------------------------
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=10000
HISTFILESIZE=20000
HISTTIMEFORMAT="%F %T "
shopt -s histappend

#-------------------------------------------------------------------------------
# Shell Options
#-------------------------------------------------------------------------------
shopt -s checkwinsize   # Update window size after each command
shopt -s globstar       # ** matches all files and directories recursively
shopt -s cdspell        # Autocorrect typos in cd
shopt -s dirspell       # Autocorrect directory names
shopt -s autocd         # Type directory name to cd into it

#-------------------------------------------------------------------------------
# Environment Variables
#-------------------------------------------------------------------------------
export EDITOR=vim
export VISUAL=vim
export PAGER=less
export LESS='-R -F -X'

# Local bin paths
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

# Go
if [ -d "/usr/local/go" ]; then
    export GOPATH="$HOME/go"
    export PATH="$PATH:/usr/local/go/bin:$GOPATH/bin"
fi

# Rust
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi

# Kubernetes
export KUBECONFIG="$HOME/.kube/config"

# Python
export PYTHONDONTWRITEBYTECODE=1

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

# Git branch in prompt
parse_git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

# Kubernetes context in prompt (optional - can be slow)
parse_kube_context() {
    if command -v kubectl &>/dev/null && [ -f "$KUBECONFIG" ]; then
        local ctx=$(kubectl config current-context 2>/dev/null)
        [ -n "$ctx" ] && echo " [k8s:${ctx}]"
    fi
}

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

# Get public IP
myip() {
    curl -s ifconfig.me
    echo ""
}

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

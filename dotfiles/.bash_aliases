#===============================================================================
# .bash_aliases - Alias Definitions
#===============================================================================
# shellcheck shell=bash

#-------------------------------------------------------------------------------
# Navigation
#-------------------------------------------------------------------------------
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias -- -='cd -'

#-------------------------------------------------------------------------------
# List Directory
#-------------------------------------------------------------------------------
alias ls='ls --color=auto'
alias ll='ls -alFh'
alias la='ls -A'
alias l='ls -CF'
alias lt='ls -alFht'           # Sort by time
alias lS='ls -alFhS'           # Sort by size
alias ltr='ls -alFhtr'         # Sort by time, reversed

#-------------------------------------------------------------------------------
# Safety Nets
#-------------------------------------------------------------------------------
# `rm -I` prompts once for 3+ files or recursive deletes — less annoying than
# `-i` (which prompts per file) but still catches `rm -rf *` accidents.
alias rm='rm -I --preserve-root'
alias cp='cp -i'
alias mv='mv -i'
alias ln='ln -i'

# `-p` (no-error on existing) and `-v` (verbose) for visibility.
alias mkdir='mkdir -pv'

#-------------------------------------------------------------------------------
# Grep
#-------------------------------------------------------------------------------
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

#-------------------------------------------------------------------------------
# System
#-------------------------------------------------------------------------------
alias df='df -h'
alias du='du -h'
alias free='free -h'
# `top` left alone on purpose — silently rebinding it surprises you a year
# later. Type `htop` directly when you want it.
alias meminfo='free -h -l -t'
alias cpuinfo='lscpu'
alias diskinfo='lsblk -f'
# `ss` replaces deprecated `netstat`; same flag semantics for these cases.
alias ports='ss -tulpn'
alias listening='ss -tlnp | grep LISTEN'
alias connections='ss -tan state established'

# Systemd
alias sc='sudo systemctl'
alias scs='sudo systemctl status'
alias scr='sudo systemctl restart'
alias scl='sudo systemctl list-units'
alias jcl='journalctl'
alias jcf='journalctl -f'
alias jcu='journalctl -u'

#-------------------------------------------------------------------------------
# Docker
#-------------------------------------------------------------------------------
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dex='docker exec -it'
alias dl='docker logs'
alias dlf='docker logs -f'
alias drm='docker rm'
alias drmi='docker rmi'
alias dprune='docker system prune -af'
alias dstop='docker stop $(docker ps -q)'
alias dclean='docker system prune -af && docker volume prune -f'

# Docker compose shortcuts
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'
alias dcr='docker compose restart'
alias dcps='docker compose ps'

#-------------------------------------------------------------------------------
# Kubernetes
#-------------------------------------------------------------------------------
alias k='kubectl'
alias kx='kubectx'
alias kn='kubens'

# Get resources
alias kg='kubectl get'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgd='kubectl get deployments'
alias kgs='kubectl get services'
alias kgn='kubectl get nodes'
alias kgns='kubectl get namespaces'
alias kgpv='kubectl get pv'
alias kgpvc='kubectl get pvc'
alias kgcm='kubectl get configmaps'
alias kgsec='kubectl get secrets'
alias kging='kubectl get ingress'

# Describe
alias kd='kubectl describe'
alias kdp='kubectl describe pod'
alias kdn='kubectl describe node'

# Logs
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias klt='kubectl logs --tail=100'

# Exec
alias kex='kubectl exec -it'
alias kexsh='kubectl exec -it -- /bin/sh'
alias kexbash='kubectl exec -it -- /bin/bash'

# Apply/Delete
alias ka='kubectl apply -f'
alias kdel='kubectl delete'
alias kdelp='kubectl delete pod'

# Context and namespace
alias kcg='kubectl config get-contexts'
alias kcu='kubectl config use-context'
alias kcn='kubectl config set-context --current --namespace'

# Watch
alias kw='kubectl get pods -w'
alias kwa='kubectl get pods -A -w'

# Port forward
alias kpf='kubectl port-forward'

# Top
alias ktop='kubectl top'
alias ktopp='kubectl top pods'
alias ktopn='kubectl top nodes'

#-------------------------------------------------------------------------------
# Git
#-------------------------------------------------------------------------------
alias g='git'
alias gs='git status'
alias ga='git add'
alias gaa='git add -A'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpl='git pull'
alias gf='git fetch'
alias gfa='git fetch --all'
alias gb='git branch'
alias gba='git branch -a'
alias gbd='git branch -d'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gm='git merge'
alias gr='git rebase'
alias gri='git rebase -i'
alias gl='git log --oneline -20'
alias glog='git log --oneline --graph --decorate'
alias gd='git diff'
alias gds='git diff --staged'
alias gst='git stash'
alias gstp='git stash pop'
alias gstl='git stash list'
alias grh='git reset HEAD'
# `grhh` and `gclean` discard uncommitted work irreversibly. No shortcut on
# purpose — type them in full so the muscle memory doesn't trip you.
# alias grhh='git reset HEAD --hard'
# alias gclean='git clean -fd'

#-------------------------------------------------------------------------------
# Python
#-------------------------------------------------------------------------------
alias py='python3'
alias pip='python3 -m pip'
alias venv='python3 -m venv'
# Try `.venv/` first (modern convention), fall back to `venv/`.
alias activate='source .venv/bin/activate 2>/dev/null || source venv/bin/activate'
alias pipreq='pip freeze > requirements.txt'
alias pipinstall='pip install -r requirements.txt'

#-------------------------------------------------------------------------------
# Network
#-------------------------------------------------------------------------------
alias ping='ping -c 5'
alias fastping='ping -c 100 -s.2'
alias myip='curl -s ifconfig.me && echo'
# shellcheck disable=SC2142  # $1 is awk's, not a shell positional
alias localip="hostname -I | awk '{print \$1}'"
alias ips="ip -c a"
# `listening` and `connections` moved to the System section (using `ss`).

#-------------------------------------------------------------------------------
# SSH
#-------------------------------------------------------------------------------
alias sshconfig='vim ~/.ssh/config'
alias sshkey='cat ~/.ssh/id_ed25519.pub'
alias sshcopy='xclip -sel clip < ~/.ssh/id_ed25519.pub && echo "SSH key copied to clipboard"'

#-------------------------------------------------------------------------------
# Misc
#-------------------------------------------------------------------------------
alias c='clear'
alias h='history'
alias j='jobs -l'
alias path='echo -e ${PATH//:/\\n}'
alias now='date +"%Y-%m-%d %H:%M:%S"'
alias week='date +%V'
alias reload='source ~/.bashrc'
alias editbash='vim ~/.bashrc'
alias editalias='vim ~/.bash_aliases'

# Quick edit common configs
alias vimrc='vim ~/.vimrc'
alias tmuxconf='vim ~/.tmux.conf'

# Tar shortcuts
alias tarc='tar -czvf'
alias tarx='tar -xzvf'
alias tart='tar -tzvf'

# Find shortcuts
alias fd='find . -type d -name'
alias ff='find . -type f -name'

# Disk usage
alias duh='du -h --max-depth=1 | sort -hr'
alias duf='du -sh * | sort -hr'

# Update system (Debian/Ubuntu)
alias update='sudo apt update && sudo apt upgrade -y'
# `autoremove` left interactive — `-y` has silently removed wanted packages
# (kernel images, etc.). Run `sudo apt autoremove` and review the list.
alias autoremove='sudo apt autoremove'

# Watch with 1 second interval
alias watch='watch -n 1'

# `make='make -j$(nproc)'` removed: many Makefiles have race conditions and
# silently break under parallel build. Pass `-j$(nproc)` explicitly when safe.

# Clipboard (requires xclip)
alias pbcopy='xclip -selection clipboard'
alias pbpaste='xclip -selection clipboard -o'

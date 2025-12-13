#!/bin/bash
#
# distribute-aliases.sh
# Distributes bash aliases to all nodes listed in /etc/hosts
# Supports parallel deployment for faster execution
#

# ============================================================
# CONFIGURATION - Add your aliases here
# ============================================================
ALIASES=(
    # ------------------------------
    # Navigation & Directory
    # ------------------------------
    "alias ll='ls -lAhF --color=auto'"
    "alias la='ls -A'"
    "alias l='ls -CF'"
    "alias ls='ls --color=auto'"
    "alias ..='cd ..'"
    "alias ...='cd ../..'"
    "alias ....='cd ../../..'"
    "alias ~='cd ~'"
    "alias -- -='cd -'"
    "alias mkdir='mkdir -pv'"
    "alias tree='tree -C'"

    # ------------------------------
    # File Operations
    # ------------------------------
    "alias cp='cp -iv'"
    "alias mv='mv -iv'"
    "alias rm='rm -Iv'"
    "alias ln='ln -iv'"
    "alias chmod='chmod -v'"
    "alias chown='chown -v'"
    "alias df='df -hT'"
    "alias du='du -h'"
    "alias dus='du -sh * | sort -h'"
    "alias free='free -h'"

    # ------------------------------
    # Search & Find
    # ------------------------------
    "alias grep='grep --color=auto'"
    "alias egrep='egrep --color=auto'"
    "alias fgrep='fgrep --color=auto'"
    "alias ff='find . -type f -name'"
    "alias fd='find . -type d -name'"
    "alias h='history'"
    "alias hg='history | grep'"

    # ------------------------------
    # System & Process
    # ------------------------------
    "alias s='sudo'"
    "alias ps='ps auxf'"
    "alias psg='ps aux | grep -v grep | grep -i'"
    "alias top='htop 2>/dev/null || top'"
    "alias kill9='kill -9'"
    "alias meminfo='free -h -l -t'"
    "alias cpuinfo='lscpu'"
    "alias temp='vcgencmd measure_temp 2>/dev/null || sensors 2>/dev/null || cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null'"

    # ------------------------------
    # Networking
    # ------------------------------
    "alias ports='ss -tulpn'"
    "alias listening='ss -tulpn | grep LISTEN'"
    "alias myip='curl -s ifconfig.me'"
    "alias localip=\"ip -4 addr show | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | grep -v 127.0.0.1\""
    "alias ping='ping -c 5'"
    "alias pingg='ping google.com'"
    "alias wget='wget -c'"
    "alias speedtest='curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 -'"
    "alias flushdns='sudo systemd-resolve --flush-caches'"

    # ------------------------------
    # Package Management (Debian/Ubuntu)
    # ------------------------------
    "alias update='sudo apt update && sudo apt upgrade -y'"
    "alias install='sudo apt install'"
    "alias remove='sudo apt remove'"
    "alias autoremove='sudo apt autoremove -y'"
    "alias search='apt search'"
    "alias cleanup='sudo apt autoremove -y && sudo apt autoclean'"

    # ------------------------------
    # Systemd & Services
    # ------------------------------
    "alias sc='sudo systemctl'"
    "alias scstart='sudo systemctl start'"
    "alias scstop='sudo systemctl stop'"
    "alias screstart='sudo systemctl restart'"
    "alias scstatus='sudo systemctl status'"
    "alias scenable='sudo systemctl enable'"
    "alias scdisable='sudo systemctl disable'"
    "alias sclog='journalctl -xeu'"
    "alias jlog='journalctl -f'"
    "alias failed='systemctl --failed'"

    # ------------------------------
    # Docker
    # ------------------------------
    "alias d='docker'"
    "alias dc='docker compose'"
    "alias dps='docker ps --format \"table {{.Names}}\\t{{.Status}}\\t{{.Ports}}\"'"
    "alias dpsa='docker ps -a --format \"table {{.Names}}\\t{{.Status}}\\t{{.Ports}}\"'"
    "alias dimg='docker images'"
    "alias dlog='docker logs -f'"
    "alias dexec='docker exec -it'"
    "alias dstop='docker stop \$(docker ps -q)'"
    "alias dprune='docker system prune -af'"
    "alias dvprune='docker volume prune -f'"
    "alias dstats='docker stats --no-stream'"
    "alias dtop='docker stats --format \"table {{.Name}}\\t{{.CPUPerc}}\\t{{.MemUsage}}\"'"
    "alias dclean='docker system prune -af && docker volume prune -f'"
    "alias dnet='docker network ls'"
    "alias dinspect='docker inspect'"
    "alias dip='docker inspect -f \"{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}\"'"

    # ------------------------------
    # Kubernetes / k3s
    # ------------------------------
    "alias k='kubectl'"
    "alias kgp='kubectl get pods'"
    "alias kgpa='kubectl get pods -A'"
    "alias kgn='kubectl get nodes'"
    "alias kgs='kubectl get svc'"
    "alias kgd='kubectl get deployments'"
    "alias kgi='kubectl get ingress'"
    "alias kgpv='kubectl get pv'"
    "alias kgpvc='kubectl get pvc'"
    "alias kga='kubectl get all'"
    "alias kgaa='kubectl get all -A'"
    "alias kdesc='kubectl describe'"
    "alias klog='kubectl logs -f'"
    "alias kexec='kubectl exec -it'"
    "alias kaf='kubectl apply -f'"
    "alias kdf='kubectl delete -f'"
    "alias kctx='kubectl config get-contexts'"
    "alias kns='kubectl config set-context --current --namespace'"
    "alias ktop='kubectl top'"
    "alias kwatch='watch -n1 kubectl get pods'"
    "alias krollout='kubectl rollout restart deployment'"

    # ------------------------------
    # Git
    # ------------------------------
    "alias g='git'"
    "alias gs='git status'"
    "alias ga='git add'"
    "alias gaa='git add -A'"
    "alias gc='git commit -m'"
    "alias gp='git push'"
    "alias gpl='git pull'"
    "alias gf='git fetch'"
    "alias gb='git branch'"
    "alias gco='git checkout'"
    "alias gd='git diff'"
    "alias glog='git log --oneline --graph --decorate -10'"
    "alias gclone='git clone'"

    # ------------------------------
    # Editors & Config
    # ------------------------------
    "alias nano='nano -l'"
    "alias bashrc='nano ~/.bashrc && source ~/.bashrc'"
    "alias src='source ~/.bashrc'"
    "alias path='echo \$PATH | tr \":\" \"\\n\"'"
    "alias hosts='sudo nano /etc/hosts'"

    # ------------------------------
    # Quick Shortcuts
    # ------------------------------
    "alias c='clear'"
    "alias q='exit'"
    "alias now='date +\"%Y-%m-%d %H:%M:%S\"'"
    "alias week='date +%V'"
    "alias timestamp='date +%s'"
    "alias weather='curl wttr.in/?0'"
    "alias moon='curl wttr.in/Moon'"
    "alias sha='shasum -a 256'"
    "alias genpass='openssl rand -base64 20'"
    "alias busy=\"cat /dev/urandom | hexdump -C | grep 'ca fe'\""

    # ------------------------------
    # Safety Nets
    # ------------------------------
    "alias reboot='sudo /sbin/reboot'"
    "alias poweroff='sudo /sbin/poweroff'"
    "alias shutdown='sudo /sbin/shutdown'"

    # ------------------------------
    # Tail & Watch
    # ------------------------------
    "alias tf='tail -f'"
    "alias t100='tail -100'"
    "alias watch='watch -n 2'"

    # ------------------------------
    # Add your custom aliases below
    # ------------------------------
    # "alias myalias='my command'"
)

# ============================================================
# SETTINGS
# ============================================================

# SSH user (change if different per host)
SSH_USER="${SSH_USER:-$(whoami)}"

# Max parallel jobs (adjust based on your network)
MAX_PARALLEL="${MAX_PARALLEL:-10}"

# SSH timeout in seconds
SSH_TIMEOUT=10

# Marker to identify our managed alias block
MARKER_START="# >>> DISTRIBUTED ALIASES START <<<"
MARKER_END="# >>> DISTRIBUTED ALIASES END <<<"

# Temp directory for parallel results
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# ============================================================
# FUNCTIONS
# ============================================================

get_hosts() {
    grep -v '^#' /etc/hosts | \
    grep -v '^\s*$' | \
    grep -v -E 'localhost|broadcasthost' | \
    grep -v '127.0.0.1' | \
    grep -v '127.0.1.1' | \
    grep -v '::1' | \
    grep -v ':' | \
    awk '{print $1}' | \
    sort -u
}

generate_alias_block() {
    echo "$MARKER_START"
    echo "# Distributed on: $(date)"
    echo "# From: $(hostname)"
    for alias_line in "${ALIASES[@]}"; do
        # Skip comment-only lines for the actual file
        if [[ ! "$alias_line" =~ ^[[:space:]]*# ]]; then
            echo "$alias_line"
        fi
    done
    echo "$MARKER_END"
}

deploy_to_host() {
    local host=$1
    local result_file="$TMPDIR/result_${host//\./_}"
    local alias_block
    alias_block=$(generate_alias_block)
    
    # Test SSH connectivity first
    if ! ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -o StrictHostKeyChecking=no \
         "${SSH_USER}@${host}" "echo 'OK'" &>/dev/null; then
        echo "SKIP:$host:Cannot connect" > "$result_file"
        return 1
    fi
    
    # Remove existing alias block and add new one
    ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes "${SSH_USER}@${host}" bash -s <<EOF
        BASHRC="\$HOME/.bashrc"
        MARKER_START="$MARKER_START"
        MARKER_END="$MARKER_END"
        
        # Create .bashrc if it doesn't exist
        touch "\$BASHRC"
        
        # Create backup
        cp "\$BASHRC" "\$BASHRC.bak.\$(date +%Y%m%d%H%M%S)" 2>/dev/null
        
        # Remove existing block if present
        if grep -q "\$MARKER_START" "\$BASHRC" 2>/dev/null; then
            sed -i "/\$MARKER_START/,/\$MARKER_END/d" "\$BASHRC"
        fi
        
        # Append new alias block
        cat >> "\$BASHRC" <<'ALIASBLOCK'
$alias_block
ALIASBLOCK
        
        echo "Deployed successfully"
EOF
    
    if [[ $? -eq 0 ]]; then
        echo "OK:$host:Deployed ${#ALIASES[@]} aliases" > "$result_file"
        return 0
    else
        echo "FAIL:$host:SSH command failed" > "$result_file"
        return 1
    fi
}

run_parallel() {
    local hosts=("$@")
    local running=0
    local pids=()
    
    for host in "${hosts[@]}"; do
        # Wait if we've hit max parallel jobs
        while [[ $running -ge $MAX_PARALLEL ]]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    unset 'pids[i]'
                    ((running--))
                fi
            done
            pids=("${pids[@]}")  # Re-index array
            sleep 0.1
        done
        
        # Launch deployment in background
        deploy_to_host "$host" &
        pids+=($!)
        ((running++))
        echo -ne "\rDeploying... [$running active jobs]    "
    done
    
    # Wait for all remaining jobs
    echo -ne "\rWaiting for remaining jobs to complete...    "
    wait
    echo -e "\rAll deployments complete.                     "
}

print_results() {
    local success=0
    local failed=0
    local skipped=0
    
    echo ""
    echo "========================================"
    echo "  Results"
    echo "========================================"
    
    for result_file in "$TMPDIR"/result_*; do
        [[ -f "$result_file" ]] || continue
        local line=$(cat "$result_file")
        local status=$(echo "$line" | cut -d: -f1)
        local host=$(echo "$line" | cut -d: -f2)
        local msg=$(echo "$line" | cut -d: -f3-)
        
        case "$status" in
            OK)
                echo -e "  [\e[32m✓\e[0m] $host - $msg"
                ((success++))
                ;;
            SKIP)
                echo -e "  [\e[33m-\e[0m] $host - $msg"
                ((skipped++))
                ;;
            FAIL)
                echo -e "  [\e[31m✗\e[0m] $host - $msg"
                ((failed++))
                ;;
        esac
    done
    
    echo ""
    echo "========================================"
    echo "  Summary"
    echo "========================================"
    echo -e "  Successful: \e[32m$success\e[0m"
    echo -e "  Skipped:    \e[33m$skipped\e[0m"
    echo -e "  Failed:     \e[31m$failed\e[0m"
    echo ""
    echo "  Run 'source ~/.bashrc' or 'src' (after first deploy)"
    echo "  on each node to activate aliases."
}

show_aliases() {
    echo ""
    echo "Aliases to deploy (${#ALIASES[@]} total):"
    echo "----------------------------------------"
    for alias_line in "${ALIASES[@]}"; do
        echo "  $alias_line"
    done
    echo "----------------------------------------"
}

# ============================================================
# MAIN
# ============================================================

echo "========================================"
echo "  Alias Distribution Script"
echo "========================================"
echo "  SSH User:      $SSH_USER"
echo "  Max Parallel:  $MAX_PARALLEL"
echo "  Aliases:       ${#ALIASES[@]}"
echo ""

# Parse arguments
DRY_RUN=false
SHOW_ALIASES=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--dry-run)   DRY_RUN=true; shift ;;
        -l|--list)      SHOW_ALIASES=true; shift ;;
        -p|--parallel)  MAX_PARALLEL="$2"; shift 2 ;;
        -u|--user)      SSH_USER="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "  -n, --dry-run      Show what would be done without deploying"
            echo "  -l, --list         List all aliases"
            echo "  -p, --parallel N   Max parallel jobs (default: 10)"
            echo "  -u, --user USER    SSH user (default: current user)"
            echo "  -h, --help         Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if $SHOW_ALIASES; then
    show_aliases
    exit 0
fi

# Get list of hosts
HOSTS=($(get_hosts))

if [[ ${#HOSTS[@]} -eq 0 ]]; then
    echo "No hosts found in /etc/hosts"
    exit 1
fi

echo "Found ${#HOSTS[@]} hosts in /etc/hosts:"
printf '  - %s\n' "${HOSTS[@]}"
echo ""

if $DRY_RUN; then
    echo "[DRY RUN] Would deploy to the above hosts."
    show_aliases
    exit 0
fi

read -p "Deploy ${#ALIASES[@]} aliases to ${#HOSTS[@]} hosts? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Starting parallel deployment..."
START_TIME=$(date +%s)

run_parallel "${HOSTS[@]}"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

print_results
echo "  Completed in ${ELAPSED}s"
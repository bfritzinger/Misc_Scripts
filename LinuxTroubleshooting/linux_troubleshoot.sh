#!/usr/bin/env bash
# =============================================================================
#  linux_troubleshoot.sh — Comprehensive Linux Troubleshooting Toolkit
#  Covers: System, CPU/Memory, Disk, Network, Processes, Logs, Security,
#          Containers, Kubernetes/k3s, Services, Hardware, and Kernel
# =============================================================================

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

# ─── Helpers ─────────────────────────────────────────────────────────────────
header()  { echo -e "\n${BOLD}${CYAN}════════════════════════════════════════${RESET}";
            echo -e "${BOLD}${CYAN}  $*${RESET}";
            echo -e "${BOLD}${CYAN}════════════════════════════════════════${RESET}"; }
section() { echo -e "\n${BOLD}${BLUE}▶ $*${RESET}"; }
ok()      { echo -e "${GREEN}✔ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $*${RESET}"; }
err()     { echo -e "${RED}✖ $*${RESET}"; }
run()     { echo -e "${YELLOW}$ $*${RESET}"; eval "$@" 2>/dev/null || warn "Command failed or not available"; }
hr()      { echo -e "${CYAN}────────────────────────────────────────${RESET}"; }

cmd_exists() { command -v "$1" &>/dev/null; }
require_root() { [[ $EUID -eq 0 ]] || { warn "Some output requires root. Re-run with sudo for full results."; }; }

pause() { echo; read -rp "Press [Enter] to continue..." _; }

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/troubleshoot"
LOG_FILE=""

init_log() {
    local ts; ts=$(date +%Y%m%d_%H%M%S)
    LOG_FILE="/tmp/troubleshoot_${ts}.log"
    exec > >(tee -a "$LOG_FILE") 2>&1
    ok "Logging to: $LOG_FILE"
}

# =============================================================================
#  CONFIGURATION
#  Edit these variables to match the target network environment.
#
#  DNS_TEST_HOSTS   — Space-separated list of hostnames/IPs for DNS lookup
#                     tests and connectivity checks.
#                     Open networks:   use public FQDNs (e.g. google.com)
#                     Closed networks: replace with internal hostnames/IPs
#                     /etc/hosts entries are appended automatically when
#                     DNS_INCLUDE_HOSTS_FILE=true (see below).
#
#  DNS_REVERSE_IP   — IP used for the reverse DNS (PTR) lookup test.
#                     On closed networks, use an internal DNS server IP.
#
#  PING_TEST_HOSTS  — Space-separated IPs/hosts for the Network module
#                     connectivity ping tests.
#
#  DNS_INCLUDE_HOSTS_FILE — Set "true" to automatically pull non-loopback
#                     hostnames from /etc/hosts into the DNS test targets.
# =============================================================================

DNS_TEST_HOSTS="google.com cloudflare.com"
DNS_REVERSE_IP="8.8.8.8"
PING_TEST_HOSTS="8.8.8.8 1.1.1.1"
DNS_INCLUDE_HOSTS_FILE="true"

# Merge DNS_TEST_HOSTS with non-loopback /etc/hosts entries at runtime.
build_dns_targets() {
    local targets="$DNS_TEST_HOSTS"
    if [[ "$DNS_INCLUDE_HOSTS_FILE" == "true" ]] && [[ -f /etc/hosts ]]; then
        local hosts_entries
        hosts_entries=$(awk '
            /^\s*#/ || /^\s*$/ { next }
            /^127\./ || /^::1/ || /^fe80/ { next }
            { for (i=2; i<=NF; i++) if ($i !~ /^#/) print $i }
        ' /etc/hosts | sort -u | tr '\n' ' ')
        targets="$targets $hosts_entries"
    fi
    # Deduplicate while preserving order
    echo "$targets" | tr ' ' '\n' | awk '!seen[$0]++' | tr '\n' ' '
}

# =============================================================================
#  MODULES
# =============================================================================

# ─── 1. System Overview ───────────────────────────────────────────────────────
mod_system_overview() {
    header "SYSTEM OVERVIEW"

    section "OS & Kernel"
    run "uname -a"
    [[ -f /etc/os-release ]] && run "cat /etc/os-release"
    run "hostnamectl 2>/dev/null || hostname"

    section "Uptime & Load"
    run "uptime -p 2>/dev/null || uptime"
    run "cat /proc/loadavg"

    section "Date / Time / Timezone"
    run "date"
    run "timedatectl 2>/dev/null || date"

    section "System Limits"
    run "ulimit -a"

    section "Environment"
    run "env | sort"
}

# ─── 2. CPU & Memory ──────────────────────────────────────────────────────────
mod_cpu_memory() {
    header "CPU & MEMORY"

    section "CPU Info"
    run "lscpu 2>/dev/null || cat /proc/cpuinfo | grep -E 'model name|cpu cores|siblings' | sort -u"
    run "nproc"

    section "CPU Usage (snapshot)"
    if cmd_exists mpstat; then
        run "mpstat -P ALL 1 1"
    else
        run "cat /proc/stat | head -5"
        warn "mpstat not found — install sysstat for richer CPU stats"
    fi

    section "Memory"
    run "free -h"
    run "cat /proc/meminfo | grep -E 'MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|Dirty|Shmem'"

    section "Swap Usage"
    run "swapon --show 2>/dev/null || cat /proc/swaps"

    section "Virtual Memory Stats"
    run "vmstat -s 2>/dev/null | head -20"

    section "Huge Pages"
    run "cat /proc/meminfo | grep -i huge"

    section "Top Memory Consumers (RSS)"
    run "ps aux --sort=-%mem | head -15"

    section "OOM Killer History"
    run "dmesg 2>/dev/null | grep -i 'oom\|kill' | tail -20 || journalctl -k --no-pager 2>/dev/null | grep -i oom | tail -20"
}

# ─── 3. Disk & Filesystem ────────────────────────────────────────────────────
mod_disk() {
    header "DISK & FILESYSTEM"

    section "Block Devices"
    run "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL 2>/dev/null || lsblk"

    section "Disk Usage"
    run "df -hT"

    section "Inode Usage"
    run "df -i"

    section "Mounts"
    run "mount | column -t"

    section "fstab"
    run "cat /etc/fstab"

    section "Disk I/O Stats"
    if cmd_exists iostat; then
        run "iostat -xz 1 2"
    else
        run "cat /proc/diskstats | awk '{print \$3, \$4, \$8}' | head -20"
        warn "iostat not found — install sysstat"
    fi

    section "Large Files (>100MB in /)"
    run "find / -xdev -size +100M -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -20"

    section "Open File Handles"
    run "lsof 2>/dev/null | wc -l || cat /proc/sys/fs/file-nr"

    section "SMART Status (if available)"
    if cmd_exists smartctl; then
        for dev in /dev/sd? /dev/nvme?; do
            [[ -b "$dev" ]] && { echo "→ $dev"; smartctl -H "$dev" 2>/dev/null | grep -E 'result|Status|PASSED|FAILED'; }
        done
    else
        warn "smartctl not found — install smartmontools"
    fi

    section "LVM (if present)"
    cmd_exists pvs  && run "pvs"
    cmd_exists vgs  && run "vgs"
    cmd_exists lvs  && run "lvs"

    section "RAID / MD (if present)"
    [[ -f /proc/mdstat ]] && run "cat /proc/mdstat"
}

# ─── 4. Network ───────────────────────────────────────────────────────────────
mod_network() {
    header "NETWORK"

    section "Interfaces"
    run "ip -br addr"
    run "ip -br link"

    section "Routing Table"
    run "ip route"
    run "ip -6 route 2>/dev/null | head -10"

    section "ARP / Neighbor Table"
    run "ip neigh"

    section "DNS Configuration"
    run "cat /etc/resolv.conf"
    run "resolvectl status 2>/dev/null | head -30 || true"

    section "Active Connections"
    if cmd_exists ss; then
        run "ss -tulpn"
        run "ss -s"
    else
        run "netstat -tulpn 2>/dev/null"
    fi

    section "Established TCP Connections"
    run "ss -tn state established 2>/dev/null | head -30"

    section "Connection State Summary"
    echo -e "${BOLD}Count by state:${RESET}"
    ss -tan 2>/dev/null | awk 'NR>1 {state[$1]++} END {for (s in state) printf "  %-20s %d\n", s, state[s]}' | sort -k2 -rn

    section "Connection Details by State"
    for state in ESTABLISHED CLOSE-WAIT TIME-WAIT SYN-SENT SYN-RECV FIN-WAIT-1 FIN-WAIT-2 LAST-ACK CLOSING; do
        local count; count=$(ss -tan 2>/dev/null | awk -v s="$state" '$1==s' | wc -l)
        if [[ $count -gt 0 ]]; then
            echo -e "\n${YELLOW}── $state ($count connections) ──${RESET}"
            ss -tanp 2>/dev/null | awk -v s="$state" '$1==s {print}' | \
                awk '{printf "  Local: %-25s  Remote: %-25s  Process: %s\n", $4, $5, $6}' | head -20
        fi
    done

    section "Top Remote IPs by Connection Count"
    ss -tan 2>/dev/null | awk 'NR>1 && $5 !~ /^$/ {
        split($5, a, ":"); ip=a[1]
        if (ip ~ /^[0-9]/) count[ip]++
    } END {for (ip in count) printf "  %5d  %s\n", count[ip], ip}' | sort -rn | head -20

    section "Top Remote IPs in CLOSE_WAIT (potential leaks)"
    ss -tan state close-wait 2>/dev/null | awk 'NR>1 {
        split($5, a, ":"); ip=a[1]; count[ip]++
    } END {for (ip in count) printf "  %5d  %s\n", count[ip], ip}' | sort -rn | head -10

    section "Connections per Local Port"
    ss -tan 2>/dev/null | awk 'NR>1 && $1=="ESTAB" {
        split($4, a, ":"); port[a[length(a)]]++
    } END {for (p in port) printf "  %-8s %d\n", p, port[p]}' | sort -k2 -rn | head -20

    section "Firewall (iptables)"
    if [[ $EUID -eq 0 ]]; then
        run "iptables -L -n -v --line-numbers 2>/dev/null | head -60"
        run "iptables -t nat -L -n -v 2>/dev/null | head -30"
    else
        warn "Firewall rules require root"
    fi

    section "nftables"
    cmd_exists nft && run "nft list ruleset 2>/dev/null | head -60" || true

    section "UFW Status"
    cmd_exists ufw && run "ufw status verbose 2>/dev/null" || true

    section "Network Sysctl"
    run "sysctl -a 2>/dev/null | grep -E 'net\.(ipv4|ipv6)\.(tcp_|udp_|ip_forward|conf\.all)' | sort | head -40"

    section "Network Namespaces"
    run "ip netns list 2>/dev/null"

    section "Wireless (if present)"
    cmd_exists iwconfig && run "iwconfig 2>/dev/null" || true
    cmd_exists iw       && run "iw dev 2>/dev/null"   || true

    section "Connectivity Tests"
    for _ping_host in $PING_TEST_HOSTS; do
        ping -c 2 -W 2 "$_ping_host" &>/dev/null             && ok "ping OK: $_ping_host"             || warn "ping FAIL: $_ping_host"
    done
    run "curl -sS --max-time 5 https://example.com -o /dev/null -w 'HTTP %{http_code}\n' 2>/dev/null || warn 'curl failed'"

    section "Network Bridges"
    run "brctl show 2>/dev/null || ip link show type bridge 2>/dev/null"

    section "Bonding / Teaming"
    run "cat /proc/net/bonding/* 2>/dev/null | head -40 || true"
    cmd_exists teamdctl && run "teamdctl --list 2>/dev/null" || true

    section "Bandwidth (if nload/iftop available)"
    cmd_exists nload  && warn "nload available — run manually for live bandwidth"
    cmd_exists iftop  && warn "iftop available — run manually for live bandwidth"
    cmd_exists nethogs && warn "nethogs available — run manually for per-process bandwidth"
}

# ─── 5. Processes ─────────────────────────────────────────────────────────────
mod_processes() {
    header "PROCESSES"

    section "Process Snapshot (top 30 CPU)"
    run "ps aux --sort=-%cpu | head -30"

    section "Process Tree"
    run "pstree -p 2>/dev/null | head -60 || ps auxf | head -40"

    section "Zombie Processes"
    ZOMBIES=$(ps aux | awk '$8=="Z"' | wc -l)
    echo "Zombie count: $ZOMBIES"
    [[ $ZOMBIES -gt 0 ]] && ps aux | awk '$8=="Z"'

    section "Stopped / Sleeping Processes"
    ps aux | awk '$8 ~ /T|D/' | head -20

    section "Process Limits (per-process)"
    # Show limits for PID 1
    [[ -f /proc/1/limits ]] && { echo "Limits for PID 1:"; cat /proc/1/limits; }

    section "Threads"
    run "ps -eLf | wc -l"

    section "Strace / lsof on a PID (manual)"
    warn "To trace a specific process: strace -p <PID>  |  lsof -p <PID>"

    section "Signals"
    warn "To kill a process: kill -9 <PID>  |  pkill <name>  |  killall <name>"
}

# ─── 6. System Logs ───────────────────────────────────────────────────────────
mod_logs() {
    header "SYSTEM LOGS"

    section "Kernel Ring Buffer (dmesg)"
    run "dmesg --level=err,warn --time-format reltime 2>/dev/null | tail -40 || dmesg | tail -40"

    section "Recent Journal Errors"
    run "journalctl -p err..emerg --no-pager -n 50 2>/dev/null || tail -50 /var/log/syslog 2>/dev/null || tail -50 /var/log/messages 2>/dev/null"

    section "Boot Log"
    run "journalctl -b --no-pager -n 50 2>/dev/null | tail -50"

    section "Auth Log"
    run "journalctl -u sshd --no-pager -n 30 2>/dev/null || tail -30 /var/log/auth.log 2>/dev/null || tail -30 /var/log/secure 2>/dev/null"

    section "Failed Logins"
    run "lastb 2>/dev/null | head -20 || journalctl --no-pager | grep -i 'failed\|invalid user' | tail -20"

    section "Last Logins"
    run "last | head -20"

    section "Cron Log"
    run "journalctl -u cron --no-pager -n 20 2>/dev/null || tail -20 /var/log/cron 2>/dev/null || true"

    section "Log File Sizes"
    run "du -sh /var/log/* 2>/dev/null | sort -h | tail -20"
}

# ─── 7. Services & Systemd ────────────────────────────────────────────────────
mod_services() {
    header "SERVICES & SYSTEMD"

    section "Failed Units"
    run "systemctl --failed --no-pager 2>/dev/null"

    section "All Active Services"
    run "systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -40"

    section "Masked / Disabled Services"
    run "systemctl list-unit-files --state=masked,disabled --type=service --no-pager 2>/dev/null | head -30"

    section "Timers"
    run "systemctl list-timers --no-pager 2>/dev/null"

    section "Journal Disk Usage"
    run "journalctl --disk-usage 2>/dev/null"

    section "Init System"
    [[ -d /run/systemd/system ]] && ok "systemd" || warn "Non-systemd init detected"
    run "ps -p 1 -o comm="

    section "rc.local / Legacy Init"
    [[ -f /etc/rc.local ]] && run "cat /etc/rc.local"
}

# ─── 8. Hardware ──────────────────────────────────────────────────────────────
mod_hardware() {
    header "HARDWARE"

    section "Full Hardware Inventory (lshw)"
    if cmd_exists lshw; then
        run "lshw -short 2>/dev/null"
    else
        warn "lshw not found — install lshw (apt install lshw / yum install lshw)"
    fi

    section "CPU Details (lshw)"
    cmd_exists lshw && run "lshw -class processor 2>/dev/null"

    section "Memory / DIMMs (lshw)"
    if cmd_exists lshw; then
        run "lshw -class memory 2>/dev/null"
    else
        warn "Install lshw for DIMM slot info"
    fi

    section "Storage Controllers & Disks (lshw)"
    cmd_exists lshw && run "lshw -class storage -class disk 2>/dev/null"

    section "Network Adapters (lshw)"
    cmd_exists lshw && run "lshw -class network 2>/dev/null"

    section "PCI Devices"
    run "lspci 2>/dev/null || warn 'lspci not found — install pciutils'"

    section "USB Devices"
    run "lsusb 2>/dev/null || warn 'lsusb not found — install usbutils'"

    section "DMI / BIOS Info"
    run "dmidecode -t system 2>/dev/null | head -20 || warn 'dmidecode not found or requires root'"

    section "DMI Memory Details (dmidecode)"
    if [[ $EUID -eq 0 ]] && cmd_exists dmidecode; then
        run "dmidecode -t memory 2>/dev/null | grep -E 'Memory Device|Size|Speed|Type|Manufacturer|Part Number|Locator' | grep -v 'No Module\|Unknown' | head -60"
    else
        warn "Requires root for dmidecode memory details"
    fi

    section "CPU Temperature"
    if cmd_exists sensors; then
        run "sensors"
    elif [[ -d /sys/class/thermal ]]; then
        for f in /sys/class/thermal/thermal_zone*/temp; do
            zone=$(dirname "$f" | xargs basename)
            temp=$(cat "$f" 2>/dev/null || echo "N/A")
            echo "$zone: $((temp/1000))°C"
        done
    else
        warn "Temperature sensors not accessible — install lm-sensors"
    fi

    section "GPU (NVIDIA)"
    cmd_exists nvidia-smi && run "nvidia-smi" || warn "nvidia-smi not found"

    section "Power / Battery"
    run "upower -i \$(upower -e | grep BAT) 2>/dev/null | head -20 || true"
    [[ -d /sys/class/power_supply ]] && ls /sys/class/power_supply/

    section "Kernel Modules"
    run "lsmod | sort | head -40"

    section "IOMMU / Virtualization"
    run "dmesg 2>/dev/null | grep -iE 'iommu|vt-d|amd-vi' | head -10"
    run "egrep -c '(vmx|svm)' /proc/cpuinfo && echo 'Hardware virtualization supported' || true"
}

# ─── 9. Security ──────────────────────────────────────────────────────────────
mod_security() {
    header "SECURITY"

    section "Users & Groups"
    run "cat /etc/passwd | grep -v 'nologin\|false' | cut -d: -f1,3,4,6"
    run "getent group sudo wheel 2>/dev/null"

    section "Sudo Configuration"
    [[ $EUID -eq 0 ]] && run "cat /etc/sudoers" || warn "Requires root to view /etc/sudoers"

    section "SUID / SGID Binaries"
    warn "Searching for SUID/SGID (may be slow)..."
    run "find / -xdev -perm /6000 -type f 2>/dev/null | sort | head -30"

    section "World-Writable Files"
    run "find / -xdev -perm -0002 -not -type l -type f 2>/dev/null | head -20"

    section "Listening Ports (security view)"
    run "ss -tulpn 2>/dev/null | grep -v '127.0.0.1\|::1'"

    section "SSH Configuration"
    run "sshd -T 2>/dev/null | grep -E 'permitroot|passwordauth|pubkeyauth|port|allowusers|protocol'"
    run "cat /etc/ssh/sshd_config 2>/dev/null | grep -v '^#' | grep -v '^$'"

    section "PAM Configuration"
    run "ls /etc/pam.d/"

    section "SELinux"
    cmd_exists getenforce && run "getenforce"    || warn "SELinux not present"
    cmd_exists sestatus   && run "sestatus"      || true

    section "AppArmor"
    cmd_exists apparmor_status && run "apparmor_status 2>/dev/null" || true
    cmd_exists aa-status        && run "aa-status 2>/dev/null"       || warn "AppArmor not present"

    section "Auditd"
    cmd_exists auditctl && run "auditctl -l 2>/dev/null | head -20" || warn "auditd not found"

    section "Fail2ban"
    cmd_exists fail2ban-client && run "fail2ban-client status 2>/dev/null" || warn "fail2ban not found"

    section "Recently Modified Files in /etc"
    run "find /etc -mtime -7 -type f 2>/dev/null | sort | head -30"
}

# ─── 10. Docker / Containers ─────────────────────────────────────────────────
mod_containers() {
    header "CONTAINERS (Docker / Podman)"

    if cmd_exists docker; then
        section "Docker Version"
        run "docker version"

        section "Docker Info"
        run "docker info 2>/dev/null | grep -E 'Containers|Images|Driver|Logging|Cgroup|Server Version'"

        section "Running Containers"
        run "docker ps"

        section "All Containers"
        run "docker ps -a"

        section "Container Resource Usage"
        run "docker stats --no-stream 2>/dev/null"

        section "Images"
        run "docker images"

        section "Volumes"
        run "docker volume ls"

        section "Networks"
        run "docker network ls"

        section "Docker Disk Usage"
        run "docker system df"

        section "Dangling Resources"
        warn "To clean up: docker system prune -af --volumes"
    else
        warn "Docker not found"
    fi

    if cmd_exists podman; then
        section "Podman Containers"
        run "podman ps -a"
    fi

    section "cgroup v1/v2"
    run "mount | grep cgroup"
    [[ -f /sys/fs/cgroup/cgroup.controllers ]] && ok "cgroup v2" || ok "cgroup v1"
}

# ─── 11. Kubernetes / k3s ────────────────────────────────────────────────────
mod_kubernetes() {
    header "KUBERNETES / k3s"

    local KUBECTL=""
    cmd_exists kubectl && KUBECTL="kubectl"
    cmd_exists k3s     && KUBECTL="k3s kubectl"
    [[ -z "$KUBECTL" ]] && { warn "kubectl / k3s not found"; return; }

    section "Cluster Info"
    run "$KUBECTL cluster-info 2>/dev/null"

    section "Node Status"
    run "$KUBECTL get nodes -o wide"

    section "Pods (all namespaces)"
    run "$KUBECTL get pods -A -o wide"

    section "Failed / Pending Pods"
    run "$KUBECTL get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null"

    section "Services"
    run "$KUBECTL get svc -A"

    section "Deployments"
    run "$KUBECTL get deploy -A"

    section "DaemonSets"
    run "$KUBECTL get ds -A"

    section "PersistentVolumes"
    run "$KUBECTL get pv"
    run "$KUBECTL get pvc -A"

    section "Recent Events (Warnings)"
    run "$KUBECTL get events -A --sort-by='.lastTimestamp' 2>/dev/null | grep -i warning | tail -30"

    section "ConfigMaps & Secrets Count"
    run "$KUBECTL get cm -A | wc -l"
    run "$KUBECTL get secret -A | wc -l"

    section "Resource Quotas"
    run "$KUBECTL get resourcequota -A 2>/dev/null"

    section "Ingress"
    run "$KUBECTL get ingress -A 2>/dev/null"

    section "k3s-specific"
    if cmd_exists k3s; then
        run "k3s check-config 2>/dev/null | head -30"
        run "systemctl status k3s k3s-agent 2>/dev/null | head -20"
    fi

    section "Helm Releases (if helm present)"
    cmd_exists helm && run "helm list -A 2>/dev/null" || warn "helm not found"
}

# ─── 12. DNS Diagnostics ─────────────────────────────────────────────────────
mod_dns() {
    header "DNS DIAGNOSTICS"

    section "Resolver Configuration"
    run "cat /etc/resolv.conf"
    run "cat /etc/nsswitch.conf | grep hosts"

    section "systemd-resolved"
    run "resolvectl status 2>/dev/null | head -40 || true"
    run "resolvectl statistics 2>/dev/null || true"

    section "DNS Test Targets"
    local all_targets; all_targets=$(build_dns_targets)
    echo -e "${BOLD}Configured hosts:${RESET}       $DNS_TEST_HOSTS"
    echo -e "${BOLD}Include /etc/hosts:${RESET}     $DNS_INCLUDE_HOSTS_FILE"
    echo -e "${BOLD}Full target list:${RESET}       $all_targets"

    section "DNS Lookup Tests"
    for target in $all_targets; do
        echo -e "\n${BOLD}→ $target${RESET}"
        if cmd_exists dig; then
            dig +short +time=3 +tries=1 "$target" 2>/dev/null                 && ok "dig OK: $target" || warn "dig: no result for $target"
        elif cmd_exists nslookup; then
            nslookup "$target" 2>/dev/null | grep -E "Address|Name"                 && ok "nslookup OK: $target" || warn "nslookup: no result for $target"
        elif cmd_exists host; then
            host "$target" 2>/dev/null                 && ok "host OK: $target" || warn "host: no result for $target"
        else
            warn "No DNS lookup tool found (dig / nslookup / host)"
            break
        fi
    done

    section "Reverse DNS"
    echo -e "${BOLD}→ Reverse lookup for:${RESET} $DNS_REVERSE_IP"
    if cmd_exists dig; then
        run "dig -x $DNS_REVERSE_IP +short"
    else
        run "nslookup $DNS_REVERSE_IP 2>/dev/null | tail -3"
    fi

    section "/etc/hosts"
    run "cat /etc/hosts"
}

# ─── 13. Performance Profiling ───────────────────────────────────────────────
mod_performance() {
    header "PERFORMANCE PROFILING"

    section "Load Average History"
    run "uptime"
    cmd_exists sar && run "sar -q 1 3 2>/dev/null | tail -10" || warn "sar not found — install sysstat"

    section "CPU Frequency Scaling"
    [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]] && {
        run "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
        run "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
    } || warn "CPU freq scaling not exposed"

    section "Interrupts"
    run "cat /proc/interrupts | head -30"

    section "Context Switches & Interrupts"
    run "vmstat 1 3 2>/dev/null"

    section "Scheduler Stats"
    run "cat /proc/schedstat 2>/dev/null | head -10"

    section "Page Faults"
    run "ps -o pid,comm,min_flt,maj_flt --sort=-maj_flt | head -20"

    section "Network Latency"
    run "ping -c 5 8.8.8.8 2>/dev/null | tail -3"

    section "traceroute / tracepath"
    warn "For route tracing: traceroute 8.8.8.8  |  tracepath 8.8.8.8"
}

# ─── 14. Kernel & Boot ───────────────────────────────────────────────────────
mod_kernel() {
    header "KERNEL & BOOT"

    section "Kernel Parameters"
    run "sysctl -a 2>/dev/null | grep -E 'kernel\.(hostname|ostype|version|pid_max|panic|dmesg_restrict)|vm\.(swappiness|dirty_ratio|overcommit)|net\.ipv4\.(ip_forward|tcp_syncookies)' | sort"

    section "Boot Parameters"
    run "cat /proc/cmdline"

    section "Loaded Modules"
    run "lsmod | wc -l"
    run "lsmod | sort"

    section "Module Blacklist"
    run "find /etc/modprobe.d/ -name '*.conf' -exec grep -H blacklist {} \; 2>/dev/null | head -20"

    section "GRUB Configuration"
    run "cat /etc/default/grub 2>/dev/null || cat /boot/grub/grub.cfg 2>/dev/null | grep -E 'linux|initrd|title' | head -20"

    section "Installed Kernels"
    run "ls /boot/vmlinuz* 2>/dev/null || ls /boot/ 2>/dev/null"

    section "Core Dumps"
    run "sysctl kernel.core_pattern"
    run "ls -lh /var/crash/ /var/core/ /tmp/core.* 2>/dev/null | head -10 || true"

    section "Kernel Taint Flags"
    run "cat /proc/sys/kernel/tainted"
    echo "(0 = clean; non-zero = tainted — check kernel docs for flags)"
}

# ─── 15. Quick Health Summary ────────────────────────────────────────────────
mod_health_summary() {
    header "QUICK HEALTH SUMMARY"
    local issues=0

    # Load
    local load1; load1=$(awk '{print $1}' /proc/loadavg)
    local cpus;  cpus=$(nproc)
    if awk "BEGIN{exit !($load1 > $cpus * 2)}"; then
        warn "HIGH LOAD: $load1 (CPUs: $cpus)"; ((issues++))
    else
        ok "Load average OK: $load1"
    fi

    # Memory
    local mem_free; mem_free=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
    local mem_total; mem_total=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    local mem_pct=$(( (mem_total - mem_free) * 100 / mem_total ))
    [[ $mem_pct -gt 90 ]] && { warn "HIGH MEMORY USAGE: ${mem_pct}%"; ((issues++)); } || ok "Memory: ${mem_pct}% used"

    # Disk
    while read -r _ size used avail pct mountpoint; do
        local p="${pct/\%/}"
        [[ "$p" =~ ^[0-9]+$ ]] && [[ $p -gt 85 ]] && { warn "DISK ${mountpoint} at ${pct}"; ((issues++)); }
    done < <(df -h | tail -n +2)
    [[ $issues -eq 0 ]] && ok "All monitored disks have sufficient space"

    # Failed services
    if cmd_exists systemctl; then
        local failed; failed=$(systemctl --failed --no-pager --no-legend 2>/dev/null | wc -l)
        [[ $failed -gt 0 ]] && { warn "FAILED SERVICES: $failed"; ((issues++)); } || ok "No failed systemd units"
    fi

    # Zombies
    local zombies; zombies=$(ps aux | awk '$8=="Z"' | wc -l)
    [[ $zombies -gt 0 ]] && { warn "ZOMBIE PROCESSES: $zombies"; ((issues++)); } || ok "No zombie processes"

    # Swap
    local swap_used; swap_used=$(free | awk '/Swap/{print $3}')
    [[ $swap_used -gt 524288 ]] && { warn "SWAP IN USE: $((swap_used/1024)) MB"; ((issues++)); } || ok "Swap usage nominal"

    hr
    [[ $issues -eq 0 ]] && ok "All checks passed!" || warn "Issues found: $issues — review details above"
}

# =============================================================================
#  INTERACTIVE MENU
# =============================================================================

show_menu() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║         Linux Troubleshooting Toolkit                ║"
    echo "  ║         $(date '+%Y-%m-%d %H:%M:%S')                          ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  ${BOLD}Select a module:${RESET}\n"
    echo -e "   ${CYAN}1${RESET}  System Overview          ${CYAN}9${RESET}  Security"
    echo -e "   ${CYAN}2${RESET}  CPU & Memory            ${CYAN}10${RESET}  Docker / Containers"
    echo -e "   ${CYAN}3${RESET}  Disk & Filesystem       ${CYAN}11${RESET}  Kubernetes / k3s"
    echo -e "   ${CYAN}4${RESET}  Network                 ${CYAN}12${RESET}  DNS Diagnostics"
    echo -e "   ${CYAN}5${RESET}  Processes               ${CYAN}13${RESET}  Performance Profiling"
    echo -e "   ${CYAN}6${RESET}  System Logs             ${CYAN}14${RESET}  Kernel & Boot"
    echo -e "   ${CYAN}7${RESET}  Services & Systemd      ${CYAN}15${RESET}  Quick Health Summary"
    echo -e "   ${CYAN}8${RESET}  Hardware"
    echo
    echo -e "   ${YELLOW}A${RESET}  Run ALL modules"
    echo -e "   ${YELLOW}L${RESET}  Toggle log to file (currently: ${LOG_FILE:-OFF})"
    echo -e "   ${RED}Q${RESET}  Quit"
    echo
}

dispatch() {
    case "$1" in
        1)  mod_system_overview  ;;
        2)  mod_cpu_memory       ;;
        3)  mod_disk             ;;
        4)  mod_network          ;;
        5)  mod_processes        ;;
        6)  mod_logs             ;;
        7)  mod_services         ;;
        8)  mod_hardware         ;;
        9)  mod_security         ;;
        10) mod_containers       ;;
        11) mod_kubernetes       ;;
        12) mod_dns              ;;
        13) mod_performance      ;;
        14) mod_kernel           ;;
        15) mod_health_summary   ;;
        [Aa]) run_all            ;;
        [Ll]) toggle_log         ;;
        [Qq]) echo -e "${GREEN}Goodbye!${RESET}"; exit 0 ;;
        *)   warn "Invalid option: $1" ;;
    esac
}

run_all() {
    for i in $(seq 1 15); do
        dispatch "$i"
    done
}

toggle_log() {
    if [[ -z "$LOG_FILE" ]]; then
        init_log
    else
        ok "Already logging to: $LOG_FILE"
    fi
}

# =============================================================================
#  ENTRY POINT
# =============================================================================

# If args provided, run those modules non-interactively
if [[ $# -gt 0 ]]; then
    require_root
    for arg in "$@"; do
        dispatch "$arg"
    done
    exit 0
fi

# Interactive mode
require_root
while true; do
    show_menu
    read -rp "  Choice: " choice
    dispatch "$choice"
    pause
done

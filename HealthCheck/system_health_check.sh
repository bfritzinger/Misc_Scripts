#!/usr/bin/env bash
# =============================================================================
# system_health_check.sh  v2.1.0
# Comprehensive Linux System Health Check + Trend Data Export
#
# Outputs (every run):
#   1. Coloured human-readable report  →  stdout + LOG_FILE
#   2. Appended CSV row                →  METRICS_CSV   (one row per run)
#   3. JSON snapshot                   →  METRICS_JSON  (per-run file)
#
# Override any setting via env var before running:
#   METRICS_DIR=/data/health DISK_WARN=75 sudo ./system_health_check.sh
# =============================================================================

# NOTE: -e intentionally omitted — a health-check script must survive failed
# sub-commands (smartctl, vmstat, sensors …).  We handle errors explicitly.
set -uo pipefail

# ---------------------------------------------------------------------------
# CONFIG
# ---------------------------------------------------------------------------
SCRIPT_VERSION="2.1.0"
RUN_EPOCH=$(date +%s)
REPORT_DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')
THIS_HOST=$(hostname -f 2>/dev/null || hostname)

METRICS_DIR="${METRICS_DIR:-/var/log/sys_health}"
mkdir -p "$METRICS_DIR"

LOG_FILE="${LOG_FILE:-${METRICS_DIR}/report_$(date +%Y%m%d_%H%M%S).log}"
METRICS_CSV="${METRICS_CSV:-${METRICS_DIR}/metrics.csv}"
METRICS_JSON="${METRICS_JSON:-${METRICS_DIR}/snapshot_$(date +%Y%m%d_%H%M%S).json}"

DISK_WARN="${DISK_WARN:-80}";   DISK_CRIT="${DISK_CRIT:-90}"
MEM_WARN="${MEM_WARN:-80}";     MEM_CRIT="${MEM_CRIT:-95}"
LOAD_WARN="${LOAD_WARN:-2}";    LOAD_CRIT="${LOAD_CRIT:-4}"
INODE_WARN="${INODE_WARN:-80}"; INODE_CRIT="${INODE_CRIT:-90}"
SWAP_WARN="${SWAP_WARN:-50}";   SWAP_CRIT="${SWAP_CRIT:-80}"
CLOSE_WAIT_WARN="${CLOSE_WAIT_WARN:-100}"
TIME_WAIT_WARN="${TIME_WAIT_WARN:-500}"

# ---------------------------------------------------------------------------
# COLOURS
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    # $'...' syntax embeds actual ESC bytes so ANSI stripping works reliably
    RED=$'\033[0;31m';   YELLOW=$'\033[1;33m'; GREEN=$'\033[0;32m'
    CYAN=$'\033[0;36m';  BOLD=$'\033[1m';      RESET=$'\033[0m'
    BLUE=$'\033[0;34m';  MAGENTA=$'\033[0;35m'; DIM=$'\033[2m'
else
    RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; RESET=''; BLUE=''; MAGENTA=''; DIM=''
fi

# ---------------------------------------------------------------------------
# COUNTERS  (use += 0 trick to avoid (( x++ )) returning 1 under set -e)
# ---------------------------------------------------------------------------
WARNINGS=0; CRITICALS=0; CHECKS_PASSED=0

# ---------------------------------------------------------------------------
# METRIC STORE
# ---------------------------------------------------------------------------
declare -A  M
declare -a  M_KEYS=()

# metric <key> <value> [unit] [description]
# Stores value AND prints it inline (dim) under the relevant check line.
metric() {
    local key="$1" value="$2" unit="${3:-}" desc="${4:-}"
    # Sanitize: strip newlines/CR and trim whitespace so values are always single-line
    value="${value//$'\n'/ }"; value="${value//$'\r'/ }"
    value="$(printf '%s' "$value" | tr -d '\n\r' | xargs)"
    if [[ -z "${M[$key]+_}" ]]; then M_KEYS+=("$key"); fi
    M["$key"]="$value"
    local disp="${key}=${value}${unit:+ ${unit}}${desc:+  (${desc})}"
    echo -e "  ${DIM}  ↳ ${disp}${RESET}"
}

# ---------------------------------------------------------------------------
# DISPLAY HELPERS
# ---------------------------------------------------------------------------

# visible_len <string>
# Count printable characters after stripping ANSI escape codes.
# Uses Python3 (always present on modern Linux) for locale-safe Unicode char counting —
# avoids wc -m byte/char inconsistencies across C vs UTF-8 locales.
visible_len() {
    python3 -c "
import sys, re
s = sys.argv[1]
s = re.sub(r'\x1b\[[0-9;]*[mK]', '', s)
print(len(s), end='')
" "$1"
}

# hline <width> <char>
# Print exactly <width> repetitions of <char> using awk — safe for multi-byte chars.
hline() {
    awk -v n="$1" -v c="${2:-═}" 'BEGIN{ for(i=0;i<n;i++) printf c }'
}

# term_width
# Return usable terminal width: tput cols capped to [60, 120].
term_width() {
    local w; w=$(tput cols 2>/dev/null || echo 80)
    (( w > 120 )) && w=120
    (( w < 60  )) && w=60
    echo "$w"
}

# header <title>
# Single-row box sized to the title, with 2-space padding each side.
header() {
    local title="$1"
    local tw; tw=$(term_width)
    local tlen; tlen=$(visible_len "$title")
    local inner=$(( tlen + 4 ))
    (( inner < 40       )) && inner=40
    (( inner > tw - 2   )) && inner=$(( tw - 2 ))
    local bar; bar=$(hline "$inner" '═')
    echo
    printf "${BOLD}${CYAN}╔%s╗${RESET}\n" "$bar"
    printf "${BOLD}${CYAN}║${RESET}  %-$(( inner - 4 ))s  ${BOLD}${CYAN}║${RESET}\n" "$title"
    printf "${BOLD}${CYAN}╚%s╝${RESET}\n" "$bar"
}

# section <title>
# Bold ▶ heading followed by a full terminal-width rule.
section() {
    local tw; tw=$(term_width)
    echo
    printf "${BOLD}${BLUE}▶  %s${RESET}\n" "$1"
    hline "$tw" '─'; echo
}

# box_banner <colour> <title> [row ...]
#
# Draws a box that auto-sizes to its widest content row or title.
# Row prefixes:
#   "="   → render as a ╠═╣ divider (no content)
#   "~"   → row contains embedded ANSI colour codes; strip them for width measurement
#   (none)→ plain text row, no embedded codes
#
# Example:
#   box_banner "$CYAN" "MY TITLE" \
#       "plain row" \
#       "~${GREEN}coloured${RESET} row" \
#       "=" \
#       "another plain row"
box_banner() {
    local colour="$1" title="$2"; shift 2
    local rows=("$@")
    local tw; tw=$(term_width)

    # --- measure widest row ---
    local title_len; title_len=$(visible_len "$title")
    local max=$(( title_len + 4 ))   # title + 2-space padding each side + 2 for ║

    for row in "${rows[@]}"; do
        [[ "$row" == "=" ]] && continue
        local plain="${row#\~}"
        local vl; vl=$(visible_len "$plain")
        local needed=$(( vl + 4 ))
        (( needed > max )) && max=$needed
    done

    local inner=$max
    (( inner > tw - 2 )) && inner=$(( tw - 2 ))
    local content_w=$(( inner - 4 ))   # printable width between the two ║ + 2-space pads

    local bar; bar=$(hline "$inner" '═')

    # --- title row (centred against full inner width, no 2-space margin) ---
    local pad_total=$(( inner - title_len ))
    local pad_l=$(( pad_total / 2 ))
    local pad_r=$(( pad_total - pad_l ))

    echo
    printf "${BOLD}${colour}╔%s╗${RESET}\n" "$bar"
    printf "${BOLD}${colour}║${RESET}%*s%s%*s${BOLD}${colour}║${RESET}\n" \
        "$pad_l" "" "$title" "$pad_r" ""
    printf "${BOLD}${colour}╠%s╣${RESET}\n" "$bar"

    # --- content rows ---
    for row in "${rows[@]}"; do
        if [[ "$row" == "=" ]]; then
            printf "${BOLD}${colour}╠%s╣${RESET}\n" "$bar"
            continue
        fi
        local plain="${row#\~}"
        local vl; vl=$(visible_len "$plain")
        local rpad=$(( content_w - vl ))
        # %b interprets escape sequences so actual ESC colour codes render correctly
        printf "${BOLD}${colour}║${RESET}  %b%*s  ${BOLD}${colour}║${RESET}\n" \
            "$plain" "$rpad" ""
    done

    printf "${BOLD}${colour}╚%s╝${RESET}\n" "$bar"
}

ok()   { echo -e "  ${GREEN}[  OK  ]${RESET}  $*"; CHECKS_PASSED=$(( CHECKS_PASSED + 1 )); }
warn() { echo -e "  ${YELLOW}[ WARN ]${RESET}  $*"; WARNINGS=$(( WARNINGS + 1 )); }
crit() { echo -e "  ${RED}[ CRIT ]${RESET}  $*"; CRITICALS=$(( CRITICALS + 1 )); }
info() { echo -e "  ${CYAN}[ INFO ]${RESET}  $*"; }

cmd_exists() { command -v "$1" &>/dev/null; }
gt() { awk "BEGIN{exit !($1 > $2)}"; }

# Safe command runner — captures output, returns empty string on failure
safe() { "$@" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# TEE OUTPUT TO LOG
# ---------------------------------------------------------------------------
exec > >(tee -a "$LOG_FILE") 2>&1

# ===========================================================================
# BANNER
# ===========================================================================
echo -e "${BOLD}${MAGENTA}"
cat <<'BANNER'
  ███████╗██╗   ██╗███████╗    ██╗  ██╗███████╗ █████╗ ██╗  ████████╗██╗  ██╗
  ██╔════╝╚██╗ ██╔╝██╔════╝    ██║  ██║██╔════╝██╔══██╗██║  ╚══██╔══╝██║  ██║
  ███████╗ ╚████╔╝ ███████╗    ███████║█████╗  ███████║██║     ██║   ███████║
  ╚════██║  ╚██╔╝  ╚════██║    ██╔══██║██╔══╝  ██╔══██║██║     ██║   ██╔══██║
  ███████║   ██║   ███████║    ██║  ██║███████╗██║  ██║███████╗██║   ██║  ██║
  ╚══════╝   ╚═╝   ╚══════╝    ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝  ╚═╝
BANNER
echo -e "${RESET}"

header "System Health Check  v${SCRIPT_VERSION}"
info "Host       : ${THIS_HOST}"
info "Date       : ${REPORT_DATE}"
info "Metrics CSV: ${METRICS_CSV}  (appended each run)"
info "JSON snap  : ${METRICS_JSON}"
info "Run as     : $(id)"

metric "timestamp_epoch" "$RUN_EPOCH"   "s"  "Unix epoch of this run"
metric "timestamp_human" "$REPORT_DATE" ""   "Human-readable timestamp"
metric "hostname"        "$THIS_HOST"   ""   "System hostname"

# ===========================================================================
# 1. OS & KERNEL
# ===========================================================================
section "OS & Kernel"

KERNEL=$(uname -r)
ARCH=$(uname -m)
UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime)
UPTIME_HUMAN=$(awk '{d=int($1/86400);h=int(($1%86400)/3600);m=int(($1%3600)/60);
    printf "%dd %02dh %02dm",d,h,m}' /proc/uptime)
OS_NAME=$(grep -oP '(?<=PRETTY_NAME=")[^"]+' /etc/os-release 2>/dev/null || uname -s)

info "OS: ${OS_NAME}  |  Kernel: ${KERNEL}  |  Arch: ${ARCH}"
info "Uptime: ${UPTIME_HUMAN}"

metric "uptime_sec"      "$UPTIME_SEC"  "s"  "Seconds since boot"
metric "kernel"          "$KERNEL"      ""   "Running kernel"
metric "os"              "$OS_NAME"     ""   "OS name"
metric "arch"            "$ARCH"        ""   "CPU architecture"

REBOOT_REQUIRED=0
if [[ -f /var/run/reboot-required ]]; then
    REBOOT_REQUIRED=1
    PKGS=$(tr '\n' ' ' < /var/run/reboot-required.pkgs 2>/dev/null | head -c 80)
    warn "Reboot required: ${PKGS}"
fi
metric "reboot_required" "$REBOOT_REQUIRED" "bool" "Pending reboot"

if (( UPTIME_SEC < 300 )); then
    warn "Rebooted less than 5 minutes ago"
else
    ok "Uptime: ${UPTIME_HUMAN}"
fi

# ===========================================================================
# 2. CPU & LOAD
# ===========================================================================
section "CPU & Load Average"

CPU_COUNT=$(nproc)
read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg

info "CPU cores : ${CPU_COUNT}"
info "Load avg  : ${LOAD1} (1m)  ${LOAD5} (5m)  ${LOAD15} (15m)"

metric "cpu_count" "$CPU_COUNT" "cores" "Logical CPUs"
metric "load_1m"   "$LOAD1"     ""      "1-min load average"
metric "load_5m"   "$LOAD5"     ""      "5-min load average"
metric "load_15m"  "$LOAD15"    ""      "15-min load average"

LOAD_WARN_VAL=$(awk "BEGIN{printf \"%.2f\", ${CPU_COUNT} * ${LOAD_WARN}}")
LOAD_CRIT_VAL=$(awk "BEGIN{printf \"%.2f\", ${CPU_COUNT} * ${LOAD_CRIT}}")

if   gt "$LOAD1" "$LOAD_CRIT_VAL"; then crit "Load ${LOAD1} > critical (${LOAD_CRIT_VAL})"
elif gt "$LOAD1" "$LOAD_WARN_VAL"; then warn "Load ${LOAD1} > warning (${LOAD_WARN_VAL})"
else ok "Load average: ${LOAD1}  (warn=${LOAD_WARN_VAL})"; fi

# CPU frequency
if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
    CPU_FREQ_MHZ=$(awk '{printf "%.0f", $1/1000}' \
        /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
    info "CPU freq  : ${CPU_FREQ_MHZ} MHz"
    metric "cpu_freq_mhz" "$CPU_FREQ_MHZ" "MHz" "CPU freq core0"
fi
if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
    GOV=$(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    info "Governor  : ${GOV}"
    metric "cpu_governor" "$GOV" "" "Scaling governor"
fi

# CPU steal — guard against vmstat failure
CPU_STEAL=0
if cmd_exists vmstat; then
    _steal=$(vmstat 1 2 2>/dev/null | awk 'NR==4{print $17}')
    CPU_STEAL="${_steal:-0}"
    info "CPU steal : ${CPU_STEAL}%"
    metric "cpu_steal_pct" "$CPU_STEAL" "%" "CPU steal (VM)"
    if [[ -n "$CPU_STEAL" ]] && (( CPU_STEAL > 10 )); then
        warn "CPU steal ${CPU_STEAL}% — possible noisy neighbour"
    else
        ok "CPU steal: ${CPU_STEAL}%"
    fi
fi

# CPU time breakdown from /proc/stat
if [[ -r /proc/stat ]]; then
    read -r _ u n s id wa hi si st _ < /proc/stat
    T=$(( u+n+s+id+wa+hi+si+st ))
    if (( T > 0 )); then
        CPU_USER=$(awk   "BEGIN{printf \"%.1f\", ($u+$n)*100/$T}")
        CPU_SYS=$(awk    "BEGIN{printf \"%.1f\", $s*100/$T}")
        CPU_IDLE=$(awk   "BEGIN{printf \"%.1f\", $id*100/$T}")
        CPU_IOWAIT=$(awk "BEGIN{printf \"%.1f\", $wa*100/$T}")
        info "CPU split : user=${CPU_USER}%  sys=${CPU_SYS}%  idle=${CPU_IDLE}%  iowait=${CPU_IOWAIT}%"
        metric "cpu_user_pct"   "$CPU_USER"   "%" "User CPU %"
        metric "cpu_sys_pct"    "$CPU_SYS"    "%" "Sys CPU %"
        metric "cpu_idle_pct"   "$CPU_IDLE"   "%" "Idle CPU %"
        metric "cpu_iowait_pct" "$CPU_IOWAIT" "%" "I/O wait %"
    fi
    CTXT=$(awk '/^ctxt/{print $2}' /proc/stat)
    INTR=$(awk '/^intr/{print $2}' /proc/stat)
    [[ -n "$CTXT" ]] && metric "cpu_context_switches_total" "$CTXT" "" "Context switches since boot"
    [[ -n "$INTR" ]] && metric "cpu_interrupts_total"       "$INTR" "" "Interrupts since boot"
fi

# ===========================================================================
# 3. MEMORY & SWAP
# ===========================================================================
section "Memory & Swap"

rmf() { awk "/^${1}:/{print \$2}" /proc/meminfo; }

MEM_TOTAL=$(rmf MemTotal);  MEM_AVAIL=$(rmf MemAvailable)
MEM_FREE=$(rmf MemFree);    MEM_BUFFERS=$(rmf Buffers)
MEM_CACHED=$(rmf Cached);   MEM_SLAB=$(rmf Slab)
SWAP_TOTAL=$(rmf SwapTotal); SWAP_FREE=$(rmf SwapFree)

MEM_USED_KB=$(( MEM_TOTAL - MEM_AVAIL ))
MEM_USED_MB=$(( MEM_USED_KB / 1024 ))
MEM_TOTAL_MB=$(( MEM_TOTAL / 1024 ))
MEM_AVAIL_MB=$(( MEM_AVAIL / 1024 ))
MEM_BUFFERS_MB=$(( MEM_BUFFERS / 1024 ))
MEM_CACHED_MB=$(( MEM_CACHED / 1024 ))
MEM_SLAB_MB=$(( MEM_SLAB / 1024 ))
MEM_USED_PCT=$(awk "BEGIN{printf \"%.1f\", ${MEM_USED_KB}*100/${MEM_TOTAL}}")

info "RAM: total=${MEM_TOTAL_MB}MB  avail=${MEM_AVAIL_MB}MB  used=${MEM_USED_MB}MB (${MEM_USED_PCT}%)"
info "     buffers=${MEM_BUFFERS_MB}MB  cached=${MEM_CACHED_MB}MB  slab=${MEM_SLAB_MB}MB"

metric "mem_total_mb"   "$MEM_TOTAL_MB"   "MB" "Total RAM"
metric "mem_avail_mb"   "$MEM_AVAIL_MB"   "MB" "Available RAM"
metric "mem_used_mb"    "$MEM_USED_MB"    "MB" "Used RAM"
metric "mem_used_pct"   "$MEM_USED_PCT"   "%"  "RAM utilisation"
metric "mem_buffers_mb" "$MEM_BUFFERS_MB" "MB" "Kernel buffers"
metric "mem_cached_mb"  "$MEM_CACHED_MB"  "MB" "Page cache"
metric "mem_slab_mb"    "$MEM_SLAB_MB"    "MB" "Slab allocator"

if   gt "$MEM_USED_PCT" "$MEM_CRIT"; then crit "Memory ${MEM_USED_PCT}% > critical (${MEM_CRIT}%)"
elif gt "$MEM_USED_PCT" "$MEM_WARN"; then warn "Memory ${MEM_USED_PCT}% > warning (${MEM_WARN}%)"
else ok "Memory: ${MEM_USED_PCT}% used"; fi

SWAP_USED_MB=0; SWAP_TOTAL_MB=0; SWAP_USED_PCT=0
if (( SWAP_TOTAL > 0 )); then
    SWAP_USED=$(( SWAP_TOTAL - SWAP_FREE ))
    SWAP_USED_MB=$(( SWAP_USED / 1024 ))
    SWAP_TOTAL_MB=$(( SWAP_TOTAL / 1024 ))
    SWAP_USED_PCT=$(awk "BEGIN{printf \"%.1f\", ${SWAP_USED}*100/${SWAP_TOTAL}}")
    info "Swap: ${SWAP_USED_MB}MB / ${SWAP_TOTAL_MB}MB (${SWAP_USED_PCT}%)"
    if   gt "$SWAP_USED_PCT" "$SWAP_CRIT"; then crit "Swap ${SWAP_USED_PCT}% — heavy memory pressure"
    elif gt "$SWAP_USED_PCT" "$SWAP_WARN"; then warn "Swap ${SWAP_USED_PCT}%"
    else ok "Swap: ${SWAP_USED_PCT}% used"; fi
else
    info "No swap configured"
fi
metric "swap_total_mb" "$SWAP_TOTAL_MB" "MB" "Total swap"
metric "swap_used_mb"  "$SWAP_USED_MB"  "MB" "Used swap"
metric "swap_used_pct" "$SWAP_USED_PCT" "%"  "Swap utilisation"

# ===========================================================================
# 4. DISK SPACE & INODES
# ===========================================================================
section "Disk Space & Inodes"

DISK_CRIT_COUNT=0; DISK_WARN_COUNT=0

while IFS= read -r line; do
    [[ "$line" =~ ^Filesystem ]] && continue
    [[ "$line" =~ ^(tmpfs|devtmpfs|overlay|squashfs|udev|none|cgroupfs|shm) ]] && continue
    FS=$(    awk '{print $1}' <<< "$line")
    USE_PCT=$(awk '{print $5}' <<< "$line" | tr -d '%')
    MOUNT=$(  awk '{print $6}' <<< "$line")
    [[ -z "$USE_PCT" || ! "$USE_PCT" =~ ^[0-9]+$ ]] && continue

    MKEY=$(sed 's|/|_|g; s|^_||; s/[^a-zA-Z0-9_]/_/g' <<< "$MOUNT")
    [[ -z "$MKEY" ]] && MKEY="root"

    # Get MB values from a second df call
    read -r _ TOTAL_MB USED_MB AVAIL_MB _ _ <<< \
        "$(df -BM "$MOUNT" 2>/dev/null | awk 'NR==2{gsub(/M/,"",$2); gsub(/M/,"",$3); gsub(/M/,"",$4); print}')" || true
    TOTAL_MB="${TOTAL_MB:-0}"; USED_MB="${USED_MB:-0}"; AVAIL_MB="${AVAIL_MB:-0}"

    info "  ${MOUNT}: ${USE_PCT}% used  (${AVAIL_MB}MB free / ${TOTAL_MB}MB total)"
    metric "disk_${MKEY}_used_pct" "$USE_PCT"  "%" "Disk usage: ${MOUNT}"
    metric "disk_${MKEY}_avail_mb" "$AVAIL_MB" "MB" "Free: ${MOUNT}"
    metric "disk_${MKEY}_used_mb"  "$USED_MB"  "MB" "Used: ${MOUNT}"
    metric "disk_${MKEY}_total_mb" "$TOTAL_MB" "MB" "Total: ${MOUNT}"

    if   (( USE_PCT >= DISK_CRIT )); then
        crit "Disk ${MOUNT}: ${USE_PCT}%"
        DISK_CRIT_COUNT=$(( DISK_CRIT_COUNT + 1 ))
    elif (( USE_PCT >= DISK_WARN )); then
        warn "Disk ${MOUNT}: ${USE_PCT}%"
        DISK_WARN_COUNT=$(( DISK_WARN_COUNT + 1 ))
    else
        ok   "Disk ${MOUNT}: ${USE_PCT}%"
    fi
done < <(df -h --output=source,size,used,avail,pcent,target 2>/dev/null \
         || df -h 2>/dev/null)

metric "disk_crit_count" "$DISK_CRIT_COUNT" "" "Disks at critical"
metric "disk_warn_count" "$DISK_WARN_COUNT" "" "Disks at warning"

echo
info "Inode usage:"
while IFS= read -r line; do
    [[ "$line" =~ ^Filesystem ]] && continue
    [[ "$line" =~ ^(tmpfs|devtmpfs|overlay|squashfs|udev|shm) ]] && continue
    IUSE=$( awk '{print $5}' <<< "$line" | tr -d '%')
    MOUNT=$(awk '{print $6}' <<< "$line")
    [[ -z "$IUSE" || "$IUSE" == "-" || ! "$IUSE" =~ ^[0-9]+$ ]] && continue
    MKEY=$(sed 's|/|_|g; s|^_||; s/[^a-zA-Z0-9_]/_/g' <<< "$MOUNT")
    [[ -z "$MKEY" ]] && MKEY="root"
    metric "inode_${MKEY}_used_pct" "$IUSE" "%" "Inode usage: ${MOUNT}"
    if   (( IUSE >= INODE_CRIT )); then crit "Inodes ${MOUNT}: ${IUSE}%"
    elif (( IUSE >= INODE_WARN )); then warn "Inodes ${MOUNT}: ${IUSE}%"
    else ok "Inodes ${MOUNT}: ${IUSE}%"; fi
done < <(df -i 2>/dev/null)

# ===========================================================================
# 5. DISK I/O STATS (/proc/diskstats)
# ===========================================================================
section "Disk I/O Statistics"

if [[ -r /proc/diskstats ]]; then
    FOUND_DISK=0
    while IFS= read -r line; do
        DEV=$(awk '{print $3}' <<< "$line")
        # match physical disks only
        [[ "$DEV" =~ ^(sd[a-z]$|nvme[0-9]+n[0-9]+$|mmcblk[0-9]+$|hd[a-z]$|vd[a-z]$|xvd[a-z]$) ]] || continue
        FOUND_DISK=1
        READS=$(awk '{print $4}'  <<< "$line")
        RSEC=$(awk  '{print $6}'  <<< "$line")
        WRITES=$(awk '{print $8}' <<< "$line")
        WSEC=$(awk  '{print $10}' <<< "$line")
        IO_MS=$(awk '{print $13}' <<< "$line")
        RKB=$(( RSEC * 512 / 1024 ))
        WKB=$(( WSEC * 512 / 1024 ))
        info "  ${DEV}: reads=${READS} (${RKB} KB)  writes=${WRITES} (${WKB} KB)  io_ms=${IO_MS}"
        metric "io_${DEV}_reads_total"  "$READS" ""   "Reads since boot"
        metric "io_${DEV}_writes_total" "$WRITES" ""  "Writes since boot"
        metric "io_${DEV}_read_kb"      "$RKB"   "KB" "KB read since boot"
        metric "io_${DEV}_write_kb"     "$WKB"   "KB" "KB written since boot"
        metric "io_${DEV}_io_ms"        "$IO_MS" "ms" "ms in I/O since boot"
        ok "${DEV}: I/O stats captured"
    done < /proc/diskstats
    (( FOUND_DISK == 0 )) && info "No physical disks found in /proc/diskstats"
fi

# ===========================================================================
# 6. DISK HEALTH (S.M.A.R.T.)
# ===========================================================================
section "Disk Health (S.M.A.R.T.)"

SMART_FAIL_COUNT=0
if cmd_exists smartctl; then
    mapfile -t DISKS < <(lsblk -d -o NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1}')
    if (( ${#DISKS[@]} == 0 )); then
        info "No disks found via lsblk"
    fi
    for DISK in "${DISKS[@]}"; do
        DK=$(basename "$DISK")
        SOUT=$(smartctl -H "$DISK" 2>&1) || true
        SSTATUS=$(grep -i "SMART overall-health" <<< "$SOUT" | awk -F: '{print $2}' | xargs || true)
        if grep -qi "Permission denied\|Operation not permitted" <<< "$SOUT" 2>/dev/null; then
            info "${DISK}: needs root for SMART"
            metric "smart_${DK}_status" "no_permission" "" "SMART status"
            continue
        elif [[ -z "$SSTATUS" ]]; then
            info "${DISK}: SMART not supported"
            metric "smart_${DK}_status" "unsupported" "" "SMART status"
            continue
        fi
        metric "smart_${DK}_status" "$SSTATUS" "" "SMART health"
        REALLOC=$(smartctl -A "$DISK" 2>/dev/null | awk '/Reallocated_Sector_Ct/{print $10}' || true)
        PENDING=$(smartctl -A "$DISK" 2>/dev/null | awk '/Current_Pending_Sector/{print $10}' || true)
        PWRON=$(  smartctl -A "$DISK" 2>/dev/null | awk '/Power_On_Hours/{print $10}'          || true)
        TDISK=$(  smartctl -A "$DISK" 2>/dev/null | awk '/Temperature_Celsius/{print $10}' | head -1 || true)
        [[ -n "$REALLOC" ]] && metric "smart_${DK}_reallocated"   "$REALLOC" ""  "Reallocated sectors"
        [[ -n "$PENDING" ]] && metric "smart_${DK}_pending"        "$PENDING" ""  "Pending sectors"
        [[ -n "$PWRON"   ]] && metric "smart_${DK}_power_on_hours" "$PWRON"   "h" "Power-on hours"
        [[ -n "$TDISK"   ]] && metric "smart_${DK}_temp_c"         "$TDISK"   "°C" "Drive temp"
        if grep -qi "PASSED\|OK" <<< "$SSTATUS"; then
            ok "${DISK}: SMART ${SSTATUS}${PWRON:+  (${PWRON}h on)}"
        else
            crit "${DISK}: SMART ${SSTATUS}"
            SMART_FAIL_COUNT=$(( SMART_FAIL_COUNT + 1 ))
        fi
        [[ -n "$REALLOC" && "$REALLOC" =~ ^[0-9]+$ && $REALLOC -gt 0 ]] && \
            warn "${DISK}: ${REALLOC} reallocated sectors"
        [[ -n "$PENDING" && "$PENDING" =~ ^[0-9]+$ && $PENDING -gt 0 ]] && \
            warn "${DISK}: ${PENDING} pending sectors"
    done
else
    info "smartctl not found — install smartmontools"
fi
metric "smart_fail_count" "$SMART_FAIL_COUNT" "" "Disks failing SMART"

if cmd_exists mdadm && [[ -r /proc/mdstat ]]; then
    section "Software RAID (mdadm)"
    RAID_DEG=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        info "$line"
        if grep -qiE "\[.*_.*\]|degraded|failed" <<< "$line"; then
            crit "RAID degraded: $line"
            RAID_DEG=$(( RAID_DEG + 1 ))
        fi
    done < <(grep -v "^Personalities\|^unused\|^ *$" /proc/mdstat || true)
    metric "raid_degraded_count" "$RAID_DEG" "" "Degraded RAID arrays"
fi

# ===========================================================================
# 7. NETWORK INTERFACES
# ===========================================================================
section "Network Interface Status"

IFACE_DOWN=0
IFACE_COUNT=0

if cmd_exists ip; then
    # Build list of interfaces from /sys directly — more reliable than parsing ip output
    for IFACE_PATH in /sys/class/net/*/; do
        iface=$(basename "$IFACE_PATH")
        [[ "$iface" == "lo" ]] && continue

        IFACE_COUNT=$(( IFACE_COUNT + 1 ))
        IK=$(tr '.-' '__' <<< "$iface")

        # State
        STATE=$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null || echo "unknown")

        # Speed (may not exist for virtual/wifi)
        SPEED=""
        if [[ -r "/sys/class/net/${iface}/speed" ]]; then
            _spd=$(cat "/sys/class/net/${iface}/speed" 2>/dev/null || true)
            [[ "$_spd" =~ ^[0-9]+$ && $_spd -gt 0 ]] && SPEED="$_spd"
        fi

        # IP addresses
        IPS=$(ip -br addr show "$iface" 2>/dev/null | awk '{$1=$2=""; gsub(/^ */,"",$0); print $0}' | xargs || true)

        # Stats
        RXB=$(cat  "/sys/class/net/${iface}/statistics/rx_bytes"    2>/dev/null || echo 0)
        TXB=$(cat  "/sys/class/net/${iface}/statistics/tx_bytes"    2>/dev/null || echo 0)
        RXP=$(cat  "/sys/class/net/${iface}/statistics/rx_packets"  2>/dev/null || echo 0)
        TXP=$(cat  "/sys/class/net/${iface}/statistics/tx_packets"  2>/dev/null || echo 0)
        RXE=$(cat  "/sys/class/net/${iface}/statistics/rx_errors"   2>/dev/null || echo 0)
        TXE=$(cat  "/sys/class/net/${iface}/statistics/tx_errors"   2>/dev/null || echo 0)
        RXD=$(cat  "/sys/class/net/${iface}/statistics/rx_dropped"  2>/dev/null || echo 0)
        TXD=$(cat  "/sys/class/net/${iface}/statistics/tx_dropped"  2>/dev/null || echo 0)

        RXMB=$(( RXB / 1048576 ))
        TXMB=$(( TXB / 1048576 ))

        info "  ${iface}  state=${STATE}${SPEED:+  speed=${SPEED}Mbps}  ${IPS:-no IP}"
        info "     RX=${RXMB}MB (${RXP} pkts, ${RXE} err, ${RXD} drop)  TX=${TXMB}MB (${TXP} pkts, ${TXE} err, ${TXD} drop)"

        metric "net_${IK}_state"   "$STATE"  ""    "Link state"
        metric "net_${IK}_rx_mb"   "$RXMB"   "MB"  "RX since boot"
        metric "net_${IK}_tx_mb"   "$TXMB"   "MB"  "TX since boot"
        metric "net_${IK}_rx_pkts" "$RXP"    ""    "RX packets"
        metric "net_${IK}_tx_pkts" "$TXP"    ""    "TX packets"
        metric "net_${IK}_rx_err"  "$RXE"    ""    "RX errors"
        metric "net_${IK}_tx_err"  "$TXE"    ""    "TX errors"
        metric "net_${IK}_rx_drop" "$RXD"    ""    "RX dropped"
        metric "net_${IK}_tx_drop" "$TXD"    ""    "TX dropped"
        [[ -n "$SPEED" ]] && metric "net_${IK}_speed_mbps" "$SPEED" "Mbps" "Link speed"

        case "$STATE" in
            up)
                ok "${iface}: UP${SPEED:+ @ ${SPEED}Mbps}  RX=${RXMB}MB TX=${TXMB}MB" ;;
            down)
                warn "${iface}: DOWN"
                IFACE_DOWN=$(( IFACE_DOWN + 1 )) ;;
            *)
                info "${iface}: state=${STATE}" ;;
        esac

        (( RXE > 100 || TXE > 100 )) && \
            warn "${iface}: interface errors  RX=${RXE}  TX=${TXE}"
        (( RXD > 1000 )) && \
            warn "${iface}: ${RXD} RX dropped packets"
    done

    if (( IFACE_COUNT == 0 )); then
        info "No non-loopback interfaces found in /sys/class/net"
    fi
else
    info "ip command not found"
fi

metric "net_iface_count"     "$IFACE_COUNT" ""  "Non-loopback interfaces"
metric "net_iface_down_count" "$IFACE_DOWN"  ""  "Interfaces in DOWN state"

# ===========================================================================
# 8. SOCKET / CONNECTION STATES
# ===========================================================================
section "Socket & Connection States"

# Pre-seed every standard TCP state to 0 so CSV columns are consistent
# across every run regardless of whether any connections exist in that state.
declare -A SS_STATES=(
    ["LISTEN"]=0      ["ESTABLISHED"]=0   ["CLOSE-WAIT"]=0
    ["TIME-WAIT"]=0   ["FIN-WAIT-1"]=0    ["FIN-WAIT-2"]=0
    ["SYN-SENT"]=0    ["SYN-RECV"]=0      ["LAST-ACK"]=0
    ["CLOSING"]=0     ["CLOSE"]=0
)

SOCK_CMD=""
if   cmd_exists ss;      then SOCK_CMD="ss -tan"
elif cmd_exists netstat; then SOCK_CMD="netstat -tan"; fi

TCP_TOTAL=0
SOCK_TOOL_FOUND=0

if [[ -n "$SOCK_CMD" ]]; then
    SOCK_TOOL_FOUND=1

    # Scan live socket table and accumulate counts
    while IFS= read -r line; do
        S=$(awk '{print $1}' <<< "$line")
        [[ "$S" =~ ^(State|Recv-Q)$ || -z "$S" ]] && continue
        # Normalise: ss uses ESTAB, netstat uses ESTABLISHED — map to ESTABLISHED
        [[ "$S" == "ESTAB" ]] && S="ESTABLISHED"
        SS_STATES["$S"]=$(( ${SS_STATES["$S"]:-0} + 1 ))
    done < <($SOCK_CMD 2>/dev/null || true)

    # Compute total from all states
    for C in "${SS_STATES[@]}"; do
        TCP_TOTAL=$(( TCP_TOTAL + C ))
    done

    # Print state table in a consistent order and emit a metric for each
    info "TCP socket state counts:"
    for S in LISTEN ESTABLISHED CLOSE-WAIT TIME-WAIT SYN-SENT SYN-RECV \
             FIN-WAIT-1 FIN-WAIT-2 LAST-ACK CLOSING CLOSE; do
        C=${SS_STATES["$S"]:-0}
        printf "  ${CYAN}[ INFO ]${RESET}    %-20s %d\n" "${S}:" "$C"
        SK=$(tr '-' '_' <<< "$S" | tr '[:upper:]' '[:lower:]')
        metric "tcp_${SK}" "$C" "" "TCP connections in state ${S}"
    done
    # Catch any unexpected states that were in the live table
    for S in "${!SS_STATES[@]}"; do
        case "$S" in
            LISTEN|ESTABLISHED|CLOSE-WAIT|TIME-WAIT|SYN-SENT|SYN-RECV|\
            FIN-WAIT-1|FIN-WAIT-2|LAST-ACK|CLOSING|CLOSE) continue ;;
        esac
        C=${SS_STATES["$S"]:-0}
        (( C == 0 )) && continue
        SK=$(tr '-' '_' <<< "$S" | tr '[:upper:]' '[:lower:]')
        info "  ${S}: ${C}  (unexpected state)"
        metric "tcp_${SK}" "$C" "" "TCP connections in state ${S}"
        TCP_TOTAL=$(( TCP_TOTAL + C ))
    done

    metric "tcp_total" "$TCP_TOTAL" "" "Total TCP table entries"
    info "TCP total: ${TCP_TOTAL}"

    # --- Convenience aliases used for threshold checks and display ---
    TCP_EST=${SS_STATES["ESTABLISHED"]}
    TCP_CW=${SS_STATES["CLOSE-WAIT"]}
    TCP_TW=${SS_STATES["TIME-WAIT"]}
    TCP_LS=${SS_STATES["LISTEN"]}
    TCP_F1=${SS_STATES["FIN-WAIT-1"]}
    TCP_F2=${SS_STATES["FIN-WAIT-2"]}
    TCP_LA=${SS_STATES["LAST-ACK"]}
    TCP_SR=${SS_STATES["SYN-RECV"]}
    TCP_SS=${SS_STATES["SYN-SENT"]}

    # --- Health evaluations ---
    if   (( TCP_CW >= CLOSE_WAIT_WARN )); then
        crit "CLOSE_WAIT=${TCP_CW} >= ${CLOSE_WAIT_WARN} — possible socket leak or hung app"
    elif (( TCP_CW > 0 )); then
        warn "CLOSE_WAIT=${TCP_CW}"
    else
        ok   "CLOSE_WAIT: 0"
    fi

    if (( TCP_TW >= TIME_WAIT_WARN )); then
        warn "TIME_WAIT=${TCP_TW} >= ${TIME_WAIT_WARN} — high connection churn"
    else
        ok   "TIME_WAIT: ${TCP_TW}"
    fi

    ok "ESTABLISHED: ${TCP_EST}   LISTEN: ${TCP_LS}"
    (( TCP_F1 + TCP_F2 > 50 )) && warn "FIN-WAIT-1=${TCP_F1}  FIN-WAIT-2=${TCP_F2} — slow close"
    (( TCP_LA > 20 ))           && warn "LAST-ACK=${TCP_LA} — remote peer not acknowledging close"
    (( TCP_SR > 50 ))           && warn "SYN-RECV=${TCP_SR} — possible SYN flood"
    (( TCP_SS > 20 ))           && warn "SYN-SENT=${TCP_SS} — many outbound connects pending"

    # --- UDP ---
    UDP_UNCONN=0; UDP_ESTAB=0
    if cmd_exists ss; then
        UDP_UNCONN=$(ss -uanp 2>/dev/null | grep -c "^UNCONN" || true); UDP_UNCONN=${UDP_UNCONN:-0}
        UDP_ESTAB=$( ss -uanp 2>/dev/null | grep -c "^ESTAB"  || true); UDP_ESTAB=${UDP_ESTAB:-0}
    fi
    UDP_TOTAL=$(( UDP_UNCONN + UDP_ESTAB ))
    info "UDP sockets: total=${UDP_TOTAL}  UNCONN=${UDP_UNCONN}  ESTAB=${UDP_ESTAB}"
    metric "udp_total"  "$UDP_TOTAL"  "" "Total UDP sockets"
    metric "udp_unconn" "$UDP_UNCONN" "" "UDP unconnected sockets"
    metric "udp_estab"  "$UDP_ESTAB"  "" "UDP connected sockets"

    # --- Unix domain sockets ---
    UNIX_TOTAL=0
    if cmd_exists ss; then
        UNIX_TOTAL=$(ss -xanp 2>/dev/null | tail -n +2 | wc -l || echo 0)
    fi
    info "Unix domain sockets: ${UNIX_TOTAL}"
    metric "unix_socket_total" "$UNIX_TOTAL" "" "Unix domain sockets"

    # --- Listening port list (human display only, not in CSV) ---
    echo
    info "Listening TCP ports:"
    if cmd_exists ss; then
        ss -tlnp 2>/dev/null \
            | awk 'NR>1 && /LISTEN/{printf "    %-28s %s\n",$4,$NF}' \
            | sort | head -20 || true
    fi

    echo
    info "Top 10 remote IPs by ESTABLISHED count:"
    if cmd_exists ss; then
        ss -tn state established 2>/dev/null \
            | awk 'NR>1{print $5}' \
            | sed 's/:[^:]*$//' \
            | sort | uniq -c | sort -rn | head -10 \
            | awk '{printf "    %5d  %s\n",$1,$2}' || true
    fi

else
    # No socket tool — still emit zeroed metrics so CSV columns stay consistent
    info "Neither ss nor netstat found — emitting zero socket metrics"
    for S in LISTEN ESTABLISHED CLOSE-WAIT TIME-WAIT SYN-SENT SYN-RECV \
             FIN-WAIT-1 FIN-WAIT-2 LAST-ACK CLOSING CLOSE; do
        SK=$(tr '-' '_' <<< "$S" | tr '[:upper:]' '[:lower:]')
        metric "tcp_${SK}" "0" "" "TCP connections in state ${S}"
    done
    metric "tcp_total"        "0" "" "Total TCP table entries"
    metric "udp_total"        "0" "" "Total UDP sockets"
    metric "udp_unconn"       "0" "" "UDP unconnected sockets"
    metric "udp_estab"        "0" "" "UDP connected sockets"
    metric "unix_socket_total" "0" "" "Unix domain sockets"
fi

# ===========================================================================
# 9. TOP PROCESSES
# ===========================================================================
section "Top Processes"

info "Top 10 by CPU:"
ps -eo pid,ppid,user,pcpu,pmem,vsz,rss,stat,comm --sort=-%cpu 2>/dev/null \
    | head -11 \
    | awk 'NR==1{printf "  %-7s %-7s %-12s %6s %6s %10s %10s %6s  %s\n",$1,$2,$3,$4,$5,$6,$7,$8,$9}
           NR>1{printf "  %-7s %-7s %-12s %6s %6s %10s %10s %6s  %s\n",$1,$2,$3,$4,$5,$6,$7,$8,$9}'

echo
info "Top 10 by Memory:"
ps -eo pid,ppid,user,pcpu,pmem,vsz,rss,stat,comm --sort=-%mem 2>/dev/null \
    | head -11 \
    | awk 'NR==1{printf "  %-7s %-7s %-12s %6s %6s %10s %10s %6s  %s\n",$1,$2,$3,$4,$5,$6,$7,$8,$9}
           NR>1{printf "  %-7s %-7s %-12s %6s %6s %10s %10s %6s  %s\n",$1,$2,$3,$4,$5,$6,$7,$8,$9}'

PROC_TOTAL=$(ps aux 2>/dev/null | tail -n +2 | wc -l || echo 0)
ZOMBIE_COUNT=$(ps aux 2>/dev/null | awk '$8~/^Z/{c++}END{print c+0}')
DSTATE_COUNT=$(ps aux 2>/dev/null | awk '$8~/^D/{c++}END{print c+0}')
THREAD_COUNT=$(ps -eo nlwp 2>/dev/null | tail -n +2 | awk '{s+=$1}END{print s+0}')

info "Processes: ${PROC_TOTAL}  Threads: ${THREAD_COUNT}  Zombies: ${ZOMBIE_COUNT}  D-state: ${DSTATE_COUNT}"
metric "proc_total"   "$PROC_TOTAL"   "" "Total processes"
metric "proc_threads" "$THREAD_COUNT" "" "Total threads"
metric "proc_zombie"  "$ZOMBIE_COUNT" "" "Zombie processes"
metric "proc_dstate"  "$DSTATE_COUNT" "" "D-state (I/O hung)"

if (( ZOMBIE_COUNT > 0 )); then
    warn "${ZOMBIE_COUNT} zombie process(es)"
    ps aux 2>/dev/null | awk '$8~/^Z/{print "    PID:"$2, $1, $11}' | head -5
else
    ok "No zombie processes"
fi
if (( DSTATE_COUNT > 5 )); then
    warn "${DSTATE_COUNT} D-state processes — possible I/O hang"
    ps aux 2>/dev/null | awk '$8~/^D/{print "    PID:"$2, $11}' | head -5
else
    ok "D-state processes: ${DSTATE_COUNT}"
fi

# ===========================================================================
# 10. SYSTEMD
# ===========================================================================
section "Systemd Service Health"

FAILED_UNIT_COUNT=0
if cmd_exists systemctl; then
    FAILED_UNITS=$(systemctl list-units --state=failed --no-legend 2>/dev/null | awk '{print $1}' || true)
    if [[ -n "$FAILED_UNITS" ]]; then
        FAILED_UNIT_COUNT=$(wc -l <<< "$FAILED_UNITS")
        crit "${FAILED_UNIT_COUNT} failed systemd unit(s):"
        while IFS= read -r u; do echo "    ✗ ${u}"; done <<< "$FAILED_UNITS"
    else
        ok "No failed systemd units"
    fi
else
    info "systemctl not found — skipping service checks"
fi
metric "systemd_failed_units" "$FAILED_UNIT_COUNT" "" "Failed systemd units"

# ===========================================================================
# 11. SYSTEM LOGS
# ===========================================================================
section "Recent System Log Errors"

JOURNAL_ERR=0; OOM_COUNT=0
if cmd_exists journalctl; then
    JOURNAL_ERR=$(journalctl -p err -n 200 --no-pager 2>/dev/null | wc -l || echo 0)
    OOM_COUNT=$(journalctl -k --no-pager 2>/dev/null \
        | grep -c "Killed process\|Out of memory" || true); OOM_COUNT=${OOM_COUNT:-0}
    if (( JOURNAL_ERR > 0 )); then
        warn "${JOURNAL_ERR} recent journal error entries"
        journalctl -p err -n 10 --no-pager --output=short-iso 2>/dev/null \
            | while IFS= read -r l; do echo "    $l"; done
    else
        ok "No recent journal errors"
    fi
    if (( OOM_COUNT > 0 )); then
        crit "${OOM_COUNT} OOM kill event(s) since boot"
    else
        ok "No OOM kills"
    fi
elif [[ -r /var/log/syslog ]]; then
    JOURNAL_ERR=$(grep -ciE "error|crit|emerg|panic" /var/log/syslog || true); JOURNAL_ERR=${JOURNAL_ERR:-0}
    (( JOURNAL_ERR > 0 )) && warn "${JOURNAL_ERR} error lines in syslog" \
                           || ok "No error lines in syslog"
fi
metric "journal_error_count" "$JOURNAL_ERR" "" "Recent journal errors"
metric "oom_kill_count"      "$OOM_COUNT"   "" "OOM kills since boot"

# ===========================================================================
# 12. SECURITY
# ===========================================================================
section "Security Checks"

FAIL_AUTH=0
if [[ -r /etc/ssh/sshd_config ]]; then
    RL=$(grep -i "^PermitRootLogin"        /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || true)
    PA=$(grep -i "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || true)
    metric "ssh_permit_root_login"       "${RL:-unset}" "" "SSH PermitRootLogin"
    metric "ssh_password_authentication" "${PA:-unset}" "" "SSH PasswordAuthentication"
    [[ "$RL" == "yes" ]] && warn "SSH PermitRootLogin=yes" \
                          || ok  "SSH PermitRootLogin: ${RL:-default}"
    [[ "$PA" == "yes" ]] && warn "SSH PasswordAuthentication enabled" \
                          || ok  "SSH PasswordAuthentication: ${PA:-default}"
fi

if [[ -r /var/log/auth.log ]]; then
    FAIL_AUTH=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || true); FAIL_AUTH=${FAIL_AUTH:-0}
elif cmd_exists journalctl; then
    FAIL_AUTH=$(journalctl _SYSTEMD_UNIT=sshd.service 2>/dev/null \
        | grep -c "Failed password" || true); FAIL_AUTH=${FAIL_AUTH:-0}
fi
metric "ssh_failed_auth_total" "$FAIL_AUTH" "" "Failed SSH auth attempts"
(( FAIL_AUTH > 100 )) && warn "High failed SSH auth: ${FAIL_AUTH}" \
                       || ok  "Failed SSH auth: ${FAIL_AUTH}"

FW_ACTIVE=0
if cmd_exists ufw; then
    UFW_ST=$(ufw status 2>/dev/null | head -1 || true)
    grep -qi "active" <<< "$UFW_ST" && FW_ACTIVE=1
    metric "firewall_type"   "ufw"        "" "Firewall type"
    metric "firewall_active" "$FW_ACTIVE" "bool" "Firewall active"
    (( FW_ACTIVE )) && ok "UFW: ${UFW_ST}" || warn "UFW inactive"
elif cmd_exists firewall-cmd; then
    FWS=$(firewall-cmd --state 2>/dev/null || true)
    [[ "$FWS" == "running" ]] && FW_ACTIVE=1
    metric "firewall_type"   "firewalld"  "" "Firewall type"
    metric "firewall_active" "$FW_ACTIVE" "bool" "Firewall active"
    (( FW_ACTIVE )) && ok "firewalld running" || warn "firewalld: ${FWS}"
elif cmd_exists iptables; then
    RULE_COUNT=$(iptables -L 2>/dev/null | grep -c "^[A-Z]" || true); RULE_COUNT=${RULE_COUNT:-0}
    (( RULE_COUNT > 3 )) && { FW_ACTIVE=1; ok "iptables: ${RULE_COUNT} rules"; } \
                          || warn "iptables: no active rules"
    metric "firewall_type"   "iptables"   "" "Firewall type"
    metric "firewall_active" "$FW_ACTIVE" "bool" "Firewall active"
fi

# ===========================================================================
# 13. TIME SYNC
# ===========================================================================
section "Time Synchronisation"

NTP_SYNCED=0
if cmd_exists timedatectl; then
    NTP_S=$(timedatectl show 2>/dev/null | grep NTPSynchronized | cut -d= -f2 || true)
    TZ=$(timedatectl show 2>/dev/null | grep ^Timezone | cut -d= -f2 \
         || timedatectl 2>/dev/null | awk '/Time zone/{print $3}' \
         || echo "unknown")
    info "Timezone: ${TZ}"
    metric "timezone" "$TZ" "" "System timezone"
    if [[ "$NTP_S" == "yes" ]]; then
        NTP_SYNCED=1; ok "NTP synchronised"
    else
        warn "NTP not synchronised — check systemd-timesyncd or chrony"
    fi
elif cmd_exists chronyc; then
    NTP_SYNCED=1
    COFF=$(chronyc tracking 2>/dev/null | awk '/System time/{print $4}' || true)
    metric "chrony_offset_sec" "${COFF:-0}" "s" "Chrony offset"
    ok "chrony running (offset=${COFF:-?}s)"
fi
metric "ntp_synced" "$NTP_SYNCED" "bool" "1=NTP in sync"

# ===========================================================================
# 14. TEMPERATURE
# ===========================================================================
section "Hardware Temperature"

TEMP_CRIT_COUNT=0; TEMP_WARN_COUNT=0; TEMP_SUSPECT_COUNT=0; IDX=0

# Temperatures below this value (°C) are treated as bogus sensor readings.
# Genuine hardware sensors on Linux systems should never report below -40°C.
# Negative readings are almost always a misinterpreted register or a driver
# returning an error code (e.g. -128°C is a common IPMI/ACPI sentinel).
# Override via env: TEMP_FLOOR=-50 sudo ./system_health_check.sh
TEMP_FLOOR="${TEMP_FLOOR:--40}"

# _eval_temp <label> <float_value> <int_value>
# Central threshold logic — call from both the sensors and thermal_zone paths.
_eval_temp() {
    local lbl="$1" tc="$2" ti="$3"

    metric "temp_${IDX}_label" "$lbl" ""   "Sensor name"
    metric "temp_${IDX}_c"     "$tc"  "°C" "Temperature"

    if (( ti < TEMP_FLOOR )); then
        # Almost certainly a driver artifact or error sentinel, not a real reading.
        # Record it in metrics but do not raise an alert — just note it.
        info "  ${DIM}${lbl}: ${tc}°C  (suspect — below floor ${TEMP_FLOOR}°C, skipping alert)${RESET}"
        metric "temp_${IDX}_suspect" "1" "bool" "Flagged as suspect reading"
        TEMP_SUSPECT_COUNT=$(( TEMP_SUSPECT_COUNT + 1 ))
    elif (( ti >= 85 )); then
        info "  ${lbl}: ${tc}°C"
        crit "${lbl}: ${tc}°C"
        TEMP_CRIT_COUNT=$(( TEMP_CRIT_COUNT + 1 ))
    elif (( ti >= 70 )); then
        info "  ${lbl}: ${tc}°C"
        warn "${lbl}: ${tc}°C"
        TEMP_WARN_COUNT=$(( TEMP_WARN_COUNT + 1 ))
    else
        info "  ${lbl}: ${tc}°C"
        ok "${lbl}: ${tc}°C"
    fi

    IDX=$(( IDX + 1 ))
}

if cmd_exists sensors; then
    while IFS= read -r line; do
        T=$(grep -oP '[+-]?[0-9]+\.[0-9]+(?=°C)' <<< "$line" | head -1 || true)
        [[ -z "$T" ]] && continue
        LBL=$(awk -F: '{print $1}' <<< "$line" | xargs | tr ' /()+' '_____')
        # Integer part preserving sign — do NOT strip the minus before comparing
        TI=$(awk "BEGIN{printf \"%d\", $T}")
        _eval_temp "$LBL" "$T" "$TI"
    done < <(sensors 2>/dev/null | grep -E "°C" || true)
elif ls /sys/class/thermal/thermal_zone*/temp &>/dev/null 2>&1; then
    for zone in /sys/class/thermal/thermal_zone*/; do
        ZN=$(cat "${zone}type" 2>/dev/null || basename "$zone")
        ZR=$(cat "${zone}temp" 2>/dev/null || echo 0)
        ZC=$(awk "BEGIN{printf \"%.1f\", ${ZR}/1000}")
        ZI=$(( ZR / 1000 ))
        _eval_temp "$ZN" "$ZC" "$ZI"
    done
else
    info "No temperature sensors found (install lm-sensors)"
fi
metric "temp_crit_count"    "$TEMP_CRIT_COUNT"    "" "Sensors > 85°C"
metric "temp_warn_count"    "$TEMP_WARN_COUNT"    "" "Sensors 70-85°C"
metric "temp_suspect_count" "$TEMP_SUSPECT_COUNT" "" "Suspect/bogus sensor readings"

if (( TEMP_SUSPECT_COUNT > 0 )); then
    warn "${TEMP_SUSPECT_COUNT} suspect temperature reading(s) below ${TEMP_FLOOR}°C — likely sensor artifact, not alerted"
fi

# ===========================================================================
# 15. FILE DESCRIPTORS
# ===========================================================================
section "File Descriptors & Limits"

FD_USED=0; FD_MAX=1; FD_PCT=0
if [[ -r /proc/sys/fs/file-nr ]]; then
    FD_USED=$(awk '{print $1}' /proc/sys/fs/file-nr)
    FD_MAX=$(awk  '{print $3}' /proc/sys/fs/file-nr)
    FD_PCT=$(awk  "BEGIN{printf \"%.1f\", ${FD_USED}*100/${FD_MAX}}")
    info "FD: ${FD_USED} / ${FD_MAX} (${FD_PCT}%)"
    metric "fd_used"     "$FD_USED" ""  "Open FDs (system)"
    metric "fd_max"      "$FD_MAX"  ""  "System FD limit"
    metric "fd_used_pct" "$FD_PCT"  "%" "FD utilisation"
    if gt "$FD_PCT" "80"; then
        warn "FD usage ${FD_PCT}% — approaching limit"
    else
        ok "FD: ${FD_USED}/${FD_MAX} (${FD_PCT}%)"
    fi
fi

info "Top 5 processes by open FD count:"
ls /proc/*/fd 2>/dev/null \
    | awk -F/ '{print $3}' | sort | uniq -c | sort -rn 2>/dev/null \
    | head -5 | while read -r cnt pid; do
        PNAME=$(ps -p "$pid" -o comm= 2>/dev/null || echo "pid${pid}")
        echo "    ${cnt} FDs — ${PNAME} (PID ${pid})"
    done

# ===========================================================================
# RESULT SUMMARY METRICS
# ===========================================================================
TOTAL_CHECKS=$(( CHECKS_PASSED + WARNINGS + CRITICALS ))
metric "result_checks_passed" "$CHECKS_PASSED" ""  "Passed checks"
metric "result_warnings"      "$WARNINGS"      ""  "Warnings raised"
metric "result_criticals"     "$CRITICALS"     ""  "Criticals raised"
metric "result_total_checks"  "$TOTAL_CHECKS"  ""  "Total checks"
metric "result_metric_count"  "${#M_KEYS[@]}"  ""  "Metrics recorded this run"

if   (( CRITICALS > 0 )); then OVERALL_STATUS="CRITICAL"; EXIT_CODE=2
elif (( WARNINGS  > 0 )); then OVERALL_STATUS="WARNING";  EXIT_CODE=1
else                            OVERALL_STATUS="HEALTHY";  EXIT_CODE=0; fi
metric "result_overall_status" "$OVERALL_STATUS" "" "Overall health"

# ===========================================================================
# WRITE CSV  — header written once; one data row appended per run
# ===========================================================================
write_csv() {
    local csv="$1" header="" row=""
    for k in "${M_KEYS[@]}"; do
        header+="${k},"
        local v="${M[$k]}"
        # Escape: double any internal quotes, then wrap in quotes if needed
        v="${v//\"/\"\"}"
        [[ "$v" == *","* || "$v" == *'"'* || "$v" == *$'\n'* ]] && v="\"${v}\""
        row+="${v},"
    done
    header="${header%,}"; row="${row%,}"
    if [[ ! -f "$csv" ]]; then
        echo "$header" > "$csv"
    fi
    echo "$row" >> "$csv"
    echo "  Wrote CSV row ($(wc -l < "$csv") total rows incl. header) → ${csv}"
}

# ===========================================================================
# WRITE JSON SNAPSHOT
# ===========================================================================
write_json() {
    local json="$1"
    local count="${#M_KEYS[@]}" i=0
    {
        printf '{\n'
        for k in "${M_KEYS[@]}"; do
            local v="${M[$k]}"
            i=$(( i + 1 ))
            local comma=","
            (( i >= count )) && comma=""
            if [[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
                printf '  "%s": %s%s\n' "$k" "$v" "$comma"
            else
                v="${v//\\/\\\\}"; v="${v//\"/\\\"}"
                printf '  "%s": "%s"%s\n' "$k" "$v" "$comma"
            fi
        done
        printf '}\n'
    } > "$json"
    echo "  Wrote JSON snapshot → ${json}"
}

echo
write_csv  "$METRICS_CSV"
write_json "$METRICS_JSON"

# Verify files exist and are non-empty
if [[ -s "$METRICS_CSV" ]];  then ok  "CSV verified: $(wc -l < "$METRICS_CSV") rows"
else                              crit "CSV file missing or empty!"; fi
if [[ -s "$METRICS_JSON" ]]; then ok  "JSON verified: $(wc -c < "$METRICS_JSON") bytes"
else                              crit "JSON file missing or empty!"; fi

# ===========================================================================
# SUMMARY BANNER
# ===========================================================================

case "$OVERALL_STATUS" in
    CRITICAL) OD="${RED}CRITICAL — Immediate attention required${RESET}" ;;
    WARNING)  OD="${YELLOW}WARNING  — Review recommended${RESET}" ;;
    *)        OD="${GREEN}HEALTHY  — All checks passed${RESET}" ;;
esac

box_banner "$CYAN" "HEALTH SUMMARY" \
    "Host     : ${THIS_HOST}" \
    "Date     : ${REPORT_DATE}" \
    "=" \
    "~${GREEN}Passed    : ${CHECKS_PASSED}${RESET}" \
    "~${YELLOW}Warnings  : ${WARNINGS}${RESET}" \
    "~${RED}Criticals : ${CRITICALS}${RESET}" \
    "Metrics   : ${#M_KEYS[@]} values captured" \
    "=" \
    "~Overall  : ${OD}" \
    "=" \
    "~${DIM}Log  : ${LOG_FILE}${RESET}" \
    "~${DIM}CSV  : ${METRICS_CSV}${RESET}" \
    "~${DIM}JSON : ${METRICS_JSON}${RESET}"

echo

exit ${EXIT_CODE}

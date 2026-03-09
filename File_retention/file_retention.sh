#!/usr/bin/env bash
# =============================================================================
# file_retention.sh — Age-based file cleanup with per-directory configuration
# Version: 1.0.0
# =============================================================================
# Usage:
#   ./file_retention.sh [OPTIONS]
#
# Options:
#   -c FILE     Config file path (default: /etc/file_retention.conf)
#   -n          Dry-run — show what would be deleted, but don't delete
#   -v          Verbose output
#   -l FILE     Log file path (default: /var/log/file_retention.log)
#   -h          Show this help
#
# Config file format (one rule per line, # for comments):
#   DIRECTORY|MAX_AGE_DAYS[|PATTERN[|RECURSIVE]]
#
# Examples:
#   /var/log/app|30|*.log|yes
#   /tmp/uploads|7|*|no
#   /data/exports|90|*.csv|yes
#   /data/exports|90|*.json|yes
#
# Cron example (daily at 2am):
#   0 2 * * * /usr/local/bin/file_retention.sh -c /etc/file_retention.conf
# =============================================================================

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
CONFIG_FILE="/etc/file_retention.conf"
LOG_FILE="/var/log/file_retention.log"
DRY_RUN=false
VERBOSE=false
DELETED_COUNT=0
DELETED_BYTES=0
ERROR_COUNT=0
SCRIPT_START=$(date +%s)

# ─── Colors (only when interactive) ──────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; RESET=''
fi

# ─── Logging ─────────────────────────────────────────────────────────────────
log() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local log_line="[$ts] [$level] $msg"

    # Always write to log file
    echo "$log_line" >> "$LOG_FILE" 2>/dev/null || true

    # Console output with color
    case "$level" in
        INFO)  [[ "$VERBOSE" == true ]] && echo -e "${CYAN}${log_line}${RESET}" || true ;;
        WARN)  echo -e "${YELLOW}${log_line}${RESET}" ;;
        ERROR) echo -e "${RED}${log_line}${RESET}" ;;
        DONE)  echo -e "${GREEN}${log_line}${RESET}" ;;
        DRY)   echo -e "${YELLOW}[DRY-RUN]${RESET} $msg" ;;
        STAT)  echo -e "${BOLD}${log_line}${RESET}" ;;
    esac
}

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    sed -n '/^# Usage:/,/^# ====/{ /^# ====/d; s/^# \?//; p }' "$0"
    exit 0
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────
while getopts ":c:l:nvh" opt; do
    case $opt in
        c) CONFIG_FILE="$OPTARG" ;;
        l) LOG_FILE="$OPTARG" ;;
        n) DRY_RUN=true ;;
        v) VERBOSE=true ;;
        h) usage ;;
        :) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
        \?) echo "Unknown option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# ─── Preflight ───────────────────────────────────────────────────────────────
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}ERROR: Config file not found: $CONFIG_FILE${RESET}" >&2
    echo "Create it or specify one with -c. See script header for format." >&2
    exit 1
fi

# Ensure log file is writable
touch "$LOG_FILE" 2>/dev/null || {
    echo "WARNING: Cannot write to $LOG_FILE, logging to stderr only." >&2
    LOG_FILE=/dev/stderr
}

# ─── Human-readable byte formatter ───────────────────────────────────────────
format_bytes() {
    local bytes=$1
    if   (( bytes >= 1073741824 )); then printf "%.2f GB" "$(echo "scale=2; $bytes/1073741824" | bc)"
    elif (( bytes >= 1048576    )); then printf "%.2f MB" "$(echo "scale=2; $bytes/1048576"    | bc)"
    elif (( bytes >= 1024       )); then printf "%.2f KB" "$(echo "scale=2; $bytes/1024"       | bc)"
    else printf "%d B" "$bytes"
    fi
}

# ─── Core: process one config rule ───────────────────────────────────────────
process_rule() {
    local dir="$1"
    local max_days="$2"
    local pattern="${3:-*}"
    local recursive="${4:-yes}"

    # Validate directory
    if [[ ! -d "$dir" ]]; then
        log WARN "Directory not found, skipping: $dir"
        (( ERROR_COUNT++ )) || true
        return
    fi

    # Validate max_days is a positive integer
    if ! [[ "$max_days" =~ ^[0-9]+$ ]] || (( max_days < 1 )); then
        log ERROR "Invalid MAX_AGE_DAYS '$max_days' for $dir — must be a positive integer"
        (( ERROR_COUNT++ )) || true
        return
    fi

    log INFO "Processing: $dir | age=${max_days}d | pattern='$pattern' | recursive=$recursive"

    # Build find command args
    local find_args=("$dir")
    [[ "$recursive" =~ ^(no|false|0)$ ]] && find_args+=("-maxdepth" "1")
    find_args+=("-type" "f" "-name" "$pattern" "-mtime" "+${max_days}")

    # Collect matching files
    local file size
    while IFS= read -r -d '' file; do
        size=$(stat -c%s "$file" 2>/dev/null || echo 0)

        if [[ "$DRY_RUN" == true ]]; then
            log DRY "Would delete: $file ($(format_bytes "$size"), $(( ( $(date +%s) - $(stat -c%Y "$file") ) / 86400 ))d old)"
        else
            if rm -f -- "$file" 2>/dev/null; then
                log INFO "Deleted: $file ($(format_bytes "$size"))"
                (( DELETED_BYTES += size )) || true
                (( DELETED_COUNT++ )) || true
            else
                log ERROR "Failed to delete: $file"
                (( ERROR_COUNT++ )) || true
            fi
        fi
    done < <(find "${find_args[@]}" -print0 2>/dev/null)

    # Optional: remove empty subdirectories (only if recursive)
    if [[ "$recursive" =~ ^(yes|true|1)$ ]] && [[ "$DRY_RUN" == false ]]; then
        find "$dir" -mindepth 1 -type d -empty -delete 2>/dev/null || true
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    log STAT "=== file_retention.sh START === $(date) ==="
    [[ "$DRY_RUN" == true ]] && log WARN "DRY-RUN MODE — no files will be deleted"

    local line_num=0
    local rule_count=0

    while IFS= read -r line; do
        (( line_num++ )) || true

        # Skip blanks and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Parse pipe-delimited fields
        IFS='|' read -r dir max_days pattern recursive <<< "$line"

        # Trim whitespace
        dir="${dir// /}"; max_days="${max_days// /}"
        pattern="${pattern:-*}"; recursive="${recursive:-yes}"
        pattern="${pattern// /}"; recursive="${recursive// /}"

        if [[ -z "$dir" || -z "$max_days" ]]; then
            log WARN "Line $line_num: malformed rule, skipping: '$line'"
            continue
        fi

        (( rule_count++ )) || true
        process_rule "$dir" "$max_days" "$pattern" "$recursive"

    done < "$CONFIG_FILE"

    # ─── Summary ─────────────────────────────────────────────────────────────
    local elapsed=$(( $(date +%s) - SCRIPT_START ))
    echo ""
    log STAT "=== SUMMARY ==="
    log STAT "  Rules processed : $rule_count"

    if [[ "$DRY_RUN" == true ]]; then
        log STAT "  Mode            : DRY-RUN (nothing deleted)"
    else
        log STAT "  Files deleted   : $DELETED_COUNT"
        log STAT "  Space freed     : $(format_bytes "$DELETED_BYTES")"
    fi

    log STAT "  Errors          : $ERROR_COUNT"
    log STAT "  Elapsed         : ${elapsed}s"
    log STAT "=== file_retention.sh END ==="

    [[ "$ERROR_COUNT" -gt 0 ]] && exit 1 || exit 0
}

main

#!/usr/bin/env bash
#
# Hung Connection Killer (Bash Version)
# ======================================
# Monitors network connections on Unix-based systems, identifies hung connections,
# and terminates them while leaving healthy connections alone.
#
# Hung connections are identified by:
# - Connections stuck in CLOSE_WAIT, FIN_WAIT_1, FIN_WAIT_2, TIME_WAIT states
# - Connections idle beyond a configurable threshold
#
# Requirements:
# - Bash 4.0+
# - ss command (preferred) or netstat
# - Root/sudo privileges (for terminating connections)
#
# Usage:
#   sudo ./hung_connection_killer.sh [options]
#
# 
#

set -o pipefail

# ==============================================================================
# Configuration Defaults
# ==============================================================================

DRY_RUN=true
VERBOSE=false
LOG_FILE=""

# Timeouts (seconds)
CLOSE_WAIT_TIMEOUT=60
FIN_WAIT_TIMEOUT=120
TIME_WAIT_TIMEOUT=120

# Ports to exclude (space-separated)
EXCLUDE_PORTS="22"

# Ports to include only (empty = all ports)
INCLUDE_PORTS=""

# Processes to never kill
PROTECTED_PROCESSES="sshd systemd init kernel kthreadd containerd dockerd kubelet k3s"

# Additional processes to exclude (user-specified)
EXCLUDE_PROCESSES=""

# Hung states to check
HUNG_STATES="CLOSE-WAIT CLOSE_WAIT FIN-WAIT-1 FIN_WAIT1 FIN-WAIT-2 FIN_WAIT2 CLOSING LAST-ACK LAST_ACK"

# Safe states - never touch these
SAFE_STATES="ESTABLISHED LISTEN SYN-SENT SYN_SENT SYN-RECV SYN_RECV"

# ==============================================================================
# Colors and Formatting
# ==============================================================================

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# ==============================================================================
# Logging Functions
# ==============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local color=""
    case "$level" in
        INFO)    color="$GREEN" ;;
        WARN)    color="$YELLOW" ;;
        ERROR)   color="$RED" ;;
        DEBUG)   color="$BLUE" ;;
    esac
    
    # Console output
    if [[ "$level" != "DEBUG" ]] || [[ "$VERBOSE" == "true" ]]; then
        echo -e "${color}${timestamp} - ${level} - ${message}${NC}" >&2
    fi
    
    # File output
    if [[ -n "$LOG_FILE" ]]; then
        echo "${timestamp} - ${level} - ${message}" >> "$LOG_FILE"
    fi
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { log "DEBUG" "$@"; }

# ==============================================================================
# Utility Functions
# ==============================================================================

# Check if a value is in a space-separated list
in_list() {
    local value="$1"
    local list="$2"
    [[ " $list " == *" $value "* ]]
}

# Check if we have a command available
has_command() {
    command -v "$1" &>/dev/null
}

# Parse time string to seconds (handles formats like "1min30sec", "5.2", "30sec")
parse_time_to_seconds() {
    local time_str="$1"
    local total=0
    
    # Extract minutes
    if [[ "$time_str" =~ ([0-9]+)min ]]; then
        total=$((total + ${BASH_REMATCH[1]} * 60))
    fi
    
    # Extract seconds
    if [[ "$time_str" =~ ([0-9]+(\.[0-9]+)?)sec ]]; then
        # Bash doesn't do float math, so we'll truncate
        local secs="${BASH_REMATCH[1]}"
        secs="${secs%%.*}"  # Remove decimal
        total=$((total + secs))
    elif [[ ! "$time_str" =~ min ]] && [[ "$time_str" =~ ^([0-9]+(\.[0-9]+)?)$ ]]; then
        # Plain number
        local secs="${BASH_REMATCH[1]}"
        secs="${secs%%.*}"
        total=$((total + secs))
    fi
    
    echo "$total"
}

# ==============================================================================
# Connection Detection Functions
# ==============================================================================

# Get connections using ss (preferred)
get_connections_ss() {
    if ! has_command ss; then
        return 1
    fi
    
    # Get TCP connections with timer and process info
    ss -tanp -o state all 2>/dev/null | tail -n +2 | while read -r line; do
        parse_ss_line "$line"
    done
}

# Parse a line from ss output
# Output format: STATE|LOCAL_ADDR|LOCAL_PORT|REMOTE_ADDR|REMOTE_PORT|PID|PROCESS|TIMER_VALUE
parse_ss_line() {
    local line="$1"
    
    # ss output: State Recv-Q Send-Q Local:Port Peer:Port Process Timer
    local state recv_q send_q local_addr remote_addr rest
    
    read -r state recv_q send_q local_addr remote_addr rest <<< "$line"
    
    [[ -z "$state" ]] && return
    
    # Parse local address and port
    local l_addr l_port
    if [[ "$local_addr" == *"]:"* ]]; then
        # IPv6: [::1]:8080
        l_addr="${local_addr%]:*}]"
        l_addr="${l_addr#[}"
        l_addr="${l_addr%]}"
        l_port="${local_addr##*]:}"
    else
        l_addr="${local_addr%:*}"
        l_port="${local_addr##*:}"
    fi
    
    # Parse remote address and port
    local r_addr r_port
    if [[ "$remote_addr" == *"]:"* ]]; then
        r_addr="${remote_addr%]:*}]"
        r_addr="${r_addr#[}"
        r_addr="${r_addr%]}"
        r_port="${remote_addr##*]:}"
    else
        r_addr="${remote_addr%:*}"
        r_port="${remote_addr##*:}"
    fi
    
    # Handle wildcard ports
    [[ "$l_port" == "*" ]] && l_port=0
    [[ "$r_port" == "*" ]] && r_port=0
    
    # Extract PID and process name
    local pid="" process=""
    if [[ "$rest" =~ pid=([0-9]+) ]]; then
        pid="${BASH_REMATCH[1]}"
    fi
    if [[ "$rest" =~ \(\"([^\"]+)\" ]]; then
        process="${BASH_REMATCH[1]}"
    fi
    
    # Extract timer value
    local timer_value=""
    if [[ "$rest" =~ timer:\(([^,]+),([^,\)]+) ]]; then
        local timer_type="${BASH_REMATCH[1]}"
        local timer_str="${BASH_REMATCH[2]}"
        timer_value=$(parse_time_to_seconds "$timer_str")
    fi
    
    # Output in parseable format
    echo "${state}|${l_addr}|${l_port}|${r_addr}|${r_port}|${pid}|${process}|${timer_value}"
}

# Get connections using netstat (fallback)
get_connections_netstat() {
    if ! has_command netstat; then
        return 1
    fi
    
    netstat -tanp 2>/dev/null | tail -n +3 | while read -r line; do
        parse_netstat_line "$line"
    done
}

# Parse a line from netstat output
parse_netstat_line() {
    local line="$1"
    
    # netstat output: Proto Recv-Q Send-Q Local Foreign State PID/Program
    local proto recv_q send_q local_addr remote_addr state proc_info
    
    read -r proto recv_q send_q local_addr remote_addr state proc_info <<< "$line"
    
    [[ -z "$proto" ]] && return
    [[ "$proto" != "tcp"* ]] && return
    
    # Parse addresses
    local l_addr l_port r_addr r_port
    l_addr="${local_addr%:*}"
    l_port="${local_addr##*:}"
    r_addr="${remote_addr%:*}"
    r_port="${remote_addr##*:}"
    
    [[ "$l_port" == "*" ]] && l_port=0
    [[ "$r_port" == "*" ]] && r_port=0
    
    # Parse process info (PID/name)
    local pid="" process=""
    if [[ "$proc_info" == *"/"* ]]; then
        pid="${proc_info%%/*}"
        process="${proc_info#*/}"
    fi
    
    # netstat doesn't give timer info
    echo "${state}|${l_addr}|${l_port}|${r_addr}|${r_port}|${pid}|${process}|"
}

# Get all connections using available tools
get_connections() {
    local connections
    
    connections=$(get_connections_ss)
    if [[ -z "$connections" ]]; then
        log_info "Falling back to netstat"
        connections=$(get_connections_netstat)
    fi
    
    echo "$connections"
}

# ==============================================================================
# Connection Analysis Functions
# ==============================================================================

# Check if a connection should be skipped
# Returns 0 if should skip, 1 if should process
should_skip_connection() {
    local state="$1"
    local l_port="$2"
    local r_port="$3"
    local pid="$4"
    local process="$5"
    
    # Skip safe states
    if in_list "$state" "$SAFE_STATES"; then
        log_debug "Skipping safe state: $state"
        return 0
    fi
    
    # Check port exclusions
    if in_list "$l_port" "$EXCLUDE_PORTS" || in_list "$r_port" "$EXCLUDE_PORTS"; then
        log_debug "Skipping excluded port: $l_port / $r_port"
        return 0
    fi
    
    # Check port inclusions
    if [[ -n "$INCLUDE_PORTS" ]]; then
        if ! in_list "$l_port" "$INCLUDE_PORTS" && ! in_list "$r_port" "$INCLUDE_PORTS"; then
            log_debug "Skipping port not in include list"
            return 0
        fi
    fi
    
    # Check protected processes
    if [[ -n "$process" ]] && in_list "$process" "$PROTECTED_PROCESSES"; then
        log_debug "Skipping protected process: $process"
        return 0
    fi
    
    # Check excluded processes
    if [[ -n "$process" ]] && [[ -n "$EXCLUDE_PROCESSES" ]] && in_list "$process" "$EXCLUDE_PROCESSES"; then
        log_debug "Skipping excluded process: $process"
        return 0
    fi
    
    # Skip if no PID
    if [[ -z "$pid" ]]; then
        log_debug "Skipping connection without PID"
        return 0
    fi
    
    return 1
}

# Check if a connection is hung
# Returns 0 if hung, 1 if healthy
# Sets global HUNG_REASON
is_hung_connection() {
    local state="$1"
    local timer_value="$2"
    
    HUNG_REASON=""
    
    # Normalize state name (handle both - and _ variants)
    local norm_state
    norm_state=$(echo "$state" | tr '-' '_')
    
    # Check if in a hung state
    if ! in_list "$state" "$HUNG_STATES" && ! in_list "$norm_state" "$HUNG_STATES"; then
        return 1
    fi
    
    # Determine timeout based on state
    local timeout=0
    case "$norm_state" in
        CLOSE_WAIT)
            timeout=$CLOSE_WAIT_TIMEOUT
            ;;
        FIN_WAIT1|FIN_WAIT2|CLOSING|LAST_ACK)
            timeout=$FIN_WAIT_TIMEOUT
            ;;
        TIME_WAIT)
            timeout=$TIME_WAIT_TIMEOUT
            ;;
    esac
    
    # If we have timer info, check against timeout
    if [[ -n "$timer_value" ]] && [[ "$timer_value" -gt 0 ]]; then
        if [[ "$timer_value" -gt "$timeout" ]]; then
            HUNG_REASON="State $state exceeded timeout (${timer_value}s > ${timeout}s)"
            return 0
        fi
    else
        # No timer info - flag certain states as suspicious
        case "$norm_state" in
            CLOSE_WAIT)
                HUNG_REASON="CLOSE_WAIT without active timer (likely app not closing socket)"
                return 0
                ;;
            FIN_WAIT1|FIN_WAIT2|CLOSING|LAST_ACK)
                HUNG_REASON="${state} state detected (typically indicates hung connection)"
                return 0
                ;;
        esac
    fi
    
    return 1
}

# ==============================================================================
# Connection Termination Functions
# ==============================================================================

# Terminate a connection using ss -K
kill_socket_ss() {
    local l_addr="$1"
    local l_port="$2"
    local r_addr="$3"
    local r_port="$4"
    
    if ! has_command ss; then
        return 1
    fi
    
    ss -K dst "$r_addr" dport eq "$r_port" src "$l_addr" sport eq "$l_port" &>/dev/null
    return $?
}

# Terminate by killing the process
kill_process() {
    local pid="$1"
    local process="$2"
    
    # Double-check protected processes
    if [[ -n "$process" ]] && in_list "$process" "$PROTECTED_PROCESSES"; then
        log_warn "Refusing to kill protected process: $process"
        return 1
    fi
    
    # Send SIGTERM first
    if kill -15 "$pid" 2>/dev/null; then
        sleep 1
        
        # Check if still running
        if [[ -d "/proc/$pid" ]]; then
            # Force kill
            kill -9 "$pid" 2>/dev/null
        fi
        return 0
    fi
    
    return 1
}

# Terminate a hung connection
terminate_connection() {
    local state="$1"
    local l_addr="$2"
    local l_port="$3"
    local r_addr="$4"
    local r_port="$5"
    local pid="$6"
    local process="$7"
    
    local conn_str="tcp $state $l_addr:$l_port -> $r_addr:$r_port (PID: $pid, Process: $process)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would terminate: $conn_str"
        return 0
    fi
    
    # Method 1: Try ss -K
    if kill_socket_ss "$l_addr" "$l_port" "$r_addr" "$r_port"; then
        log_info "Terminated via ss -K: $conn_str"
        return 0
    fi
    
    # Method 2: Kill the process (if safe)
    if [[ -n "$pid" ]] && [[ -n "$process" ]]; then
        if ! in_list "$process" "$PROTECTED_PROCESSES"; then
            if kill_process "$pid" "$process"; then
                log_info "Terminated process: $conn_str"
                return 0
            fi
        fi
    fi
    
    log_warn "Failed to terminate: $conn_str"
    return 1
}

# ==============================================================================
# Main Execution
# ==============================================================================

run() {
    local total=0
    local hung=0
    local skipped=0
    local terminated=0
    local failed=0
    
    log_info "============================================================"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Hung Connection Killer - DRY RUN"
    else
        log_info "Hung Connection Killer - LIVE MODE"
    fi
    log_info "============================================================"
    
    # Check for root
    if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" != "true" ]]; then
        log_warn "Not running as root - some operations may fail"
    fi
    
    # Get connections
    local connections
    connections=$(get_connections)
    
    if [[ -z "$connections" ]]; then
        log_error "Failed to get connections. Ensure ss or netstat is available."
        return 1
    fi
    
    # Count total
    total=$(echo "$connections" | grep -c .)
    log_info "Found $total total connections"
    
    # Process each connection
    while IFS='|' read -r state l_addr l_port r_addr r_port pid process timer_value; do
        [[ -z "$state" ]] && continue
        
        # Check if should skip
        if should_skip_connection "$state" "$l_port" "$r_port" "$pid" "$process"; then
            ((skipped++))
            continue
        fi
        
        # Check if hung
        if ! is_hung_connection "$state" "$timer_value"; then
            log_debug "Healthy: $state $l_addr:$l_port -> $r_addr:$r_port"
            continue
        fi
        
        ((hung++))
        log_warn "Hung connection detected: $state $l_addr:$l_port -> $r_addr:$r_port (PID: $pid)"
        log_warn "  Reason: $HUNG_REASON"
        
        # Terminate
        if terminate_connection "$state" "$l_addr" "$l_port" "$r_addr" "$r_port" "$pid" "$process"; then
            ((terminated++))
        else
            ((failed++))
        fi
        
    done <<< "$connections"
    
    # Summary
    log_info "------------------------------------------------------------"
    log_info "Summary:"
    log_info "  Total connections scanned: $total"
    log_info "  Hung connections found: $hung"
    log_info "  Connections skipped: $skipped"
    log_info "  Connections terminated: $terminated"
    log_info "  Failed terminations: $failed"
    log_info "============================================================"
    
    # Return error if any failures
    [[ $failed -gt 0 ]] && return 1
    return 0
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Detect and terminate hung network connections on Unix systems.

Mode (required - choose one):
  -n, --dry-run              Show what would be done without making changes (safe)
  -l, --live                 Actually terminate hung connections (requires root)

Timeout Configuration:
  --close-wait-timeout SEC   Seconds before CLOSE_WAIT is considered hung (default: 60)
  --fin-wait-timeout SEC     Seconds before FIN_WAIT states are considered hung (default: 120)
  --time-wait-timeout SEC    Seconds before TIME_WAIT is considered hung (default: 120)

Filtering:
  --exclude-ports PORTS      Space-separated ports to exclude (default: "22")
  --include-ports PORTS      Only check these ports (default: all)
  --exclude-processes PROCS  Space-separated process names to exclude

Logging:
  --log-file FILE            Write logs to this file
  -v, --verbose              Enable verbose output

Other:
  -h, --help                 Show this help message

Examples:
  # Dry run (safe - shows what would be done)
  sudo $0 --dry-run

  # Live mode - actually terminate hung connections
  sudo $0 --live

  # Custom timeouts
  sudo $0 --live --close-wait-timeout 30

  # Exclude specific ports
  sudo $0 --live --exclude-ports "22 3306 5432"

  # Only monitor specific ports
  sudo $0 --live --include-ports "80 443 8080"

  # Verbose logging to file
  sudo $0 --live -v --log-file /var/log/hung_conn.log

EOF
    exit 0
}

parse_args() {
    local mode_set=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=true
                mode_set=true
                shift
                ;;
            -l|--live)
                DRY_RUN=false
                mode_set=true
                shift
                ;;
            --close-wait-timeout)
                CLOSE_WAIT_TIMEOUT="$2"
                shift 2
                ;;
            --fin-wait-timeout)
                FIN_WAIT_TIMEOUT="$2"
                shift 2
                ;;
            --time-wait-timeout)
                TIME_WAIT_TIMEOUT="$2"
                shift 2
                ;;
            --exclude-ports)
                EXCLUDE_PORTS="$2"
                shift 2
                ;;
            --include-ports)
                INCLUDE_PORTS="$2"
                shift 2
                ;;
            --exclude-processes)
                EXCLUDE_PROCESSES="$2"
                shift 2
                ;;
            --log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    if [[ "$mode_set" != "true" ]]; then
        log_error "You must specify either --dry-run or --live"
        echo "Use --help for usage information"
        exit 1
    fi
}

# ==============================================================================
# Entry Point
# ==============================================================================

main() {
    parse_args "$@"
    run
    exit $?
}

main "$@"

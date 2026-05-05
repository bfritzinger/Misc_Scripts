#!/usr/bin/env bash
# =============================================================================
# chown_throttled.sh
# Recursively chowns files across multiple directories with controlled priority,
# parallel worker support, and skips files already matching the target owner/group.
#
# Usage:
#   ./chown_throttled.sh [OPTIONS]
#
# Options:
#   -u USER[:GROUP]   Owner to set (required)
#   -d DIR            Target directory (repeatable, e.g. -d /a -d /b)
#   -b BATCH_SIZE     Files per chown call per worker     (default: 500)
#   -w WORKERS        Parallel workers (xargs -P)         (default: nproc or 4)
#   -s SLEEP_MS       Sleep between batches in ms         (default: 50)
#   -t TYPE           Find type: f=files, d=dirs, a=all   (default: a)
#   -p NICE_LEVEL     CPU nice level: 0=normal..19=lowest (default: 10)
#   -i IONICE_CLASS   IO class: 1=realtime 2=best-effort 3=idle (default: 2)
#   -D                Process multiple -d directories in parallel
#   -n                Dry run -- print what would be chowned, no changes made
#   -h                Show this help
#
# Examples:
#   ./chown_throttled.sh -u www-data:www-data -d /var/www -d /srv/data -w 4
#   ./chown_throttled.sh -u deploy:deploy -d /opt/app -w 8 -b 200 -s 25 -p 5
#   ./chown_throttled.sh -u deploy:deploy -d /opt/app -d /srv/data -D -w 4
#   ./chown_throttled.sh -u deploy:deploy -d /opt/app -n
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
OWNER=""
TARGET_USER=""
TARGET_GROUP=""
DIRS=()
BATCH_SIZE=500
WORKERS=0           # 0 = auto-detect via nproc
SLEEP_MS=50
FIND_TYPE="a"
NICE_LEVEL=10
IONICE_CLASS=2
PARALLEL_DIRS=false
DRY_RUN=false

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$$] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$$] WARN: $*" >&2; }
die()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$$] ERROR: $*" >&2; exit 1; }

# Detect available CPU count
cpu_count() {
    nproc 2>/dev/null \
        || grep -c '^processor' /proc/cpuinfo 2>/dev/null \
        || sysctl -n hw.logicalcpu 2>/dev/null \
        || echo 4
}

# --------------------------------------------------------------------------- #
# Parse arguments
# --------------------------------------------------------------------------- #
while getopts ":u:d:b:w:s:t:p:i:Dnh" opt; do
    case $opt in
        u) OWNER="$OPTARG" ;;
        d) DIRS+=("$OPTARG") ;;
        b) BATCH_SIZE="$OPTARG" ;;
        w) WORKERS="$OPTARG" ;;
        s) SLEEP_MS="$OPTARG" ;;
        t) FIND_TYPE="$OPTARG" ;;
        p) NICE_LEVEL="$OPTARG" ;;
        i) IONICE_CLASS="$OPTARG" ;;
        D) PARALLEL_DIRS=true ;;
        n) DRY_RUN=true ;;
        h) grep "^#" "$0" | head -35 | sed 's/^# \{0,3\}//'; exit 0 ;;
        :) die "Option -$OPTARG requires an argument." ;;
       \?) die "Unknown option: -$OPTARG" ;;
    esac
done

# --------------------------------------------------------------------------- #
# Validate & parse owner/group
# --------------------------------------------------------------------------- #
[[ -z "$OWNER" ]]       && die "Owner (-u USER[:GROUP]) is required."
[[ ${#DIRS[@]} -eq 0 ]] && die "At least one directory (-d) is required."

if [[ "$OWNER" == *:* ]]; then
    TARGET_USER="${OWNER%%:*}"
    TARGET_GROUP="${OWNER##*:}"
else
    TARGET_USER="$OWNER"
    TARGET_GROUP=""
fi

id -u "$TARGET_USER" &>/dev/null || die "User '$TARGET_USER' does not exist on this system."
if [[ -n "$TARGET_GROUP" ]]; then
    getent group "$TARGET_GROUP" &>/dev/null || die "Group '$TARGET_GROUP' does not exist on this system."
fi

for dir in "${DIRS[@]}"; do
    [[ -d "$dir" ]] || die "Directory does not exist: $dir"
done

[[ "$BATCH_SIZE"   =~ ^[0-9]+$ && "$BATCH_SIZE" -gt 0 ]] || die "Batch size must be a positive integer."
[[ "$WORKERS"      =~ ^[0-9]+$                         ]] || die "Workers must be a non-negative integer (0=auto)."
[[ "$SLEEP_MS"     =~ ^[0-9]+$                         ]] || die "Sleep must be a non-negative integer (ms)."
[[ "$NICE_LEVEL"   =~ ^[0-9]+$ && "$NICE_LEVEL" -le 19 ]] || die "Nice level must be 0-19."
[[ "$IONICE_CLASS" =~ ^[123]$                          ]] || die "ionice class must be 1, 2, or 3."

# Resolve auto worker count
if [[ "$WORKERS" -eq 0 ]]; then
    WORKERS=$(cpu_count)
    WORKERS_SOURCE="auto-detected"
else
    WORKERS_SOURCE="user-specified"
fi

# Build find type filter
case "$FIND_TYPE" in
    a) FIND_TYPE_ARG=() ;;
    f) FIND_TYPE_ARG=(-type f) ;;
    d) FIND_TYPE_ARG=(-type d) ;;
    *) die "Invalid type '$FIND_TYPE'. Use: f, d, or a" ;;
esac

# --------------------------------------------------------------------------- #
# Dependency checks
# --------------------------------------------------------------------------- #
for cmd in find xargs nice bc; do
    command -v "$cmd" &>/dev/null || warn "'$cmd' not found -- some features may be limited."
done

HAS_IONICE=false
command -v ionice &>/dev/null && HAS_IONICE=true

# --------------------------------------------------------------------------- #
# Shared temp dir for inter-process counters
# Each directory worker writes its counts here; main process sums at the end.
# --------------------------------------------------------------------------- #
TMPDIR_BASE=$(mktemp -d /tmp/chown_throttled_XXXXXX)
BATCH_SCRIPT="$TMPDIR_BASE/batch_exec.sh"

cleanup() {
    rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

# --------------------------------------------------------------------------- #
# Build the batch executor script
# Each xargs worker calls this with a batch of paths.
# --------------------------------------------------------------------------- #
cat > "$BATCH_SCRIPT" <<EOF
#!/usr/bin/env bash
OWNER="$OWNER"
DRY_RUN=$DRY_RUN
SLEEP_MS=$SLEEP_MS
NICE_LEVEL=$NICE_LEVEL
IONICE_CLASS=$IONICE_CLASS
HAS_IONICE=$HAS_IONICE

if \$DRY_RUN; then
    echo "[DRY-RUN] [\$\$] Would chown $OWNER \$# item(s):"
    for f in "\$@"; do echo "    \$f"; done
else
    if \$HAS_IONICE; then
        nice -n "\$NICE_LEVEL" ionice -c "\$IONICE_CLASS" chown "$OWNER" "\$@"
    else
        nice -n "\$NICE_LEVEL" chown "$OWNER" "\$@"
    fi
fi

# Per-worker throttle: each worker sleeps independently so they don't all
# hammer the disk in lockstep but also don't block each other.
if [[ \$SLEEP_MS -gt 0 ]]; then
    sleep_val=\$(echo "scale=3; \$SLEEP_MS / 1000" | bc 2>/dev/null || echo "0.05")
    sleep "\$sleep_val"
fi
EOF
chmod 700 "$BATCH_SCRIPT"

# --------------------------------------------------------------------------- #
# Summary header
# --------------------------------------------------------------------------- #
log "========================================"
log "  chown_throttled.sh"
log "========================================"
log "  Owner        : $OWNER"
log "  Directories  : ${DIRS[*]}"
log "  Batch size   : $BATCH_SIZE items/worker/call"
log "  Workers      : $WORKERS ($WORKERS_SOURCE)"
log "  Parallel dirs: $PARALLEL_DIRS"
log "  Throttle     : ${SLEEP_MS}ms per worker between batches"
log "  CPU nice     : $NICE_LEVEL (0=normal, 19=lowest)"
log "  IO class     : $IONICE_CLASS (1=rt, 2=best-effort, 3=idle)"
log "  Find type    : $FIND_TYPE (f=files, d=dirs, a=all)"
log "  Skip owned   : YES -- items already owned by $OWNER are skipped"
log "  Dry run      : $DRY_RUN"
log "========================================"

# --------------------------------------------------------------------------- #
# Per-directory processing function
# Writes found/skipped counts to temp files for the main process to aggregate.
# --------------------------------------------------------------------------- #
process_dir() {
    local TARGET_DIR="$1"
    local COUNTER_FILE="$TMPDIR_BASE/counts_$(echo "$TARGET_DIR" | tr '/' '_').txt"

    log "--- Directory: $TARGET_DIR (workers: $WORKERS) ---"

    # Count total items
    local TOTAL_ITEMS
    TOTAL_ITEMS=$(nice -n 19 find "$TARGET_DIR" \
        "${FIND_TYPE_ARG[@]}" \
        -print 2>/dev/null | wc -l || echo 0)

    # Count already-correct items
    local ALREADY_OWNED
    if [[ -n "$TARGET_GROUP" ]]; then
        ALREADY_OWNED=$(nice -n 19 find "$TARGET_DIR" \
            "${FIND_TYPE_ARG[@]}" \
            -user "$TARGET_USER" -group "$TARGET_GROUP" \
            -print 2>/dev/null | wc -l || echo 0)
    else
        ALREADY_OWNED=$(nice -n 19 find "$TARGET_DIR" \
            "${FIND_TYPE_ARG[@]}" \
            -user "$TARGET_USER" \
            -print 2>/dev/null | wc -l || echo 0)
    fi

    local TO_PROCESS=$(( TOTAL_ITEMS - ALREADY_OWNED ))
    log "  [$TARGET_DIR] Total: $TOTAL_ITEMS | Already owned: $ALREADY_OWNED | To process: $TO_PROCESS"

    # Persist counts for aggregation
    echo "$TOTAL_ITEMS $ALREADY_OWNED" > "$COUNTER_FILE"

    if [[ "$TO_PROCESS" -le 0 ]]; then
        log "  [$TARGET_DIR] Nothing to do -- all items already owned by $OWNER"
        return 0
    fi

    # ----------------------------------------------------------------------- #
    # Stream unowned paths into xargs with -P WORKERS for parallel execution.
    # Each worker picks up a batch of BATCH_SIZE paths and calls chown on them.
    # Workers run independently -- no coordination needed since chown is atomic
    # per-file and no two workers will receive the same path from xargs.
    # ----------------------------------------------------------------------- #
    local DIR_STATUS
    if [[ -n "$TARGET_GROUP" ]]; then
        nice -n "$NICE_LEVEL" find "$TARGET_DIR" \
            "${FIND_TYPE_ARG[@]}" \
            \( ! -user "$TARGET_USER" -o ! -group "$TARGET_GROUP" \) \
            -print0 2>/dev/null \
        | ( $HAS_IONICE \
                && ionice -c "$IONICE_CLASS" \
                    xargs -0 -n "$BATCH_SIZE" -P "$WORKERS" bash "$BATCH_SCRIPT" \
                || xargs -0 -n "$BATCH_SIZE" -P "$WORKERS" bash "$BATCH_SCRIPT" \
          ) \
        && DIR_STATUS="OK" || DIR_STATUS="PARTIAL (check permissions)"
    else
        nice -n "$NICE_LEVEL" find "$TARGET_DIR" \
            "${FIND_TYPE_ARG[@]}" \
            ! -user "$TARGET_USER" \
            -print0 2>/dev/null \
        | ( $HAS_IONICE \
                && ionice -c "$IONICE_CLASS" \
                    xargs -0 -n "$BATCH_SIZE" -P "$WORKERS" bash "$BATCH_SCRIPT" \
                || xargs -0 -n "$BATCH_SIZE" -P "$WORKERS" bash "$BATCH_SCRIPT" \
          ) \
        && DIR_STATUS="OK" || DIR_STATUS="PARTIAL (check permissions)"
    fi

    log "  [$TARGET_DIR] Status: $DIR_STATUS"
}

# Export everything process_dir needs when running in subshells
export -f process_dir
export TMPDIR_BASE BATCH_SCRIPT OWNER TARGET_USER TARGET_GROUP
export BATCH_SIZE WORKERS SLEEP_MS NICE_LEVEL IONICE_CLASS
export DRY_RUN HAS_IONICE FIND_TYPE
export -a FIND_TYPE_ARG

# --------------------------------------------------------------------------- #
# Dispatch: parallel directories or sequential
# --------------------------------------------------------------------------- #
if $PARALLEL_DIRS && [[ ${#DIRS[@]} -gt 1 ]]; then
    log "Processing ${#DIRS[@]} directories in parallel..."
    PIDS=()
    for TARGET_DIR in "${DIRS[@]}"; do
        process_dir "$TARGET_DIR" &
        PIDS+=($!)
    done

    # Wait for all background jobs and capture any failures
    FAILED=0
    for pid in "${PIDS[@]}"; do
        wait "$pid" || FAILED=$(( FAILED + 1 ))
    done

    [[ $FAILED -gt 0 ]] && warn "$FAILED directory job(s) reported errors."
else
    for TARGET_DIR in "${DIRS[@]}"; do
        process_dir "$TARGET_DIR"
    done
fi

# --------------------------------------------------------------------------- #
# Aggregate counters from all directory workers
# --------------------------------------------------------------------------- #
GRAND_TOTAL_FOUND=0
GRAND_TOTAL_SKIPPED=0

for COUNT_FILE in "$TMPDIR_BASE"/counts_*.txt; do
    [[ -f "$COUNT_FILE" ]] || continue
    read -r found skipped < "$COUNT_FILE"
    GRAND_TOTAL_FOUND=$(( GRAND_TOTAL_FOUND + found ))
    GRAND_TOTAL_SKIPPED=$(( GRAND_TOTAL_SKIPPED + skipped ))
done

# --------------------------------------------------------------------------- #
# Final summary
# --------------------------------------------------------------------------- #
log "========================================"
log "  Run complete"
log "  Total items found   : $GRAND_TOTAL_FOUND"
log "  Skipped (owned)     : $GRAND_TOTAL_SKIPPED"
log "  Processed           : $(( GRAND_TOTAL_FOUND - GRAND_TOTAL_SKIPPED ))"
log "  Workers used        : $WORKERS"
$DRY_RUN && log "  (Dry run -- no changes were made)"
log "========================================"

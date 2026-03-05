#!/usr/bin/env bash
# =============================================================================
# chown_throttled.sh
# Recursively chowns files across multiple directories with controlled priority
# and skips files already matching the target owner/group.
#
# Usage:
#   ./chown_throttled.sh [OPTIONS]
#
# Options:
#   -u USER[:GROUP]   Owner to set (required)
#   -d DIR            Target directory (repeatable, e.g. -d /a -d /b)
#   -b BATCH_SIZE     Files per chown call            (default: 500)
#   -s SLEEP_MS       Sleep between batches in ms     (default: 50)
#   -t TYPE           Find type: f=files, d=dirs, a=all (default: a)
#   -p NICE_LEVEL     CPU nice level: 0=normal .. 19=lowest (default: 10)
#   -i IONICE_CLASS   IO class: 1=realtime 2=best-effort 3=idle (default: 2)
#   -n                Dry run -- print what would be chowned, no changes made
#   -h                Show this help
#
# Examples:
#   ./chown_throttled.sh -u www-data:www-data -d /var/www -d /srv/data
#   ./chown_throttled.sh -u deploy:deploy -d /opt/app -b 200 -s 25 -p 5 -i 2
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
SLEEP_MS=50
FIND_TYPE="a"
NICE_LEVEL=10       # mid-range: still responsive but not system-hogging
IONICE_CLASS=2      # best-effort: gets IO time but yields to higher priority
DRY_RUN=false

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }
die()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }

sleep_ms() {
    local ms=$1
    [[ $ms -le 0 ]] && return
    local secs
    secs=$(echo "scale=3; $ms / 1000" | bc 2>/dev/null || echo "0.05")
    sleep "$secs"
}

# --------------------------------------------------------------------------- #
# Parse arguments
# --------------------------------------------------------------------------- #
while getopts ":u:d:b:s:t:p:i:nh" opt; do
    case $opt in
        u) OWNER="$OPTARG" ;;
        d) DIRS+=("$OPTARG") ;;
        b) BATCH_SIZE="$OPTARG" ;;
        s) SLEEP_MS="$OPTARG" ;;
        t) FIND_TYPE="$OPTARG" ;;
        p) NICE_LEVEL="$OPTARG" ;;
        i) IONICE_CLASS="$OPTARG" ;;
        n) DRY_RUN=true ;;
        h) grep "^#" "$0" | head -30 | sed 's/^# \{0,3\}//'; exit 0 ;;
        :) die "Option -$OPTARG requires an argument." ;;
       \?) die "Unknown option: -$OPTARG" ;;
    esac
done

# --------------------------------------------------------------------------- #
# Validate & parse owner/group
# --------------------------------------------------------------------------- #
[[ -z "$OWNER" ]]       && die "Owner (-u USER[:GROUP]) is required."
[[ ${#DIRS[@]} -eq 0 ]] && die "At least one directory (-d) is required."

# Split USER:GROUP
if [[ "$OWNER" == *:* ]]; then
    TARGET_USER="${OWNER%%:*}"
    TARGET_GROUP="${OWNER##*:}"
else
    TARGET_USER="$OWNER"
    TARGET_GROUP=""
fi

# Verify user/group exist
id -u "$TARGET_USER" &>/dev/null || die "User '$TARGET_USER' does not exist on this system."
if [[ -n "$TARGET_GROUP" ]]; then
    getent group "$TARGET_GROUP" &>/dev/null || die "Group '$TARGET_GROUP' does not exist on this system."
fi

for dir in "${DIRS[@]}"; do
    [[ -d "$dir" ]] || die "Directory does not exist: $dir"
done

[[ "$BATCH_SIZE"   =~ ^[0-9]+$ && "$BATCH_SIZE" -gt 0 ]] || die "Batch size must be a positive integer."
[[ "$SLEEP_MS"     =~ ^[0-9]+$                         ]] || die "Sleep must be a non-negative integer (ms)."
[[ "$NICE_LEVEL"   =~ ^[0-9]+$ && "$NICE_LEVEL" -le 19 ]] || die "Nice level must be 0-19."
[[ "$IONICE_CLASS" =~ ^[123]$                          ]] || die "ionice class must be 1, 2, or 3."

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
for cmd in find xargs nice ionice bc; do
    command -v "$cmd" &>/dev/null || warn "'$cmd' not found -- some features may be limited."
done

HAS_IONICE=false
command -v ionice &>/dev/null && HAS_IONICE=true

# --------------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------------- #
log "========================================"
log "  chown_throttled.sh"
log "========================================"
log "  Owner      : $OWNER"
log "  Directories: ${DIRS[*]}"
log "  Batch size : $BATCH_SIZE items/call"
log "  Throttle   : ${SLEEP_MS}ms between batches"
log "  CPU nice   : $NICE_LEVEL (0=normal, 19=lowest)"
log "  IO class   : $IONICE_CLASS (1=rt, 2=best-effort, 3=idle)"
log "  Find type  : $FIND_TYPE (f=files, d=dirs, a=all)"
log "  Skip owned : YES -- skipping items already owned by $OWNER"
log "  Dry run    : $DRY_RUN"
log "========================================"

# --------------------------------------------------------------------------- #
# Build batch executor script (called by xargs for each batch)
# --------------------------------------------------------------------------- #
BATCH_SCRIPT=$(mktemp /tmp/chown_batch_XXXXXX.sh)
chmod 700 "$BATCH_SCRIPT"
trap 'rm -f "$BATCH_SCRIPT"' EXIT

cat > "$BATCH_SCRIPT" <<EOF
#!/usr/bin/env bash
OWNER="$OWNER"
DRY_RUN=$DRY_RUN
SLEEP_MS=$SLEEP_MS
NICE_LEVEL=$NICE_LEVEL
IONICE_CLASS=$IONICE_CLASS
HAS_IONICE=$HAS_IONICE

count=\$#
if \$DRY_RUN; then
    echo "[DRY-RUN] Would chown $OWNER \$count item(s):"
    for f in "\$@"; do echo "  \$f"; done
else
    if \$HAS_IONICE; then
        nice -n "\$NICE_LEVEL" ionice -c "\$IONICE_CLASS" chown "$OWNER" "\$@"
    else
        nice -n "\$NICE_LEVEL" chown "$OWNER" "\$@"
    fi
fi

# Throttle between batches
if [[ \$SLEEP_MS -gt 0 ]]; then
    sleep_val=\$(echo "scale=3; \$SLEEP_MS / 1000" | bc 2>/dev/null || echo "0.05")
    sleep "\$sleep_val"
fi
EOF

# --------------------------------------------------------------------------- #
# Main processing loop
# --------------------------------------------------------------------------- #
GRAND_TOTAL_FOUND=0
GRAND_TOTAL_SKIPPED=0

for TARGET_DIR in "${DIRS[@]}"; do
    log "--- Directory: $TARGET_DIR ---"

    # Count total items (for reporting)
    TOTAL_ITEMS=$(nice -n 19 find "$TARGET_DIR" \
        "${FIND_TYPE_ARG[@]}" \
        -print 2>/dev/null | wc -l || echo 0)

    # Count items already correctly owned (will be skipped)
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

    TO_PROCESS=$((TOTAL_ITEMS - ALREADY_OWNED))
    log "  Total items    : $TOTAL_ITEMS"
    log "  Already owned  : $ALREADY_OWNED (skipping)"
    log "  To process     : $TO_PROCESS"

    if [[ "$TO_PROCESS" -le 0 ]]; then
        log "  Nothing to do in $TARGET_DIR -- all items already owned by $OWNER"
        continue
    fi

    # -------------------------------------------------------------------------
    # find with ownership exclusion filter:
    #   ( ! -user U -o ! -group G ) selects ONLY items needing chown.
    # -print0 / xargs -0 safely handles filenames with spaces, newlines, etc.
    # -------------------------------------------------------------------------
    if [[ -n "$TARGET_GROUP" ]]; then
        nice -n "$NICE_LEVEL" find "$TARGET_DIR" \
            "${FIND_TYPE_ARG[@]}" \
            \( ! -user "$TARGET_USER" -o ! -group "$TARGET_GROUP" \) \
            -print0 2>/dev/null \
        | ( $HAS_IONICE \
                && ionice -c "$IONICE_CLASS" xargs -0 -n "$BATCH_SIZE" -P 1 bash "$BATCH_SCRIPT" \
                || xargs -0 -n "$BATCH_SIZE" -P 1 bash "$BATCH_SCRIPT" \
          ) \
        && DIR_STATUS="OK" || DIR_STATUS="PARTIAL (check permissions)"
    else
        nice -n "$NICE_LEVEL" find "$TARGET_DIR" \
            "${FIND_TYPE_ARG[@]}" \
            ! -user "$TARGET_USER" \
            -print0 2>/dev/null \
        | ( $HAS_IONICE \
                && ionice -c "$IONICE_CLASS" xargs -0 -n "$BATCH_SIZE" -P 1 bash "$BATCH_SCRIPT" \
                || xargs -0 -n "$BATCH_SIZE" -P 1 bash "$BATCH_SCRIPT" \
          ) \
        && DIR_STATUS="OK" || DIR_STATUS="PARTIAL (check permissions)"
    fi

    GRAND_TOTAL_FOUND=$((GRAND_TOTAL_FOUND + TOTAL_ITEMS))
    GRAND_TOTAL_SKIPPED=$((GRAND_TOTAL_SKIPPED + ALREADY_OWNED))

    log "  Status: $DIR_STATUS"
done

log "========================================"
log "  Run complete"
log "  Total items found   : $GRAND_TOTAL_FOUND"
log "  Skipped (owned)     : $GRAND_TOTAL_SKIPPED"
log "  Processed           : $((GRAND_TOTAL_FOUND - GRAND_TOTAL_SKIPPED))"
$DRY_RUN && log "  (Dry run -- no changes were made)"
log "========================================"

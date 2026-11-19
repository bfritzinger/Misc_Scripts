#!/usr/bin/env bash
#
# run-playbooks.sh - Run multiple Ansible playbooks (from any directories)
#                    using a single shared inventory file.
#
# Usage:
#   ./run-playbooks.sh                     # run all playbooks from the list below
#   ./run-playbooks.sh playbook1.yml ...   # run the given playbooks instead
#   Options must come BEFORE playbook paths (getopts stops at the first non-option).
#
# Options:
#   -i INVENTORY   Inventory file (default: inventory.txt next to this script)
#   -f             Fail-fast: stop at the first failing playbook (default: continue)
#   -c             Run in check mode (dry run)
#   -d             Enable diff mode
#   -L TAGS        Limit to comma-separated tags (--tags)
#   -S TAGS        Skip tags (--skip-tags)
#   -l HOSTS       Limit targets (--limit)
#   -e KEY=VALUE   Extra vars (repeatable; each becomes its own --extra-vars)
#   -v             Verbose (repeatable: -v, -vv, -vvv)
#   -h             Show this help
#
# Exit status: 0 only if every playbook ran and passed; 1 if any failed or
# was not found; 2 on a usage error.

set -u

# ---------------------------------------------------------------------------
# CONFIG: your playbooks, each can live in a different directory.
# Relative paths resolve from where the script is run; use absolute paths
# or $(dirname "$0") to be safe.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PLAYBOOKS=(
  "${SCRIPT_DIR}/site/playbooks/deploy.yml"
  "${SCRIPT_DIR}/site/playbooks/harden.yml"
  "${SCRIPT_DIR}/network/playbooks/switches.yml"
  "${SCRIPT_DIR}/ops/provisioning/backup.yml"
)

INVENTORY="${SCRIPT_DIR}/inventory.txt"
FAIL_FAST=false
VERBOSE_COUNT=0
ANSIBLE_ARGS=()

usage() { awk 'NR>1 && !/^#/ {exit} NR>2 {sub(/^# ?/, ""); print}' "$0"; exit "${1:-0}"; }

while getopts "i:fcdl:L:S:e:vh" opt; do
  case "$opt" in
    i) INVENTORY="$OPTARG" ;;
    f) FAIL_FAST=true ;;
    c) ANSIBLE_ARGS+=(--check) ;;
    d) ANSIBLE_ARGS+=(--diff) ;;
    l) ANSIBLE_ARGS+=(--limit "$OPTARG") ;;
    L) ANSIBLE_ARGS+=(--tags "$OPTARG") ;;
    S) ANSIBLE_ARGS+=(--skip-tags "$OPTARG") ;;
    e) ANSIBLE_ARGS+=(--extra-vars "$OPTARG") ;;
    v) VERBOSE_COUNT=$((VERBOSE_COUNT + 1)) ;;
    h) usage 0 ;;
    *) usage 2 ;;
  esac
done
shift $((OPTIND - 1))

# Build the -v flag from the number of times -v was passed.
if (( VERBOSE_COUNT > 0 )); then
  vflag="-$(printf 'v%.0s' $(seq 1 "$VERBOSE_COUNT"))"
  ANSIBLE_ARGS+=("$vflag")
fi

# Allow positional playbook paths to override the configured list.
if (( $# > 0 )); then
  PLAYBOOKS=("$@")
fi

if [[ ! -f "$INVENTORY" ]]; then
  echo "ERROR: inventory file not found: $INVENTORY" >&2
  exit 1
fi

echo "==> Inventory : $INVENTORY"
echo "==> Playbooks : ${PLAYBOOKS[*]}"
echo

PASSED=()
FAILED=()
SKIPPED=()

for playbook in "${PLAYBOOKS[@]}"; do
  if [[ ! -f "$playbook" ]]; then
    echo "!!! SKIP (not found): $playbook"
    SKIPPED+=("$playbook")
    if $FAIL_FAST; then
      echo
      echo "Fail-fast enabled: stopping before remaining playbooks."
      break
    fi
    continue
  fi

  echo "=================================================================="
  echo "==> Running: $playbook"
  echo "=================================================================="
  ansible-playbook -i "$INVENTORY" ${ANSIBLE_ARGS[@]+"${ANSIBLE_ARGS[@]}"} "$playbook"
  status=$?

  if (( status == 0 )); then
    echo "==> OK: $playbook"
    PASSED+=("$playbook")
  else
    echo "==> FAILED (exit $status): $playbook"
    FAILED+=("$playbook")
    if $FAIL_FAST; then
      echo
      echo "Fail-fast enabled: stopping before remaining playbooks."
      break
    fi
  fi
  echo
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "===================== SUMMARY ====================="
printf '  %s : %s\n' "OK"      "${#PASSED[@]}"
printf '  %s : %s\n' "FAILED"  "${#FAILED[@]}"
printf '  %s : %s\n' "SKIPPED" "${#SKIPPED[@]}"
for pb in "${PASSED[@]:-}";   do [[ -n $pb ]] && printf '    [OK]      %s\n' "$pb"; done
for pb in "${FAILED[@]:-}";   do [[ -n $pb ]] && printf '    [FAILED]  %s\n' "$pb"; done
for pb in "${SKIPPED[@]:-}";  do [[ -n $pb ]] && printf '    [SKIPPED] %s\n' "$pb"; done
echo "==================================================="

(( ${#FAILED[@]} == 0 && ${#SKIPPED[@]} == 0 )) || exit 1
exit 0

#!/usr/bin/env bash
#
# uninstall-extensions.sh
# Uninstalls VS Code extensions listed in extensions.txt, or all installed
# extensions when --all is passed (full reset).
#
# Usage:
#   ./uninstall-extensions.sh [--file PATH] [--cmd CMD] [--all] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSIONS_FILE="${SCRIPT_DIR}/extensions.txt"
CODE_CMD="code"
DRY_RUN=0
ALL=0

usage() {
  cat <<EOF
Usage: ${0##*/} [options]

Uninstall VS Code extensions.

Options:
  -f, --file FILE   Path to extensions list (default: ./extensions.txt)
  -c, --cmd CMD     VS Code CLI to use (default: code)
  -a, --all         Uninstall ALL installed extensions (full reset)
  -n, --dry-run     Show what would be done without making changes
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)    EXTENSIONS_FILE="$2"; shift 2 ;;
    -c|--cmd)     CODE_CMD="$2"; shift 2 ;;
    -a|--all)     ALL=1; shift ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if ! command -v "$CODE_CMD" >/dev/null 2>&1; then
  echo "ERROR: '$CODE_CMD' CLI not found in PATH." >&2
  exit 1
fi

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

INSTALLED_RAW="$("$CODE_CMD" --list-extensions 2>/dev/null || true)"

# Build list of targets (extension IDs only, no versions)
TARGETS=()
if [[ $ALL -eq 1 ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    TARGETS+=("$line")
  done <<< "$INSTALLED_RAW"

  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "No extensions installed; nothing to do."
    exit 0
  fi

  echo "About to uninstall ALL ${#TARGETS[@]} installed extensions."
  if [[ $DRY_RUN -eq 0 ]]; then
    read -r -p "Are you sure? [y/N] " ans
    case "$ans" in
      y|Y|yes|YES) ;;
      *) echo "Aborted."; exit 0 ;;
    esac
  fi
else
  if [[ ! -f "$EXTENSIONS_FILE" ]]; then
    echo "ERROR: extensions file not found: $EXTENSIONS_FILE" >&2
    exit 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [[ -z "$line" ]] && continue
    # Drop any @version suffix
    line="${line%@*}"
    TARGETS+=("$line")
  done < "$EXTENSIONS_FILE"
fi

# is_installed <id>: true if any version of the id is installed
is_installed() {
  local id="$1" id_lc line
  id_lc="$(lower "$id")"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$(lower "$line")" == "$id_lc" ]]; then
      return 0
    fi
  done <<< "$INSTALLED_RAW"
  return 1
}

ok=0; skip=0; fail=0
for id in "${TARGETS[@]}"; do
  [[ -z "$id" ]] && continue

  if ! is_installed "$id"; then
    echo "○ ${id} (not installed, skipping)"
    skip=$((skip + 1))
    continue
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "→ Would uninstall ${id}"
    ok=$((ok + 1))
    continue
  fi

  echo "→ Uninstalling ${id}"
  if "$CODE_CMD" --uninstall-extension "$id" >/dev/null 2>&1; then
    ok=$((ok + 1))
  else
    echo "✗ Failed to uninstall ${id}" >&2
    fail=$((fail + 1))
  fi
done

echo
echo "Summary: ${ok} uninstalled, ${skip} not present, ${fail} failed"
[[ $fail -eq 0 ]] || exit 1

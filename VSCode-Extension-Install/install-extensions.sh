#!/usr/bin/env bash
#
# install-extensions.sh
# Installs the team's standard VS Code extensions from extensions.txt.
#
# Usage:
#   ./install-extensions.sh [--file PATH] [--cmd CMD] [--dry-run]
#
# Companion: uninstall-extensions.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSIONS_FILE="${SCRIPT_DIR}/extensions.txt"
CODE_CMD="code"
DRY_RUN=0

usage() {
  cat <<EOF
Usage: ${0##*/} [options]

Install the team's standard VS Code extensions.

Options:
  -f, --file FILE   Path to extensions list (default: ./extensions.txt)
  -c, --cmd CMD     VS Code CLI to use (default: code; try code-insiders, cursor)
  -n, --dry-run     Show what would be done without making changes
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)    EXTENSIONS_FILE="$2"; shift 2 ;;
    -c|--cmd)     CODE_CMD="$2"; shift 2 ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if ! command -v "$CODE_CMD" >/dev/null 2>&1; then
  echo "ERROR: '$CODE_CMD' CLI not found in PATH." >&2
  echo "  macOS: in VS Code press Cmd+Shift+P, run" >&2
  echo "         'Shell Command: Install code command in PATH'" >&2
  echo "  Linux: should be installed with VS Code; restart your shell" >&2
  echo "         or check 'which code'" >&2
  exit 1
fi

if [[ ! -f "$EXTENSIONS_FILE" ]]; then
  echo "ERROR: extensions file not found: $EXTENSIONS_FILE" >&2
  exit 1
fi

# Portable lowercase helper (avoids bash 4+ ${var,,})
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Parse extensions file: strip comments, trim, drop blanks
WANTED=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="$(printf '%s' "$line" | tr -d '[:space:]')"
  [[ -z "$line" ]] && continue
  WANTED+=("$line")
done < "$EXTENSIONS_FILE"

if [[ ${#WANTED[@]} -eq 0 ]]; then
  echo "No extensions listed in $EXTENSIONS_FILE"
  exit 0
fi

# Snapshot installed extensions once (id@version per line)
INSTALLED_RAW="$("$CODE_CMD" --list-extensions --show-versions 2>/dev/null || true)"

# is_installed <id> [ver]
# - With ver: returns 0 only if that exact version is installed.
# - Without ver: returns 0 if any version is installed; echoes that version.
is_installed() {
  local id="$1" ver="${2:-}"
  local id_lc line line_id line_ver line_id_lc
  id_lc="$(lower "$id")"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line_id="${line%@*}"
    line_ver="${line#*@}"
    line_id_lc="$(lower "$line_id")"
    if [[ "$line_id_lc" == "$id_lc" ]]; then
      if [[ -z "$ver" || "$line_ver" == "$ver" ]]; then
        printf '%s' "$line_ver"
        return 0
      fi
    fi
  done <<< "$INSTALLED_RAW"
  return 1
}

ok=0; skip=0; fail=0
for entry in "${WANTED[@]}"; do
  if [[ "$entry" == *"@"* ]]; then
    id="${entry%@*}"
    ver="${entry#*@}"
    target="${id}@${ver}"
  else
    id="$entry"
    ver=""
    target="$id"
  fi

  if cur="$(is_installed "$id" "$ver")"; then
    if [[ -n "$ver" ]]; then
      echo "✓ ${id}@${ver} (already installed)"
    else
      echo "✓ ${id} (already installed: ${cur})"
    fi
    skip=$((skip + 1))
    continue
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "→ Would install ${target}"
    ok=$((ok + 1))
    continue
  fi

  echo "→ Installing ${target}"
  if "$CODE_CMD" --install-extension "$target" --force >/dev/null 2>&1; then
    ok=$((ok + 1))
  else
    echo "✗ Failed to install ${target}" >&2
    fail=$((fail + 1))
  fi
done

echo
echo "Summary: ${ok} installed, ${skip} already present, ${fail} failed"
[[ $fail -eq 0 ]] || exit 1

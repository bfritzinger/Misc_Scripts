#!/usr/bin/env bash
# fapolicyd-trust - build and maintain a fapolicyd trust list from what is
#                   actually running on this system.
#
# WHY THIS EXISTS
#   The RHEL STIG profile installs, enables and starts fapolicyd
#   (package_fapolicyd_installed / service_fapolicyd_enabled). fapolicyd ships
#   ENFORCING with trust sourced from the RPM database, so anything not
#   installed by rpm -- Centrify, vendor agents, in-house apps -- stops working
#   the moment the service starts. This tool builds the allow-list from the
#   software that is genuinely present and running, so the control can be met
#   without taking the system down.
#
# THE SHAPE, deliberately mirroring fw-discover:
#   default     discover and report; changes nothing
#   --generate  write the trust file(s); does not tell the daemon
#   --apply     generate + reload trust; STAYS PERMISSIVE
#   --enforce   flip to enforcing behind an auto-revert timer
#   --verify    report drift between the trust file and disk
#
# Measured on RHEL 8.10 / fapolicyd 1.3.2. See NOTES at the bottom for the
# behaviours that drove the design -- several of them are traps.

set -o errexit -o nounset -o pipefail

PROG="${0##*/}"
VERSION="1.0.0"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
TRUST_DIR="/etc/fapolicyd/trust.d"
FAPD_CONF="/etc/fapolicyd/fapolicyd.conf"
RULES_DIR="/etc/fapolicyd/rules.d"
NAME="local"
declare -a APP_PATHS=()
declare -a EXCLUDE_PATHS=()
MODE="report"
TIMEOUT=300
WATCH_SECS=120
INCLUDE_RUNNING=1
DENY_LOG=""
OUTDIR=""
ASSUME_YES=0
DIR_RULE=0
PERMANENT_OK=0
ALL_FILES=0
VERIFY_RPM=0
RPM_INDEX=""

# Paths that are never trust candidates even when a live process maps them.
# /memfd: and (deleted) are not files on disk; /proc, /sys, /run and /dev are
# kernel or runtime surfaces; kernel module indexes are rebuilt by depmod.
readonly SKIP_RE='^(/memfd:|/dev/|/proc/|/sys/|/run/|/var/run/)|\(deleted\)$|/usr/lib/modules/.*\.bin$'

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_YEL=$'\033[33m'; C_GRN=$'\033[32m'
  C_DIM=$'\033[2m';  C_RST=$'\033[0m'
else
  C_RED=""; C_YEL=""; C_GRN=""; C_DIM=""; C_RST=""
fi

log()  { printf '%s\n' "$*"; }
ok()   { printf '%s[ ok ]%s %s\n'   "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s[warn]%s %s\n'   "$C_YEL" "$C_RST" "$*" >&2; }
err()  { printf '%s[fail]%s %s\n'   "$C_RED" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }
step() { printf '\n%s== %s ==%s\n' "$C_DIM" "$*" "$C_RST"; }

confirm() {
  local prompt="$1" reply
  ((ASSUME_YES)) && { log "$prompt -> auto-confirmed (--yes)"; return 0; }
  [[ -t 0 ]] || { err "$prompt"; die "not a terminal and --yes was not given"; }
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy] ]]
}

# --yes deliberately does NOT authorise this. Making enforcement permanent is
# the one change that outlives the auto-revert timer: get it wrong unattended
# and the box stays locked with no human having watched it. Same reasoning as
# fw-discover keeping --allow-unmask separate from --yes.
confirm_permanent() {
  local prompt="$1" reply
  ((PERMANENT_OK)) && { log "$prompt -> authorised by --allow-permanent"; return 0; }
  if [[ ! -t 0 ]]; then
    warn "$prompt"
    warn "not a terminal and --allow-permanent was not given -> reverting to permissive"
    return 1
  fi
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy] ]]
}

usage() {
  cat <<EOF
$PROG $VERSION - build a fapolicyd trust list from what is actually running

USAGE
  $PROG [options]

MODES
  (default)         Discover and report. Writes nothing, changes nothing.
  --generate        Write the trust file. Does not notify the daemon.
  --apply           Generate + reload the trust database. Stays PERMISSIVE,
                    so nothing can be blocked as a result of running this.
  --enforce         Set permissive=0 behind an auto-revert timer, verify,
                    then ask before making it permanent.
  --verify          Report drift between the trust file and what is on disk.
  --watch [SEC]     Run fapolicyd in the foreground with --debug-deny for SEC
                    seconds (default $WATCH_SECS) and record every denial while
                    you exercise the system. Safe: restores prior state after.
  --status          Show fapolicyd state, trust sources and managed files.

OPTIONS
  -n, --name NAME       Trust file name under $TRUST_DIR (default: $NAME)
  -p, --path DIR        Application root to trust. Repeatable.
  -x, --exclude PATH    Path prefix to skip. Repeatable.
  -t, --timeout SEC     Auto-revert window for --enforce (default: $TIMEOUT)
      --from-deny FILE  Build trust from a denial log captured by --watch
      --no-running      Do not harvest from running processes (/proc)
      --all-files       Trust every file found, not just the types the policy
                        can actually deny. Much larger list; usually wrong.
      --verify-rpm      Also treat MODIFIED rpm-owned files as candidates.
                        Thorough but slow on a host with many packages.
      --dir-rule        ALSO emit a directory allow rule. Read the warning in
                        --help output before using this; it is weaker.
  -o, --outdir DIR      Where reports are written (default: a temp dir)
  -y, --yes             Skip confirmation prompts. Does NOT authorise making
                        enforcement permanent - see --allow-permanent.
      --allow-permanent Permit --enforce to make enforcement permanent without
                        a human answering. Deliberately separate from --yes:
                        permanence is the one change the auto-revert timer
                        cannot undo for you.
  -h, --help            This message
  -V, --version         Print version

EXAMPLES
  # See what would be trusted. Always start here. Changes nothing.
  sudo $PROG -p /opt/centrify -p /usr/share/centrifydc

  # Record what fapolicyd WOULD block while you log in and start the apps
  sudo $PROG --watch 300 -o /root/fapd

  # Build trust from that recording plus the app roots, and load it
  sudo $PROG --apply -n siteapps -p /opt/centrify --from-deny /root/fapd/denials.log

  # Turn enforcement on with a 5 minute safety net
  sudo $PROG --enforce -t 300

  # After an application update, re-run. Idempotent: same inputs, same file.
  sudo $PROG --apply -n siteapps -p /opt/centrify

SAFETY
  Nothing in this tool sets permissive=0 except --enforce, and --enforce always
  arms a timer that puts it back. The permanent change is a separate, explicit
  confirmation after verification passes.
EOF
}

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
parse_args() {
  while (($#)); do
    case "$1" in
      --generate)   MODE="generate"; shift ;;
      --apply)      MODE="apply";    shift ;;
      --enforce)    MODE="enforce";  shift ;;
      --verify)     MODE="verify";   shift ;;
      --status)     MODE="status";   shift ;;
      --watch)
        MODE="watch"
        if [[ "${2:-}" =~ ^[0-9]+$ ]]; then WATCH_SECS="$2"; shift 2; else shift; fi ;;
      --watch=*)    MODE="watch"; WATCH_SECS="${1#*=}"; shift ;;
      -n|--name)    NAME="${2:?--name needs a value}"; shift 2 ;;
      --name=*)     NAME="${1#*=}"; shift ;;
      -p|--path)    APP_PATHS+=("${2:?--path needs a value}"); shift 2 ;;
      --path=*)     APP_PATHS+=("${1#*=}"); shift ;;
      -x|--exclude) EXCLUDE_PATHS+=("${2:?--exclude needs a value}"); shift 2 ;;
      --exclude=*)  EXCLUDE_PATHS+=("${1#*=}"); shift ;;
      -t|--timeout) TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
      --timeout=*)  TIMEOUT="${1#*=}"; shift ;;
      --from-deny)  DENY_LOG="${2:?--from-deny needs a value}"; shift 2 ;;
      --from-deny=*) DENY_LOG="${1#*=}"; shift ;;
      --no-running) INCLUDE_RUNNING=0; shift ;;
      --all-files)  ALL_FILES=1; shift ;;
      --verify-rpm) VERIFY_RPM=1; shift ;;
      --dir-rule)   DIR_RULE=1; shift ;;
      -o|--outdir)  OUTDIR="${2:?--outdir needs a value}"; shift 2 ;;
      --outdir=*)   OUTDIR="${1#*=}"; shift ;;
      -y|--yes)     ASSUME_YES=1; shift ;;
      --allow-permanent) PERMANENT_OK=1; shift ;;
      -h|--help)    usage; exit 0 ;;
      -V|--version) printf '%s %s\n' "$PROG" "$VERSION"; exit 0 ;;
      *)            die "unknown option: $1 (try --help)" ;;
    esac
  done

  [[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] \
    || die "--name must be a plain filename: got '$NAME'"
  [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || die "--timeout must be an integer"
  ((TIMEOUT >= 60)) || die "--timeout below 60s leaves no time to verify"
  [[ "$WATCH_SECS" =~ ^[0-9]+$ ]] || die "--watch needs an integer"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
need_root() {
  ((EUID == 0)) || die "must run as root (reads every process and writes $TRUST_DIR)"
}

have_fapolicyd() { command -v fapolicyd >/dev/null 2>&1; }

preflight() {
  need_root
  command -v rpm >/dev/null 2>&1 || die "rpm not found; this tool is for RPM systems"
  command -v sha256sum >/dev/null 2>&1 || die "sha256sum not found (coreutils)"

  if ! have_fapolicyd; then
    # Discovery is still entirely valid -- and is exactly what you want to run
    # BEFORE installing fapolicyd, so the trust list exists before the service
    # that needs it.
    case "$MODE" in
      # show_status reports the not-installed state itself, and that is exactly
      # the state a host is in BEFORE the STIG turns fapolicyd on -- which is
      # when you most want to run it.
      status) : ;;
      report|generate) warn "fapolicyd is not installed - discovery only, nothing will be loaded" ;;
      *) die "fapolicyd is not installed; '$MODE' needs it. Run the default report mode first." ;;
    esac
  fi

  if [[ -z "$OUTDIR" ]]; then
    OUTDIR="$(mktemp -d -t fapolicyd-trust-XXXXXX)"
  else
    mkdir -p "$OUTDIR"
  fi
}

# ---------------------------------------------------------------------------
# Trust decisions
# ---------------------------------------------------------------------------

# Only these file types can ever be DENIED by the shipped policy, so only these
# are worth trusting. Everything else -- README files, .json, source code, the
# database files docker mmaps -- is allowed by 95-allow-open no matter what, and
# putting it in the trust list is pure noise that makes the list harder to
# defend to an assessor.
#   ELF               -> 90-deny-execute (execute), 41-shared-obj (open)
#   %languages        -> 70-trusted-lang (open): python, perl, java, ruby, ...
#   text/x-shellscript-> allowed by 72-shell.rules regardless of trust, but
#                        included because a site that tightens that rule would
#                        otherwise lose every script at once.
readonly RELEVANT_RE='^(application/(x-executable|x-pie-executable|x-sharedlib|x-mach-binary|java-archive|javascript|x-elc|x-bytecode\.(python|ocaml)|x-sharedlib.*)|text/(x-(python|perl|ruby|php|lua|tcl|java|awk|gawk|lisp|m4|nftables|R|luatex|systemtap|script\.guile|shellscript)|javascript))$'

# Building the owned-path set ONCE turns an O(files) fork storm into a sorted
# lookup. Measured on a host with 222,196 rpm-owned paths: per-file `rpm -qf`
# plus `rpm -Vf` took 3m32s; the index takes a couple of seconds.
build_rpm_index() {
  RPM_INDEX="$OUTDIR/rpm-owned.txt"
  [[ -s "$RPM_INDEX" ]] && return 0
  rpm -qal 2>/dev/null | sort -u > "$RPM_INDEX"
  local n; n="$(wc -l < "$RPM_INDEX")"
  log "  ${C_DIM}indexed $n rpm-owned paths${C_RST}" >&2
}

# rpm owning the path is what the rpmdb backend keys on. A MODIFIED rpm-owned
# file loses that trust (fapolicyd stores rpm's hash), but proving that needs
# `rpm -V` per file, which is what made this unusable on a real host. Default
# to the fast path; --verify-rpm buys the thorough one. Files missed this way
# still surface through --watch, which is the empirical source anyway.
rpm_covers() {
  local f="$1"
  grep -qxF "$f" "$RPM_INDEX" || return 1
  ((VERIFY_RPM)) || return 0
  local v
  v="$(rpm -Vf "$f" 2>/dev/null | awk -v p="$f" '$NF == p {print $1}')" || true
  [[ -z "$v" || ! "$v" =~ [5S] ]]
}

# Is this file something the policy could actually block?
relevant_ftype() {
  local f="$1" t
  ((ALL_FILES)) && return 0
  t="$(file -b --mime-type "$f" 2>/dev/null)" || return 1
  [[ "$t" =~ $RELEVANT_RE ]] && return 0
  # A file with the execute bit set is a candidate whatever `file` thinks it is.
  [[ -x "$f" ]]
}

excluded() {
  local f="$1" pfx
  for pfx in ${EXCLUDE_PATHS+"${EXCLUDE_PATHS[@]}"}; do
    [[ "$f" == "$pfx"* ]] && return 0
  done
  return 1
}

# A path with whitespace cannot be represented: the trust file format is
# space-separated PATH SIZE SHA256 with no quoting. Refusing loudly beats
# writing a line fapolicyd will parse into the wrong fields.
usable_path() {
  local f="$1"
  if [[ "$f" =~ [[:space:]] ]]; then
    warn "skipping path containing whitespace (unrepresentable in a trust file): $f"
    return 1
  fi
  [[ -f "$f" && -r "$f" ]]
}

# ---------------------------------------------------------------------------
# Discovery sources
# ---------------------------------------------------------------------------

# 1. Static: every regular file under the application roots the operator named.
discover_static() {
  local root
  for root in ${APP_PATHS+"${APP_PATHS[@]}"}; do
    [[ -e "$root" ]] || { warn "no such path, skipping: $root"; continue; }
    if [[ -f "$root" ]]; then printf '%s\n' "$root"; continue; fi
    find "$root" -type f -print 2>/dev/null || true
  done
}

# 2. Running: executables and mapped libraries of live processes. This is the
#    literal reading of "trust what is running".
discover_running() {
  ((INCLUDE_RUNNING)) || return 0
  local p e
  for p in /proc/[0-9]*; do
    e="$(readlink -f "$p/exe" 2>/dev/null)" || continue
    [[ -n "$e" ]] && printf '%s\n' "$e"
  done
  # $6 is the pathname column of /proc/PID/maps; entries without one are
  # anonymous memory and have no file to trust.
  awk '$6 ~ /^\//{print $6}' /proc/[0-9]*/maps 2>/dev/null || true
}

# 3. Denials: paths fapolicyd actually blocked, harvested by --watch.
#    Format (fapolicyd 1.3.2):
#      rule=13 dec=deny_audit perm=execute auid=0 pid=N exe=/usr/bin/bash \
#        : path=/opt/acme/bin/acmed ftype=application/x-executable trust=0
discover_denials() {
  [[ -n "$DENY_LOG" ]] || return 0
  [[ -r "$DENY_LOG" ]] || die "--from-deny file not readable: $DENY_LOG"
  local n
  n="$(grep -c 'dec=deny' "$DENY_LOG" || true)"
  log "  ${C_DIM}denial log: $DENY_LOG ($n denial records)${C_RST}" >&2
  sed -n 's/.* path=\(.*\) ftype=.*/\1/p' "$DENY_LOG" 2>/dev/null || true
}

# Collect, filter, de-duplicate. Emits the final candidate list.
collect_candidates() {
  build_rpm_index
  {
    discover_static
    discover_running
    discover_denials
  } | sort -u | while IFS= read -r f; do
        [[ "$f" =~ $SKIP_RE ]] && continue
        excluded "$f"        && continue
        usable_path "$f"     || continue
        rpm_covers "$f"      && continue
        relevant_ftype "$f"  || continue
        printf '%s\n' "$f"
      done
}

# ---------------------------------------------------------------------------
# Trust file generation -- regenerate from scratch, always
# ---------------------------------------------------------------------------
# Regenerating wholesale is what makes this idempotent. It handles an added
# file, a changed file and a DELETED file with one code path, and it is the
# only way to remove an orphan: fapolicyd-cli --file delete refuses a path that
# no longer exists. See NOTES.
trust_file_path() { printf '%s/%s' "$TRUST_DIR" "$NAME"; }

generate_trust_file() {
  local dest tmp entries n=0
  dest="$(trust_file_path)"
  entries="$(mktemp)"

  while IFS= read -r f; do
    printf '%s %s %s\n' "$f" "$(stat -c%s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)" >> "$entries"
    n=$((n + 1))
  done < "$CANDIDATES"

  if ((n == 0)); then
    rm -f "$entries"
    warn "no untrusted files found - nothing to write"
    return 1
  fi

  # TRUE idempotency: when the entries are unchanged, do not touch the file at
  # all -- same bytes, same mtime. A header timestamp that moves on every run
  # makes config management (Ansible, Puppet) see a changed file every time and
  # fire its handler forever, restarting fapolicyd on a box where nothing
  # changed. Recording when the CONTENT last changed is also the more useful
  # fact than when the tool last ran.
  if [[ -r "$dest" ]] && diff -q <(grep -v '^#' "$dest" || true) "$entries" >/dev/null 2>&1; then
    rm -f "$entries"
    ok "$n entries already current in $dest (file untouched)"
    return 0
  fi

  mkdir -p "$TRUST_DIR"
  tmp="$(mktemp "${dest}.XXXXXX")"
  {
    printf '# managed by %s %s -- regenerated in full when content changes\n' "$PROG" "$VERSION"
    printf '# source paths: %s\n' "${APP_PATHS[*]:-<none>}"
    printf '# content last changed: %s on %s\n' "$(date -Is)" "$(uname -n)"
    printf '# FULL PATH  SIZE  SHA256\n'
    cat "$entries"
  } > "$tmp"
  rm -f "$entries"
  chmod 644 "$tmp"; chown root:root "$tmp"
  # Same-filesystem rename: the daemon never sees a half-written trust file.
  mv -f "$tmp" "$dest"
  ok "wrote $n entries to $dest"
  return 0
}

reload_trust() {
  fapolicyd-cli --update >/dev/null 2>&1 \
    && ok "fapolicyd notified (trust database reloaded)" \
    || warn "fapolicyd-cli --update failed; is the daemon running?"
}

# ---------------------------------------------------------------------------
# Directory rule (opt-in, weaker)
# ---------------------------------------------------------------------------
write_dir_rule() {
  local rf="$RULES_DIR/45-${NAME}-dirs.rules" root
  ((${#APP_PATHS[@]})) || { warn "--dir-rule needs at least one --path"; return 1; }
  {
    printf '# managed by %s -- directory allow rules\n' "$PROG"
    printf '# WEAKER THAN PER-FILE TRUST: anything later dropped into these\n'
    printf '# directories is trusted without being hashed or reviewed.\n'
    for root in "${APP_PATHS[@]}"; do
      [[ -d "$root" ]] && printf 'allow perm=any all : dir=%s/\n' "${root%/}"
    done
  } > "$rf"
  chmod 644 "$rf"
  ok "wrote $rf"
  command -v fagenrules >/dev/null 2>&1 && fagenrules --load >/dev/null 2>&1 \
    && ok "rules recompiled"
}

# ---------------------------------------------------------------------------
# Watch mode -- capture real denials
# ---------------------------------------------------------------------------
# On a kernel without fanotify audit support, deny_audit decisions reach NO
# persistent log: not auditd, not syslog, not the journal. Running the daemon
# in the foreground with --debug-deny is the only way to see them. That is why
# this mode exists rather than just reading /var/log/audit/audit.log.
watch_denials() {
  local out="$OUTDIR/denials.log" was_active=0 prev_permissive
  have_fapolicyd || die "fapolicyd is not installed"

  systemctl is-active --quiet fapolicyd && was_active=1
  prev_permissive="$(awk -F'= *' '/^permissive/{print $2}' "$FAPD_CONF")"

  step "Recording denials for ${WATCH_SECS}s"
  log "Exercise the system NOW: log in as the service accounts, start the apps,"
  log "run the scheduled jobs. Everything fapolicyd would block gets recorded."
  log ""
  log "Running PERMISSIVE - nothing is actually blocked during this window."

  restore_watch() {
    pkill -f 'fapolicyd --debug-deny' 2>/dev/null || true
    sed -i "s/^permissive = .*/permissive = ${prev_permissive}/" "$FAPD_CONF"
    ((was_active)) && systemctl start fapolicyd >/dev/null 2>&1 || true
  }
  trap restore_watch EXIT INT TERM

  systemctl stop fapolicyd >/dev/null 2>&1 || true
  sed -i 's/^permissive = .*/permissive = 1/' "$FAPD_CONF"
  timeout "$WATCH_SECS" /usr/sbin/fapolicyd --debug-deny > "$out" 2>&1 || true

  trap - EXIT INT TERM
  restore_watch

  local n
  n="$(grep -c 'dec=deny' "$out" 2>/dev/null || true)"
  ok "captured ${n:-0} denial record(s) -> $out"
  if [[ "${n:-0}" -gt 0 ]]; then
    log ""
    log "Distinct paths that would have been blocked:"
    sed -n 's/.* path=\(.*\) ftype=.*/  \1/p' "$out" | sort -u
    log ""
    log "Feed it back in:  $PROG --apply -n $NAME --from-deny $out"
  else
    log ""
    log "No denials recorded. Either nothing untrusted ran during the window,"
    log "or the window was too short. This is NOT proof the system is clean --"
    log "re-run with a longer --watch while exercising more of the workload."
  fi
}

# ---------------------------------------------------------------------------
# Verify / drift
# ---------------------------------------------------------------------------
verify_trust() {
  local dest missing=0 changed=0 total=0 path size hash cur_size cur_hash
  dest="$(trust_file_path)"
  [[ -r "$dest" ]] || die "no trust file at $dest - run --generate first"

  step "Verifying $dest"
  while read -r path size hash; do
    [[ "$path" =~ ^# ]] && continue
    [[ -z "${path:-}" ]] && continue
    total=$((total + 1))
    if [[ ! -e "$path" ]]; then
      err "MISSING  $path"
      missing=$((missing + 1))
      continue
    fi
    cur_size="$(stat -c%s "$path")"
    cur_hash="$(sha256sum "$path" | cut -d' ' -f1)"
    if [[ "$cur_size" != "$size" || "$cur_hash" != "$hash" ]]; then
      warn "CHANGED  $path (size $size->$cur_size)"
      changed=$((changed + 1))
    fi
  done < "$dest"

  log ""
  log "  entries: $total   changed: $changed   missing: $missing"
  if ((missing || changed)); then
    log ""
    log "  Re-run '$PROG --apply -n $NAME ...' to bring the trust file back in"
    log "  line with disk. With integrity=none a stale hash does not block"
    log "  execution today, but it makes this file a false record -- and if"
    log "  integrity is ever raised, every stale entry becomes a denial."
    return 2
  fi
  ok "trust file matches disk"
  return 0
}

# ---------------------------------------------------------------------------
# Enforce, behind a timer
# ---------------------------------------------------------------------------
enforce() {
  have_fapolicyd || die "fapolicyd is not installed"
  local dest; dest="$(trust_file_path)"
  [[ -r "$dest" ]] || die "no trust file at $dest - run --apply first"

  verify_trust || warn "trust file does not match disk; continuing anyway"

  step "Enabling enforcement with a ${TIMEOUT}s auto-revert"
  warn "fapolicyd will block untrusted execution for the next ${TIMEOUT}s."
  warn "If anything breaks, DO NOTHING - it reverts to permissive by itself."
  confirm "Enable enforcement now?" || die "aborted by operator"

  # The revert is scheduled BEFORE enforcement is enabled, and is detached from
  # this shell, so losing the session cannot leave the system enforcing.
  if command -v systemd-run >/dev/null 2>&1; then
    systemd-run --quiet --on-active="${TIMEOUT}" --unit="fapolicyd-trust-revert" \
      /bin/bash -c "sed -i 's/^permissive = .*/permissive = 1/' '$FAPD_CONF'; systemctl restart fapolicyd" \
      || die "could not schedule the auto-revert; refusing to enforce without it"
  else
    setsid nohup bash -c "sleep ${TIMEOUT}; sed -i 's/^permissive = .*/permissive = 1/' '$FAPD_CONF'; systemctl restart fapolicyd" \
      >/dev/null 2>&1 < /dev/null &
    disown || true
  fi
  ok "auto-revert armed for ${TIMEOUT}s"

  sed -i 's/^permissive = .*/permissive = 0/' "$FAPD_CONF"
  systemctl restart fapolicyd
  sleep 3
  systemctl is-active --quiet fapolicyd || die "fapolicyd failed to start; check journalctl -u fapolicyd"
  ok "fapolicyd is ENFORCING (reverts in ${TIMEOUT}s unless made permanent)"

  log ""
  log "Verify the system NOW - log in, start the apps, run the jobs."
  log ""
  if confirm_permanent "Did everything work? Make enforcement permanent?"; then
    systemctl stop fapolicyd-trust-revert.timer >/dev/null 2>&1 || true
    systemctl reset-failed fapolicyd-trust-revert.timer >/dev/null 2>&1 || true
    pkill -f "sleep ${TIMEOUT}" 2>/dev/null || true
    systemctl enable fapolicyd >/dev/null 2>&1 || true
    ok "enforcement is permanent; fapolicyd enabled at boot"
  else
    sed -i 's/^permissive = .*/permissive = 1/' "$FAPD_CONF"
    systemctl restart fapolicyd
    ok "reverted to permissive"
  fi
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
show_status() {
  step "fapolicyd status"
  if ! have_fapolicyd; then
    log "  fapolicyd: NOT INSTALLED"
    log "  (the STIG will install it - build the trust list BEFORE that happens)"
    return 0
  fi
  printf '  package:    %s\n' "$(rpm -q fapolicyd 2>&1)"
  printf '  service:    %s\n' "$(systemctl is-active fapolicyd 2>&1) / $(systemctl is-enabled fapolicyd 2>&1)"
  printf '  permissive: %s\n' "$(awk -F'= *' '/^permissive/{print $2}' "$FAPD_CONF" 2>/dev/null)"
  printf '  trust:      %s\n' "$(awk -F'= *' '/^trust/{print $2}' "$FAPD_CONF" 2>/dev/null)"
  printf '  integrity:  %s\n' "$(awk -F'= *' '/^integrity/{print $2}' "$FAPD_CONF" 2>/dev/null)"
  log ""
  log "  managed trust files in $TRUST_DIR:"
  if compgen -G "$TRUST_DIR/*" >/dev/null; then
    local f
    for f in "$TRUST_DIR"/*; do
      printf '    %-40s %s entries\n' "$f" "$(grep -vc '^#' "$f" 2>/dev/null || printf 0)"
    done
  else
    log "    (none)"
  fi
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
report() {
  local n; n="$(wc -l < "$CANDIDATES")"
  step "Discovery"
  printf '  application roots : %s\n' "${APP_PATHS[*]:-<none given>}"
  printf '  running processes : %s\n' "$( ((INCLUDE_RUNNING)) && echo included || echo skipped)"
  printf '  denial log        : %s\n' "${DENY_LOG:-<none>}"
  printf '  untrusted files   : %s\n' "$n"
  log ""
  if ((n == 0)); then
    ok "nothing outside the RPM database needs trusting"
    log "  If the apps still fail under fapolicyd, run --watch while exercising"
    log "  them: static discovery cannot see a file that is only opened at"
    log "  runtime from a path no one told this tool about."
    return 0
  fi
  log "Files that would be added to the trust list:"
  local f
  while IFS= read -r f; do
    printf '  %-58s %s\n' "$f" "$(file -b --mime-type "$f" 2>/dev/null || echo '?')"
  done < "$CANDIDATES"
  log ""
  log "Nothing has been changed. To write the trust file:"
  log "  $PROG --apply -n $NAME ${APP_PATHS[*]/#/-p }"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"
  preflight

  CANDIDATES="$OUTDIR/candidates.txt"

  case "$MODE" in
    status) show_status; exit 0 ;;
    verify) verify_trust; exit $? ;;
    watch)  watch_denials; exit 0 ;;
    enforce) enforce; exit 0 ;;
  esac

  if ((${#APP_PATHS[@]} == 0)) && [[ -z "$DENY_LOG" ]] && ((INCLUDE_RUNNING == 0)); then
    die "nothing to discover: give --path, --from-deny, or leave /proc harvesting on"
  fi

  step "Collecting candidates"
  collect_candidates > "$CANDIDATES"

  case "$MODE" in
    report)   report ;;
    generate) report; generate_trust_file || true; ((DIR_RULE)) && write_dir_rule || true ;;
    apply)
      report
      if generate_trust_file; then
        ((DIR_RULE)) && write_dir_rule || true
        reload_trust
        log ""
        log "Trust is loaded and fapolicyd is still PERMISSIVE - nothing can break"
        log "as a result of this run. When you are ready:  $PROG --enforce"
      fi ;;
  esac
}

main "$@"

# ---------------------------------------------------------------------------
# NOTES - measured on RHEL 8.10, fapolicyd 1.3.2-1.el8, SSG 0.1.72
# ---------------------------------------------------------------------------
#
# 1. NEVER call `fapolicyd-cli --file update <dir>`.
#    If a single file listed in the trust file has since been deleted, the
#    command reports "Cannot open <path>" and leaves the trust file EMPTY.
#    Measured: 2 entries -> delete one file -> --file update -> 0 entries.
#    That turns one removed file into a total loss of trust for the whole
#    application. `--file delete` cannot repair it either, because it refuses a
#    path that no longer resolves. This tool regenerates the file instead.
#
# 2. `fapolicyd-cli --file add` is ADD-ONLY.
#    It appends new files and de-duplicates, but it does NOT refresh the size
#    or hash of a file that changed, and it does NOT remove entries for files
#    that are gone. After an application update it silently leaves stale data.
#
# 3. Denials may be logged NOWHERE.
#    Every shipped rule uses deny_audit. On a kernel without fanotify audit
#    support (RHEL 8.10 logs "allow_filesystem_mark is unsupported on this
#    kernel"), the denial reaches neither auditd, nor syslog, nor the journal.
#    Applications fail with "Operation not permitted" and leave no trail.
#    `fapolicyd --debug-deny` in the foreground is the only reliable source,
#    which is what --watch uses.
#
# 4. Root is exempt, so root-only testing proves nothing.
#    /etc/fapolicyd/rules.d/20-dracut.rules contains
#        allow perm=any uid=0 trust=1 : all
#    so root running a trusted binary is allowed everything. Untrusted software
#    fails only for NON-ROOT subjects. Always test as the service account.
#
# 5. The three breakage vectors, in the order they hurt:
#      - untrusted .so  -> denied on open (41-shared-obj). If a PAM module is
#                          not rpm-owned, AUTHENTICATION FAILS. This is usually
#                          what takes the system down.
#      - untrusted interpreted scripts -> denied on open (70-trusted-lang):
#                          python, perl, java, ruby, javascript, lua, php...
#      - untrusted ELF  -> denied on execute (90-deny-execute).
#    Shell scripts are NOT affected: 72-shell.rules allows text/x-shellscript
#    regardless of trust.
#
# 6. integrity = none means trust is BY PATH.
#    A file whose content no longer matches its recorded hash still executes.
#    Verified: a trust entry recording size 40 against a real size of 49 ran
#    without complaint. So a stale trust file does not break anything today --
#    but it is an inaccurate record, and raising `integrity` later converts
#    every stale entry into an outage. --verify reports the drift.
#
# 7. Build the trust list BEFORE the STIG enables the service.
#    package_fapolicyd_installed and service_fapolicyd_enabled are the two SSG
#    rules that turn this on. If they run on a subscribed host with no trust
#    list in place, every non-root application stops at once.

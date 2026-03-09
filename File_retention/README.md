# file_retention.sh

A config-driven bash script for age-based file cleanup across multiple directories. Each directory can have its own retention policy, glob pattern, and recursion setting — all managed from a single config file without touching the script itself.

---

## Features

- Per-directory retention rules with independent age thresholds
- Glob pattern filtering per rule (e.g., `*.log`, `*.csv`, `*`)
- Optional recursion control per directory
- Dry-run mode to preview deletions before committing
- Structured log output with timestamps and log levels
- Post-run summary: files deleted, space freed, elapsed time
- Empty subdirectory pruning after cleanup
- Exit code `1` on errors (cron/monitoring friendly)
- Safe handling of filenames with spaces and special characters

---

## Requirements

- Bash 4.0+
- Standard GNU coreutils: `find`, `stat`, `rm`, `date`
- `bc` (for human-readable byte formatting)

---

## Installation

```bash
# Install the script
cp file_retention.sh /usr/local/bin/file_retention.sh
chmod +x /usr/local/bin/file_retention.sh

# Install the config
cp file_retention.conf /etc/file_retention.conf

# Create log directory if needed
touch /var/log/file_retention.log
```

---

## Usage

```
file_retention.sh [OPTIONS]

Options:
  -c FILE     Config file path (default: /etc/file_retention.conf)
  -l FILE     Log file path    (default: /var/log/file_retention.log)
  -n          Dry-run — show what would be deleted, but don't delete
  -v          Verbose output (INFO-level messages to stdout)
  -h          Show help
```

### Examples

```bash
# Dry run with verbose output — recommended before first production run
file_retention.sh -n -v

# Run with a custom config and log file
file_retention.sh -c /opt/myapp/retention.conf -l /opt/myapp/retention.log

# Verbose production run
file_retention.sh -v
```

---

## Config File Format

One rule per line. Fields are pipe-delimited. Lines beginning with `#` are comments; blank lines are ignored.

```
DIRECTORY | MAX_AGE_DAYS | PATTERN | RECURSIVE
```

| Field | Required | Default | Description |
|---|---|---|---|
| `DIRECTORY` | Yes | — | Absolute path to target directory |
| `MAX_AGE_DAYS` | Yes | — | Delete files older than this many days (must be ≥ 1) |
| `PATTERN` | No | `*` | Glob pattern to match filenames |
| `RECURSIVE` | No | `yes` | Descend into subdirectories (`yes` / `no`) |

### Example Config

```ini
# ── Temp / Working Dirs ───────────────────────────────────────────
/tmp/uploads            |  7  | *        | no
/tmp/processing         |  1  | *        | yes

# ── Application Logs ─────────────────────────────────────────────
/var/log/app            | 30  | *.log    | yes
/var/log/app            | 14  | *.log.gz | yes
/var/log/nginx          | 14  | *.log    | no

# ── Export / Report Outputs ───────────────────────────────────────
/data/exports/csv       | 90  | *.csv    | yes
/data/exports/json      | 90  | *.json   | yes
/data/reports           | 60  | *.pdf    | no

# ── Backup Staging ────────────────────────────────────────────────
/data/backup/staging    | 14  | *.tar.gz | no
/data/backup/snapshots  | 30  | *        | yes
```

> **Note:** The same directory can appear in multiple rules with different patterns or age thresholds. Rules are processed independently and in order.

---

## Cron Setup

```bash
# Run daily at 2:00 AM
0 2 * * * /usr/local/bin/file_retention.sh -c /etc/file_retention.conf

# Run daily at 2:00 AM with a custom log file
0 2 * * * /usr/local/bin/file_retention.sh -c /etc/file_retention.conf -l /var/log/file_retention.log
```

Since the script exits with code `1` on any errors, cron will report failures via `MAILTO` if configured.

---

## Log Output

The script writes structured log lines to the log file (and optionally stdout with `-v`):

```
[2025-03-09 02:00:01] [STAT] === file_retention.sh START === Sun Mar  9 02:00:01 2025 ===
[2025-03-09 02:00:01] [INFO] Processing: /var/log/app | age=30d | pattern='*.log' | recursive=yes
[2025-03-09 02:00:01] [INFO] Deleted: /var/log/app/debug.log (2.31 MB)
[2025-03-09 02:00:02] [INFO] Deleted: /var/log/app/access.log.1 (856.00 KB)
[2025-03-09 02:00:02] [WARN] Directory not found, skipping: /data/exports/old
[2025-03-09 02:00:02] [STAT] === SUMMARY ===
[2025-03-09 02:00:02] [STAT]   Rules processed : 8
[2025-03-09 02:00:02] [STAT]   Files deleted   : 47
[2025-03-09 02:00:02] [STAT]   Space freed     : 312.44 MB
[2025-03-09 02:00:02] [STAT]   Errors          : 1
[2025-03-09 02:00:02] [STAT]   Elapsed         : 1s
[2025-03-09 02:00:02] [STAT] === file_retention.sh END ===
```

### Log Levels

| Level | Meaning |
|---|---|
| `STAT` | Start/end banners and summary metrics |
| `INFO` | Per-file actions and rule processing (verbose only) |
| `WARN` | Non-fatal issues (missing directory, malformed rule) |
| `ERROR` | Failed deletions or invalid config values |
| `DRY` | Dry-run output showing what would be deleted |

---

## Dry-Run Mode

Always run with `-n` first when deploying to a new environment or after making config changes:

```bash
file_retention.sh -n -v -c /etc/file_retention.conf
```

Output will show each file that *would* be deleted along with its size and age in days — no files are touched.

```
[DRY-RUN] Would delete: /var/log/app/debug.log (2.31 MB, 34d old)
[DRY-RUN] Would delete: /var/log/app/trace.log (441.00 KB, 45d old)
```

---

## Error Handling

| Condition | Behavior |
|---|---|
| Config file not found | Fatal — exits immediately with code `1` |
| Directory not found | Skips rule, logs `WARN`, continues |
| Invalid `MAX_AGE_DAYS` value | Skips rule, logs `ERROR`, continues |
| Malformed config line | Skips line, logs `WARN`, continues |
| File deletion failure | Logs `ERROR`, increments error count, continues |
| Log file not writable | Falls back to stderr, continues |
| Any errors occurred | Exits with code `1` after processing all rules |

---

## File Deletion Behavior

- Files are matched using `find -mtime +N`, where `N` is `MAX_AGE_DAYS`. This means files whose modification time is **strictly greater than** N days old (i.e., last modified more than N×24 hours ago).
- When `RECURSIVE=yes`, empty subdirectories are automatically removed after file cleanup.
- When `RECURSIVE=no`, only the top-level directory is scanned (`-maxdepth 1`).
- Filenames with spaces, newlines, or special characters are handled safely via `-print0`.

---

## Files

| File | Description |
|---|---|
| `file_retention.sh` | Main script |
| `file_retention.conf` | Retention rules config (edit this for your environment) |

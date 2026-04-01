# dirsync.py

A lightweight Python script that compares two directories and copies only the changed or new files (deltas) from source to destination. No external dependencies — stdlib only.

---

## Requirements

- Python 3.8+

---

## Usage

```bash
python3 dirsync.py <source_dir> <dest_dir> [options]
```

### Examples

```bash
# Basic sync — copy new and changed files
python3 dirsync.py /data/source /data/backup

# Preview changes without copying anything
python3 dirsync.py /data/source /data/backup --dry-run

# Sync and remove files in dest that no longer exist in source
python3 dirsync.py /data/source /data/backup --delete

# Use MD5 checksum comparison instead of mtime + size
python3 dirsync.py /data/source /data/backup --checksum

# Full verbose output showing unchanged files as well
python3 dirsync.py /data/source /data/backup --verbose

# Combine flags
python3 dirsync.py /data/source /data/backup --dry-run --delete --checksum --verbose
```

---

## Options

| Flag | Description |
|---|---|
| `--dry-run` | Simulate the sync — show what would be copied/deleted without making any changes |
| `--delete` | Remove files in the destination that no longer exist in the source |
| `--verbose` | Print all compared files, including those that are unchanged |
| `--checksum` | Compare files using MD5 hash instead of mtime + size |

---

## Comparison Logic

By default, two files are considered different if:

- Their **sizes differ**, or
- Their **modification times differ by more than 2 seconds**

The 2-second mtime tolerance is intentional — FAT and exFAT filesystems round timestamps to 2-second intervals, so this prevents false positives when syncing across different filesystem types (e.g., ext4 → USB drive).

With `--checksum`, files are compared using a full **MD5 hash**. This is more accurate but slower, and is recommended when syncing across network shares, NFS mounts, or other environments where mtime is unreliable.

---

## Output Reference

Each file processed during a sync is tagged with a status label:

| Tag | Meaning |
|---|---|
| `[NEW]` | File exists in source but not in destination — will be copied |
| `[CHANGED]` | File exists in both but differs — destination copy will be overwritten |
| `[DELETE]` | File exists in destination but not in source — will be removed (`--delete` only) |
| `[OK]` | Files match, no action taken (`--verbose` only) |
| `[ERROR]` | A copy or delete operation failed — details printed to stderr |

---

## Behavior Notes

- The destination directory is **created automatically** if it does not exist.
- Subdirectory structure from the source is **preserved** in the destination.
- File metadata (mtime, permissions) is preserved via `shutil.copy2`.
- When `--delete` is used, **empty directories** left behind after deletions are cleaned up automatically.
- Source and destination **cannot be the same path**.

---

## Recommended Workflow

Always do a dry run first, especially with `--delete`:

```bash
# Step 1: Preview
python3 dirsync.py /data/source /data/backup --dry-run --delete

# Step 2: Execute if output looks correct
python3 dirsync.py /data/source /data/backup --delete
```

---

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Completed successfully (errors during copy/delete are reported but do not set exit code) |
| `1` | Fatal error — source directory not found, or source and dest are the same path |

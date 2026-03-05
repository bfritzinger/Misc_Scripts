# chown_throttled.sh

A performance-conscious bash script for recursively changing file ownership across multiple directories on high-throughput systems. Designed to run safely alongside active workloads by controlling CPU and I/O priority, batching filesystem operations to avoid argument list limits, and skipping files that are already correctly owned.

---

## Features

- **Skips already-owned files** — uses `find`'s native `-user`/`-group` predicates to filter at traversal time, so correctly owned files never reach `chown`
- **Avoids `ARG_MAX` overflow** — pipes through `xargs -n BATCH_SIZE` so no "Argument list too long" errors regardless of file count
- **Tunable CPU priority** — `nice` level is configurable from normal (`0`) to lowest (`19`)
- **Tunable I/O priority** — `ionice` class is configurable: realtime, best-effort, or idle
- **Configurable throttle** — millisecond sleep between batches keeps burst I/O in check
- **Null-delimited paths** — `find -print0 | xargs -0` safely handles filenames with spaces, newlines, or special characters
- **Dry-run mode** — preview exactly what would be changed before making any modifications
- **Multi-directory support** — process any number of target directories in a single run
- **Input validation** — verifies target user/group exist on the system before starting
- **Timestamped logging** — all output includes timestamps; warnings and errors go to stderr

---

## Requirements

| Dependency | Purpose | Required |
|---|---|---|
| `bash` | Shell interpreter | Yes |
| `find` | Filesystem traversal and ownership filtering | Yes |
| `xargs` | Batched execution | Yes |
| `nice` | CPU priority control | Yes |
| `bc` | Millisecond sleep conversion | Recommended |
| `ionice` | I/O priority control | Optional (gracefully skipped if absent) |

All of the above are standard on Linux systems. `ionice` is part of the `util-linux` package and is available on virtually all modern Linux distributions.

---

## Installation

```bash
# Download / copy the script
chmod +x chown_throttled.sh

# Optionally move to a location on your PATH
sudo mv chown_throttled.sh /usr/local/bin/chown_throttled
```

---

## Usage

```
./chown_throttled.sh [OPTIONS]

Options:
  -u USER[:GROUP]   Owner to set (required)
  -d DIR            Target directory (repeatable)
  -b BATCH_SIZE     Files per chown call            (default: 500)
  -s SLEEP_MS       Sleep between batches in ms     (default: 50)
  -t TYPE           Find type: f=files d=dirs a=all (default: a)
  -p NICE_LEVEL     CPU nice level 0=normal..19=lowest (default: 10)
  -i IONICE_CLASS   IO class: 1=realtime 2=best-effort 3=idle (default: 2)
  -n                Dry run — show what would change, make no changes
  -h                Show help
```

---

## Examples

**Basic usage — two directories, default throttle:**
```bash
./chown_throttled.sh -u www-data:www-data -d /var/www -d /srv/uploads
```

**Files only, smaller batches, 25ms throttle:**
```bash
./chown_throttled.sh -u deploy:deploy -d /opt/app -t f -b 200 -s 25
```

**Dry run first — always recommended on production systems:**
```bash
./chown_throttled.sh -u deploy:deploy -d /opt/app -n
```

**Elevated priority during a maintenance window:**
```bash
./chown_throttled.sh -u app:app -d /data -p 0 -i 1
```

**Backed-off priority during peak hours:**
```bash
./chown_throttled.sh -u app:app -d /data -p 15 -i 3 -s 200
```

**User-only change (no group):**
```bash
./chown_throttled.sh -u deploy -d /srv/app
```

---

## Priority Tuning Reference

### CPU Priority (`-p`)

Controls how aggressively the script competes for CPU time relative to other processes.

| Value | Effect |
|---|---|
| `0` | Normal priority — same as any other process |
| `10` | Default — mild background behavior |
| `19` | Lowest possible — only runs when CPU is otherwise idle |

### I/O Priority (`-i`)

Controls how the kernel schedules disk access for this script.

| Class | Value | Effect |
|---|---|---|
| Realtime | `1` | Highest I/O priority — preempts other processes |
| Best-effort | `2` | Default — scheduled fairly alongside other processes |
| Idle | `3` | Only accesses disk when no other process needs it |

### Recommended Presets

| Scenario | Flags |
|---|---|
| Maintenance window, no active load | `-p 0 -i 1 -s 0` |
| Low-traffic period | `-p 5 -i 2 -s 25` |
| Default / moderate load | `-p 10 -i 2 -s 50` |
| Peak hours, high-throughput system | `-p 15 -i 3 -s 200` |
| Maximum yield — near-zero impact | `-p 19 -i 3 -b 100 -s 500` |

---

## How It Works

1. **Validation** — confirms the target user and group exist on the system and all directories are accessible before doing any work.

2. **Pre-scan** — counts total items and already-correctly-owned items per directory and reports the delta before processing begins.

3. **Filtered traversal** — `find` uses `-user` / `-group` predicates to emit only paths that actually need changing. Correctly owned files never leave `find`.

4. **Batched execution** — paths flow through a `|` into `xargs -0 -n BATCH_SIZE`, which invokes `chown` on chunks of up to `BATCH_SIZE` files per call. This keeps individual argument lists well within OS limits.

5. **Priority-controlled execution** — each `chown` call is wrapped in `nice` and `ionice` at the configured levels.

6. **Throttle** — a configurable sleep pause runs after each batch to spread I/O load over time rather than spiking it.

7. **Cleanup** — the temporary batch executor script written to `/tmp` is removed automatically on exit via a `trap`.

---

## Sample Output

```
[2025-06-12 14:22:01] ========================================
[2025-06-12 14:22:01]   chown_throttled.sh
[2025-06-12 14:22:01] ========================================
[2025-06-12 14:22:01]   Owner      : www-data:www-data
[2025-06-12 14:22:01]   Directories: /var/www /srv/uploads
[2025-06-12 14:22:01]   Batch size : 500 items/call
[2025-06-12 14:22:01]   Throttle   : 50ms between batches
[2025-06-12 14:22:01]   CPU nice   : 10 (0=normal, 19=lowest)
[2025-06-12 14:22:01]   IO class   : 2 (1=rt, 2=best-effort, 3=idle)
[2025-06-12 14:22:01]   Find type  : a (f=files, d=dirs, a=all)
[2025-06-12 14:22:01]   Skip owned : YES -- skipping items already owned by www-data:www-data
[2025-06-12 14:22:01]   Dry run    : false
[2025-06-12 14:22:01] ========================================
[2025-06-12 14:22:01] --- Directory: /var/www ---
[2025-06-12 14:22:02]   Total items    : 18432
[2025-06-12 14:22:02]   Already owned  : 16105 (skipping)
[2025-06-12 14:22:02]   To process     : 2327
[2025-06-12 14:22:09]   Status: OK
[2025-06-12 14:22:09] --- Directory: /srv/uploads ---
[2025-06-12 14:22:10]   Total items    : 4210
[2025-06-12 14:22:10]   Already owned  : 4210 (skipping)
[2025-06-12 14:22:10]   Nothing to do in /srv/uploads -- all items already owned by www-data:www-data
[2025-06-12 14:22:10] ========================================
[2025-06-12 14:22:10]   Run complete
[2025-06-12 14:22:10]   Total items found   : 22642
[2025-06-12 14:22:10]   Skipped (owned)     : 20315
[2025-06-12 14:22:10]   Processed           : 2327
[2025-06-12 14:22:10] ========================================
```

---

## Cron / Scheduled Use

The script is well-suited for scheduled runs on active systems. Redirect output to a log file and let cron manage scheduling:

```cron
# Run every 15 minutes, backed-off priority, log output
*/15 * * * * /usr/local/bin/chown_throttled -u www-data:www-data -d /var/www -p 10 -i 3 -s 100 >> /var/log/chown_throttled.log 2>&1
```

To keep log files from growing unbounded, pair with `logrotate` or use a wrapper that truncates on a schedule.

---

## Notes

- The script must be run as `root` or a user with permission to `chown` the target files.
- The pre-scan counts are informational and run at lowest priority (`nice -n 19`). On very large trees they add a small delay before processing begins — set `-s 0` and `-b 1000` if you want to skip the wait.
- `ionice` is silently skipped if not available on the system; `nice` is always applied.
- The temporary batch executor created in `/tmp` is automatically removed when the script exits, including on `Ctrl+C` or error.

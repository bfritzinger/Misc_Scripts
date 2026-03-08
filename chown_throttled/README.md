# chown_throttled.sh

A performance-conscious bash script for recursively changing file ownership across multiple directories on high-throughput systems. Designed to run safely alongside active workloads by controlling CPU and I/O priority, running parallel workers for faster throughput, batching filesystem operations to avoid argument list limits, and skipping files that are already correctly owned.

---

## Features

- **Parallel workers** — `xargs -P N` runs multiple `chown` batches concurrently; worker count auto-detected from CPU count or set manually
- **Parallel directory processing** — optional `-D` flag processes multiple target directories simultaneously as background jobs
- **Skips already-owned files** — uses `find`'s native `-user`/`-group` predicates to filter at traversal time; correctly owned files never reach `chown`
- **Avoids `ARG_MAX` overflow** — pipes through `xargs -n BATCH_SIZE` so no "Argument list too long" errors regardless of file count
- **Tunable CPU priority** — `nice` level is configurable from normal (`0`) to lowest (`19`)
- **Tunable I/O priority** — `ionice` class is configurable: realtime, best-effort, or idle
- **Per-worker throttle** — each worker sleeps independently between batches, spreading disk load rather than synchronizing spikes
- **Null-delimited paths** — `find -print0 | xargs -0` safely handles filenames with spaces, newlines, or special characters
- **Dry-run mode** — preview exactly what would be changed before making any modifications
- **Multi-directory support** — process any number of target directories in a single run, sequentially or in parallel
- **Input validation** — verifies target user/group exist on the system before starting
- **Timestamped logging** — all output includes timestamps and PID; warnings and errors go to stderr
- **Aggregated summary** — per-directory counts are combined into a final run total even when running in parallel

---

## Requirements

| Dependency | Purpose | Required |
|---|---|---|
| `bash` | Shell interpreter | Yes |
| `find` | Filesystem traversal and ownership filtering | Yes |
| `xargs` | Batched and parallel execution | Yes |
| `nice` | CPU priority control | Yes |
| `bc` | Millisecond sleep conversion | Recommended |
| `ionice` | I/O priority control | Optional (gracefully skipped if absent) |
| `nproc` | Auto-detect CPU count for default workers | Optional (falls back to 4) |

All of the above are standard on Linux systems. `ionice` is part of the `util-linux` package and is available on virtually all modern Linux distributions.

---

## Installation

```bash
chmod +x chown_throttled.sh

# Optionally install system-wide
sudo mv chown_throttled.sh /usr/local/bin/chown_throttled
```

---

## Usage

```
./chown_throttled.sh [OPTIONS]

Options:
  -u USER[:GROUP]   Owner to set (required)
  -d DIR            Target directory (repeatable)
  -b BATCH_SIZE     Files per worker per chown call      (default: 500)
  -w WORKERS        Parallel workers                     (default: nproc)
  -s SLEEP_MS       Sleep per worker between batches ms  (default: 50)
  -t TYPE           Find type: f=files d=dirs a=all      (default: a)
  -p NICE_LEVEL     CPU nice level 0=normal..19=lowest   (default: 10)
  -i IONICE_CLASS   IO class: 1=realtime 2=best-effort 3=idle (default: 2)
  -D                Process multiple -d directories in parallel
  -n                Dry run -- show what would change, make no changes
  -h                Show help
```

---

## Examples

**Basic — auto worker count, two directories:**
```bash
./chown_throttled.sh -u www-data:www-data -d /var/www -d /srv/uploads
```

**Explicit 8 workers, files only, fast throttle:**
```bash
./chown_throttled.sh -u deploy:deploy -d /opt/app -w 8 -t f -s 10
```

**Multiple directories processed in parallel, 4 workers each:**
```bash
./chown_throttled.sh -u app:app -d /data/a -d /data/b -d /data/c -D -w 4
```

**Dry run first — always recommended on production systems:**
```bash
./chown_throttled.sh -u deploy:deploy -d /opt/app -n
```

**Maximum throughput during maintenance window:**
```bash
./chown_throttled.sh -u app:app -d /data -w 16 -b 1000 -s 0 -p 0 -i 1
```

**Peak hours — backed off, slow and steady:**
```bash
./chown_throttled.sh -u app:app -d /data -w 2 -b 200 -s 250 -p 15 -i 3
```

---

## Parallelism Model

There are two independent layers of parallelism, both configurable:

### Layer 1 — Worker parallelism within a directory (`-w`)

`xargs -P WORKERS` dispatches batches of `BATCH_SIZE` paths to `WORKERS` concurrent `chown` processes simultaneously. Since `xargs` feeds each worker a distinct batch from the stream, there is no file overlap and no coordination needed between workers.

```
find output stream
        │
        ▼
  ┌─────────────────────────────────┐
  │         xargs -P 4              │
  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ │
  │  │chown │ │chown │ │chown │ │chown │ │  ← 4 concurrent workers
  │  │batch1│ │batch2│ │batch3│ │batch4│ │
  │  └──────┘ └──────┘ └──────┘ └──────┘ │
  └─────────────────────────────────┘
```

### Layer 2 — Directory parallelism (`-D`)

With `-D`, each target directory is launched as a background job and all directories are processed simultaneously. Each directory job has its own `find` stream and its own `xargs -P WORKERS` pool.

```
  /data/a ──► [find | xargs -P 4] ──► chown workers
  /data/b ──► [find | xargs -P 4] ──► chown workers   (all running at once)
  /data/c ──► [find | xargs -P 4] ──► chown workers
```

Results from each directory job are written to temp files and aggregated into the final summary after all jobs complete.

### Choosing the right worker count

The optimal worker count depends on your storage type:

| Storage | Recommended `-w` | Reason |
|---|---|---|
| NVMe SSD | `8`–`16` | High IOPS, parallelism pays off |
| SATA SSD | `4`–`8` | Good IOPS, diminishing returns above 8 |
| HDD / RAID spinning | `2`–`4` | Sequential access is faster; too many workers causes seek thrash |
| NFS / network storage | `2`–`4` | Latency-bound; more workers increase server load |

A reasonable starting point is `nproc` (the default), then tune based on observed `iowait` in `top` or `iostat`.

---

## Priority Tuning Reference

### CPU Priority (`-p`)

| Value | Effect |
|---|---|
| `0` | Normal priority |
| `10` | Default — mild background behavior |
| `19` | Lowest — only runs when CPU is otherwise idle |

### I/O Priority (`-i`)

| Class | Value | Effect |
|---|---|---|
| Realtime | `1` | Highest I/O priority — preempts other processes |
| Best-effort | `2` | Default — scheduled fairly alongside others |
| Idle | `3` | Only accesses disk when nothing else needs it |

### Throttle and Priority Presets

| Scenario | Flags |
|---|---|
| Maintenance window, no load | `-w auto -p 0 -i 1 -s 0` |
| Low-traffic period | `-w 4 -p 5 -i 2 -s 10` |
| Default / moderate load | `-w auto -p 10 -i 2 -s 50` |
| Peak hours, high-throughput | `-w 2 -p 15 -i 3 -s 200` |
| Maximum yield, near-zero impact | `-w 1 -p 19 -i 3 -b 100 -s 500` |

---

## How It Works

1. **Validation** — confirms the target user and group exist on the system and all directories are accessible before any work begins.

2. **Batch executor** — a small helper shell script is written to a temp directory. `xargs` calls this script once per batch, passing the batch of paths as arguments. It handles the `nice`/`ionice` wrapping, the actual `chown`, and the per-worker sleep throttle.

3. **Pre-scan** — for each directory, `find` counts total items and already-correctly-owned items at lowest priority (`nice -n 19`) and reports the delta.

4. **Filtered traversal** — `find` uses `-user`/`-group` predicates to emit only paths that actually need changing. Correctly owned files never leave `find`.

5. **Parallel batch execution** — paths stream through a pipe into `xargs -0 -n BATCH_SIZE -P WORKERS`. `xargs` distributes batches across up to `WORKERS` concurrent `chown` invocations. Each worker sleeps independently after its batch, so workers don't synchronize their disk pressure.

6. **Directory parallelism (optional)** — with `-D`, each directory is launched as a background process. All directories run their own `find | xargs` pipeline simultaneously.

7. **Aggregation** — each directory worker writes its found/skipped counts to a temp file. After all workers complete, the main process reads and sums them for the final report.

8. **Cleanup** — the temp directory (batch script + count files) is removed automatically on exit via a `trap`, including on `Ctrl+C` or error.

---

## Sample Output

```
[2025-06-12 14:22:01] [12345] ========================================
[2025-06-12 14:22:01] [12345]   chown_throttled.sh
[2025-06-12 14:22:01] [12345] ========================================
[2025-06-12 14:22:01] [12345]   Owner        : www-data:www-data
[2025-06-12 14:22:01] [12345]   Directories  : /var/www /srv/uploads
[2025-06-12 14:22:01] [12345]   Batch size   : 500 items/worker/call
[2025-06-12 14:22:01] [12345]   Workers      : 8 (auto-detected)
[2025-06-12 14:22:01] [12345]   Parallel dirs: false
[2025-06-12 14:22:01] [12345]   Throttle     : 50ms per worker between batches
[2025-06-12 14:22:01] [12345]   CPU nice     : 10 (0=normal, 19=lowest)
[2025-06-12 14:22:01] [12345]   IO class     : 2 (1=rt, 2=best-effort, 3=idle)
[2025-06-12 14:22:01] [12345]   Find type    : a (f=files, d=dirs, a=all)
[2025-06-12 14:22:01] [12345]   Skip owned   : YES
[2025-06-12 14:22:01] [12345]   Dry run      : false
[2025-06-12 14:22:01] [12345] ========================================
[2025-06-12 14:22:01] [12345] --- Directory: /var/www (workers: 8) ---
[2025-06-12 14:22:02] [12345]   [/var/www] Total: 18432 | Already owned: 16105 | To process: 2327
[2025-06-12 14:22:04] [12345]   [/var/www] Status: OK
[2025-06-12 14:22:04] [12345] --- Directory: /srv/uploads (workers: 8) ---
[2025-06-12 14:22:05] [12345]   [/srv/uploads] Total: 4210 | Already owned: 4210 | To process: 0
[2025-06-12 14:22:05] [12345]   [/srv/uploads] Nothing to do -- all items already owned by www-data:www-data
[2025-06-12 14:22:05] [12345] ========================================
[2025-06-12 14:22:05] [12345]   Run complete
[2025-06-12 14:22:05] [12345]   Total items found   : 22642
[2025-06-12 14:22:05] [12345]   Skipped (owned)     : 20315
[2025-06-12 14:22:05] [12345]   Processed           : 2327
[2025-06-12 14:22:05] [12345]   Workers used        : 8
[2025-06-12 14:22:05] [12345] ========================================
```

---

## Cron / Scheduled Use

```cron
# Run every 15 minutes, 4 workers, backed-off priority
*/15 * * * * /usr/local/bin/chown_throttled -u www-data:www-data -d /var/www -w 4 -p 10 -i 3 -s 100 >> /var/log/chown_throttled.log 2>&1
```

Pair with `logrotate` to prevent unbounded log growth.

---

## Notes

- The script must be run as `root` or a user with permission to `chown` the target files.
- With `-D`, the effective total worker count is `WORKERS × number of directories`. On a 4-core system running 3 directories with `-w 4`, up to 12 concurrent `chown` processes may be active. Reduce `-w` accordingly when using `-D` on resource-constrained systems.
- `ionice` is silently skipped if not available; `nice` is always applied.
- The temp directory in `/tmp` is automatically removed on exit, including on `Ctrl+C` or error.
- Per-worker throttle (`-s`) is independent per worker — with 8 workers each sleeping 50ms, the aggregate throughput is not reduced proportionally; workers sleep in parallel, not sequentially.

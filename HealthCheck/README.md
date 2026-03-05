# system_health_check.sh

**Version:** 2.1.0  
**Compatibility:** Any Linux distro with bash 4.2+ (Debian/Ubuntu, RHEL/CentOS/Fedora, Arch, Raspberry Pi OS, etc.)

A single-file bash script that performs a comprehensive system health check and simultaneously exports every measured value to a **CSV** (for trend analysis) and a **JSON snapshot** (for tooling integration). Run it on a schedule and pipe the CSV into pandas, Grafana, Excel, or gnuplot to watch metrics evolve over time.

---

## Features at a Glance

| Section | What's checked |
|---|---|
| OS & Kernel | OS name, kernel version, architecture, uptime, pending reboot |
| CPU & Load | Load averages, per-core count, frequency, governor, steal time, user/sys/idle/iowait split, context switches |
| Memory & Swap | RAM total/available/used, buffers, cache, slab, swap pressure |
| Disk Space | Per-mount usage %, free/used/total MB, inode usage % |
| Disk I/O | Per-device reads/writes, KB transferred, ms in I/O (from `/proc/diskstats`) |
| Disk Health | S.M.A.R.T. overall status, reallocated/pending sectors, power-on hours, drive temp, mdadm RAID degradation |
| Network Interfaces | Per-interface state, link speed, RX/TX MB & packets, errors, drops (reads from `/sys/class/net/`) |
| Socket States | All 11 TCP states, UDP (total/UNCONN/ESTAB), Unix domain sockets, listening ports, top talkers |
| Processes | Top 10 by CPU & memory, total process/thread count, zombie & D-state detection |
| Systemd | Failed unit count and names |
| System Logs | Recent journal error count, OOM kill events |
| Security | SSH `PermitRootLogin` & `PasswordAuthentication`, failed auth attempts, firewall status (ufw/firewalld/iptables), SELinux/AppArmor |
| Time Sync | NTP sync status (timedatectl/chrony), clock offset, timezone |
| Temperature | Per-sensor readings via `lm-sensors` or `/sys/class/thermal` (ideal for Raspberry Pi, Jetson, etc.) |
| File Descriptors | System-wide FD used/max/%, top 5 FD consumers by process |

---

## Output Files

Every run produces three outputs:

```
/var/log/sys_health/
├── report_20240315_143022.log      # Full human-readable run log (one per run)
├── metrics.csv                     # Appended CSV — one header row + one data row per run
└── snapshot_20240315_143022.json   # JSON snapshot of all metrics (one per run)
```

### metrics.csv

The CSV file is the primary file for trend analysis. The header row is written once on the first run; every subsequent run appends a single data row. All ~70+ metric columns are always present, including all TCP socket states — even when their value is zero — so column counts never vary between runs.

```
timestamp_epoch,hostname,uptime_sec,load_1m,mem_used_pct,disk_root_used_pct,tcp_established,...
1710505822,webserver01,864000,0.42,61.3,44,...
1710509422,webserver01,867600,0.38,62.1,44,...
```

### snapshot_*.json

Each run produces a complete JSON object with all metrics. Numeric values are stored as numbers; string values as quoted strings.

```json
{
  "timestamp_epoch": 1710505822,
  "timestamp_human": "2024-03-15 14:30:22 UTC",
  "hostname": "webserver01",
  "uptime_sec": 864000,
  "load_1m": 0.42,
  "mem_used_pct": 61.3,
  "tcp_established": 42,
  "tcp_close_wait": 0,
  "tcp_time_wait": 17,
  ...
}
```

---

## Quick Start

```bash
# Clone or copy the script
chmod +x system_health_check.sh

# Run as root (required for S.M.A.R.T., shadow file checks, and some sysfs reads)
sudo ./system_health_check.sh

# Output files will be in /var/log/sys_health/ by default
ls /var/log/sys_health/
```

---

## Scheduled Execution (Recommended)

### cron — run every 5 minutes

```bash
sudo crontab -e
```
```
*/5 * * * * /opt/scripts/system_health_check.sh >> /dev/null 2>&1
```

### systemd timer — more precise and gets journal integration

Create `/etc/systemd/system/sys-health.service`:
```ini
[Unit]
Description=System Health Check

[Service]
Type=oneshot
ExecStart=/opt/scripts/system_health_check.sh
```

Create `/etc/systemd/system/sys-health.timer`:
```ini
[Unit]
Description=Run system health check every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=10s

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now sys-health.timer
sudo systemctl list-timers sys-health.timer
```

---

## Configuration

All settings are controlled via environment variables — no need to edit the script.

### Paths

| Variable | Default | Description |
|---|---|---|
| `METRICS_DIR` | `/var/log/sys_health` | Directory for all output files |
| `LOG_FILE` | `$METRICS_DIR/report_YYYYMMDD_HHMMSS.log` | Human-readable log path |
| `METRICS_CSV` | `$METRICS_DIR/metrics.csv` | Appended CSV path |
| `METRICS_JSON` | `$METRICS_DIR/snapshot_YYYYMMDD_HHMMSS.json` | JSON snapshot path |

### Thresholds

| Variable | Default | Meaning |
|---|---|---|
| `DISK_WARN` | `80` | Disk usage % that triggers a warning |
| `DISK_CRIT` | `90` | Disk usage % that triggers a critical |
| `MEM_WARN` | `80` | RAM usage % warning threshold |
| `MEM_CRIT` | `95` | RAM usage % critical threshold |
| `SWAP_WARN` | `50` | Swap usage % warning threshold |
| `SWAP_CRIT` | `80` | Swap usage % critical threshold |
| `LOAD_WARN` | `2` | Load average multiplier × CPU count for warning |
| `LOAD_CRIT` | `4` | Load average multiplier × CPU count for critical |
| `INODE_WARN` | `80` | Inode usage % warning threshold |
| `INODE_CRIT` | `90` | Inode usage % critical threshold |
| `CLOSE_WAIT_WARN` | `100` | CLOSE_WAIT socket count that triggers a critical |
| `TIME_WAIT_WARN` | `500` | TIME_WAIT socket count that triggers a warning |

### Example: override thresholds at runtime

```bash
DISK_WARN=70 DISK_CRIT=85 MEM_WARN=75 sudo ./system_health_check.sh

# Write outputs to a custom directory
METRICS_DIR=/data/monitoring sudo ./system_health_check.sh

# Combine multiple overrides
METRICS_DIR=/data/monitoring CLOSE_WAIT_WARN=50 TIME_WAIT_WARN=200 \
    sudo ./system_health_check.sh
```

---

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | HEALTHY — all checks passed |
| `1` | WARNING — one or more warning-level findings |
| `2` | CRITICAL — one or more critical-level findings |

The exit code makes the script directly usable in monitoring pipelines, CI checks, or any orchestration that inspects `$?`.

```bash
sudo ./system_health_check.sh
case $? in
    0) echo "All good" ;;
    1) echo "Warnings — review log" ;;
    2) echo "CRITICAL — page on-call" ;;
esac
```

---

## Optional Dependencies

The script works without any of these, but installs them for full coverage:

| Package | What it enables |
|---|---|
| `smartmontools` | S.M.A.R.T. disk health checks (`smartctl`) |
| `lm-sensors` | Hardware temperature readings (`sensors`) |
| `iproute2` | Network interface details (`ip`, `ss`) |
| `mdadm` | Software RAID degradation checks |
| `chrony` | NTP clock offset metrics (alternative to `systemd-timesyncd`) |

```bash
# Debian / Ubuntu
sudo apt install smartmontools lm-sensors iproute2 mdadm

# RHEL / CentOS / Fedora
sudo dnf install smartmontools lm_sensors iproute mdadm

# Arch
sudo pacman -S smartmontools lm_sensors iproute2 mdadm
```

---

## Metric Reference

### Identity & Timing

| Metric | Type | Description |
|---|---|---|
| `timestamp_epoch` | int | Unix epoch of this run |
| `timestamp_human` | string | Human-readable run timestamp |
| `hostname` | string | System hostname |

### OS & Kernel

| Metric | Type | Description |
|---|---|---|
| `uptime_sec` | int | Seconds since last boot |
| `kernel` | string | Running kernel version |
| `os` | string | OS pretty name |
| `arch` | string | CPU architecture |
| `reboot_required` | bool (0/1) | Pending reboot flag (Debian/Ubuntu) |

### CPU

| Metric | Type | Description |
|---|---|---|
| `cpu_count` | int | Logical CPU count |
| `load_1m` / `load_5m` / `load_15m` | float | Load averages |
| `cpu_freq_mhz` | int | Current frequency of core 0 (if available) |
| `cpu_governor` | string | Scaling governor (if available) |
| `cpu_steal_pct` | float | CPU steal time % (hypervisor overhead) |
| `cpu_user_pct` | float | Cumulative user-space CPU % |
| `cpu_sys_pct` | float | Cumulative kernel CPU % |
| `cpu_idle_pct` | float | Cumulative idle CPU % |
| `cpu_iowait_pct` | float | Cumulative I/O wait % |
| `cpu_context_switches_total` | int | Total context switches since boot |
| `cpu_interrupts_total` | int | Total interrupts since boot |

### Memory

| Metric | Type | Description |
|---|---|---|
| `mem_total_mb` | int | Total installed RAM (MB) |
| `mem_avail_mb` | int | Available RAM (free + reclaimable, MB) |
| `mem_used_mb` | int | Used RAM (MB) |
| `mem_used_pct` | float | RAM utilisation % |
| `mem_buffers_mb` | int | Kernel I/O buffers (MB) |
| `mem_cached_mb` | int | Page cache (MB) |
| `mem_slab_mb` | int | Kernel slab allocator (MB) |
| `swap_total_mb` | int | Total swap (MB) |
| `swap_used_mb` | int | Used swap (MB) |
| `swap_used_pct` | float | Swap utilisation % |

### Disk Space (per mount)

Keys use the mount point with `/` replaced by `_`. The root filesystem becomes `root`.

| Metric | Type | Description |
|---|---|---|
| `disk_<mount>_used_pct` | int | Disk usage % |
| `disk_<mount>_avail_mb` | int | Free space (MB) |
| `disk_<mount>_used_mb` | int | Used space (MB) |
| `disk_<mount>_total_mb` | int | Total size (MB) |
| `inode_<mount>_used_pct` | int | Inode usage % |
| `disk_crit_count` | int | Number of filesystems at critical level |
| `disk_warn_count` | int | Number of filesystems at warning level |

### Disk I/O (per physical device)

Keys use the device name (e.g. `sda`, `nvme0n1`).

| Metric | Type | Description |
|---|---|---|
| `io_<dev>_reads_total` | int | Total read operations since boot |
| `io_<dev>_writes_total` | int | Total write operations since boot |
| `io_<dev>_read_kb` | int | Total KB read since boot |
| `io_<dev>_write_kb` | int | Total KB written since boot |
| `io_<dev>_io_ms` | int | Total ms spent in I/O since boot |

### Disk Health (per physical device)

| Metric | Type | Description |
|---|---|---|
| `smart_<dev>_status` | string | SMART overall health (PASSED / FAILED / unsupported) |
| `smart_<dev>_reallocated` | int | Reallocated sector count |
| `smart_<dev>_pending` | int | Current pending sector count |
| `smart_<dev>_uncorrectable` | int | Offline uncorrectable sectors |
| `smart_<dev>_power_on_hours` | int | Drive power-on hours |
| `smart_<dev>_temp_c` | float | Drive temperature (°C) |
| `smart_fail_count` | int | Disks with a non-PASSED SMART status |
| `raid_degraded_count` | int | Degraded mdadm RAID arrays |

### Network (per interface, loopback excluded)

Keys use the interface name with `-` and `.` replaced by `_`.

| Metric | Type | Description |
|---|---|---|
| `net_<iface>_state` | string | Operstate (up / down / unknown) |
| `net_<iface>_speed_mbps` | int | Link speed in Mbps (if available) |
| `net_<iface>_rx_mb` | int | Total MB received since boot |
| `net_<iface>_tx_mb` | int | Total MB transmitted since boot |
| `net_<iface>_rx_pkts` | int | Total RX packets since boot |
| `net_<iface>_tx_pkts` | int | Total TX packets since boot |
| `net_<iface>_rx_err` | int | RX error count |
| `net_<iface>_tx_err` | int | TX error count |
| `net_<iface>_rx_drop` | int | RX dropped packet count |
| `net_<iface>_tx_drop` | int | TX dropped packet count |
| `net_iface_count` | int | Total non-loopback interfaces found |
| `net_iface_down_count` | int | Interfaces in DOWN state |

### Sockets

All TCP state metrics are always present (pre-seeded to 0) so CSV column counts never vary.

| Metric | Type | Description |
|---|---|---|
| `tcp_listen` | int | Listening sockets |
| `tcp_established` | int | Active established connections |
| `tcp_close_wait` | int | CLOSE_WAIT — app hasn't closed socket; watch for socket leaks |
| `tcp_time_wait` | int | TIME_WAIT — connections cooling down; high values = high churn |
| `tcp_syn_sent` | int | Outbound connections pending completion |
| `tcp_syn_recv` | int | Inbound connections in handshake |
| `tcp_fin_wait_1` | int | Connections in first FIN stage |
| `tcp_fin_wait_2` | int | Connections waiting for remote FIN |
| `tcp_last_ack` | int | Waiting for final ACK from remote |
| `tcp_closing` | int | Simultaneous close in progress |
| `tcp_close` | int | Closed sockets still in table |
| `tcp_total` | int | Sum of all TCP table entries |
| `udp_total` | int | Total UDP sockets |
| `udp_unconn` | int | Unconnected UDP sockets |
| `udp_estab` | int | Connected UDP sockets |
| `unix_socket_total` | int | Unix domain sockets |

### Processes

| Metric | Type | Description |
|---|---|---|
| `proc_total` | int | Total running processes |
| `proc_threads` | int | Total threads across all processes |
| `proc_zombie` | int | Zombie processes |
| `proc_dstate` | int | Processes in uninterruptible sleep (D-state, possible I/O hang) |

### Services & Logs

| Metric | Type | Description |
|---|---|---|
| `systemd_failed_units` | int | Number of failed systemd units |
| `journal_error_count` | int | Recent priority-error journal entries |
| `oom_kill_count` | int | OOM kill events since boot |

### Security

| Metric | Type | Description |
|---|---|---|
| `ssh_permit_root_login` | string | Value of `PermitRootLogin` in sshd_config |
| `ssh_password_authentication` | string | Value of `PasswordAuthentication` in sshd_config |
| `ssh_failed_auth_total` | int | Total failed SSH password attempts in auth log |
| `firewall_type` | string | Detected firewall: ufw / firewalld / iptables |
| `firewall_active` | bool (0/1) | Whether firewall is active |

### Time Sync

| Metric | Type | Description |
|---|---|---|
| `ntp_synced` | bool (0/1) | 1 if NTP is synchronised |
| `timezone` | string | System timezone |
| `chrony_offset_sec` | float | Chrony clock offset in seconds (if using chrony) |

### Temperature

Indexed by sensor order (0, 1, 2, …).

| Metric | Type | Description |
|---|---|---|
| `temp_<N>_label` | string | Sensor name or thermal zone name |
| `temp_<N>_c` | float | Temperature in °C |
| `temp_crit_count` | int | Sensors above 85°C |
| `temp_warn_count` | int | Sensors between 70°C and 85°C |

### File Descriptors

| Metric | Type | Description |
|---|---|---|
| `fd_used` | int | Open file descriptors (system-wide) |
| `fd_max` | int | System FD limit |
| `fd_used_pct` | float | FD utilisation % |

### Run Results

| Metric | Type | Description |
|---|---|---|
| `result_checks_passed` | int | Checks that returned OK |
| `result_warnings` | int | Warning-level findings this run |
| `result_criticals` | int | Critical-level findings this run |
| `result_total_checks` | int | Total checks performed |
| `result_metric_count` | int | Total metrics recorded this run |
| `result_overall_status` | string | HEALTHY / WARNING / CRITICAL |

---

## Trend Analysis Examples

### Python / pandas

```python
import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_csv('/var/log/sys_health/metrics.csv')
df['time'] = pd.to_datetime(df['timestamp_epoch'], unit='s')
df = df.set_index('time')

# Memory and swap pressure over time
df[['mem_used_pct', 'swap_used_pct']].plot(title='Memory Pressure')
plt.tight_layout(); plt.savefig('memory_trend.png')

# TCP socket health — spot CLOSE_WAIT leaks building up
df[['tcp_established', 'tcp_close_wait', 'tcp_time_wait']].plot(title='TCP Sockets')
plt.tight_layout(); plt.savefig('tcp_trend.png')

# CPU breakdown
df[['cpu_user_pct', 'cpu_sys_pct', 'cpu_iowait_pct', 'cpu_idle_pct']].plot.area(
    title='CPU Utilisation', alpha=0.6)
plt.tight_layout(); plt.savefig('cpu_trend.png')

# Disk space remaining on root
df['disk_root_avail_mb'].plot(title='Root FS Free Space (MB)')
plt.tight_layout(); plt.savefig('disk_trend.png')

# Find runs where CLOSE_WAIT exceeded threshold
leaks = df[df['tcp_close_wait'] > 10][['tcp_close_wait', 'tcp_established']]
print(leaks)
```

### Shell — quick check for degradation trends

```bash
# Show the last 20 memory usage readings
awk -F, 'NR==1{for(i=1;i<=NF;i++) if($i=="mem_used_pct") col=i}
         NR>1{print $1, $col}' /var/log/sys_health/metrics.csv | tail -20

# Alert if any run had criticals
awk -F, 'NR==1{for(i=1;i<=NF;i++) if($i=="result_criticals") col=i}
         NR>1 && $col>0{print "CRIT at", $1, "—", $col, "critical(s)"}' \
    /var/log/sys_health/metrics.csv
```

### jq — query a JSON snapshot

```bash
# Show all socket state counts from the latest snapshot
ls -t /var/log/sys_health/snapshot_*.json | head -1 \
    | xargs jq '{tcp_established, tcp_close_wait, tcp_time_wait, udp_total}'

# Show disk usage across all mounts
ls -t /var/log/sys_health/snapshot_*.json | head -1 \
    | xargs jq 'to_entries | map(select(.key | startswith("disk_") and endswith("_used_pct"))) | from_entries'
```

---

## Cleaning Up Old Files

Each run creates a new log and JSON file. Add a cron job to rotate them:

```bash
# Keep 30 days of logs and JSON snapshots
0 3 * * * find /var/log/sys_health -name 'report_*.log' -mtime +30 -delete
0 3 * * * find /var/log/sys_health -name 'snapshot_*.json' -mtime +30 -delete
```

The `metrics.csv` file grows by one row per run and is never auto-deleted — manage it manually or truncate periodically if disk space is a concern.

---

## Troubleshooting

**CSV or JSON not being created**
Ensure the script is run with sufficient permissions to write to `METRICS_DIR`. The default `/var/log/sys_health/` requires root or a user with write access to `/var/log/`.

```bash
sudo mkdir -p /var/log/sys_health
sudo chown $(whoami) /var/log/sys_health
./system_health_check.sh
```

**SMART checks show `no_permission`**
S.M.A.R.T. requires root access. Run with `sudo`.

**Temperature section shows "No sensors found"**
Install `lm-sensors` and run `sudo sensors-detect` once to configure it. On Raspberry Pi and Jetson devices, `/sys/class/thermal` is used automatically as a fallback — no extra packages needed.

**Network section shows "No non-loopback interfaces found"**
This occurs in containers or restricted environments where `/sys/class/net/` is not fully exposed. On bare-metal and standard VMs it will enumerate all interfaces.

**`vmstat` errors in output**
Some containerised environments restrict `vmstat`. The script handles this gracefully — CPU steal will be reported as 0 and execution continues normally.

---

## Design Notes

- **No `set -e`** — a monitoring script must survive individual tool failures (`smartctl`, `sensors`, `vmstat`, etc.). All errors are handled explicitly with `|| true` guards and the `safe()` helper.
- **Metric sanitisation** — all values are stripped of newlines and trimmed before storage to prevent malformed JSON or broken CSV rows.
- **Pre-seeded socket states** — all 11 TCP socket states are initialised to `0` before the socket scan so CSV columns are always consistent, regardless of whether any connections exist in a given state.
- **No external dependencies for core operation** — the script reads from `/proc`, `/sys`, and standard utilities (`ps`, `df`, `ip`). Optional tools like `smartctl`, `sensors`, and `ss` add extra data when present but are never required.

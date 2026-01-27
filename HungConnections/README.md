# Hung Connection Killer

A utility for detecting and terminating hung network connections on Unix-based systems. Available in both Python and Bash versions for maximum compatibility across different infrastructure environments.

## Overview

Network connections can become "hung" or stuck in various states due to application bugs, network issues, or improper socket handling. These orphaned connections consume system resources and can eventually exhaust available file descriptors or ports. This tool identifies such connections and safely terminates them while leaving healthy connections untouched.

### What Qualifies as a "Hung" Connection?

| State | Description | Default Timeout |
|-------|-------------|-----------------|
| `CLOSE_WAIT` | Remote end closed, but local application hasn't. Often indicates app bug. | 60s |
| `FIN_WAIT1` | Local end closed, waiting for ACK. Stuck here indicates network issues. | 120s |
| `FIN_WAIT2` | Received ACK for FIN, waiting for remote FIN. | 120s |
| `CLOSING` | Both sides closing simultaneously, waiting for ACK. | 60s |
| `LAST_ACK` | Waiting for final ACK after sending FIN. | 60s |
| `TIME_WAIT` | Connection closed, waiting before reuse. Normally kernel-managed. | 120s |

### Safe States (Never Touched)

- `ESTABLISHED` - Active, healthy connections
- `LISTEN` - Server sockets waiting for connections
- `SYN_SENT` / `SYN_RECV` - Connection establishment in progress

## Requirements

### Python Version
- Python 3.6+
- Root/sudo privileges (for termination)
- Linux with `ss` command (preferred) or `netstat`

### Bash Version
- Bash 4.0+
- Root/sudo privileges (for termination)
- `ss` command (preferred) or `netstat`

## Installation

```bash
# Download both scripts
curl -O https://example.com/hung_connection_killer.py
curl -O https://example.com/hung_connection_killer.sh

# Make executable
chmod +x hung_connection_killer.py hung_connection_killer.sh

# Optional: Move to system path
sudo mv hung_connection_killer.py /usr/local/bin/
sudo mv hung_connection_killer.sh /usr/local/bin/
```

## Usage

Both scripts share identical command-line interfaces.

### Basic Usage

```bash
# ALWAYS start with a dry run to see what would be terminated
sudo ./hung_connection_killer.py --dry-run
sudo ./hung_connection_killer.sh --dry-run

# Live mode - actually terminate hung connections
sudo ./hung_connection_killer.py --live
sudo ./hung_connection_killer.sh --live
```

### Command Line Options

```
Mode (required - choose one):
  -n, --dry-run              Show what would be done without making changes (safe)
  -l, --live                 Actually terminate hung connections (requires root)

Timeout Configuration:
  --close-wait-timeout SEC   Seconds before CLOSE_WAIT is considered hung (default: 60)
  --fin-wait-timeout SEC     Seconds before FIN_WAIT states are considered hung (default: 120)
  --time-wait-timeout SEC    Seconds before TIME_WAIT is considered hung (default: 120)

Filtering:
  --exclude-ports PORTS      Ports to exclude from termination (default: 22)
  --include-ports PORTS      Only check these ports (default: all)
  --exclude-processes PROCS  Process names to exclude from termination

Logging:
  --log-file FILE            Write logs to this file
  -v, --verbose              Enable verbose/debug output

Other:
  -h, --help                 Show help message
```

### Examples

```bash
# Dry run with verbose output
sudo ./hung_connection_killer.py --dry-run -v

# Live mode with custom CLOSE_WAIT timeout (30 seconds)
sudo ./hung_connection_killer.py --live --close-wait-timeout 30

# Exclude database ports from termination
# Python version:
sudo ./hung_connection_killer.py --live --exclude-ports 22 3306 5432 6379

# Bash version (space-separated string):
sudo ./hung_connection_killer.sh --live --exclude-ports "22 3306 5432 6379"

# Only monitor web traffic ports
# Python version:
sudo ./hung_connection_killer.py --live --include-ports 80 443 8080

# Bash version:
sudo ./hung_connection_killer.sh --live --include-ports "80 443 8080"

# Exclude specific application processes
# Python version:
sudo ./hung_connection_killer.py --live --exclude-processes nginx postgres

# Bash version:
sudo ./hung_connection_killer.sh --live --exclude-processes "nginx postgres"

# Full logging to file
sudo ./hung_connection_killer.py --live -v --log-file /var/log/hung_connections.log
```

## Safety Features

### Protected Processes

The following processes are **never** terminated, regardless of connection state:

- `sshd` - SSH daemon (prevents lockout)
- `systemd` / `init` - System initialization
- `kernel` / `kthreadd` - Kernel threads
- `containerd` / `dockerd` - Container runtimes
- `kubelet` / `k3s` - Kubernetes components

### Default Exclusions

- **Port 22 (SSH)** is excluded by default to prevent remote access disruption
- Connections without a PID are skipped (can't be terminated safely)
- Safe states (`ESTABLISHED`, `LISTEN`, etc.) are never touched

### Termination Methods

The scripts attempt termination in order of preference:

1. **`ss -K`** - Kernel socket termination (cleanest, no process impact)
2. **Process SIGTERM** - Graceful process termination
3. **Process SIGKILL** - Forced termination (last resort, only for non-protected processes)

## Automated Execution

### Cron Job

Run every 5 minutes:

```bash
# Edit crontab
sudo crontab -e

# Add line:
*/5 * * * * /usr/local/bin/hung_connection_killer.py --live --log-file /var/log/hung_connections.log 2>&1
```

### Systemd Timer

Create `/etc/systemd/system/hung-connection-killer.service`:

```ini
[Unit]
Description=Hung Connection Killer
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hung_connection_killer.py --live --log-file /var/log/hung_connections.log
```

Create `/etc/systemd/system/hung-connection-killer.timer`:

```ini
[Unit]
Description=Run Hung Connection Killer every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now hung-connection-killer.timer
```

## Output Examples

### Dry Run Output

```
2024-01-15 10:30:45 - INFO - ============================================================
2024-01-15 10:30:45 - INFO - Hung Connection Killer - DRY RUN
2024-01-15 10:30:45 - INFO - ============================================================
2024-01-15 10:30:45 - INFO - Found 47 total connections
2024-01-15 10:30:45 - WARN - Hung connection detected: tcp CLOSE_WAIT 10.0.0.5:8080 -> 10.0.0.100:52431 (PID: 1234, Process: myapp)
2024-01-15 10:30:45 - WARN -   Reason: CLOSE_WAIT without active timer (likely app not closing socket)
2024-01-15 10:30:45 - INFO - [DRY RUN] Would terminate: tcp CLOSE_WAIT 10.0.0.5:8080 -> 10.0.0.100:52431 (PID: 1234, Process: myapp)
2024-01-15 10:30:45 - INFO - ------------------------------------------------------------
2024-01-15 10:30:45 - INFO - Summary:
2024-01-15 10:30:45 - INFO -   Total connections scanned: 47
2024-01-15 10:30:45 - INFO -   Hung connections found: 1
2024-01-15 10:30:45 - INFO -   Connections skipped: 12
2024-01-15 10:30:45 - INFO -   Connections terminated: 1
2024-01-15 10:30:45 - INFO -   Failed terminations: 0
2024-01-15 10:30:45 - INFO - ============================================================
```

## Troubleshooting

### "Permission denied" errors

Run with `sudo` or as root. Socket termination requires elevated privileges.

### "ss command not found"

Install iproute2:
```bash
# Debian/Ubuntu
sudo apt install iproute2

# RHEL/CentOS
sudo yum install iproute

# Alpine
sudo apk add iproute2
```

### "netstat command not found"

Install net-tools (legacy):
```bash
# Debian/Ubuntu
sudo apt install net-tools

# RHEL/CentOS
sudo yum install net-tools
```

### No connections being detected

- Verify you're running as root: `sudo ./hung_connection_killer.py --dry-run`
- Check that `ss` or `netstat` works: `ss -tanp` or `netstat -tanp`
- Ensure there are actually TCP connections: `ss -tan`

### Connections not being terminated

- Check if the process is in the protected list
- Check if the port is excluded (22 by default)
- Run with `-v` for verbose output to see skip reasons

## Version Comparison

| Feature | Python | Bash |
|---------|--------|------|
| Dependencies | Python 3.6+ | Bash 4.0+, coreutils |
| Timer parsing | Full float support | Integer seconds |
| Code structure | Object-oriented | Procedural |
| Best for | Complex environments | Minimal systems |
| File size | ~18 KB | ~12 KB |

**Recommendation:** Use the Python version where available for better timer precision. Use the Bash version on minimal systems, containers, or embedded devices where Python isn't installed.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (all hung connections terminated or none found) |
| 1 | Failure (some connections could not be terminated) |


## Updates

Enhancements being worked on:

- UDP connection monitoring
- Integration with monitoring systems (Prometheus metrics)
- Slack/Discord notifications for terminated connections
- Per-process timeout configuration

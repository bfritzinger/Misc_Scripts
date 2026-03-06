# linux_troubleshoot.sh

A comprehensive, interactive shell script for diagnosing and troubleshooting x86_64 Linux servers. Covers 15 diagnostic modules ranging from hardware inventory and network connection analysis to Kubernetes cluster health and security auditing — all from a single script with no external dependencies beyond standard Linux tooling.

---

## Requirements

| Requirement | Notes |
|---|---|
| **OS** | Any modern Linux distribution (Debian/Ubuntu, RHEL/CentOS/Rocky, SUSE, Arch, etc.) |
| **Architecture** | x86_64 |
| **Shell** | Bash 4.0+ |
| **Privileges** | Run as **root** (or via `sudo`) for full output. Most modules will still run unprivileged but will produce warnings where elevated access is required. |

### Optional Packages (enhance output)

The script gracefully degrades when optional tools are missing, but installing these gives richer results:

```
# Debian / Ubuntu
apt install -y lshw pciutils usbutils sysstat lm-sensors smartmontools \
               dmidecode net-tools iproute2 util-linux procps

# RHEL / Rocky / CentOS
yum install -y lshw pciutils usbutils sysstat lm_sensors smartmontools \
               dmidecode net-tools iproute procps-ng
```

---

## Configuration

Near the top of the script, four variables control DNS and connectivity test behavior. Edit them before running on any new network environment:

```bash
# Hostnames / IPs to resolve during DNS lookup tests (space-separated)
DNS_TEST_HOSTS="google.com cloudflare.com"

# IP address used for the reverse DNS (PTR) lookup test
DNS_REVERSE_IP="8.8.8.8"

# Hosts / IPs used for ping connectivity tests in the Network module
PING_TEST_HOSTS="8.8.8.8 1.1.1.1"

# Automatically include non-loopback /etc/hosts entries as additional DNS targets
DNS_INCLUDE_HOSTS_FILE="true"
```

### Open networks (internet access)
The defaults work as-is — public DNS and ping targets are reachable.

### Closed / air-gapped networks
Replace the public targets with internal hosts or IPs that are reachable on that network:

```bash
DNS_TEST_HOSTS="dc01.corp.local fileserver.corp.local 10.10.1.1"
DNS_REVERSE_IP="10.10.1.1"
PING_TEST_HOSTS="10.10.1.1 10.10.1.254"
DNS_INCLUDE_HOSTS_FILE="true"
```

### /etc/hosts integration

When `DNS_INCLUDE_HOSTS_FILE="true"` (the default), the script automatically parses `/etc/hosts` at runtime and appends any non-loopback, non-link-local hostnames to the DNS test target list. This means any static host entries already configured on the server — such as cluster nodes, internal services, or infrastructure hosts — are tested automatically without any manual configuration.

Loopback (`127.x.x.x`), IPv6 loopback (`::1`), and link-local (`fe80`) entries are always excluded.

To disable this behavior and test only the explicitly configured hosts:

```bash
DNS_INCLUDE_HOSTS_FILE="false"
```

---

## Installation

```bash
# Download / copy the script
chmod +x linux_troubleshoot.sh

# Run interactively (recommended)
sudo ./linux_troubleshoot.sh

# Run specific modules non-interactively
sudo ./linux_troubleshoot.sh 4 8 15

# Run all modules and save output
sudo ./linux_troubleshoot.sh A 2>&1 | tee server_report_$(date +%F).log
```

---

## Usage

### Interactive Mode

Running the script with no arguments launches an interactive menu:

```
  ╔══════════════════════════════════════════════════════╗
  ║         Linux Troubleshooting Toolkit                ║
  ║         2025-01-15 14:30:00                          ║
  ╚══════════════════════════════════════════════════════╝

   1  System Overview          9  Security
   2  CPU & Memory            10  Docker / Containers
   3  Disk & Filesystem       11  Kubernetes / k3s
   4  Network                 12  DNS Diagnostics
   5  Processes               13  Performance Profiling
   6  System Logs             14  Kernel & Boot
   7  Services & Systemd      15  Quick Health Summary
   8  Hardware

   A  Run ALL modules
   L  Toggle log to file
   Q  Quit
```

Select a number to run that module. Output pauses after each module so you can review results before continuing.

### Non-Interactive / CLI Mode

Pass module numbers (or `A` for all) as arguments to run without the menu — useful for scripting or automated collection:

```bash
# Run modules 2, 4, and 15
sudo ./linux_troubleshoot.sh 2 4 15

# Run everything, pipe to a file
sudo ./linux_troubleshoot.sh A > /tmp/full_report.txt 2>&1
```

### Log Toggle

From the interactive menu, press **`L`** to enable live logging. Output is written to `/tmp/troubleshoot_<timestamp>.log` while simultaneously displaying on screen via `tee`.

---

## Module Reference

### 1 · System Overview
General system identity and environment.
- OS release, kernel version, hostname
- Uptime, load average, `/proc/loadavg`
- Date, time, timezone (`timedatectl`)
- User limits (`ulimit -a`)
- Full environment variable listing

### 2 · CPU & Memory
Processor and memory utilization deep-dive.
- CPU model, core count, NUMA topology (`lscpu`)
- Per-core utilization snapshot (`mpstat`)
- Memory breakdown: total, free, available, buffers, cached, dirty (`/proc/meminfo`)
- Swap usage and swap devices
- Virtual memory stats (`vmstat`)
- Huge pages configuration
- Top 15 memory-consuming processes
- OOM killer history from `dmesg` / `journalctl`

### 3 · Disk & Filesystem
Storage health and utilization.
- Block device tree with filesystem type and mount point (`lsblk`)
- Disk usage per filesystem (`df -hT`)
- Inode exhaustion check (`df -i`)
- Active mounts and `/etc/fstab`
- Disk I/O statistics (`iostat -xz`)
- Large files scan (>100 MB)
- Open file handle count
- SMART health status per drive (`smartctl`)
- LVM physical volumes, volume groups, logical volumes
- Software RAID status (`/proc/mdstat`)

### 4 · Network
Full network stack inspection.
- Interface addresses and link state (`ip -br addr/link`)
- IPv4 and IPv6 routing tables
- ARP / neighbor table
- DNS resolver config (`/etc/resolv.conf`, `resolvectl`)
- All listening ports with owning process (`ss -tulpn`)
- Socket summary statistics (`ss -s`)
- **Connection state breakdown** — count per state (ESTABLISHED, CLOSE-WAIT, TIME-WAIT, SYN-SENT, FIN-WAIT-1/2, LAST-ACK, CLOSING)
- **Per-state detail** — local IP:port → remote IP:port + process name for every active state
- **Top remote IPs** by total connection count
- **Top remote IPs in CLOSE_WAIT** — useful for diagnosing socket leak sources
- **Connections per local port** — shows which services have the most active sessions
- iptables rules (INPUT, FORWARD, OUTPUT, NAT)
- nftables ruleset
- UFW status
- Network-related sysctl parameters
- Network namespaces
- Wireless interface info (if present)
- Connectivity tests — pings every host in `PING_TEST_HOSTS` and runs an HTTPS curl check
- Bridge interfaces
- Bonding / teaming status

### 5 · Processes
Process health and resource consumption.
- Top 30 CPU-consuming processes
- Full process tree (`pstree` / `ps auxf`)
- Zombie process detection and listing
- Stopped (`T`) and uninterruptible sleep (`D`) processes
- Per-process limits for PID 1
- Total thread count
- Guidance for `strace` and `lsof` on specific PIDs

### 6 · System Logs
Log analysis for errors and security events.
- Kernel errors and warnings (`dmesg --level=err,warn`)
- Recent journal errors (`journalctl -p err..emerg`)
- Current boot log tail
- SSH / auth log (failed logins, invalid users)
- `last` and `lastb` login history
- Cron log
- Log file sizes under `/var/log`

### 7 · Services & Systemd
Service and unit file health.
- All failed systemd units
- Currently running services
- Masked and disabled service files
- Active systemd timers with next trigger time
- Journal disk usage
- Init system identification
- Legacy `/etc/rc.local` contents (if present)

### 8 · Hardware
Physical hardware inventory and health — optimized for x86_64 servers.
- **Full hardware inventory** (`lshw -short`) — compact summary of all detected hardware
- **CPU details** (`lshw -class processor`) — socket, cores, capabilities
- **Memory / DIMM slots** (`lshw -class memory`) — installed DIMMs and memory banks
- **Storage controllers and disks** (`lshw -class storage -class disk`)
- **Network adapters** (`lshw -class network`) — driver, firmware version, capabilities
- PCI device listing (`lspci`)
- USB device listing (`lsusb`)
- System / BIOS info (`dmidecode -t system`)
- **DIMM detail** (`dmidecode -t memory`) — size, speed, type, manufacturer, part number per slot (root required)
- CPU temperature and thermal zones (`sensors` / `/sys/class/thermal`)
- NVIDIA GPU status (`nvidia-smi`)
- Power supply / battery info (`upower`)
- Loaded kernel modules
- IOMMU / hardware virtualization detection

### 9 · Security
Security posture and misconfiguration checks.
- Non-system user accounts
- sudo / wheel group membership
- sudoers file (root required)
- SUID / SGID binary scan
- World-writable file scan
- Externally exposed listening ports (excludes loopback)
- SSH daemon effective configuration (`sshd -T`)
- PAM module listing
- SELinux enforce status and full status
- AppArmor status
- auditd active rules
- fail2ban jail status
- Files in `/etc` modified within the last 7 days

### 10 · Docker / Containers
Container runtime health and resource usage.
- Docker version and server info
- Running and all containers
- Per-container resource usage snapshot (`docker stats --no-stream`)
- Image listing
- Volume listing
- Network listing
- Docker disk usage (`docker system df`)
- Guidance for pruning dangling resources
- Podman container listing (if present)
- cgroup v1 / v2 detection

### 11 · Kubernetes / k3s
Cluster-level health checks (works with both `kubectl` and `k3s kubectl`).
- Cluster endpoint info
- Node status and roles (`kubectl get nodes -o wide`)
- All pods across all namespaces
- Non-running / non-succeeded pods (failed, pending, crashlooping)
- Services and endpoints
- Deployments and DaemonSets
- PersistentVolumes and PersistentVolumeClaims
- Recent warning events sorted by timestamp
- ConfigMap and Secret counts
- ResourceQuotas
- Ingress resources
- k3s config check and service status
- Helm release listing (if Helm is installed)

### 12 · DNS Diagnostics
End-to-end DNS resolution checks driven by the top-of-script configuration variables.
- `/etc/resolv.conf` and `nsswitch.conf` hosts order
- `systemd-resolved` status and statistics
- **DNS target summary** — prints the configured hosts, whether `/etc/hosts` inclusion is enabled, and the full resolved target list
- **Forward lookups** for every host in `DNS_TEST_HOSTS` plus any non-loopback entries pulled from `/etc/hosts` (when `DNS_INCLUDE_HOSTS_FILE=true`), using `dig` / `nslookup` / `host` in that preference order
- **Reverse DNS** lookup against `DNS_REVERSE_IP`
- `/etc/hosts` contents

### 13 · Performance Profiling
Deeper performance metrics beyond the overview.
- Load average history (`sar -q`)
- CPU frequency scaling governor and current frequency
- Hardware interrupt counts (`/proc/interrupts`)
- Context switches and interrupt rates (`vmstat 1 3`)
- Kernel scheduler stats
- Page fault counts per process (minor and major)
- Network round-trip latency (5-ping test)
- Guidance for `traceroute` / `tracepath`

### 14 · Kernel & Boot
Kernel configuration and boot environment.
- Key sysctl parameters (kernel, VM, network)
- Kernel boot command line (`/proc/cmdline`)
- Loaded module count and full listing
- Module blacklist entries
- GRUB configuration
- Installed kernel images under `/boot`
- Core dump path and existing core files
- Kernel taint flags with interpretation note

### 15 · Quick Health Summary
Automated pass/fail checks — good starting point for any investigation.
- Load average vs. CPU count (warns if load > 2× CPU count)
- Memory utilization percentage (warns above 90%)
- Disk usage per mount (warns above 85%)
- Failed systemd unit count
- Zombie process count
- Swap utilization

---

## Output Conventions

| Symbol | Meaning |
|---|---|
| `✔` (green) | Check passed / command succeeded |
| `⚠` (yellow) | Warning, degraded result, or tool not found |
| `✖` (red) | Error |
| `$` (yellow prefix) | Command being executed |

---

## Notes

- The script uses `set -euo pipefail` but wraps all diagnostic commands through the `run()` helper which suppresses non-zero exits, so a single failing command will not abort the entire run.
- Commands that are not available on the system are skipped with a warning rather than failing.
- Destructive operations (pruning, killing processes, etc.) are never performed — the script is read-only and observational.
- For large environments, the **SUID scan** and **world-writable file scan** in module 9 traverse the entire filesystem and may take time on systems with many files.

---

## License

MIT — free to use, modify, and distribute.

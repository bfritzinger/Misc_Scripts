# Distribute Aliases

A bash script to deploy a consistent set of shell aliases across all nodes in your network. Perfect for home labs, Raspberry Pi clusters, or any environment where you want unified command shortcuts across multiple systems.

## Features

- **Parallel Deployment** - Deploys to multiple hosts simultaneously for fast execution
- **Idempotent** - Safe to run multiple times; uses markers to replace existing aliases cleanly
- **Automatic Backups** - Creates timestamped backups of `.bashrc` before modification
- **Smart Host Discovery** - Reads hosts from `/etc/hosts`, filtering out localhost entries
- **Connection Handling** - Skips unreachable hosts without blocking other deployments
- **Dry Run Mode** - Preview what would happen without making changes
- **Comprehensive Alias Collection** - Includes 90+ useful aliases out of the box

## Prerequisites

- SSH key-based authentication configured for all target nodes
- Target hosts listed in `/etc/hosts` with their IP addresses
- Bash 4.0+ on the control machine

## Installation

```bash
# Download or create the script
curl -O https://your-repo/alias-dist.sh

# Make executable
chmod +x alias-dist.sh
```

## Usage

```bash
# Basic usage - deploy to all hosts as current user
./alias-dist.sh

# Specify SSH user
./alias-dist.sh -u pi

# Set max parallel connections
./alias-dist.sh -p 20

# Dry run - see what would happen
./alias-dist.sh --dry-run

# List all aliases without deploying
./alias-dist.sh --list

# Combine options
./alias-dist.sh -u pi -p 15 --dry-run
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `-n, --dry-run` | Show what would be done without deploying |
| `-l, --list` | List all configured aliases |
| `-p, --parallel N` | Maximum parallel jobs (default: 10) |
| `-u, --user USER` | SSH user for connections (default: current user) |
| `-h, --help` | Show help message |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SSH_USER` | SSH username for all connections | Current user |
| `MAX_PARALLEL` | Maximum concurrent deployments | 10 |

```bash
# Example using environment variables
SSH_USER=pi MAX_PARALLEL=20 ./alias-dist.sh
```

## Configuration

### Adding Your Own Aliases

Edit the `ALIASES` array in the script to add your custom aliases:

```bash
ALIASES=(
    # ... existing aliases ...
    
    # ------------------------------
    # My Custom Aliases
    # ------------------------------
    "alias myserver='ssh user@myserver.local'"
    "alias deploy='cd ~/projects && ./deploy.sh'"
    "alias logs='tail -f /var/log/syslog'"
)
```

### Host Discovery

The script reads from `/etc/hosts` and automatically excludes:
- Comment lines (starting with `#`)
- Localhost entries (`127.0.0.1`, `127.0.1.1`, `::1`)
- IPv6 addresses
- `localhost` and `broadcasthost` hostnames

Example `/etc/hosts` that would deploy to `192.168.1.101`, `192.168.1.102`, and `192.168.1.103`:

```
127.0.0.1       localhost
127.0.1.1       controlnode

# My cluster nodes
192.168.1.101   node1
192.168.1.102   node2
192.168.1.103   node3
```

## Included Aliases

The script comes pre-loaded with 90+ aliases organized by category:

---

### Navigation & Directory

| Alias | Command | Description |
|-------|---------|-------------|
| `ll` | `ls -lAhF --color=auto` | Detailed list with hidden files |
| `la` | `ls -A` | List all except `.` and `..` |
| `l` | `ls -CF` | Compact list with indicators |
| `ls` | `ls --color=auto` | Colorized ls |
| `..` | `cd ..` | Go up one directory |
| `...` | `cd ../..` | Go up two directories |
| `....` | `cd ../../..` | Go up three directories |
| `~` | `cd ~` | Go to home directory |
| `-` | `cd -` | Go to previous directory |
| `mkdir` | `mkdir -pv` | Create dirs with parents, verbose |
| `tree` | `tree -C` | Colorized tree view |

---

### File Operations

| Alias | Command | Description |
|-------|---------|-------------|
| `cp` | `cp -iv` | Copy with confirmation and verbose |
| `mv` | `mv -iv` | Move with confirmation and verbose |
| `rm` | `rm -Iv` | Remove with confirmation (3+ files) |
| `ln` | `ln -iv` | Link with confirmation and verbose |
| `chmod` | `chmod -v` | Change permissions verbose |
| `chown` | `chown -v` | Change ownership verbose |
| `df` | `df -hT` | Disk free human-readable with type |
| `du` | `du -h` | Disk usage human-readable |
| `dus` | `du -sh * \| sort -h` | Directory sizes sorted |
| `free` | `free -h` | Memory info human-readable |

---

### Search & Find

| Alias | Command | Description |
|-------|---------|-------------|
| `grep` | `grep --color=auto` | Colorized grep |
| `egrep` | `egrep --color=auto` | Colorized extended grep |
| `fgrep` | `fgrep --color=auto` | Colorized fixed grep |
| `ff` | `find . -type f -name` | Find files by name |
| `fd` | `find . -type d -name` | Find directories by name |
| `h` | `history` | Show command history |
| `hg` | `history \| grep` | Search command history |

---

### System & Process

| Alias | Command | Description |
|-------|---------|-------------|
| `s` | `sudo` | Sudo |
| `ps` | `ps auxf` | Process list with tree |
| `psg` | `ps aux \| grep -v grep \| grep -i` | Search processes |
| `top` | `htop 2>/dev/null \|\| top` | Prefer htop if available |
| `kill9` | `kill -9` | Force kill shorthand |
| `meminfo` | `free -h -l -t` | Detailed memory info |
| `cpuinfo` | `lscpu` | CPU information |
| `temp` | `vcgencmd measure_temp ...` | CPU temp (Pi compatible) |

---

### Networking

| Alias | Command | Description |
|-------|---------|-------------|
| `ports` | `ss -tulpn` | Show all listening ports |
| `listening` | `ss -tulpn \| grep LISTEN` | Show only listening ports |
| `myip` | `curl -s ifconfig.me` | External IP address |
| `localip` | `ip -4 addr show ...` | Local IP addresses |
| `ping` | `ping -c 5` | Ping with 5 packets |
| `pingg` | `ping google.com` | Quick connectivity test |
| `wget` | `wget -c` | Continue partial downloads |
| `speedtest` | `curl -s ... \| python3 -` | Run speedtest |
| `flushdns` | `sudo systemd-resolve --flush-caches` | Flush DNS cache |

---

### Package Management (Debian/Ubuntu)

| Alias | Command | Description |
|-------|---------|-------------|
| `update` | `sudo apt update && sudo apt upgrade -y` | Full system update |
| `install` | `sudo apt install` | Install package |
| `remove` | `sudo apt remove` | Remove package |
| `autoremove` | `sudo apt autoremove -y` | Remove unused packages |
| `search` | `apt search` | Search packages |
| `cleanup` | `sudo apt autoremove -y && sudo apt autoclean` | Full cleanup |

---

### Systemd & Services

| Alias | Command | Description |
|-------|---------|-------------|
| `sc` | `sudo systemctl` | Systemctl shorthand |
| `scstart` | `sudo systemctl start` | Start service |
| `scstop` | `sudo systemctl stop` | Stop service |
| `screstart` | `sudo systemctl restart` | Restart service |
| `scstatus` | `sudo systemctl status` | Service status |
| `scenable` | `sudo systemctl enable` | Enable service at boot |
| `scdisable` | `sudo systemctl disable` | Disable service at boot |
| `sclog` | `journalctl -xeu` | Service logs with context |
| `jlog` | `journalctl -f` | Follow system journal |
| `failed` | `systemctl --failed` | Show failed services |

---

### Docker

| Alias | Command | Description |
|-------|---------|-------------|
| `d` | `docker` | Docker shorthand |
| `dc` | `docker compose` | Docker Compose shorthand |
| `dps` | `docker ps --format "table ..."` | Pretty container list |
| `dpsa` | `docker ps -a --format "table ..."` | All containers pretty |
| `dimg` | `docker images` | List images |
| `dlog` | `docker logs -f` | Follow container logs |
| `dexec` | `docker exec -it` | Interactive exec |
| `dstop` | `docker stop $(docker ps -q)` | Stop all running containers |
| `dprune` | `docker system prune -af` | Prune system |
| `dvprune` | `docker volume prune -f` | Prune volumes |
| `dstats` | `docker stats --no-stream` | Container stats snapshot |
| `dtop` | `docker stats --format "table ..."` | Container resource usage |
| `dclean` | `docker system prune -af && docker volume prune -f` | Full cleanup |
| `dnet` | `docker network ls` | List networks |
| `dinspect` | `docker inspect` | Inspect object |
| `dip` | `docker inspect -f "{{range...}}"` | Get container IP |

---

### Kubernetes / k3s

| Alias | Command | Description |
|-------|---------|-------------|
| `k` | `kubectl` | Kubectl shorthand |
| `kgp` | `kubectl get pods` | List pods |
| `kgpa` | `kubectl get pods -A` | List pods all namespaces |
| `kgn` | `kubectl get nodes` | List nodes |
| `kgs` | `kubectl get svc` | List services |
| `kgd` | `kubectl get deployments` | List deployments |
| `kgi` | `kubectl get ingress` | List ingress |
| `kgpv` | `kubectl get pv` | List persistent volumes |
| `kgpvc` | `kubectl get pvc` | List persistent volume claims |
| `kga` | `kubectl get all` | Get all resources |
| `kgaa` | `kubectl get all -A` | Get all resources all namespaces |
| `kdesc` | `kubectl describe` | Describe resource |
| `klog` | `kubectl logs -f` | Follow pod logs |
| `kexec` | `kubectl exec -it` | Interactive exec into pod |
| `kaf` | `kubectl apply -f` | Apply from file |
| `kdf` | `kubectl delete -f` | Delete from file |
| `kctx` | `kubectl config get-contexts` | List contexts |
| `kns` | `kubectl config set-context --current --namespace` | Set namespace |
| `ktop` | `kubectl top` | Resource usage |
| `kwatch` | `watch -n1 kubectl get pods` | Watch pods live |
| `krollout` | `kubectl rollout restart deployment` | Restart deployment |

---

### Git

| Alias | Command | Description |
|-------|---------|-------------|
| `g` | `git` | Git shorthand |
| `gs` | `git status` | Repository status |
| `ga` | `git add` | Stage files |
| `gaa` | `git add -A` | Stage all changes |
| `gc` | `git commit -m` | Commit with message |
| `gp` | `git push` | Push changes |
| `gpl` | `git pull` | Pull changes |
| `gf` | `git fetch` | Fetch from remote |
| `gb` | `git branch` | List/manage branches |
| `gco` | `git checkout` | Switch branches |
| `gd` | `git diff` | Show changes |
| `glog` | `git log --oneline --graph --decorate -10` | Pretty log |
| `gclone` | `git clone` | Clone repository |

---

### Editors & Config

| Alias | Command | Description |
|-------|---------|-------------|
| `nano` | `nano -l` | Nano with line numbers |
| `bashrc` | `nano ~/.bashrc && source ~/.bashrc` | Edit and reload bashrc |
| `src` | `source ~/.bashrc` | Reload shell config |
| `path` | `echo $PATH \| tr ":" "\n"` | Display PATH line by line |
| `hosts` | `sudo nano /etc/hosts` | Edit hosts file |

---

### Quick Shortcuts

| Alias | Command | Description |
|-------|---------|-------------|
| `c` | `clear` | Clear screen |
| `q` | `exit` | Exit shell |
| `now` | `date +"%Y-%m-%d %H:%M:%S"` | Current datetime |
| `week` | `date +%V` | Current week number |
| `timestamp` | `date +%s` | Unix timestamp |
| `weather` | `curl wttr.in/?0` | Weather report |
| `moon` | `curl wttr.in/Moon` | Moon phase |
| `sha` | `shasum -a 256` | SHA256 hash |
| `genpass` | `openssl rand -base64 20` | Generate random password |
| `busy` | `cat /dev/urandom \| hexdump -C \| grep 'ca fe'` | Fake hacker screen |

---

### Safety Nets

| Alias | Command | Description |
|-------|---------|-------------|
| `reboot` | `sudo /sbin/reboot` | Reboot system |
| `poweroff` | `sudo /sbin/poweroff` | Power off system |
| `shutdown` | `sudo /sbin/shutdown` | Shutdown system |

---

### Tail & Watch

| Alias | Command | Description |
|-------|---------|-------------|
| `tf` | `tail -f` | Follow file |
| `t100` | `tail -100` | Last 100 lines |
| `watch` | `watch -n 2` | Watch with 2s interval |

---

## How It Works

1. **Host Discovery** - Parses `/etc/hosts` to find target machines
2. **Alias Block Generation** - Creates a marked block of alias definitions
3. **Parallel SSH** - Connects to multiple hosts simultaneously
4. **Safe Replacement** - Removes any existing alias block, appends new one
5. **Result Collection** - Aggregates success/failure from all hosts

The alias block in `.bashrc` looks like:

```bash
# >>> DISTRIBUTED ALIASES START <<<
# Distributed on: Thu Dec 12 10:30:00 EST 2024
# From: controlnode
alias ll='ls -lAhF --color=auto'
alias la='ls -A'
# ... more aliases ...
# >>> DISTRIBUTED ALIASES END <<<
```

## Troubleshooting

### "Cannot connect" for all hosts
- Verify SSH key authentication: `ssh -o BatchMode=yes user@host "echo OK"`
- Check that hosts are reachable: `ping <host>`
- Ensure correct username with `-u` flag

### Aliases not working after deployment
Run `source ~/.bashrc` or start a new shell session on the target node.

### Some hosts skipped
The script skips hosts that don't respond within the timeout period (default: 10 seconds). This is by design to prevent hanging on unreachable nodes.

### Permission denied
Ensure your SSH key is authorized on the target host:
```bash
ssh-copy-id user@host
```

## Uninstalling

To remove the distributed aliases from a node:

```bash
# On the target node
sed -i '/# >>> DISTRIBUTED ALIASES START <<</,/# >>> DISTRIBUTED ALIASES END <<</d' ~/.bashrc
source ~/.bashrc
```

Or to remove from all nodes, modify the script's `deploy_to_host` function to delete instead of add.

## Contributing

Feel free to add useful aliases! Keep them:
- Broadly applicable (not too specific to one setup)
- Well-commented by category
- Safe (use confirmations for destructive commands)

## License

MIT License - Use freely, modify as needed.

## Acknowledgments

Built for managing home lab infrastructure, Raspberry Pi clusters, and keeping sanity across multiple Linux systems.
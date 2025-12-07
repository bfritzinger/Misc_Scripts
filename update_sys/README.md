# Cluster System Update

A bash script to run `apt update && apt upgrade` in parallel across multiple cluster nodes via SSH.

## Overview

This script performs system updates on all specified nodes simultaneously, collecting logs and providing a summary of successes and failures.

## Prerequisites

- SSH key-based authentication configured to all target nodes
- User must have passwordless `sudo` privileges on all target nodes
- All nodes must be reachable by hostname (via `/etc/hosts` or DNS)

## Configuration

Edit the script to customize:

```bash
# List of nodes to update
NODES=(
    "node"
    "node-1"
    "node-2"
    "node-3"
)

# SSH username
USER="<USER_NAME>"
```

## Usage

1. Make the script executable:
   ```bash
   chmod +x update_sys.sh
   ```

2. Run the script:
   ```bash
   ./update_sys.sh
   ```

## Example Output

```
Starting update on node...
Starting update on node-1...
Starting update on node-2...
Starting update on node-3...
node-1 complete.
node complete.
node-3 complete.
node-2 FAILED! Check /tmp/cluster-update-12345/node-2.log

========== SUMMARY ==========
Succeeded: 3
Failed:    1

Failed nodes:
node-2

Logs saved in: /tmp/cluster-update-12345
```

## How It Works

1. Creates a temporary log directory (`/tmp/cluster-update-<PID>`)
2. Spawns parallel SSH connections to all nodes
3. Runs `sudo apt update && sudo apt upgrade -y` on each node
4. Captures output to individual log files per node
5. Tracks success/failure status
6. Waits for all updates to complete
7. Displays summary with pass/fail counts

## Log Files

Logs are stored in `/tmp/cluster-update-<PID>/`:

| File | Contents |
|------|----------|
| `<node>.log` | Full apt output for each node |
| `success` | List of nodes that updated successfully |
| `failed` | List of nodes that failed |

## Notes

- Updates run in parallel, so output may be interleaved
- The script waits for all nodes to complete before showing the summary
- Log directory persists after script completion for troubleshooting
- Each run creates a new log directory (using PID to avoid conflicts)

## Troubleshooting

**SSH connection fails:**
- Verify SSH key authentication: `ssh user@node "echo OK"`
- Check that the node hostname resolves correctly

**Sudo password prompt hangs:**
- Configure passwordless sudo for apt on target nodes:
  ```bash
  echo "username ALL=(ALL) NOPASSWD: /usr/bin/apt" | sudo tee /etc/sudoers.d/apt-update
  ```

**Package lock errors:**
- Another apt process may be running on the node
- Check the node's log file for details

## Changelog

- **v1.0** - Initial release
# Kubernetes Cluster SSH Mesh Setup

A bash script to automate SSH key distribution and `/etc/hosts` synchronization across a cluster of nodes, enabling passwordless SSH between all nodes.

## Overview

This script performs the following operations:

1. **Phase 0**: Distributes `/etc/hosts` entries from the local machine to all cluster nodes
2. **Phase 1**: Generates SSH keys on each node (if not already present)
3. **Phase 2**: Collects all public keys from the cluster
4. **Phase 3**: Distributes the collected keys to all nodes' `authorized_keys`
5. **Phase 4**: Populates `known_hosts` on each node for all other nodes
6. **Phase 5**: Tests full mesh connectivity

## Prerequisites

- `sshpass` installed on the machine running the script
  ```bash
  sudo apt install sshpass
  ```
- All target nodes must be accessible via SSH with password authentication
- All target nodes must be listed in `/etc/hosts` on the machine running the script
- User must have sudo privileges on all target nodes (for `/etc/hosts` updates)

## Usage

1. Add your cluster nodes to `/etc/hosts` on the machine running the script:
   ```
   192.168.1.10    master
   192.168.1.11    worker1
   192.168.1.12    worker2
   192.168.1.13    worker3
   ```

2. Make the script executable:
   ```bash
   chmod +x cluster_sshKey_setup.sh
   ```

3. Run the script:
   ```bash
   ./cluster_sshKey_setup.sh
   ```

4. Follow the prompts:
   - Enter the subnet prefix (e.g., `192.168.1`)
   - Enter the SSH username
   - Enter the SSH password

## Example Output

```
Enter subnet (e.g. 192.168.1): 192.168.1
Found nodes:
  master
  worker1
  worker2
  worker3

Enter SSH username: <USER_NAME>
Enter SSH password: 
=== Phase 0: Distribute /etc/hosts entries to all nodes ===
Updating /etc/hosts on master...
Updating /etc/hosts on worker1...
...
=== Phase 5: Testing mesh connectivity ===
pi-master -> master: OK
pi-master -> worker1: OK
...
=== Done ===
```

## Notes

- The script backs up `/etc/hosts` on each node before modifying it
- SSH keys are only generated if they don't already exist
- The `authorized_keys` file is deduplicated after adding keys
- Existing subnet entries in `/etc/hosts` are replaced to avoid duplicates

## Security Considerations

- This script is intended for closed/private environments
- Password is stored in memory only during script execution
- After running, all nodes use key-based authentication
- Consider disabling password authentication after setup:
  ```bash
  sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  sudo systemctl restart sshd
  ```

## Troubleshooting

**Script still prompts for password:**
- Ensure `sshpass` is installed: `which sshpass`
- Verify password authentication is enabled on target nodes

**No nodes found:**
- Check that `/etc/hosts` contains entries matching your subnet
- Verify the subnet format (e.g., `192.168.1` not `192.168.1.0`)

**Connection failures in Phase 5:**
- Check network connectivity between nodes
- Verify SSH service is running: `sudo systemctl status sshd`

## Changelog

- **v1.0** - Initial release

#!/bin/bash

###
#
# Run this from workstation / node that can SSh into all nodes.
# Nodes to be accessed will need to be in /etc/hosts and in same subnet.  
# Update SUBNET for cluster
# Need to have sshpass installed.
# Will prompt one time for password (assuming USER/PASS for all systems is same - designed fpr LAB systems)
#
##

SUBNET="10.0.0"  # Change to your cluster subnet

# Read nodes from /etc/hosts matching the subnet
mapfile -t NODES < <(grep "^${SUBNET}" /etc/hosts | awk '{print $2}')

# Verify we found nodes
if [ ${#NODES[@]} -eq 0 ]; then
    echo "No nodes found in /etc/hosts for subnet ${SUBNET}"
    exit 1
fi

echo "Found nodes:"
printf '  %s\n' "${NODES[@]}"
echo


USER="<USER_NAME>"
read -s -p "Enter SSH password: " PASS
echo

export SSHPASS_CMD=$PASS
SSHPASS_CMD="sshpass -e"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
TEMP_DIR="/tmp/ssh-keys"

# Run this from one node that can initially reach all others (will prompt for passwords)

echo "=== Phase 0: Distribute /etc/hosts entries to all nodes ==="
HOSTS_ENTRIES=$(grep "^${SUBNET}" /etc/hosts)

for node in "${NODES[@]}"; do
    echo "Updating /etc/hosts on $node..."
    SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${node}" "
        sudo cp /etc/hosts /etc/hosts.bak
        sudo sed -i '/^${SUBNET}/d' /etc/hosts
        echo '${HOSTS_ENTRIES}' | sudo tee -a /etc/hosts > /dev/null
    "
done

echo "=== Phase 1: Generate keys on all nodes ==="
for node in "${NODES[@]}"; do
    echo "Generating key on $node..."
    SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${node}" "if [ ! -f ~/.ssh/id_rsa ]; then ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa; fi"
done

echo "=== Phase 2: Collect all public keys ==="
mkdir -p "$TEMP_DIR"
rm -f "${TEMP_DIR}/all_keys"

for node in "${NODES[@]}"; do
    echo "Fetching key from $node..."
    SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${node}" "cat ~/.ssh/id_rsa.pub" >> "${TEMP_DIR}/all_keys"
done

echo "=== Phase 3: Distribute keys to all nodes ==="
for node in "${NODES[@]}"; do
    echo "Distributing keys to $node..."
    SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${node}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    cat "${TEMP_DIR}/all_keys" | SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${node}" "cat >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
done

echo "=== Phase 4: Add all nodes to known_hosts on each node ==="
for source in "${NODES[@]}"; do
    echo "Setting up known_hosts on $source..."
    for target in "${NODES[@]}"; do
        SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${source}" "ssh-keyscan -H ${target} >> ~/.ssh/known_hosts 2>/dev/null"
    done
done

echo "=== Phase 5: Testing mesh connectivity ==="
for source in "${NODES[@]}"; do
    for target in "${NODES[@]}"; do
        echo -n "${source} -> ${target}: "
        SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${source}" "ssh -o BatchMode=yes -o ConnectTimeout=5 ${USER}@${target} 'echo OK'" 2>/dev/null || echo "FAILED"
    done
done

rm -rf "$TEMP_DIR"
echo "=== Done ==="
#!/bin/bash
#
# Kubernetes Cluster SSH Mesh Setup
# Automates SSH key distribution and /etc/hosts synchronization
# across a cluster of nodes for passwordless SSH.
#
# Version: 1.1 - Added robust duplicate detection

set -e

# Prompt for subnet
read -p "Enter subnet (e.g. 192.168.1): " SUBNET

# Build node list from /etc/hosts
mapfile -t NODES < <(grep "^${SUBNET}" /etc/hosts | awk '{print $2}')

if [ ${#NODES[@]} -eq 0 ]; then
    echo "No nodes found in /etc/hosts for subnet ${SUBNET}"
    exit 1
fi

echo "Found nodes:"
printf '  %s\n' "${NODES[@]}"
echo

read -p "Enter SSH username: " USER
read -s -p "Enter SSH password: " PASS
echo

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
TEMP_DIR="/tmp/ssh-keys-$$"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo ""
echo "=== Phase 0: Distribute /etc/hosts entries to all nodes ==="
HOSTS_ENTRIES=$(grep "^${SUBNET}" /etc/hosts)

for node in "${NODES[@]}"; do
    echo "Updating /etc/hosts on $node..."
    SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${node}" "
        sudo cp /etc/hosts /etc/hosts.bak
        # Remove existing entries for this subnet to avoid duplicates
        sudo sed -i '/^${SUBNET}/d' /etc/hosts
        echo '${HOSTS_ENTRIES}' | sudo tee -a /etc/hosts > /dev/null
    "
done

echo ""
echo "=== Phase 1: Generate keys on all nodes ==="
for node in "${NODES[@]}"; do
    echo "Generating key on $node (if not present)..."
    SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${node}" "if [ ! -f ~/.ssh/id_rsa ]; then ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa; else echo 'Key already exists, skipping'; fi"
done

echo ""
echo "=== Phase 2: Collect all public keys ==="
mkdir -p "$TEMP_DIR"
rm -f "${TEMP_DIR}/all_keys"

for node in "${NODES[@]}"; do
    echo "Fetching key from $node..."
    SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${node}" "cat ~/.ssh/id_rsa.pub" >> "${TEMP_DIR}/all_keys"
done

# Deduplicate collected keys (in case of identical keys)
sort -u "${TEMP_DIR}/all_keys" -o "${TEMP_DIR}/all_keys"

echo ""
echo "=== Phase 3: Distribute keys to all nodes (with duplicate check) ==="
for node in "${NODES[@]}"; do
    echo "Distributing keys to $node..."
    SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${node}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    
    # For each key, check if it already exists before adding
    while IFS= read -r key; do
        # Extract the key portion (without comment) for comparison
        key_data=$(echo "$key" | awk '{print $1" "$2}')
        
        SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${node}" "
            AUTH_FILE=~/.ssh/authorized_keys
            touch \"\$AUTH_FILE\"
            chmod 600 \"\$AUTH_FILE\"
            
            # Check if key already exists (match on key type and key data)
            if ! grep -qF '${key_data}' \"\$AUTH_FILE\" 2>/dev/null; then
                echo '${key}' >> \"\$AUTH_FILE\"
                echo '  Added new key'
            else
                echo '  Key already exists, skipping'
            fi
        "
    done < "${TEMP_DIR}/all_keys"
    
    # Final deduplication pass to clean up any edge cases
    SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${node}" "
        if [ -f ~/.ssh/authorized_keys ]; then
            sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys
        fi
    "
done

echo ""
echo "=== Phase 4: Add all nodes to known_hosts (with duplicate check) ==="
for source in "${NODES[@]}"; do
    echo "Setting up known_hosts on $source..."
    for target in "${NODES[@]}"; do
        # Get the host key
        HOST_KEY=$(ssh-keyscan -H ${target} 2>/dev/null | head -1)
        
        if [ -n "$HOST_KEY" ]; then
            # Extract the hashed hostname pattern for checking
            HASH_PATTERN=$(echo "$HOST_KEY" | awk '{print $1}')
            
            SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${source}" "
                KNOWN_FILE=~/.ssh/known_hosts
                touch \"\$KNOWN_FILE\"
                chmod 644 \"\$KNOWN_FILE\"
                
                # Check if an entry for this host already exists
                # Since we use hashed hostnames, we check by trying ssh-keygen -F
                if ! ssh-keygen -F '${target}' -f \"\$KNOWN_FILE\" >/dev/null 2>&1; then
                    echo '${HOST_KEY}' >> \"\$KNOWN_FILE\"
                fi
            "
        fi
    done
    
    # Remove any duplicate lines that might have snuck in
    SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${source}" "
        if [ -f ~/.ssh/known_hosts ]; then
            sort -u ~/.ssh/known_hosts -o ~/.ssh/known_hosts
        fi
    "
done

echo ""
echo "=== Phase 5: Testing mesh connectivity ==="
FAILED=0
for source in "${NODES[@]}"; do
    for target in "${NODES[@]}"; do
        echo -n "${source} -> ${target}: "
        if SSHPASS="$PASS" sshpass -e ssh $SSH_OPTS "${USER}@${source}" "ssh -o BatchMode=yes -o ConnectTimeout=5 ${USER}@${target} 'echo OK'" 2>/dev/null; then
            :
        else
            echo "FAILED"
            FAILED=$((FAILED + 1))
        fi
    done
done

echo ""
echo "=== Done ==="
if [ $FAILED -eq 0 ]; then
    echo "All connections successful!"
else
    echo "Warning: $FAILED connection(s) failed. Check the output above."
fi
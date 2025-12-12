#!/bin/bash
# Deploy Pi Monitoring to All Nodes
# Run this from your management machine (where you have SSH access to all Pis)

set -e

#===============================================================================
# CONFIGURATION - Edit these values
#===============================================================================

# List your Pi hostnames or IPs (space-separated)
PI_NODES=(
    "pi-node1"
    "pi-node2"
    "pi-node3"
    # Add more nodes here
)

# SSH user (usually 'pi' or your username)
SSH_USER="pi"

# Path to the pi-monitor folder on this machine
LOCAL_MONITOR_DIR="./pi-monitor"

# SSH options (add key path if needed)
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
# SSH_OPTS="-i ~/.ssh/pi_key -o StrictHostKeyChecking=no"

#===============================================================================
# SCRIPT START
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  Pi Monitoring Deployment Script"
echo "=========================================="
echo ""

# Check local files exist
if [ ! -f "$LOCAL_MONITOR_DIR/pi_metrics.sh" ]; then
    echo -e "${RED}Error: Cannot find $LOCAL_MONITOR_DIR/pi_metrics.sh${NC}"
    echo "Make sure you're running this from the directory containing pi-monitor/"
    exit 1
fi

# Summary
echo "Deploying to ${#PI_NODES[@]} nodes:"
printf '  - %s\n' "${PI_NODES[@]}"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Track results
SUCCESSFUL=()
FAILED=()

for NODE in "${PI_NODES[@]}"; do
    echo ""
    echo -e "${YELLOW}=========================================="
    echo "  Deploying to: $NODE"
    echo -e "==========================================${NC}"
    
    # Test SSH connection
    if ! ssh $SSH_OPTS "$SSH_USER@$NODE" "echo 'SSH OK'" &>/dev/null; then
        echo -e "${RED}✗ Cannot SSH to $NODE - skipping${NC}"
        FAILED+=("$NODE (SSH failed)")
        continue
    fi
    
    # Create remote directory
    echo "Creating remote directory..."
    ssh $SSH_OPTS "$SSH_USER@$NODE" "mkdir -p ~/pi-monitor"
    
    # Copy files
    echo "Copying files..."
    scp $SSH_OPTS -r "$LOCAL_MONITOR_DIR"/* "$SSH_USER@$NODE:~/pi-monitor/"
    
    # Run setup script (installs pi_metrics.sh and systemd timer)
    echo "Running setup script..."
    ssh $SSH_OPTS "$SSH_USER@$NODE" "cd ~/pi-monitor && chmod +x setup.sh && sudo ./setup.sh"
    
    # Update node_exporter container
    echo "Updating node_exporter container..."
    ssh $SSH_OPTS "$SSH_USER@$NODE" bash << 'REMOTE_SCRIPT'
        # Check if node_exporter container exists
        if ! docker ps -a --format '{{.Names}}' | grep -q "^node_exporter$"; then
            echo "Warning: node_exporter container not found"
            echo "You may need to manually start it with the textfile collector enabled"
            exit 0
        fi
        
        # Get current container config
        CURRENT_IMAGE=$(docker inspect node_exporter --format '{{.Config.Image}}' 2>/dev/null || echo "prom/node-exporter:latest")
        
        # Check if already configured correctly
        if docker inspect node_exporter --format '{{.Args}}' | grep -q "textfile"; then
            echo "node_exporter already has textfile collector configured"
        else
            echo "Recreating node_exporter with textfile collector..."
            
            # Stop and remove old container
            docker stop node_exporter 2>/dev/null || true
            docker rm node_exporter 2>/dev/null || true
            
            # Start with new config
            docker run -d \
                --name node_exporter \
                --restart unless-stopped \
                --net="host" \
                --pid="host" \
                -v "/:/host:ro,rslave" \
                -v "/var/lib/node_exporter/textfile_collector:/textfile:ro" \
                "$CURRENT_IMAGE" \
                --path.rootfs=/host \
                --collector.textfile.directory=/textfile
            
            echo "node_exporter container recreated"
        fi
REMOTE_SCRIPT
    
    # Verify metrics
    echo "Verifying metrics..."
    sleep 2
    if ssh $SSH_OPTS "$SSH_USER@$NODE" "curl -s localhost:9100/metrics | grep -q rpi_temperature"; then
        echo -e "${GREEN}✓ $NODE: Pi metrics working!${NC}"
        SUCCESSFUL+=("$NODE")
    else
        echo -e "${RED}✗ $NODE: Metrics not appearing yet (may need a moment)${NC}"
        FAILED+=("$NODE (metrics not found)")
    fi
done

# Summary
echo ""
echo "=========================================="
echo "  Deployment Summary"
echo "=========================================="
echo -e "${GREEN}Successful: ${#SUCCESSFUL[@]}${NC}"
printf '  - %s\n' "${SUCCESSFUL[@]}"
echo ""
if [ ${#FAILED[@]} -gt 0 ]; then
    echo -e "${RED}Failed: ${#FAILED[@]}${NC}"
    printf '  - %s\n' "${FAILED[@]}"
fi
echo ""
echo "Next steps:"
echo "  1. Add pi_alerts.yml to your Prometheus rules"
echo "  2. Configure alertmanager.yml with your notification preferences"
echo "  3. Reload Prometheus"

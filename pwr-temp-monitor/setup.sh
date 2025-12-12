#!/bin/bash
# Universal Metrics Setup Script
# Detects system type and installs appropriate metrics collector

set -e

echo "=== System Metrics Setup ==="

# Detect system type
detect_system() {
    # Check for Raspberry Pi
    if command -v vcgencmd &> /dev/null; then
        echo "raspberrypi"
        return
    fi
    
    # Check for Jetson
    if [ -f /etc/nv_tegra_release ] || [ -d /sys/devices/gpu.0 ] || grep -qi "tegra\|jetson" /proc/device-tree/model 2>/dev/null; then
        echo "jetson"
        return
    fi
    
    # Check architecture for x86
    arch=$(uname -m)
    if [[ "$arch" == "x86_64" || "$arch" == "i686" ]]; then
        echo "x86"
        return
    fi
    
    echo "unknown"
}

SYSTEM_TYPE=$(detect_system)
echo "Detected system type: $SYSTEM_TYPE"

SCRIPT_DIR="/opt/system-monitor"
TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"

# Create directories
sudo mkdir -p "$SCRIPT_DIR"
sudo mkdir -p "$TEXTFILE_DIR"

# Install appropriate script
case $SYSTEM_TYPE in
    raspberrypi)
        echo "Installing Raspberry Pi metrics collector..."
        SCRIPT_NAME="pi_metrics.sh"
        SCRIPT_SOURCE="pi_metrics.sh"
        ;;
    jetson)
        echo "Installing Jetson metrics collector..."
        SCRIPT_NAME="jetson_metrics.sh"
        SCRIPT_SOURCE="jetson_metrics.sh"
        # Jetson needs bc for calculations
        if ! command -v bc &> /dev/null; then
            echo "Installing bc..."
            sudo apt-get update && sudo apt-get install -y bc
        fi
        ;;
    x86)
        echo "Installing x86 metrics collector..."
        SCRIPT_NAME="x86_metrics.sh"
        SCRIPT_SOURCE="x86_metrics.sh"
        # x86 needs lm-sensors and bc
        if ! command -v sensors &> /dev/null; then
            echo "Installing lm-sensors..."
            sudo apt-get update && sudo apt-get install -y lm-sensors
            sudo sensors-detect --auto
        fi
        if ! command -v bc &> /dev/null; then
            echo "Installing bc..."
            sudo apt-get update && sudo apt-get install -y bc
        fi
        ;;
    *)
        echo "Unknown system type. Cannot install metrics collector."
        exit 1
        ;;
esac

# Check if source script exists
if [ ! -f "$SCRIPT_SOURCE" ]; then
    echo "Error: $SCRIPT_SOURCE not found in current directory"
    exit 1
fi

# Copy script
sudo cp "$SCRIPT_SOURCE" "$SCRIPT_DIR/$SCRIPT_NAME"
sudo chmod +x "$SCRIPT_DIR/$SCRIPT_NAME"

# Test the script
echo "Testing metrics collection..."
sudo "$SCRIPT_DIR/$SCRIPT_NAME"

# Check output
METRICS_FILE="$TEXTFILE_DIR/system_metrics.prom"
if [ "$SYSTEM_TYPE" == "raspberrypi" ]; then
    METRICS_FILE="$TEXTFILE_DIR/pi_metrics.prom"
elif [ "$SYSTEM_TYPE" == "jetson" ]; then
    METRICS_FILE="$TEXTFILE_DIR/jetson_metrics.prom"
fi

if [ -f "$METRICS_FILE" ]; then
    echo "✓ Metrics file created"
    echo "Sample output:"
    head -20 "$METRICS_FILE"
else
    echo "✗ Metrics file not created"
    exit 1
fi

# Create systemd timer
SERVICE_NAME="system-metrics"

sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Collect system metrics for Prometheus
After=network.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/$SCRIPT_NAME
User=root
EOF

sudo tee /etc/systemd/system/${SERVICE_NAME}.timer > /dev/null << EOF
[Unit]
Description=Run system metrics collection every 15 seconds

[Timer]
OnBootSec=10
OnUnitActiveSec=15s
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}.timer
sudo systemctl start ${SERVICE_NAME}.timer

echo "✓ Systemd timer enabled and started"
echo ""
echo "Setup complete for $SYSTEM_TYPE!"
echo ""
echo "Make sure node_exporter is running with:"
echo "  --collector.textfile.directory=/var/lib/node_exporter/textfile_collector"

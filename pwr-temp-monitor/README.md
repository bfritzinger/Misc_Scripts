# System Temperature & Power Monitoring

Monitor temperature, voltage, power, and throttling status on Raspberry Pi, Nvidia Jetson, and x86 systems using Prometheus and Alertmanager.

## Supported Platforms

| Platform | Detection Method | Metrics Script |
|----------|------------------|----------------|
| Raspberry Pi | `vcgencmd` available | `pi_metrics.sh` |
| Nvidia Jetson | `/etc/nv_tegra_release` or Tegra device tree | `jetson_metrics.sh` |
| x86 (Intel/AMD) | `x86_64` or `i686` architecture | `x86_metrics.sh` |

## Components

| File | Purpose |
|------|---------|
| `setup.sh` | Universal setup - auto-detects system and installs appropriate collector |
| `pi_metrics.sh` | Raspberry Pi metrics via vcgencmd |
| `jetson_metrics.sh` | Nvidia Jetson metrics (thermal zones, power rails, GPU) |
| `x86_metrics.sh` | x86 metrics via hwmon/thermal_zone |
| `pi_alerts.yml` | Prometheus alerting rules for Pi temp/power thresholds |
| `alertmanager.yml` | Alertmanager config with notification routing |
| `deploy_to_nodes.sh` | Batch deployment script for multiple Pi nodes |
| `grafana-dashboard.json` | Pre-built Grafana dashboard for Pi monitoring |
| `NODE_EXPORTER_SETUP.md` | Detailed node_exporter configuration guide |

## Metrics Collected

### Raspberry Pi (`rpi_*`)

| Metric | Description |
|--------|-------------|
| `rpi_temperature_celsius` | GPU/SoC temperature |
| `rpi_voltage_volts` | Core voltage |
| `rpi_clock_hz` | ARM clock frequency |
| `rpi_throttle_status` | Raw throttle value |
| `rpi_undervoltage_now` | Currently undervoltaged (1/0) |
| `rpi_throttled_now` | Currently throttled (1/0) |
| `rpi_freq_capped_now` | Frequency currently capped (1/0) |
| `rpi_soft_temp_limit_now` | Soft temp limit active (1/0) |
| `rpi_*_occurred` | Historical flags since boot |

### Nvidia Jetson (`jetson_*`)

| Metric | Description |
|--------|-------------|
| `jetson_cpu_temperature_celsius` | CPU temperature |
| `jetson_gpu_temperature_celsius` | GPU temperature |
| `jetson_thermal_zone_celsius` | All thermal zones with type labels |
| `jetson_power_watts` | Power consumption per rail |
| `jetson_current_amps` | Current draw per rail |
| `jetson_voltage_volts` | Voltage per rail |
| `jetson_cpu_frequency_hz` | CPU frequency |
| `jetson_gpu_frequency_hz` | GPU frequency |
| `jetson_fan_speed_percent` | Fan speed (0-100%) |
| `jetson_fan_rpm` | Fan speed in RPM |

### x86 Systems (`system_*`)

| Metric | Description |
|--------|-------------|
| `system_cpu_temperature_celsius` | CPU temperature (coretemp/k10temp) |
| `system_cpu_frequency_hz` | CPU frequency |
| `system_thermal_zone_celsius` | All thermal zones with type labels |
| `system_fan_rpm` | Fan speeds |

## Alert Thresholds (Raspberry Pi)

| Alert | Condition | Severity |
|-------|-----------|----------|
| PiTemperatureWarning | > 65°C for 2m | warning |
| PiTemperatureCritical | > 75°C for 1m | critical |
| PiTemperatureEmergency | > 80°C for 30s | critical |
| PiUndervoltageActive | undervoltage now | critical |
| PiUndervoltageOccurred | undervoltage since boot | warning |
| PiThrottlingActive | throttled now | warning |
| PiFrequencyCapped | freq capped now | warning |
| PiSoftTempLimitActive | soft temp limit now | warning |
| PiLowVoltage | voltage < 1.15V for 5m | warning |

## Quick Setup

### 1. On Each Node (Universal)

The `setup.sh` script auto-detects your system type and installs the appropriate metrics collector:

```bash
# Copy files to node
scp -r system-monitor/ user@<node-ip>:~/

# SSH in and run setup
ssh user@<node-ip>
cd ~/system-monitor
chmod +x setup.sh
sudo ./setup.sh
```

The setup script will:
- Detect if you're running Raspberry Pi, Jetson, or x86
- Install required dependencies (bc, lm-sensors as needed)
- Copy the appropriate metrics script to `/opt/system-monitor/`
- Create and enable a systemd timer (runs every 15 seconds)
- Verify metrics are being collected

### 2. Batch Deployment (Raspberry Pi Cluster)

For deploying to multiple Pi nodes at once:

```bash
# Edit deploy_to_nodes.sh with your node list
nano deploy_to_nodes.sh

# Run deployment
chmod +x deploy_to_nodes.sh
./deploy_to_nodes.sh
```

### 3. Configure Node Exporter

Node exporter must have the textfile collector enabled. See `NODE_EXPORTER_SETUP.md` for detailed instructions.

**Quick version - Docker:**

```bash
docker run -d \
  --name node_exporter \
  --net="host" \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  -v "/var/lib/node_exporter/textfile_collector:/textfile:ro" \
  prom/node-exporter:latest \
  --path.rootfs=/host \
  --collector.textfile.directory=/textfile
```

**Quick version - Systemd:**

```bash
sudo systemctl edit node_exporter
```

Add:
```ini
[Service]
ExecStart=
ExecStart=/usr/local/bin/node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile_collector
```

Then:
```bash
sudo systemctl daemon-reload
sudo systemctl restart node_exporter
```

### 4. Add Alert Rules to Prometheus

Copy `pi_alerts.yml` to your Prometheus rules directory:

```yaml
# prometheus.yml
rule_files:
  - "rules/*.yml"
  - "pi_alerts.yml"
```

Reload Prometheus:
```bash
# Docker
docker exec prometheus kill -HUP 1

# Or via API
curl -X POST http://localhost:9090/-/reload
```

### 5. Deploy Alertmanager

Edit `alertmanager.yml` with your notification preferences:

```yaml
# docker-compose.yml
alertmanager:
  image: prom/alertmanager:latest
  container_name: alertmanager
  ports:
    - "9093:9093"
  volumes:
    - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml
  command:
    - '--config.file=/etc/alertmanager/alertmanager.yml'
  restart: unless-stopped
```

### 6. Connect Prometheus to Alertmanager

```yaml
# prometheus.yml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
```

## Notification Options

Configure your preferred method in `alertmanager.yml`:

### Discord
```yaml
discord_configs:
  - webhook_url: 'https://discord.com/api/webhooks/...'
```

### Slack
```yaml
slack_configs:
  - api_url: 'https://hooks.slack.com/services/...'
    channel: '#alerts'
```

### Pushover (Mobile)
```yaml
pushover_configs:
  - user_key: 'YOUR_KEY'
    token: 'YOUR_TOKEN'
```

### ntfy (Self-hosted)
```yaml
webhook_configs:
  - url: 'https://ntfy.sh/your-topic'
```

### Email
```yaml
email_configs:
  - to: 'you@example.com'
```

## Grafana Dashboard

Import `grafana-dashboard.json` for a pre-built Pi monitoring dashboard with:
- Temperature gauges per node
- Voltage gauges per node
- Throttle/undervoltage status indicators
- Temperature history graphs
- Clock frequency over time
- Historical flags since boot
- Active alerts panel

### Custom Queries by Platform

**Raspberry Pi:**
```promql
rpi_temperature_celsius
rpi_voltage_volts
rpi_throttled_now
```

**Jetson:**
```promql
jetson_cpu_temperature_celsius
jetson_gpu_temperature_celsius
jetson_power_watts
```

**x86:**
```promql
system_cpu_temperature_celsius
system_thermal_zone_celsius
system_fan_rpm
```

## Verification

### Check Metrics Are Being Collected

```bash
# Raspberry Pi
curl -s http://<node-ip>:9100/metrics | grep rpi_

# Jetson
curl -s http://<node-ip>:9100/metrics | grep jetson_

# x86
curl -s http://<node-ip>:9100/metrics | grep system_
```

### Check Prometheus Is Scraping

```bash
# Pi metrics
curl -s http://<prometheus>:9090/api/v1/query?query=rpi_temperature_celsius

# Jetson metrics
curl -s http://<prometheus>:9090/api/v1/query?query=jetson_cpu_temperature_celsius

# x86 metrics
curl -s http://<prometheus>:9090/api/v1/query?query=system_cpu_temperature_celsius
```

### Check Alert Rules Loaded

```bash
curl -s http://<prometheus>:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.name | contains("Pi"))'
```

### Test Alertmanager

```bash
curl -X POST http://<alertmanager>:9093/api/v1/alerts -d '[{
  "labels": {"alertname": "TestAlert", "severity": "warning"},
  "annotations": {"summary": "Test notification"}
}]'
```

## Troubleshooting

### Metrics Not Appearing

```bash
# Check the .prom file exists and has content
# Raspberry Pi
cat /var/lib/node_exporter/textfile_collector/pi_metrics.prom

# Jetson
cat /var/lib/node_exporter/textfile_collector/jetson_metrics.prom

# x86
cat /var/lib/node_exporter/textfile_collector/system_metrics.prom

# Check node_exporter logs
sudo journalctl -u node_exporter -f

# Check systemd timer status
sudo systemctl status system-metrics.timer
```

### Permission Errors

```bash
# Raspberry Pi - vcgencmd requires video group
sudo usermod -aG video $(whoami)

# Ensure textfile directory is readable
sudo chmod 755 /var/lib/node_exporter/textfile_collector
sudo chmod 644 /var/lib/node_exporter/textfile_collector/*.prom
```

### Jetson-Specific Issues

```bash
# Check thermal zones exist
ls /sys/devices/virtual/thermal/thermal_zone*/

# Check power monitoring (INA3221)
ls /sys/bus/i2c/drivers/ina3221/*/hwmon/

# Ensure bc is installed (required for calculations)
sudo apt-get install bc
```

### x86-Specific Issues

```bash
# Ensure lm-sensors is installed and configured
sudo apt-get install lm-sensors
sudo sensors-detect --auto

# Test sensors output
sensors

# Check hwmon devices
ls /sys/class/hwmon/
```

### Alerts Not Firing

- Check Prometheus targets are up: `http://<prometheus>:9090/targets`
- Verify alert rules loaded: `http://<prometheus>:9090/alerts`
- Check Alertmanager status: `http://<alertmanager>:9093/#/alerts`

## File Locations

| Path | Purpose |
|------|---------|
| `/opt/system-monitor/` | Installed metrics scripts |
| `/var/lib/node_exporter/textfile_collector/` | Prometheus textfile output |
| `/etc/systemd/system/system-metrics.*` | Systemd service and timer |
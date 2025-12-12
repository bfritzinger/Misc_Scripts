# Configuring Node Exporter for Textfile Collector

The textfile collector must be enabled in node_exporter for it to read the Pi metrics.
Follow the section that matches how you installed node_exporter.

---

## Option 1: Systemd Service (Most Common)

If you installed node_exporter via apt or manually with a systemd service:

```bash
# Find current node_exporter config
sudo systemctl cat node_exporter
```

### Method A: Override file (recommended)

```bash
sudo systemctl edit node_exporter
```

This opens an editor. Add these lines between the comments:

```ini
[Service]
ExecStart=
ExecStart=/usr/local/bin/node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile_collector
```

> **Note:** The empty `ExecStart=` line is required to clear the original command.

Save and exit, then:

```bash
sudo systemctl daemon-reload
sudo systemctl restart node_exporter
```

### Method B: Edit service file directly

```bash
# Find the service file
sudo systemctl status node_exporter | grep "Loaded:"
# Usually: /etc/systemd/system/node_exporter.service
#      or: /lib/systemd/system/node_exporter.service

# Edit it
sudo nano /etc/systemd/system/node_exporter.service
```

Find the `ExecStart` line and add the flag:

```ini
ExecStart=/usr/local/bin/node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile_collector
```

Then reload and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart node_exporter
```

---

## Option 2: Docker Container

If running node_exporter in Docker, add the volume mount and argument:

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

### Docker Compose

```yaml
node_exporter:
  image: prom/node-exporter:latest
  container_name: node_exporter
  network_mode: host
  pid: host
  volumes:
    - /:/host:ro,rslave
    - /var/lib/node_exporter/textfile_collector:/textfile:ro
  command:
    - '--path.rootfs=/host'
    - '--collector.textfile.directory=/textfile'
  restart: unless-stopped
```

Then recreate the container:

```bash
docker-compose up -d node_exporter
```

---

## Option 3: Kubernetes DaemonSet

Add the volume and argument to your DaemonSet spec:

```yaml
spec:
  containers:
    - name: node-exporter
      image: prom/node-exporter:latest
      args:
        - --collector.textfile.directory=/textfile
      volumeMounts:
        - name: textfile
          mountPath: /textfile
          readOnly: true
  volumes:
    - name: textfile
      hostPath:
        path: /var/lib/node_exporter/textfile_collector
        type: DirectoryOrCreate
```

---

## Verify It's Working

After restarting node_exporter:

```bash
# Check the metrics endpoint for Pi metrics
curl -s http://localhost:9100/metrics | grep rpi_

# Should output something like:
# rpi_temperature_celsius{host="pi-node1"} 45.3
# rpi_voltage_volts{host="pi-node1"} 1.2
# rpi_undervoltage_now{host="pi-node1"} 0
# ...
```

If you see the `rpi_*` metrics, you're all set.

### Troubleshooting

**No rpi_ metrics showing:**
```bash
# Check the .prom file exists and has content
cat /var/lib/node_exporter/textfile_collector/pi_metrics.prom

# Check node_exporter logs
sudo journalctl -u node_exporter -f
```

**Permission denied errors:**
```bash
# Ensure directory is readable
sudo chmod 755 /var/lib/node_exporter/textfile_collector
sudo chmod 644 /var/lib/node_exporter/textfile_collector/*.prom
```

**node_exporter binary in different location:**
```bash
# Find it
which node_exporter
# Update the ExecStart path accordingly
```

# Misc Scripts

A collection of utility scripts for various system administration and automation tasks.

## Scripts

| Script | Description | Documentation |
|--------|-------------|---------------|
| Cluster SSH Key Setup | Automates SSH key distribution across a cluster of nodes | [README](./cluster-ssh-key-setup/README.md) |
| Cluster System Update | Runs apt update/upgrade in parallel across cluster nodes | [README](./cluster-system-update/README.md) |
| Docker Image Update | Automates the process of updating a running Docker container | [README](./docker-container-update/README.md) |
| Cloudflare IP Logger | A reverse proxy that logs visitor IPs from Cloudflare Tunnel traffic | [README](./cloudflare-ip-logger/README.md) |
| Ollama Model Updater | Checks for updates to available models on ollama.ai and installs them automatically | [README](./ollama-updater/README.md) |
| Git Update | A bash script to interactively manage Git repositories across GitHub and GitLab with clone, fetch, and push operations—individually or in batch.| [README](./git-update/README.md) |
| Power & Temp Monitor | Monitor temperature, voltage, power, and throttling status on Raspberry Pi, Nvidia Jetson, and x86 systems using Prometheus and Alertmanager | [README](./pwr-temp-monitor/README.md) |
| Alias Distribute | Distributes bash aliases to all nodes listed in /etc/hosts | [README](./alias-dist/README.md) |
| Git Star Repo | A Python script that fetches all your GitHub starred repositories and generates a summary report with statistics and a full listing. | [README](./github-star-repos/README.md) | 
| Dot Files | Personal configuration files for setting up a new Linux system.| [README](./dotfiles/README.md) |
| Hung Connections | A utility for detecting and terminating hung network connections on Unix-based systems. Available in both Python and Bash | [README](./HungConnections/README.md) |
| Health Check | A single-file bash script that performs a comprehensive system health check and simultaneously exports every measured value to a **CSV** (for trend analysis) and a **JSON snapshot** (for tooling integration). Run it on a schedule and pipe the CSV into pandas, Grafana, Excel, or gnuplot to watch metrics evolve over time | [README](./HealthCheck/README.md) |
| Chown Throttled | A performance-conscious bash script for recursively changing file ownership across multiple directories on high-throughput systems. Designed to run safely alongside active workloads by controlling CPU and I/O priority, batching filesystem operations to avoid argument list limits, and skipping files that are already correctly owned | [README](./chown_throttled/README.md) |
| Linux Troubleshooting | A comprehensive, interactive shell script for diagnosing and troubleshooting x86_64 Linux servers. Covers 15 diagnostic modules ranging from hardware inventory and network connection analysis to Kubernetes cluster health and security auditing — all from a single script with no external dependencies beyond standard Linux tooling | [README](./LinuxTroubleshooting/README.md) |
| File Retention (Age Off) | A config-driven bash script for age-based file cleanup across multiple directories. Each directory can have its own retention policy, glob pattern, and recursion setting — all managed from a single config file without touching the script itself | [README](./File_retention/README.md) |
| Dir Sync | A lightweight Python script that compares two directories and copies only the changed or new files (deltas) from source to destination. No external dependencies — stdlib only | [README](./dirsync/README.md) |

## Quick Start

Each script lives in its own directory with dedicated documentation. Click the README link above for usage instructions.

```bash
# Clone the repo
git clone https://github.com/bfritzinger/Misc_Scripts.git
cd Misc_Scripts

# Navigate to the script you need
cd cluster-ssh-key-setup

# Review the README, then run
./cluster_sshKey_setup.sh
```

## Repository Structure

```
Misc_Scripts/
├── README.md
├── LICENSE
├── _template/
│   └── README.md
├── File_retention/
│   ├── README.md
│   ├── file_retention.conf
│   └── file_retention.sh
├── HealthCheck/
│   ├── README.md
│   ├── metrics-dashboard.html
│   └── system_health_check.sh
├── HungConnections/
│   ├── README.md
│   ├── hung_conn_dashboard.html
│   ├── hung_connection_killer.py
│   └── hung_connection_killer.sh
├── LinuxTroubleshooting/
│   ├── README.md
│   ├── linux_troubleshoot.sh
│   └── linux_troubleshoot_dashboard.html
├── alias-dist/
│   ├── README.md
│   └── alias-dist.sh
├── chown_throttled/
│   ├── README.md
│   └── chown_throttled.sh
├── cloudflare-ip-logger/
│   ├── README.md
│   ├── Dockerfile
│   ├── cf-log-parser.service
│   ├── cmd/
│   │   └── logparser/
│   │       └── main.go
│   ├── docker-compose.cloudflared.yml
│   ├── docker-compose.yml
│   ├── go.mod
│   ├── main.go
│   ├── proxy-config.json.example
│   └── run-with-logging.sh
├── cluster-ssh-key-setup/
│   ├── README.md
│   └── cluster-sshKey-setup.sh
├── cluster-system-update/
│   ├── README.md
│   └── update-sys.sh
├── dirsync/
│   ├── README.md
│   └── dirsync.py
├── docker-container-update/
│   ├── README.md
│   └── docker-container-update.sh
├── dotfiles/
│   ├── README.md
│   └── bootstrap.sh
├── git-update/
│   ├── README.md
│   └── git-update.sh
├── github-star-repos/
│   ├── README.md
│   └── github-stars.py
├── ollama-updater/
│   ├── README.md
│   └── ollama-updater.py
└── pwr-temp-monitor/
    ├── README.md
    ├── NODE_EXPORTER_SETUP.md
    ├── alertmanager.yml
    ├── deploy_to_nodes.sh
    ├── grafana-dashboard.json
    ├── jetson_metrics.sh
    ├── pi_alerts.yml
    ├── pi_metrics.sh
    ├── setup.sh
    └── x86_metrics.sh
```

## Adding New Scripts

1. Copy the `_template` directory and rename it:
   ```bash
   cp -r _template my-new-script
   ```

2. Add your script and update the README inside the new directory

3. Update this main README to include your new script in the table above

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

[Brian Fritzinger](https://github.com/bfritzinger)

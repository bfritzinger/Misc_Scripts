# Misc Scripts

A collection of utility scripts for various system administration and automation tasks.

## Scripts

| Script | Description | Documentation |
|--------|-------------|---------------|
| Cluster SSH Key Setup | Automates SSH key distribution across a cluster of nodes | [README](./cluster-ssh-key-setup/README.md) |
| Cluster System Update | Runs apt update/upgrade in parallel across cluster nodes | [README](./cluster-system-update/README.md) |
| Docker Image Update | Automates the process of updating a running Docker container | [README](./docker-container-update/README.md) |
| Cloudflare IP Logger | A reverse proxy that logs visitor IPs from Cloudflare Tunnel traffic | [README](./cloudflare_ip_logger/README.md) |
| Ollama Model Updater | Checks for updates to available models on ollama.ai and installs them automatically | [README](./ollama-updater/README.md) |
| Git Update | A bash script to interactively manage Git repositories across GitHub and GitLab with clone, fetch, and push operations—individually or in batch.| [README](./git-update/README.md) |
| Power & Temp Monitor | Monitor temperature, voltage, power, and throttling status on Raspberry Pi, Nvidia Jetson, and x86 systems using Prometheus and Alertmanager | [README](./pwr-temp-monitor/README.md) |
| Alias Distribute | Distributes bash aliases to all nodes listed in /etc/hosts | [README](./alias-dist/README.md) |

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
├── cluster-ssh-key-setup/
│   ├── README.md
│   └── cluster-sshKey-setup.sh
└── cluster-system-update/
    ├── README.md
    └── update-sys.sh
└── docker-container-update/
    ├── README.md
    └── docker-container-update.sh
└── cloudflare-ip-logger/
    ├── cmd
        ├── logparser
            ├── main.go
    ├── README.md
    └── cd-log-parser.service
    └── docker-compose.cloudflared.yml
    └── docker-compose.yml
    └── Dokerfile
    └── go.mod
    └── main.go
    └── proxy-config.json.example
    └── run-with-logging.sh
└── ollama-updater/
    ├── README.md
    └── ollama-updater.py
└── git-update/
    ├── README.md
    └── git-update.sh
└── pwr-tmp-monitor/
    ├── README.md
    └── setup.sh
    └── x86_metrics.sh
    └── jetson_metrics.sh
    └── pi_metrics.sh
    └── deploy_to_nodes.sh
    └── alertmananger.yml
    └── pi_alerts.yml
    └── grafana-dashboard.json
    └── NODE_EXPORTER_SETUP.md
└── alias-dist/
    ├── README.md
    └── alias-dist.sh
    


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

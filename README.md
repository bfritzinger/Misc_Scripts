# Misc Scripts

A collection of utility scripts for various system administration and automation tasks.

## Scripts

| Script | Description | Documentation |
|--------|-------------|---------------|
| Cluster SSH Key Setup | Automates SSH key distribution across a cluster of nodes | [README](./cluster-ssh-key-setup/README.md) |
| Cluster System Update | Runs apt update/upgrade in parallel across cluster nodes | [README](./cluster-system-update/README.md) |
| Docker Image Update | Automates the process of updating a running Docker container | [README](./docker_container_update/README.md) |

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
│   └── cluster_sshKey_setup.sh
└── cluster-system-update/
    ├── README.md
    └── update_sys.sh
└── docker_container_update/
    ├── README.md
    └── docker_container_update.sh

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

Brian Fritzinger - [JBIK Security Solutions, LLC](https://github.com/bfritzinger)
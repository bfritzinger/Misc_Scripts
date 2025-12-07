# Docker Container Update

A bash script to update a running Docker container to the latest image while preserving its original run configuration.

## Overview

This script automates the process of updating a Docker container by:

1. Capturing the original `docker run` command
2. Pulling the latest image
3. Stopping and removing the old container
4. Recreating it with the same configuration

## Prerequisites

- Docker installed and running
- The container must be running (to inspect its configuration)
- Internet access to pull images

## Dependencies

This script uses [runlike](https://github.com/lavie/runlike) to capture the original run command:

```bash
docker pull assaflavie/runlike
```

## Usage

```bash
chmod +x docker_update.sh
./docker_update.sh <container_name>
```

### Example

```bash
./docker_update.sh portainer
```

## Example Output

```
==> Backing up run command for portainer...
==> Pulling latest image: portainer/portainer-ce:latest...
latest: Pulling from portainer/portainer-ce
Digest: sha256:abc123...
Status: Image is up to date for portainer/portainer-ce:latest
==> Stopping and removing portainer...
portainer
portainer
==> Recreating container...
a1b2c3d4e5f6...
==> Done! New container status:
NAMES       IMAGE                        STATUS
portainer   portainer/portainer-ce:latest   Up 2 seconds
```

## How It Works

1. **Capture config**: Uses `runlike` to reverse-engineer the `docker run` command from the running container
2. **Pull image**: Fetches the latest version of the container's image
3. **Replace container**: Stops, removes, and recreates with identical settings
4. **Verify**: Displays the new container status

## Notes

- Volumes are preserved (data persists if mounted correctly)
- Network settings, environment variables, and port mappings are retained
- The container name stays the same

## Limitations

- Container must be running to capture its configuration
- Does not handle Docker Compose managed containers (use `docker compose pull && docker compose up -d` instead)
- If `runlike` fails to capture certain options, manual intervention may be needed

## Troubleshooting

**"No such container" error:**
- Verify the container name: `docker ps`

**Container won't start after update:**
- Check logs: `docker logs <container_name>`
- The new image may have breaking changes

**Lost configuration:**
- The `runlike` tool captures most settings, but exotic options may be missed
- Consider using Docker Compose for complex containers

## Changelog

- **v1.0** - Initial release

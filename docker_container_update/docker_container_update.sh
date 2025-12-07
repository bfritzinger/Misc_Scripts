#!/bin/bash

# Usage: ./docker-update.sh <container_name>

CONTAINER=$1

if [ -z "$CONTAINER" ]; then
    echo "Usage: $0 <container_name>"
    exit 1
fi

# Get the image name from running container
IMAGE=$(docker inspect --format='{{.Config.Image}}' "$CONTAINER")

echo "==> Backing up run command for $CONTAINER..."
RUN_CMD=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock assaflavie/runlike "$CONTAINER")

echo "==> Pulling latest image: $IMAGE..."
docker pull "$IMAGE"

echo "==> Stopping and removing $CONTAINER..."
docker stop "$CONTAINER" && docker rm "$CONTAINER"

echo "==> Recreating container..."
eval "$RUN_CMD"

echo "==> Done! New container status:"
docker ps --filter "name=$CONTAINER" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
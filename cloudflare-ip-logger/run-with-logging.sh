#!/bin/bash
# run-with-logging.sh
# Runs cloudflared and pipes logs to the parser
#
# Usage: ./run-with-logging.sh
#
# This script runs cloudflared and pipes its output to cf-log-parser
# Both stdout and stderr are captured

DATA_DIR="${DATA_DIR:-./data/cf-ip-logger}"
CONFIG_FILE="${CONFIG_FILE:-./cloudflared/config.yml}"
DB_PATH="${DATA_DIR}/connections.db"

# Ensure data directory exists
mkdir -p "$DATA_DIR"

echo "Starting cloudflared with log parsing..."
echo "Config: $CONFIG_FILE"
echo "Database: $DB_PATH"

# Run cloudflared and pipe to log parser
# Using tee to also show logs in terminal
cloudflared tunnel --config "$CONFIG_FILE" --loglevel info run 2>&1 | \
    tee /dev/stderr | \
    ./cf-log-parser -db "$DB_PATH" -verbose

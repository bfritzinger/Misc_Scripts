#!/bin/bash
#

NODES=(
        "node"
        "node-1"
        "node-2"
        "node-3"
)

USER="<USER_NAME>"
LOGDIR="/tmp/cluster-update-$$"
mkdir -p "$LOGDIR"

for node in "${NODES[@]}"; do
    (
        echo "Starting update on $node..."
        if ssh ${USER}@${node} "sudo apt update && sudo apt upgrade -y" > "$LOGDIR/${node}.log" 2>&1; then
            echo "$node complete."
            echo "$node" >> "$LOGDIR/success"
        else
            echo "$node FAILED! Check $LOGDIR/${node}.log"
            echo "$node" >> "$LOGDIR/failed"
        fi
    ) &
done

wait

echo ""
echo "========== SUMMARY =========="
echo "Succeeded: $(cat "$LOGDIR/success" 2>/dev/null | wc -l)"
echo "Failed:    $(cat "$LOGDIR/failed" 2>/dev/null | wc -l)"

if [ -f "$LOGDIR/failed" ]; then
    echo ""
    echo "Failed nodes:"
    cat "$LOGDIR/failed"
    echo ""
    echo "Logs saved in: $LOGDIR"
fi
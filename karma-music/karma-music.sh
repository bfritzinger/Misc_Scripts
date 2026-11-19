#!/bin/bash
# karma-music.sh — Auto-start dog music with stream/local fallback
# Generic Linux version (no Pi-specific dependencies)

LOG_TAG="karma-music"
STREAM_PLAYLIST="streams"
MUSIC_DIR="/nas/_AUDIO/karma"
MAX_RETRIES=30
RETRY_DELAY=2
HEALTH_CHECK_INTERVAL=300  # 5 minutes

log() { logger -t "$LOG_TAG" "$1"; echo "$(date): $1"; }

# --- Wait for MPD ---
log "Waiting for MPD..."
for i in $(seq 1 $MAX_RETRIES); do
  if mpc status &>/dev/null; then
    log "MPD is ready."
    break
  fi
  if [ "$i" -eq "$MAX_RETRIES" ]; then
    log "ERROR: MPD not responding after ${MAX_RETRIES} attempts. Exiting."
    exit 1
  fi
  sleep $RETRY_DELAY
done

# --- Set playback options ---
mpc repeat on
mpc single off
mpc volume 70

# --- Try streaming first ---
start_stream() {
  log "Attempting to start SomaFM stream..."
  mpc clear
  mpc load "$STREAM_PLAYLIST" 2>/dev/null

  if [ $? -eq 0 ] && [ "$(mpc playlist | wc -l)" -gt 0 ]; then
    mpc play
    sleep 5

    if mpc status | grep -q '\[playing\]'; then
      log "Stream is playing successfully."
      return 0
    fi
  fi

  log "Stream failed to start."
  return 1
}

# --- Fallback to local files ---
start_local() {
  log "Falling back to local files..."
  mpc clear
  mpc update --wait 2>/dev/null
  mpc ls | mpc add
  mpc shuffle
  mpc play

  sleep 3
  if mpc status | grep -q '\[playing\]'; then
    log "Local playback started."
    return 0
  fi

  log "ERROR: Local playback also failed."
  return 1
}

# --- Main logic ---
if ! start_stream; then
  if ! start_local; then
    log "CRITICAL: No music source available. Check network and NAS."
    exit 1
  fi
fi

# --- Health check loop ---
log "Entering health check loop (every ${HEALTH_CHECK_INTERVAL}s)..."
LAST_ELAPSED=""
while true; do
  sleep "$HEALTH_CHECK_INTERVAL"

  CURRENT_STATUS=$(mpc status 2>/dev/null)

  if ! echo "$CURRENT_STATUS" | grep -q '\[playing\]'; then
    log "Playback stopped. Attempting recovery..."
    if ! start_stream; then
      start_local
    fi
    LAST_ELAPSED=""
  else
    # Detect stale streams (elapsed time frozen between checks)
    CURRENT_ELAPSED=$(echo "$CURRENT_STATUS" | grep -oP '#\d+/\d+\s+\K[\d:]+' 2>/dev/null)
    if [ -n "$CURRENT_ELAPSED" ] && [ "$CURRENT_ELAPSED" = "$LAST_ELAPSED" ]; then
      log "Playback appears stalled (elapsed stuck at ${CURRENT_ELAPSED}). Restarting..."
      mpc stop
      sleep 2
      if ! start_stream; then
        start_local
      fi
      LAST_ELAPSED=""
    else
      LAST_ELAPSED="$CURRENT_ELAPSED"
    fi
  fi
done

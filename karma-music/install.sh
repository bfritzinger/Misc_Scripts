#!/bin/bash
# install.sh — Deploy Karma Music Player
# Run with sudo: sudo ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MUSIC_DIR="/mnt/nas/music/dog-calm"

echo "=== Karma Music Player — Installer ==="
echo ""

# --- Check root ---
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Run with sudo: sudo ./install.sh"
  exit 1
fi

# --- Install dependencies ---
echo "[1/6] Installing packages..."
apt update -qq
apt install -y mpd mpc alsa-utils cifs-utils

# yt-dlp — prefer pip for latest version
if ! command -v yt-dlp &>/dev/null; then
  echo "       Installing yt-dlp via pip..."
  apt install -y python3-pip
  pip3 install --break-system-packages yt-dlp
else
  echo "       yt-dlp already installed: $(yt-dlp --version)"
fi

# --- Create music directory ---
echo "[2/6] Setting up music directory..."
mkdir -p "$MUSIC_DIR"

# --- Deploy MPD config ---
echo "[3/6] Deploying MPD config..."
cp "${SCRIPT_DIR}/mpd.conf" /etc/mpd.conf
chown -R mpd:audio /var/lib/mpd/

# --- Deploy streams playlist ---
echo "[4/6] Deploying stream playlist..."
cp "${SCRIPT_DIR}/streams.m3u" /var/lib/mpd/playlists/streams.m3u
chown mpd:audio /var/lib/mpd/playlists/streams.m3u

# --- Deploy scripts ---
echo "[5/6] Deploying scripts..."
cp "${SCRIPT_DIR}/karma-music.sh" /usr/local/bin/karma-music.sh
chmod +x /usr/local/bin/karma-music.sh

cp "${SCRIPT_DIR}/seed-karma-music.sh" /usr/local/bin/seed-karma-music.sh
chmod +x /usr/local/bin/seed-karma-music.sh

# --- Deploy and enable systemd service ---
echo "[6/6] Deploying systemd service..."
cp "${SCRIPT_DIR}/karma-music.service" /etc/systemd/system/karma-music.service
systemctl daemon-reload
systemctl enable mpd.service
systemctl restart mpd.service

echo ""
echo "=== Installation complete ==="
echo ""
echo "Next steps:"
echo "  1. Verify audio output:  speaker-test -t wav -c 2"
echo "  2. If using ALSA instead of PulseAudio, edit /etc/mpd.conf"
echo "  3. Seed backup music:    sudo seed-karma-music.sh"
echo "  4. Start the service:    sudo systemctl start karma-music.service"
echo "  5. Check status:         sudo systemctl status karma-music.service"
echo "  6. View logs:            journalctl -u karma-music.service -f"
echo ""
echo "Quick test (manual):"
echo "  mpc clear && mpc load streams && mpc play && mpc status"
echo ""

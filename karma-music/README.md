# Karma Music Player

Headless auto-playing music station for calming dog music. Streams SomaFM internet
radio by default, falls back to local files on NAS if internet drops. Auto-recovers
from stale streams and playback failures.

## What's in the box

```
karma-music-pkg/
├── install.sh              # Installs everything (run with sudo)
├── karma-music.sh          # Main player script with health check
├── karma-music.service     # systemd unit (User=brian)
├── mpd.conf                # MPD config (PulseAudio default, ALSA commented)
├── streams.m3u             # SomaFM stream URLs
├── seed-karma-music.sh     # Downloads backup tracks via yt-dlp
└── README.md               # This file
```

## Install

```bash
tar xzf karma-music-pkg.tar.gz
cd karma-music-pkg
sudo ./install.sh
```

## Post-install

```bash
# Test audio
speaker-test -t wav -c 2

# Seed backup tracks to NAS
sudo seed-karma-music.sh

# Start the service
sudo systemctl start karma-music.service

# Verify
sudo systemctl status karma-music.service
journalctl -u karma-music.service -f
```

## Controls

```bash
mpc status          # What's playing
mpc pause / play    # Pause / resume
mpc next            # Skip stream/track
mpc volume 60       # Set volume (0-100)
```

## Config notes

- **Audio output**: defaults to PulseAudio. If the host uses raw ALSA,
  edit `/etc/mpd.conf` — ALSA block is commented out and ready to swap.
- **Music directory**: `/mnt/nas/music/dog-calm` — adjust in `mpd.conf`
  and `karma-music.sh` if your NAS path differs.
- **User**: service runs as `brian` — change in `karma-music.service` if needed.

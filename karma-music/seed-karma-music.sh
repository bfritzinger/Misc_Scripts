#!/bin/bash
# seed-karma-music.sh — Download calming dog music to NAS for offline fallback

DEST="/nas/_AUDIO/karma"

if [ ! -d "$DEST" ]; then
  echo "ERROR: Music directory ${DEST} does not exist. Create it or check NAS mount."
  exit 1
fi

QUERIES=(
  "ytsearch3:calming music for dogs 8 hours"
  "ytsearch3:relaxing dog music separation anxiety"
  "ytsearch2:calm piano music for pets"
)

for QUERY in "${QUERIES[@]}"; do
  echo "Searching: ${QUERY}"
  yt-dlp \
    --extract-audio \
    --audio-format mp3 \
    --audio-quality 3 \
    --output "${DEST}/%(title)s.%(ext)s" \
    --no-playlist \
    --max-filesize 500M \
    --restrict-filenames \
    "$QUERY"
done

echo ""
echo "Done. Files in ${DEST}:"
ls -lh "$DEST"

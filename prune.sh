#!/bin/bash
# Delete recordings older than the retention window, then enforce the size cap.
set -euo pipefail
OUTPUT_DIR="${MIRROR_DIR:-$HOME/Documents/SecurityCam}"
RETENTION_DAYS="${MIRROR_RETENTION_DAYS:-3}"
MAX_GB="${MIRROR_MAX_GB:-0}"   # cap total folder size in GB (0 = unlimited)

# Time-based prune.
find "$OUTPUT_DIR" -type f -name 'cam_*.mp4' -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null || true

# Size-based prune: drop oldest clips until under MAX_GB (GiB). 0 = unlimited.
cap_bytes=$(awk -v gb="$MAX_GB" 'BEGIN { printf "%.0f", gb * 1024 * 1024 * 1024 }')
if [ "${cap_bytes:-0}" -gt 0 ]; then
  while :; do
    total=$(find "$OUTPUT_DIR" -type f -name 'cam_*.mp4' -print0 2>/dev/null \
            | xargs -0 stat -f '%z' 2>/dev/null | awk '{ s += $1 } END { print s + 0 }')
    [ "${total:-0}" -le "$cap_bytes" ] && break
    count=$(find "$OUTPUT_DIR" -type f -name 'cam_*.mp4' 2>/dev/null | wc -l | tr -d ' ')
    [ "${count:-0}" -le 1 ] && break        # never delete the only/active clip
    oldest=$(ls -tr "$OUTPUT_DIR"/cam_*.mp4 2>/dev/null | head -1)
    [ -z "$oldest" ] && break
    rm -f "$oldest" 2>/dev/null || break
  done
fi

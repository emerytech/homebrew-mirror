#!/bin/bash
# Show whether mirror is recording, plus disk usage and latest clip.
set -euo pipefail

OUTPUT_DIR="${MIRROR_DIR:-$HOME/Documents/SecurityCam}"

# Is the recorder process alive?
if pgrep -f 'mirror-record' >/dev/null || pgrep -f 'mirror/record.sh' >/dev/null || pgrep -f 'cam_%Y' >/dev/null; then
  echo "status   : RECORDING"
else
  echo "status   : not running"
fi

# Is the LaunchAgent loaded?
if launchctl print "gui/$(id -u)/com.temery.mirror" >/dev/null 2>&1; then
  echo "service  : installed (auto-starts at login)"
else
  echo "service  : not installed"
fi

echo "folder   : $OUTPUT_DIR"

if [ -d "$OUTPUT_DIR" ]; then
  count=$(find "$OUTPUT_DIR" -type f -name 'cam_*.mp4' | wc -l | tr -d ' ')
  size=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)
  echo "clips    : $count file(s), $size total"
  latest=$(ls -t "$OUTPUT_DIR"/cam_*.mp4 2>/dev/null | head -1 || true)
  if [ -n "${latest:-}" ]; then
    echo "latest   : $(basename "$latest") ($(date -r "$latest" '+%Y-%m-%d %H:%M:%S'))"
  fi
else
  echo "clips    : (folder does not exist yet)"
fi

# Free space on the recordings volume.
echo "disk     : $(df -h "$OUTPUT_DIR" 2>/dev/null | awk 'NR==2{print $4" free of "$2}')"

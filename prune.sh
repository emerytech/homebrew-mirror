#!/bin/bash
# Delete recordings older than the retention window.
set -euo pipefail
OUTPUT_DIR="${MIRROR_DIR:-$HOME/Documents/SecurityCam}"
RETENTION_DAYS="${MIRROR_RETENTION_DAYS:-3}"
find "$OUTPUT_DIR" -type f -name 'cam_*.mp4' -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null || true

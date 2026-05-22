#!/bin/bash
# Stop and remove the mirror LaunchAgents. Recordings are left in place.
set -euo pipefail

AGENTS="$HOME/Library/LaunchAgents"

for label in com.temery.mirror com.temery.mirror.prune; do
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  rm -f "$AGENTS/$label.plist"
  echo "removed $label"
done

# Make sure no recorder is left running.
pkill -f 'mirror-record' 2>/dev/null || true
pkill -f 'mirror/record.sh' 2>/dev/null || true
pkill -f 'cam_%Y' 2>/dev/null || true
echo "mirror uninstalled. Your recordings in Documents/SecurityCam are untouched."

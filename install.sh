#!/bin/bash
# Install the mirror LaunchAgents so recording starts at login.
#
# This generates the LaunchAgent plists from wherever the scripts actually
# live, so it works both from a source checkout and from a Homebrew install.
#
# If you installed via Homebrew, prefer:  brew services start mirror
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
AGENTS="$HOME/Library/LaunchAgents"
mkdir -p "$AGENTS"

# Resolve the record/prune scripts: prefer Homebrew shims on PATH, else the
# scripts sitting next to this installer.
RECORD="$(command -v mirror-record || echo "$HERE/record.sh")"
PRUNE="$(command -v mirror-prune || echo "$HERE/prune.sh")"
LOGDIR="$HOME/Library/Logs"
mkdir -p "$LOGDIR"

write_plist() {
  local label="$1" program="$2" log="$3" extra="$4"
  cat > "$AGENTS/$label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$program</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
$extra
    <key>StandardOutPath</key>
    <string>$log</string>
    <key>StandardErrorPath</key>
    <string>$log</string>
</dict>
</plist>
PLIST
}

write_plist com.temery.mirror "$RECORD" "$LOGDIR/mirror.log" \
"    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>15</integer>"

write_plist com.temery.mirror.prune "$PRUNE" "$LOGDIR/mirror-prune.log" \
"    <key>StartInterval</key>
    <integer>21600</integer>"

for label in com.temery.mirror com.temery.mirror.prune; do
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$AGENTS/$label.plist"
  echo "loaded $label"
done

echo
echo "mirror installed. Recording at: ${MIRROR_DIR:-$HOME/Documents/SecurityCam}"
echo "Logs: $LOGDIR/mirror.log"

#!/bin/bash
#
# mirror: continuous security-camera recorder.
# Captures the built-in camera + mic and writes rolling MP4 segments.
#
# NOTE: The green camera light is a hardware feature and CANNOT be disabled.
# It will be lit the entire time this is recording.

set -euo pipefail

# ---- Config (override via environment) ---------------------------------
VIDEO_DEVICE="${MIRROR_VIDEO:-FaceTime HD Camera}"
AUDIO_DEVICE="${MIRROR_AUDIO:-MacBook Pro Microphone}"
OUTPUT_DIR="${MIRROR_DIR:-$HOME/Documents/SecurityCam}"
SEGMENT_SECONDS="${MIRROR_SEGMENT:-600}"   # 600 = 10 minutes
FRAMERATE="${MIRROR_FPS:-30}"
RETENTION_DAYS="${MIRROR_RETENTION_DAYS:-3}"
BITRATE="${MIRROR_BITRATE:-4000k}"          # video bitrate for hardware encoder
MAX_GB="${MIRROR_MAX_GB:-0}"                # cap total folder size in GB (0 = unlimited)
# ------------------------------------------------------------------------

FFMPEG="$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)"

mkdir -p "$OUTPUT_DIR"

# Prune recordings older than RETENTION_DAYS before we start a fresh run.
prune() {
  find "$OUTPUT_DIR" -type f -name 'cam_*.mp4' -mtime "+${RETENTION_DAYS}" -print -delete 2>/dev/null || true
}

# Enforce the size cap: while the folder's clips exceed MAX_GB, delete the
# oldest clip. Never deletes the only remaining file (it's the one ffmpeg is
# currently writing). MAX_GB=0 disables the cap. GB here means GiB (1024^3).
prune_size() {
  local cap_bytes
  cap_bytes=$(awk -v gb="$MAX_GB" 'BEGIN { printf "%.0f", gb * 1024 * 1024 * 1024 }')
  [ "${cap_bytes:-0}" -le 0 ] && return 0   # 0 (or invalid) => unlimited
  while :; do
    local total count oldest
    total=$(find "$OUTPUT_DIR" -type f -name 'cam_*.mp4' -print0 2>/dev/null \
            | xargs -0 stat -f '%z' 2>/dev/null | awk '{ s += $1 } END { print s + 0 }')
    [ "${total:-0}" -le "$cap_bytes" ] && break
    count=$(find "$OUTPUT_DIR" -type f -name 'cam_*.mp4' 2>/dev/null | wc -l | tr -d ' ')
    [ "${count:-0}" -le 1 ] && break        # keep the actively-recording file
    oldest=$(ls -tr "$OUTPUT_DIR"/cam_*.mp4 2>/dev/null | head -1)
    [ -z "$oldest" ] && break
    rm -f "$oldest" 2>/dev/null || break
  done
}

prune
prune_size

echo "$(date '+%Y-%m-%d %H:%M:%S') mirror starting"
echo "  video : $VIDEO_DEVICE"
echo "  out   : $OUTPUT_DIR (segments of ${SEGMENT_SECONDS}s, keep ${RETENTION_DAYS}d, max ${MAX_GB}GB)"

# Build the input spec. An empty AUDIO_DEVICE means video-only.
if [ -n "$AUDIO_DEVICE" ]; then
  INPUT="${VIDEO_DEVICE}:${AUDIO_DEVICE}"
  AUDIO_ARGS=(-c:a aac -b:a 128k)
  echo "  audio : $AUDIO_DEVICE"
else
  INPUT="${VIDEO_DEVICE}"
  AUDIO_ARGS=(-an)
  echo "  audio : (disabled)"
fi

# -force_key_frames guarantees a keyframe at each segment boundary so cuts
# are exactly SEGMENT_SECONDS apart. strftime names files by start time.
# Run ffmpeg in the background so we can supervise it and guarantee the
# camera is released no matter how this script (or its launcher) dies.
"$FFMPEG" -hide_banner -nostdin -loglevel warning \
  -f avfoundation -framerate "$FRAMERATE" \
  -i "$INPUT" \
  -c:v h264_videotoolbox -b:v "$BITRATE" -pix_fmt yuv420p \
  -force_key_frames "expr:gte(t,n_forced*${SEGMENT_SECONDS})" \
  "${AUDIO_ARGS[@]}" \
  -f segment -segment_time "$SEGMENT_SECONDS" -reset_timestamps 1 -strftime 1 \
  "${OUTPUT_DIR}/cam_%Y-%m-%d_%H-%M-%S.mp4" &
FFPID=$!

# Always stop ffmpeg (release the camera) when we exit for any reason.
cleanup() {
  kill -TERM "$FFPID" 2>/dev/null || true
  wait "$FFPID" 2>/dev/null || true
}
trap cleanup TERM INT EXIT

# Watchdog: if the launching app (e.g. the Mirror menu bar app) disappears
# without cleanly stopping us, detect it and shut the camera down.
WATCH_PID="${MIRROR_PID:-0}"
loops=0
while kill -0 "$FFPID" 2>/dev/null; do
  if [ "$WATCH_PID" != "0" ] && ! kill -0 "$WATCH_PID" 2>/dev/null; then
    break   # launcher is gone -> trap cleanup will kill ffmpeg
  fi
  loops=$((loops + 1))
  if [ $((loops % 15)) -eq 0 ]; then   # ~every 30s: keep the folder under the cap
    prune_size
  fi
  sleep 2
done

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
# ------------------------------------------------------------------------

FFMPEG="$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)"

mkdir -p "$OUTPUT_DIR"

# Prune recordings older than RETENTION_DAYS before we start a fresh run.
prune() {
  find "$OUTPUT_DIR" -type f -name 'cam_*.mp4' -mtime "+${RETENTION_DAYS}" -print -delete 2>/dev/null || true
}
prune

echo "$(date '+%Y-%m-%d %H:%M:%S') mirror starting"
echo "  video : $VIDEO_DEVICE"
echo "  out   : $OUTPUT_DIR (segments of ${SEGMENT_SECONDS}s, keep ${RETENTION_DAYS}d)"

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
while kill -0 "$FFPID" 2>/dev/null; do
  if [ "$WATCH_PID" != "0" ] && ! kill -0 "$WATCH_PID" 2>/dev/null; then
    break   # launcher is gone -> trap cleanup will kill ffmpeg
  fi
  sleep 2
done

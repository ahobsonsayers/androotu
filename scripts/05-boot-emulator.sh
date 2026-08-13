#!/usr/bin/env bash
# Boot emulator headless (cold boot). Use WIPE_DATA=1 for clean first boot.
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$AH/platform-tools/adb"
EMU="$AH/emulator/emulator"
AVD="${AVD:-rooted33}"
API="${API:-33}"

"$ADB" emu kill 2>/dev/null || true
sleep 1
AVD_DIR="$HOME/.android/avd/$AVD.avd"
rm -f "$AVD_DIR"/*.lock 2>/dev/null || true

# ponytail: `-read-only` uses a read-only overlay that discards userdata writes
# on shutdown — fine for multi-instance safety, but it wipes Magisk's Direct
# Install, shell su grant, and any installed modules across reboots. Opt in
# with READ_ONLY=1; default is a writable cold boot that persists userdata.
EXTRA=""
[ "${READ_ONLY:-0}" = "1" ] && EXTRA="-read-only"
[ "${WIPE_DATA:-0}" = "1" ] && EXTRA="-wipe-data"

# Optional custom kernel: KERNEL=/path/to/bzImage
# Optional custom ramdisk: RAMDISK=/path/to/ramdisk.img (defaults to system-image ramdisk)
# Optional kernel cmdline: KERNEL_CMDLINE="..." (requires KERNEL)
# Optional SHOW_KERNEL=1 to see kernel boot messages (for debugging)
KERNEL_ARGS=""
if [ -n "${KERNEL:-}" ]; then
  KERNEL_ARGS="-kernel $KERNEL"
  RAMDISK_FILE="${RAMDISK:-$AH/system-images/android-$API/google_apis_playstore/x86_64/ramdisk.img}"
  KERNEL_ARGS="$KERNEL_ARGS -ramdisk $RAMDISK_FILE"
  [ -n "${KERNEL_CMDLINE:-}" ] && KERNEL_ARGS="$KERNEL_ARGS -qemu -append $KERNEL_CMDLINE"
  [ "${SHOW_KERNEL:-0}" = "1" ] && KERNEL_ARGS="$KERNEL_ARGS -show-kernel"
  echo "Boot with custom kernel: $KERNEL"
  echo "Boot with ramdisk: $RAMDISK_FILE"
fi

GPU_MODE="${GPU:-off}"
QEMU_ARGS=""
if [ -n "${KERNEL_CMDLINE:-}" ]; then
  QEMU_ARGS="-qemu -append $KERNEL_CMDLINE"
  KERNEL_ARGS="${KERNEL_ARGS%% -qemu*}"
fi
LOG_FILE="${EMU_LOG:-/tmp/emulator.log}"
# Keep only the last run: rotate the previous log, cap growth at ~50MB via head-crop
if [ -f "$LOG_FILE" ]; then
  mv -f "$LOG_FILE" "$LOG_FILE.old" 2>/dev/null || true
fi
setsid nohup "$EMU" -avd "$AVD" -no-window -no-audio -no-snapshot \
  -memory 1536 -no-boot-anim -gpu "$GPU_MODE" $EXTRA $KERNEL_ARGS $QEMU_ARGS \
  > "$LOG_FILE" 2>&1 < /dev/null &
( while [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)" -gt 52428800 ]; do
    truncate -s 52428800 "$LOG_FILE" 2>/dev/null || break; sleep 300
  done ) &

"$ADB" wait-for-device
for i in $(seq 1 120); do
  BC=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
  [ "$BC" = "1" ] && { echo "Boot complete ($i polls)."; exit 0; }
  sleep 3
done
echo "FAIL: boot timeout (360s)" >&2; exit 1
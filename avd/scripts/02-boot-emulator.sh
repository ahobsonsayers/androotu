#!/usr/bin/env bash
# Boot the a36 emulator headless with the custom KSU/SUSFS kernel.
# Use WIPE_DATA=1 for a clean first boot.
# Docker: set FOREGROUND=1, DATA_IMG, SKIP_ADB_AUTH=1, WAIT_FOR_INI=1.
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$AH/platform-tools/adb"
EMU="$AH/emulator/emulator"
AVD="${AVD:-a36}"
API="${API:-36}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_KERNEL="$ROOT/kernel/dist/bzImage-a36-btf"

# Docker: first-boot.sh creates the AVD; wait for it before launching.
if [ "${WAIT_FOR_INI:-0}" = "1" ]; then
  for _ in $(seq 1 60); do
    [ -f "/data/$AVD.ini" ] && break
    sleep 2
  done
  [ -f "/data/$AVD.ini" ] || {
    echo "ERROR: AVD $AVD not created after 120s" >&2
    exit 1
  }
fi

"$ADB" emu kill 2>/dev/null || true
sleep 1
AVD_DIR="${ANDROID_AVD_HOME:-$HOME/.android/avd}/$AVD.avd"
rm -f "$AVD_DIR"/*.lock 2>/dev/null || true

EXTRA=()
[ "${WIPE_DATA:-0}" = "1" ] && EXTRA=(-wipe-data)
[ -n "${DATA_IMG:-}" ] && EXTRA+=(-data "$DATA_IMG")
[ "${SKIP_ADB_AUTH:-0}" = "1" ] && EXTRA+=(-skip-adb-auth)

KERNEL="${KERNEL:-$DEFAULT_KERNEL}"
if [[ ! -f "$KERNEL" ]]; then
  echo "ERROR: kernel not found at $KERNEL. Build it first (see kernel/)." >&2
  exit 1
fi
RAMDISK_FILE="${RAMDISK:-$AH/system-images/android-$API/google_apis_playstore/x86_64/ramdisk.img}"
echo "Boot with custom kernel: $KERNEL"
echo "Boot with ramdisk: $RAMDISK_FILE"

GPU_MODE="${GPU:-off}"
LOG_FILE="${EMU_LOG:-/tmp/emulator.log}"
if [ -f "$LOG_FILE" ]; then
  mv -f "$LOG_FILE" "$LOG_FILE.old" 2>/dev/null || true
fi

ARGS=(-avd "$AVD" -no-window -no-audio -no-snapshot
  -memory 1536 -no-boot-anim -no-metrics -gpu "$GPU_MODE" "${EXTRA[@]}"
  -kernel "$KERNEL" -ramdisk "$RAMDISK_FILE"
  -feature -ModemSimulator)

# Docker: run in the foreground so supervisor can manage/restart it.
if [ "${FOREGROUND:-0}" = "1" ]; then
  exec "$EMU" "${ARGS[@]}"
fi

setsid nohup "$EMU" "${ARGS[@]}" >"$LOG_FILE" 2>&1 </dev/null &
(while [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)" -gt 52428800 ]; do
  truncate -s 52428800 "$LOG_FILE" 2>/dev/null || break
  sleep 300
done) &

for i in $(seq 1 60); do
  "$ADB" devices | grep -q "emulator-5554" && break
  sleep 2
done
if ! "$ADB" devices | grep -q "emulator-5554"; then
  echo "FAIL: emulator never registered with adb (120s) — check $LOG_FILE" >&2
  exit 1
fi
for i in $(seq 1 120); do
  BC=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n' || true)
  [ "$BC" = "1" ] && {
    echo "Boot complete ($i polls)."
    break
  }
  sleep 3
done
if [ "${BC:-}" != "1" ]; then
  echo "FAIL: boot timeout (360s)" >&2
  exit 1
fi
for i in $(seq 1 30); do
  "$ADB" shell true 2>/dev/null && {
    echo "ADB responsive."
    exit 0
  }
  sleep 2
done
echo "FAIL: adb shell not responsive after boot" >&2
exit 1

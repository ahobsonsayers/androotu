#!/usr/bin/env bash
# Boot emulator headless (cold boot). Use WIPE_DATA=1 for clean first boot.
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$AH/platform-tools/adb"
EMU="$AH/emulator/emulator"
AVD=rooted33

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

setsid nohup "$EMU" -avd "$AVD" -no-window -no-audio -no-snapshot \
  -memory 1536 -no-boot-anim -gpu off $EXTRA \
  > /tmp/emulator.log 2>&1 < /dev/null &

"$ADB" wait-for-device
for i in $(seq 1 120); do
  BC=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
  [ "$BC" = "1" ] && { echo "Boot complete ($i polls)."; exit 0; }
  sleep 3
done
echo "FAIL: boot timeout (360s)" >&2; exit 1
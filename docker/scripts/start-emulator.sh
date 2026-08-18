#!/usr/bin/env bash
# Boot the a36 AVD headless with the custom KSU/SUSFS kernel.
# Runs in the foreground so supervisor can manage/restart it.
set -euo pipefail

AH="${ANDROID_HOME:-/opt/android-sdk}"
ADB="$AH/platform-tools/adb"
EMU="$AH/emulator/emulator"
AVD="${AVD:-a36}"
API="${API:-36}"

# first-boot.sh creates the AVD; wait for it before launching the emulator.
for i in $(seq 1 60); do
  [ -f "/data/$AVD.ini" ] && break
  sleep 2
done
if [ ! -f "/data/$AVD.ini" ]; then
  echo "ERROR: AVD $AVD not created after 120s" >&2
  exit 1
fi

pkill -f "$EMU" 2>/dev/null || true
rm -f /data/$AVD.avd/*.lock 2>/dev/null || true

KERNEL="${KERNEL:-/opt/kernel/bzImage-a36-btf}"
if [[ ! -f "$KERNEL" ]]; then
  echo "ERROR: kernel not found at $KERNEL" >&2
  exit 1
fi
RAMDISK_FILE="$AH/system-images/android-$API/google_apis_playstore/x86_64/ramdisk.img"

# Forward the emulator's localhost ADB to eth0 so other containers (scrcpy-web)
# and the host can reach it on :5555.
LOCAL_IP=$(ip addr list eth0 2>/dev/null | grep "inet " | cut -d' ' -f6 | cut -d/ -f1)
if [ -n "$LOCAL_IP" ]; then
  socat tcp-listen:"5555",bind="$LOCAL_IP",fork tcp:127.0.0.1:"5555" &
fi

# Custom kernel is required for KSU/SUSFS root. Foreground so supervisor
# restarts it on crash. Boot headless, no snapshot. -data pins the data
# partition to a real file in /data (a volume), so user data persists across
# container restarts when the volume is mounted and stays ephemeral otherwise.
exec "$EMU" -avd "$AVD" -no-window -no-audio -no-snapshot \
  -memory 1536 -no-boot-anim -no-metrics -gpu off -skip-adb-auth \
  -data "/data/$AVD.avd/userdata-qemu.img" \
  -kernel "$KERNEL" -ramdisk "$RAMDISK_FILE"

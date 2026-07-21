#!/usr/bin/env bash
# Boot unrooted (wipe), patch ramdisk with Magisk via rootAVD.
set -euo pipefail

WIPE_DATA=1 "$(dirname "$0")/05-boot-emulator.sh"

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$AH/platform-tools/adb"
RD="${ROOTAVD_DIR:-$HOME/rootAVD}"

# Clean stale rootAVD workspace on device — a prior failed run can leave
# corrupt files that cause "ramdisk.img uses UNKNOWN compression" errors.
"$ADB" shell 'rm -rf /data/data/com.android.shell/Magisk' 2>/dev/null || true

cd "$RD"
chmod +x rootAVD.sh
echo 1 | ./rootAVD.sh system-images/android-33/google_apis_playstore/x86_64/ramdisk.img

echo "Waiting for emulator to shut down after patch..."
for i in $(seq 1 60); do
  "$ADB" get-state 2>/dev/null | grep -q device || { echo "Emulator shut down."; exit 0; }
  sleep 2
done
echo "WARN: emulator still online after 120s; rootAVD may not have shut it down."
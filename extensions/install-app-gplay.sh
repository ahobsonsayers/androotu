#!/usr/bin/env bash
# Install an app from the Play Store via gplaydl (anonymous Aurora dispenser).
# Runs on first boot after the stack is up, so adb is available.
set -euo pipefail

ADB="${ADB:-/opt/android-sdk/platform-tools/adb}"
PKG="gr.nikolasspyr.integritycheck"
DISPENSER="https://auroraoss.com/api/auth"
OUT="/tmp/gplaydl"

echo "Installing gplaydl"
python3 -m pip install --quiet gplaydl

echo "Downloading $PKG from Play Store"
gplaydl download "$PKG" -a arm64 -d "$DISPENSER" -o "$OUT"

echo "Installing $PKG"
for apk in "$OUT"/*.apk; do
  [ -e "$apk" ] || continue
  "$ADB" install -r "$apk"
done

echo "Rebooting so BetterKnownInstalled marks the app as Play Store-installed"
"$ADB" reboot
"$ADB" wait-for-device
# shellcheck disable=SC2016
"$ADB" shell 'timeout 360 sh -c '\''while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done'\'''

#!/usr/bin/env bash
# Install the bindhosts module (systemless hosts / ad blocking).
# Runs on first boot after the stack is up, so adb + su are available.
set -euo pipefail

ADB="${ADB:-/opt/android-sdk/platform-tools/adb}"
URL="https://github.com/bindhosts/bindhosts/releases/download/v2.1.4/bindhosts.zip"
ZIP="/tmp/bindhosts.zip"

echo "Downloading bindhosts"
curl -fsSL -o "$ZIP" "$URL"

echo "Installing bindhosts module"
"$ADB" push "$ZIP" /data/local/tmp/bindhosts.zip
"$ADB" shell su -c 'ksud module install /data/local/tmp/bindhosts.zip'

echo "Rebooting to activate the module"
"$ADB" reboot
"$ADB" wait-for-device
"$ADB" shell 'timeout 360 sh -c '\''while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done'\'''

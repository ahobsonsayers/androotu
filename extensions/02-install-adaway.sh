#!/usr/bin/env bash
# Demo extension: install the AdAway app (open-source ad blocker).
# Runs on first boot after the stack is up, so adb is available.
set -euo pipefail

ADB="${ADB:-/opt/android-sdk/platform-tools/adb}"
URL="https://github.com/AdAway/AdAway/releases/download/v6.1.4/AdAway-6.1.4-20241027.apk"
APK="/tmp/adaway.apk"

echo "Downloading AdAway"
curl -fsSL -o "$APK" "$URL"

echo "Installing AdAway"
"$ADB" install -r "$APK"

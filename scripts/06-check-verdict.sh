#!/usr/bin/env bash
# Install SPIC, run a Play Integrity request, and assert MEETS_DEVICE_INTEGRITY.
# Exits non-zero if the verdict is anything else (e.g. NO_INTEGRITY).
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$AH/platform-tools/adb"
SPIC_URL="https://github.com/herzhenr/spic-android/releases/download/v1.4.0/spic-v1.4.0.apk"
SPIC_APK="/tmp/spic.apk"
PKG="com.henrikherzig.playintegritychecker"

echo "==> Downloading SPIC"
curl -fsSL -o "$SPIC_APK" "$SPIC_URL"

echo "==> Installing SPIC"
"$ADB" install -r "$SPIC_APK"

echo "==> Launching SPIC"
"$ADB" shell am start -n "$PKG/.MainActivity"
sleep 10

# Dismiss the "System UI isn't responding" ANR dialog if it appears.
dump() { "$ADB" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; "$ADB" shell cat /sdcard/ui.xml 2>/dev/null; }

if dump | grep -q "System UI isn't responding"; then
  echo "==> Dismissing ANR dialog"
  "$ADB" shell input tap 540 1363
  sleep 4
fi

echo "==> Tapping Make Play Integrity Request"
"$ADB" shell input tap 574 900

# The verdict can take 30-60s in CI; poll until it renders.
VERDICT=""
for i in $(seq 1 30); do
  sleep 5
  UI=$(dump)
  VERDICT=$(echo "$UI" | grep -oE 'MEETS_[A-Z_]+|NO_INTEGRITY|UNEVALUATED' | head -1)
  [ -n "$VERDICT" ] && break
done

echo "$UI" | grep -oE 'text="[^"]*"' | sed 's/text="//;s/"$//' | grep -v '^$' | head -30
echo
echo "Verdict: ${VERDICT:-UNKNOWN}"

case "$VERDICT" in
  MEETS_DEVICE_INTEGRITY|MEETS_STRONG_INTEGRITY)
    echo "PASS: $VERDICT"
    exit 0
    ;;
  *)
    echo "FAIL: expected MEETS_DEVICE_INTEGRITY, got ${VERDICT:-UNKNOWN}" >&2
    exit 1
    ;;
esac

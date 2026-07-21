#!/usr/bin/env bash
# Check root access, Magisk version, Play Store + GMS.
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$AH/platform-tools/adb"
SERIAL="${ANDROID_SERIAL:-}"
ARGS=("$ADB")
[ -n "$SERIAL" ] && ARGS+=("-s" "$SERIAL")

echo "Checking root..."
R=$("${ARGS[@]}" shell su -c id 2>&1 || true)
echo "$R" | grep -q "uid=0(root)" && echo "PASS: rooted" || { echo "FAIL: not rooted ($R)"; exit 1; }

echo "Checking Magisk..."
M=$("${ARGS[@]}" shell magisk -v 2>&1 || true)
echo "$M" | grep -q MAGISK && echo "PASS: $M" || echo "WARN: $M"

echo "Checking Play Store + GMS..."
for p in com.android.vending com.google.android.gms; do
  "${ARGS[@]}" shell pm list packages 2>/dev/null | grep -q "$p" && echo "PASS: $p" || { echo "FAIL: $p missing"; exit 1; }
done
echo "All checks passed."
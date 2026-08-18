#!/usr/bin/env bash
# Verify the stack is healthy and the TEESimulator is in GENERATE mode.
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$AH/platform-tools/adb"
OK=1

# Nested `su root -c` is reliable on fresh AVDs. Commands must not contain single quotes.
suroot() {
  "$ADB" shell su -c "su root -c '$1'" 2>/dev/null
}

BC=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
if [ "$BC" = "1" ]; then
  echo "OK  boot completed"
else
  echo "FAIL boot not completed"
  OK=0
fi

MODS=$(suroot 'ls /data/adb/modules/playintegrityfix')
if [ -n "$MODS" ]; then
  echo "OK  Integrity Box module present"
else
  echo "FAIL Integrity Box module missing"
  OK=0
fi

if "$ADB" shell 'pm path com.google.android.gms >/dev/null 2>&1'; then
  echo "OK  GMS installed"
else
  echo "FAIL GMS not installed"
  OK=0
fi

PROP=$("$ADB" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r\n')
echo "OK  abi=$PROP"

PROVIDER=$(suroot 'grep "^spoofProvider=" /data/adb/modules/playintegrityfix/custom.pif.prop' | tr -d '\r\n')
echo "OK  $PROVIDER"

GEN=0
for _ in $(seq 1 20); do
  GEN=$(suroot "logcat -d | grep -c \"Generating new attested key pair for alias:\"" | tr -d '\r\n') || true
  [ "${GEN:-0}" -gt 0 ] 2>/dev/null && break
  sleep 3
done
PATCH=$(suroot "logcat -d | grep -c \"patched certificate chain for KeyIdentifier(uid=10146\"" | tr -d '\r\n') || true
if [ "${GEN:-0}" -gt 0 ] 2>/dev/null; then
  echo "OK  TEESimulator GENERATE mode (fresh chain per request)"
else
  echo "FAIL TEESimulator not generating — check keybox + reboot" >&2
  OK=0
fi
if [ "${PATCH:-0}" -gt 0 ] 2>/dev/null; then
  echo "WARN TEESimulator PATCH mode — reboot to restore GENERATE"
fi

if [ "$OK" = "1" ]; then
  echo
  echo "All checks passed. Verify the verdict with SPIC:"
  echo "  adb shell am start -n com.henrikherzig.playintegritychecker/.MainActivity"
  exit 0
fi
exit 1

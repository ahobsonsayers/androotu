#!/usr/bin/env bash
# Verify the stack is healthy and Tricky Store OSS keybox emulation is active.
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$AH/platform-tools/adb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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

TEE_STATUS=$(suroot 'cat /data/adb/tricky_store/tee_status.txt' 2>/dev/null || true)
if echo "$TEE_STATUS" | grep -q "tee_broken=true"; then
  echo "FAIL Tricky Store TEE broken (tee_status.txt tee_broken=true) — reboot" >&2
  OK=0
elif [ -s "$TEE_STATUS" ]; then
  echo "OK  Tricky Store TEE status not broken"
else
  echo "WARN tee_status.txt missing or empty — module may not have run"
fi

LOG=""
for _ in $(seq 1 20); do
  LOG=$(suroot 'logcat -d -s TrickyStoreOSS' 2>/dev/null || true)
  echo "$LOG" | grep -qiE "inject" && break
  sleep 3
done
if echo "$LOG" | grep -qiE "inject"; then
  echo "OK  Tricky Store injected into keystore"
else
  echo "FAIL Tricky Store not injected — check module + reboot" >&2
  OK=0
fi

KB_CHK="$TMP/kb.xml"
if suroot 'cat /data/adb/tricky_store/keybox.xml' >"$KB_CHK" 2>/dev/null && [ -s "$KB_CHK" ] && \
   bash "$SCRIPT_DIR/verify-keybox.sh" "$KB_CHK" >/dev/null 2>&1; then
  echo "OK  hardware-rooted keybox at /data/adb/tricky_store/keybox.xml"
else
  echo "FAIL keybox missing or not hardware-rooted at /data/adb/tricky_store/keybox.xml" >&2
  OK=0
fi

if echo "$LOG" | grep -qE "cert|chain|patch"; then
  echo "OK  Tricky Store patch chain active"
else
  echo "WARN Tricky Store logcat shows no cert/chain activity yet"
fi

if [ "$OK" = "1" ]; then
  echo
  echo "All checks passed. Verify the verdict with SPIC:"
  echo "  adb shell am start -n com.henrikherzig.playintegritychecker/.MainActivity"
  exit 0
fi
exit 1

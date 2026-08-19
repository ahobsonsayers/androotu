#!/usr/bin/env bash
# Configure Integrity Box: Supreme profile (Pixel 8 shiba CANARY) + the toggle combo that passes.
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$AH/platform-tools/adb"
MOD_DIR="/data/adb/modules/playintegrityfix"
BOX_DIR="/data/adb/Box-Brain"
PIF="$MOD_DIR/custom.pif.prop"

# Nested `su root -c` is reliable; plain `su -c` intermittently rejects /data/adb. No single quotes in args.
suroot() {
  for _ in 1 2 3 4 5; do
    if "$ADB" shell su -c "su root -c '$1'" 2>/dev/null; then return 0; fi
    sleep 3
  done
  echo "FAIL: su command not accepted after retries: $1" >&2
  return 1
}

suroot 'command -v ksud >/dev/null' ||
  {
    echo "FAIL: no root (ksud not found) — is the custom kernel booted?" >&2
    exit 1
  }

echo "Enabling Supreme profile"
PIF_SRC="${PIF_SRC:-$(dirname "${BASH_SOURCE[0]}")/../config/custom.pif.prop}"
"$ADB" push "$PIF_SRC" /data/local/tmp/custom.pif.prop
suroot "cp /data/local/tmp/custom.pif.prop $PIF && chmod 0644 $PIF"

echo "Writing canonical custom.pif.prop"
suroot "rm -f $BOX_DIR/pixelify $BOX_DIR/legacy $BOX_DIR/wipe && touch $BOX_DIR/advanced && chmod 0644 $BOX_DIR/advanced"

echo "Restarting GMS + Play Store so the spoof applies"
suroot 'am force-stop com.google.android.gms.unstable; am force-stop com.android.vending'

echo "Done. Run avd/scripts/05-verify-setup.sh to check the setup."

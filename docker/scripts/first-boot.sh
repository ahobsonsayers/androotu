#!/usr/bin/env bash
# One-time provisioning: create the AVD, install the module stack, configure
# the Supreme profile, and verify. Runs once per /data volume.
#
# This is a thin orchestrator over the shared avd/scripts — the single source
# of truth for what it takes to bring the emulator up. It only adds the
# docker-specific glue: env defaults and waiting for the emulator (a separate
# supervisor program) to boot.
set -euo pipefail

AH="${ANDROID_HOME:-/opt/android-sdk}"
ADB="$AH/platform-tools/adb"
AVD="${AVD:-a36}"
SCRIPTS="${SCRIPTS:-/root/scripts}"

export ANDROID_HOME="$AH"
export ANDROID_AVD_HOME=/data
export MODULES_DIR=/opt/modules
export PIF_SRC=/opt/modules/custom.pif.prop

wait_boot() {
  "$ADB" wait-for-device || true
  for i in $(seq 1 120); do
    BC=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n' || true)
    [ "$BC" = "1" ] && {
      echo "Boot complete ($i polls)."
      return 0
    }
    sleep 3
  done
  echo "FAIL: boot timeout" >&2
  exit 1
}

echo "Creating AVD $AVD"
bash "$SCRIPTS/01-create-avd.sh"

# The emulator program (supervisor) boots this AVD. Wait for it to come up.
echo "Waiting for emulator boot"
wait_boot

echo "Installing modules"
bash "$SCRIPTS/03-install-modules.sh"

echo "Configuring Supreme profile"
bash "$SCRIPTS/04-configure.sh"

echo "Verifying stack"
bash "$SCRIPTS/05-verify-integrity.sh"

touch /data/.first-boot-done
echo "Success !!"

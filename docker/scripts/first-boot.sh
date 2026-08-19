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
USER_SCRIPTS="${USER_SCRIPTS:-/opt/scripts}"

export ANDROID_HOME="$AH"
export ANDROID_AVD_HOME=/data
export MODULES_DIR=/root/modules
export PIF_SRC=/root/modules/custom.pif.prop

echo "Creating AVD $AVD"
bash "$SCRIPTS/01-create-avd.sh"

# The emulator program (supervisor) boots this AVD. Wait for it to come up.
# Poll getprop from the host so a transient adbd drop mid-boot can't kill us.
echo "Waiting for emulator boot"
for _ in $(seq 1 120); do
  BC=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n' || true)
  [ "$BC" = "1" ] && break
  sleep 3
done
if [ "${BC:-}" != "1" ]; then
  echo "FAIL: emulator did not boot in time" >&2
  exit 1
fi

echo "Installing modules"
bash "$SCRIPTS/03-install-modules.sh"

echo "Configuring Supreme profile"
bash "$SCRIPTS/04-configure.sh"

echo "Verifying stack"
bash "$SCRIPTS/05-verify-setup.sh"

# Run any user-provided startup scripts in sorted order. These run after the
# stack is up, so they can install apps or extra modules via adb/su.
if [ -d "$USER_SCRIPTS" ]; then
  for script in "$USER_SCRIPTS"/*.sh; do
    [ -e "$script" ] || continue
    echo "Running user script: $script"
    bash "$script"
  done
fi

touch /data/.first-boot-done
echo "Success !!"

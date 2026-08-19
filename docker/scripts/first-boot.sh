#!/usr/bin/env bash
# One-time provisioning: AVD, module stack, Supreme profile, verify. Thin orchestrator over avd/scripts.
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

# The emulator program (supervisor) boots this AVD; poll getprop from the host so adbd drops can't kill us.
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

# Run any user-provided startup scripts in sorted order, after the stack is up.
if [ -d "$USER_SCRIPTS" ]; then
  for script in "$USER_SCRIPTS"/*.sh; do
    [ -e "$script" ] || continue
    echo "Running user script: $script"
    bash "$script"
  done
fi

touch /data/.first-boot-done
echo "Success !!"

#!/usr/bin/env bash
# One-time provisioning: create the a36 AVD, install the integrity module
# stack, configure the Supreme profile, and verify. Runs once per /data volume.
set -euo pipefail

AH="${ANDROID_HOME:-/opt/android-sdk}"
ADB="$AH/platform-tools/adb"
AVD="${AVD:-a36}"
API="${API:-36}"
MOD_DIR="/data/adb/modules/playintegrityfix"
BOX_DIR="/data/adb/Box-Brain"
PIF="$MOD_DIR/custom.pif.prop"

# Nested `su root -c` is reliable on fresh AVDs (plain su intermittently
# rejects /data/adb). Commands here must not contain single quotes.
suroot() {
  local _
  for i in 1 2 3 4 5; do
    if "$ADB" shell su -c "su root -c '$1'" 2>/dev/null; then return 0; fi
    sleep 3
  done
  echo "FAIL: su command not accepted after retries: $1" >&2
  return 1
}

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
echo no | "$AH/cmdline-tools/latest/bin/avdmanager" create avd \
  --name "$AVD" \
  --package "system-images;android-$API;google_apis_playstore;x86_64" \
  --device "pixel_6" \
  --force

CONFIG="/data/$AVD.avd/config.ini"
python3 - "$CONFIG" <<'PY'
import sys, os
path = sys.argv[1]
overrides = {
    "hw.ramSize": "1536",
    "hw.heapSize": "512",
    "hw.gpu.enabled": "no",
    "hw.gpu.mode": "host",
    "hw.gpu.blacklisted": "yes",
    "hw.gltransport": "pipe",
    "hw.camera": "no",
    "hw.sensors.proximity": "no",
    "hw.sensors.light": "no",
    "hw.battery": "no",
    "hw.audioInput": "no",
    "hw.audioOutput": "no",
    "hw.mainKeys": "no",
    "hw.keyboard": "yes",
    "skin.dynamic": "no",
    "showDeviceFrame": "no",
    "disk.dataPartition.size": "6144M",
    "fastboot.forceColdBoot": "yes",
}
lines = open(path).read().splitlines() if os.path.exists(path) else []
seen, out = set(), []
for ln in lines:
    if '=' in ln and not ln.strip().startswith(';'):
        k = ln.split('=', 1)[0].strip()
        if k in overrides:
            out.append(f"{k}={overrides[k]}"); seen.add(k)
        else:
            out.append(ln)
    else:
        out.append(ln)
for k, v in overrides.items():
    if k not in seen: out.append(f"{k}={v}")
open(path, 'w').write("\n".join(out) + "\n")
PY

# The emulator program (supervisor) boots this AVD. Wait for it to come up.
echo "Waiting for emulator boot"
wait_boot

echo "Bootstrapping KSU manager (extracts ksud, enables su)"
"$ADB" install -r /opt/modules/ksunext.apk
"$ADB" shell am start -n com.rifsxd.ksunext/.ui.MainActivity
sleep 10

install_module() {
  echo "Installing $1"
  "$ADB" push "/opt/modules/$2" /data/local/tmp/module.zip
  "$ADB" shell su -c 'ksud module install /data/local/tmp/module.zip'
}

install_module "TEESimulator" teesimulator.zip
install_module "ReZygisk" rezygisk.zip
install_module "SUSFS-for-KernelSU" susfs.zip
install_module "Integrity Box" integrity-box.zip

echo "Installing KsuWebUIStandalone"
"$ADB" install -r /opt/modules/ksuwebui.apk

echo "Rebooting to activate the modules"
"$ADB" reboot
wait_boot

echo "Enabling Supreme profile"
"$ADB" push /opt/modules/custom.pif.prop /data/local/tmp/custom.pif.prop
suroot "cp /data/local/tmp/custom.pif.prop $PIF && chmod 0644 $PIF"

echo "Writing canonical custom.pif.prop"
suroot "rm -f $BOX_DIR/pixelify $BOX_DIR/legacy $BOX_DIR/wipe && touch $BOX_DIR/advanced && chmod 0644 $BOX_DIR/advanced"

echo "Restarting GMS + Play Store so the spoof applies"
suroot 'am force-stop com.google.android.gms.unstable; am force-stop com.android.vending'

echo "Verifying stack"
suroot 'ls /data/adb/modules/playintegrityfix' >/dev/null ||
  {
    echo "FAIL: Integrity Box module missing" >&2
    exit 1
  }
GEN=$("$ADB" logcat -d 2>/dev/null | grep -c "Generating new attested key pair" || true)
if [ "${GEN:-0}" -gt 0 ] 2>/dev/null; then
  echo "OK  TEESimulator GENERATE mode"
else
  echo "WARN TEESimulator not in GENERATE mode yet (may need a cold reboot)"
fi

touch /data/.first-boot-done
echo "Success !!"

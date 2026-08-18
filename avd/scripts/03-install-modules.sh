#!/usr/bin/env bash
# Install the module stack + WebUI/manager apps, then reboot.
#   - TEESimulator (tricky_store): hardware-backed key simulation
#   - ReZygisk: Zygisk runtime that Integrity Box's zygisk hooks need
#   - SUSFS-for-KernelSU: kernel-level hiding
#   - Integrity Box (playintegrityfix): PIF + WebUI dashboard
# Keybox is auto-fetched by the Integrity Box installer — we never manage it.
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$AH/platform-tools/adb"
TMP="/tmp/integrity-box-setup"
mkdir -p "$TMP"

TEE_URL="https://github.com/JingMatrix/TEESimulator/releases/download/v3.2/TEESimulator-v3.2-67-Release.zip"
REZYGISK_URL="https://raw.githubusercontent.com/ThePedroo/RemoteFiles/refs/heads/main/ReZygisk/ReZygisk.zip"
SUSFS_URL="https://github.com/sidex15/susfs4ksu-module/releases/download/v1.5.2%2B_R27/ksu_module_susfs_1.5.2%2B.zip"
IB_URL="https://github.com/MeowDump/Integrity-Box/releases/download/v40/v40-Integrity-Box-05-08-2026.zip"
KSU_WEBUI_URL="https://github.com/5ec1cff/KsuWebUIStandalone/releases/download/v1.0/KsuWebUI-1.0-34-release.apk"
# Manager MUST be v3.2.0 — matches the kernel's embedded ksud (33150); v3.3.0 refuses to work.
KSU_NEXT_URL="https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v3.2.0/KernelSU_Next_v3.2.0_33129-release.apk"

echo "==> Downloading modules + WebUI + manager"
curl -fsSL -o "$TMP/teesimulator.zip" "$TEE_URL"
curl -fsSL -o "$TMP/rezygisk.zip" "$REZYGISK_URL"
curl -fsSL -o "$TMP/susfs.zip" "$SUSFS_URL"
curl -fsSL -o "$TMP/integrity-box.zip" "$IB_URL"
curl -fsSL -o "$TMP/ksuwebui.apk" "$KSU_WEBUI_URL"
curl -fsSL -o "$TMP/ksunext.apk" "$KSU_NEXT_URL"

# Fresh userdata has no /data/adb/ksud — the manager extracts it on first
# launch. su is dead until then, so bootstrap it BEFORE any su-based command.
echo "==> Bootstrapping KSU manager (extracts ksud, enables su)"
"$ADB" install -r "$TMP/ksunext.apk"
"$ADB" shell am start -n com.rifsxd.ksunext/.ui.MainActivity
sleep 10

install_module() {
  echo "==> Installing $1"
  "$ADB" push "$TMP/$2" /data/local/tmp/module.zip
  "$ADB" shell su -c 'ksud module install /data/local/tmp/module.zip'
}

install_module "TEESimulator" teesimulator.zip
install_module "ReZygisk" rezygisk.zip
install_module "SUSFS-for-KernelSU" susfs.zip
install_module "Integrity Box" integrity-box.zip

echo "==> Installing KsuWebUIStandalone"
"$ADB" install -r "$TMP/ksuwebui.apk"

echo "==> Rebooting to activate the modules"
"$ADB" reboot
"$ADB" wait-for-device
for i in $(seq 1 120); do
  BC=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
  [ "$BC" = "1" ] && { echo "Reboot complete ($i polls)."; exit 0; }
  sleep 3
done
echo "FAIL: reboot timeout" >&2; exit 1

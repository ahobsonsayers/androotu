#!/usr/bin/env bash
# Install the module stack (Integrity Box first, Tricky Store OSS, MeowZygisk, SUSFS, BetterKnownInstalled) + WebUI/manager.
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$AH/platform-tools/adb"
TMP="/tmp/integrity-box-setup"
mkdir -p "$TMP"

# When MODULES_DIR is set (docker), modules are pre-baked in the image; else fetch from pinned URLs.
if [ -n "${MODULES_DIR:-}" ]; then
  echo "Using pre-baked modules from $MODULES_DIR"
  cp "$MODULES_DIR"/tricky-store-oss.zip "$MODULES_DIR"/meowzygisk.zip \
    "$MODULES_DIR"/susfs.zip "$MODULES_DIR"/integrity-box.zip \
    "$MODULES_DIR"/better-known-installed.zip \
    "$MODULES_DIR"/ksuwebui.apk "$MODULES_DIR"/ksunext.apk "$TMP"/
else
# Keybox module pin — must accept ECDSA hardware keyboxes (Integrity Box ships ECDSA only).
  TEE_URL="https://github.com/beakthoven/TrickyStoreOSS/releases/download/v3.1.0/Tricky-Store-OSS-v3.1.0-172-41383f5-Release.zip"
  MEOWZYGISK_URL="https://github.com/MeowDump/MeowZygisk/releases/download/v3/v3-MeowZygisk-22-09-2026.zip"
  SUSFS_URL="https://github.com/sidex15/susfs4ksu-module/releases/download/v1.5.2%2B_R28/ksu_module_susfs_1.5.2%2B.zip"
  IB_URL="https://github.com/MeowDump/Integrity-Box/releases/download/v45/v45-Integrity-Box-18-10-2026.zip"
  BKI_URL="https://github.com/Pixel-Props/BetterKnownInstalled/releases/download/1610/BetterKnownInstalled-v1.6.1.zip"
  KSU_WEBUI_URL="https://github.com/MeowDump/KsuWebUIStandalone/releases/download/v2/v2-Meow-KsuWebUI.apk"
  # Manager MUST be v3.2.0 — matches the kernel's embedded ksud; v3.3.0 refuses to work.
  KSU_NEXT_URL="https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v3.2.0/KernelSU_Next_v3.2.0_33129-release.apk"

  echo "Downloading modules + WebUI + manager"
  curl -fsSL -o "$TMP/tricky-store-oss.zip" "$TEE_URL"
  curl -fsSL -o "$TMP/meowzygisk.zip" "$MEOWZYGISK_URL"
  curl -fsSL -o "$TMP/susfs.zip" "$SUSFS_URL"
  curl -fsSL -o "$TMP/integrity-box.zip" "$IB_URL"
  curl -fsSL -o "$TMP/better-known-installed.zip" "$BKI_URL"
  curl -fsSL -o "$TMP/ksuwebui.apk" "$KSU_WEBUI_URL"
  curl -fsSL -o "$TMP/ksunext.apk" "$KSU_NEXT_URL"
fi

# Fresh userdata has no /data/adb/ksud; the manager extracts it on first launch. Bootstrap before su.
echo "Bootstrapping KSU manager (extracts ksud, enables su)"
"$ADB" install -r "$TMP/ksunext.apk"
"$ADB" shell am start -n com.rifsxd.ksunext/.ui.MainActivity
sleep 10

install_module() {
  echo "Installing $1"
  "$ADB" push "$TMP/$2" /data/local/tmp/module.zip
  "$ADB" shell su -c 'ksud module install /data/local/tmp/module.zip'
}

install_module "Integrity Box" integrity-box.zip
install_module "TrickyStoreOSS" tricky-store-oss.zip
install_module "MeowZygisk" meowzygisk.zip
install_module "SUSFS-for-KernelSU" susfs.zip
install_module "BetterKnownInstalled" better-known-installed.zip

# Ensure /data/adb/tricky_store/keybox.xml is hardware-rooted: Integrity Box
# auto-fetches one at install; the baked (local-only) keybox is the fallback.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST=/data/adb/tricky_store/keybox.xml
KB_SRC="$MODULES_DIR/keybox.xml"
[ -f "$KB_SRC" ] || KB_SRC="$SCRIPT_DIR/../config/keybox.xml"
suroot() {
  "$ADB" shell su -c "su root -c '$1'" 2>/dev/null
}
KB_CHK="$TMP/kb-check.xml"
if suroot "cat $DST" >"$KB_CHK" 2>/dev/null && [ -s "$KB_CHK" ] && \
   bash "$SCRIPT_DIR/verify-keybox.sh" "$KB_CHK" >/dev/null 2>&1; then
  echo "OK  $DST already hardware-rooted"
elif [ -f "$KB_SRC" ]; then
  bash "$SCRIPT_DIR/verify-keybox.sh" "$KB_SRC"
  "$ADB" push "$KB_SRC" /data/local/tmp/fallback-keybox.xml
  suroot "mkdir -p /data/adb/tricky_store && cp /data/local/tmp/fallback-keybox.xml $DST && chmod 0600 $DST"
  suroot "cat $DST" >"$KB_CHK"
  bash "$SCRIPT_DIR/verify-keybox.sh" "$KB_CHK"
  echo "Installed baked hardware keybox -> $DST"
else
  echo "No baked keybox; relying on the Integrity Box runtime fetch"
fi

echo "Installing KsuWebUIStandalone"
"$ADB" install -r "$TMP/ksuwebui.apk"

echo "Rebooting to activate the modules"
"$ADB" reboot
"$ADB" wait-for-device
# shellcheck disable=SC2016
"$ADB" shell 'timeout 360 sh -c '\''while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done'\'''

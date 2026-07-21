#!/usr/bin/env bash
set -euo pipefail

# Flow: KVM check → create AVD → boot unrooted (wipe) → rootAVD (shuts down) →
#       cold boot (no wipe) → setup-magisk (Direct Install + grant shell su) →
#       keep emulator running (tail -F log).

ANDROID_HOME="${ANDROID_HOME:-/opt/android}"
ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-/data}"
AVD_NAME="${AVD_NAME:-rooted33}"
EMULATOR_RAM="${EMULATOR_RAM:-1536}"
SYSTEM_IMAGE="system-images;android-33;google_apis_playstore;x86_64"
RAMDISK_PATH="$ANDROID_HOME/$(echo $SYSTEM_IMAGE | tr ';' '/')/ramdisk.img"
# rootAVD.sh prepends $ANDROID_HOME to $1, so pass a RELATIVE path.
RAMDISK_ARG="$(echo $SYSTEM_IMAGE | tr ';' '/')/ramdisk.img"
ROOTAVD_DIR="${ROOTAVD_DIR:-/opt/rootAVD}"
ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"
LOG_FILE="${EMULATOR_LOG:-/tmp/emulator.log}"
AVD_DIR="$ANDROID_AVD_HOME/${AVD_NAME}.avd"
SERIAL="emulator-5554"
export ANDROID_SERIAL="$SERIAL"

if [ ! -e /dev/kvm ]; then
    echo "FATAL: /dev/kvm not found. Mount it with --device /dev/kvm" >&2
    exit 1
fi

# Clean slate: kill any prior emulator + stale adb state.
"$ADB" emu kill 2>/dev/null || true
"$ADB" kill-server 2>/dev/null || true
sleep 1
rm -f "$AVD_DIR"/*.lock 2>/dev/null || true

wait_boot() {
    "$ADB" wait-for-device
    for _ in $(seq 1 120); do
        BC=$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
        [ "$BC" = "1" ] && break
        sleep 3
    done
    if [ "$BC" != "1" ]; then
        echo "FAIL: boot timeout" >&2; exit 1
    fi
    # adb can report "device offline" transiently for several seconds
    # after boot_completed=1 — poll until `adb shell true` succeeds.
    for _ in $(seq 1 30); do
        if "$ADB" -s "$SERIAL" shell true 2>/dev/null; then
            return 0
        fi
        sleep 2
    done
    echo "FAIL: adb shell never came back online after boot" >&2; exit 1
}

launch_emulator() {
    # $1 = extra args (e.g. -wipe-data). Intentionally unquoted for word-split.
    setsid nohup "$EMULATOR" \
        -avd "$AVD_NAME" \
        -no-window \
        -no-audio \
        -no-snapshot \
        -memory "$EMULATOR_RAM" \
        -no-boot-anim \
        -gpu off \
        $1 \
        > "$LOG_FILE" 2>&1 < /dev/null & disown
}

# Create AVD if absent.
if ! avdmanager list avd 2>/dev/null | grep -q "$AVD_NAME"; then
    echo "Creating AVD $AVD_NAME..."
    echo no | avdmanager create avd \
        --name "$AVD_NAME" \
        --package "$SYSTEM_IMAGE" \
        --device "pixel_6" \
        --force

    CONFIG="$AVD_DIR/config.ini"
    cat >> "$CONFIG" << EOF
hw.ramSize=$EMULATOR_RAM
hw.heapSize=512
hw.gpu.enabled=no
hw.camera=no
hw.audioInput=no
hw.audioOutput=no
hw.mainKeys=no
hw.keyboard=yes
skin.dynamic=no
showDeviceFrame=no
disk.dataPartition.size=4096M
fastboot.forceColdBoot=yes
EOF
fi

# 1. Boot unrooted with -wipe-data for clean state.
echo "Booting unrooted emulator for rootAVD patching..."
launch_emulator "-wipe-data"
wait_boot

# Clean stale rootAVD workspace on device — a prior failed run can leave
# corrupt files that cause "ramdisk.img uses UNKNOWN compression" errors.
"$ADB" -s "$SERIAL" shell 'rm -rf /data/data/com.android.shell/Magisk' 2>/dev/null || true

# 2. Patch ramdisk via rootAVD (shuts emulator down). Pipe "1" to stdin
#    to auto-select Magisk Stable from the version menu.
echo "Patching ramdisk with Magisk via rootAVD..."
cd "$ROOTAVD_DIR"
chmod +x rootAVD.sh
if ! echo 1 | ./rootAVD.sh "$RAMDISK_ARG"; then
    echo "FAIL: rootAVD exited non-zero" >&2
    "$ADB" -s "$SERIAL" emu kill 2>/dev/null || true
    exit 1
fi
# Verify the ramdisk was actually patched (backup file created by rootAVD).
if [ ! -f "$RAMDISK_PATH.backup" ]; then
    echo "FAIL: rootAVD did not patch — no $RAMDISK_PATH.backup found" >&2
    "$ADB" -s "$SERIAL" emu kill 2>/dev/null || true
    exit 1
fi

# Wait for rootAVD's shutdown to take effect, force-kill if needed.
echo "Waiting for emulator to shut down after patching..."
for _ in $(seq 1 30); do
    if ! "$ADB" -s "$SERIAL" get-state 2>/dev/null | grep -q device; then
        echo "Emulator shut down."
        break
    fi
    sleep 2
done
# Force-kill if still running (don't let a stale emulator trigger "more
# than one device" errors on the next launch).
"$ADB" -s "$SERIAL" emu kill 2>/dev/null || true
sleep 2
"$ADB" kill-server 2>/dev/null || true
sleep 1
rm -f "$AVD_DIR"/*.lock 2>/dev/null || true

# 3. Cold boot (no wipe, preserve Magisk.apk in userdata).
echo "Cold booting patched emulator..."
launch_emulator ""
wait_boot

# Ensure Magisk.apk is installed (rootAVD installs it on the first boot,
# but userdata may not have preserved it depending on AVD/snapshot config).
if ! "$ADB" -s "$SERIAL" shell pm path com.topjohnwu.magisk >/dev/null 2>&1; then
    echo "Installing Magisk.apk (not present after cold boot)..."
    "$ADB" -s "$SERIAL" install /opt/rootAVD/Apps/Magisk.apk
fi

# 4. Complete Magisk environment + grant shell su via UI automation.
echo "Setting up Magisk environment..."
sleep 5  # let the launcher / system UI settle before driving the Magisk app
if [ -x /opt/scripts/06-setup-magisk.sh ]; then
    /opt/scripts/06-setup-magisk.sh || echo "WARN: Magisk UI setup failed; root may not be functional yet" >&2
fi

echo "Emulator ready. Tailing log (Ctrl-C to detach, container keeps running)..."
tail -F "$LOG_FILE" 2>/dev/null || wait
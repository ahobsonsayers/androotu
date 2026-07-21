#!/usr/bin/env bash
# Completes Magisk environment after rootAVD-patched cold boot:
#   1. Launch Magisk app → dismiss "Requires Additional Setup" dialog
#   2. Tap Install → Direct Install → LET'S GO → wait → Reboot
#   3. Wait for cold boot
#   4. Launch Magisk → Superuser → enable Shell policy toggle
#   5. Optionally set Automatic Response = Grant (for future headless su)
#
# Idempotent: if `su -c id` already returns uid=0(root), skips straight to
# verify. If Step A (Direct Install) was already completed, skips to Step B.
#
# Coordinates target pixel_6 @ 1080x2400. If device differs, bounds may
# need re-derivation via `adb shell uiautomator dump`.
set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
SERIAL="${ANDROID_SERIAL:-emulator-5554}"

adb() { "$ADB" -s "$SERIAL" "$@"; }

verify() {
    ANDROID_SERIAL="$SERIAL" "$(dirname "$0")/07-verify-root.sh"
}

wait_boot() {
    adb wait-for-device
    for i in $(seq 1 120); do
        BC=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
        [ "$BC" = "1" ] && return 0
        sleep 3
    done
    echo "FAIL: boot timeout" >&2; exit 1
}

# Wait until adb shell is actually responsive (not just "device" state).
# Right after boot_completed=1, adb can still return "device offline" for
# a few seconds. This polls until a trivial shell command succeeds.
wait_device_ready() {
    for i in $(seq 1 30); do
        adb shell true 2>/dev/null && return 0
        sleep 2
    done
    echo "FAIL: adb shell never became responsive" >&2; return 1
}

# tap with retry — adb shell can transiently fail right after boot with
# "device offline" even though boot_completed=1. Retry up to 5 times.
tap() {
    local x="$1" y="$2"
    for i in $(seq 1 5); do
        if adb shell input tap "$x" "$y" 2>/dev/null; then return 0; fi
        sleep 2
    done
    echo "WARN: tap $x $y failed after 5 retries" >&2
    return 1
}

dump_ui() {
    # uiautomator dump can fail several ways: OOM-killed (phantom "dumped"
    # message, no file), "null root node", empty root node bounds=[0,0][0,0]
    # (app in transition), or hang indefinitely during UI transitions.
    # Retry up to 5 times with longer sleeps. Wrap dump in `timeout 30` so a
    # hung dump can't block the script.
    for _ in $(seq 1 5); do
        adb shell rm -f /sdcard/ui.xml 2>/dev/null || true
        adb shell timeout 30 uiautomator dump /sdcard/ui.xml 2>/dev/null || true
        # uiautomator prints "dumped" but may not actually write the file
        # if it was OOM-killed mid-dump. Verify the file exists AND is
        # non-empty before accepting. Also reject empty-root-node dumps
        # (bounds=[0,0][0,0]) which are transition artifacts.
        if adb shell test -s /sdcard/ui.xml 2>/dev/null; then
            local xml; xml=$(adb shell cat /sdcard/ui.xml 2>/dev/null || true)
            # Empty root node (app mid-transition) — treat as failure.
            if echo "$xml" | grep -q 'bounds="\[0,0\]\[0,0\]"' && ! echo "$xml" | grep -q 'resource-id="[^"]'; then
                sleep 2
                continue
            fi
            echo "$xml"
            return 0
        fi
        sleep 2
    done
    return 1
}

# Dismiss "System UI isn't responding" / "Close app" ANR dialogs that appear
# under RAM pressure by tapping "Wait" (android:id/aerr_wait). Takes the UI
# XML on stdin so we don't re-dump when called from wait_for_node.
dismiss_anr_from() {
    local xml="$1"
    if echo "$xml" | grep -q 'aerr_wait\|alertTitle'; then
        adb shell input tap 540 1363 2>/dev/null || true
        sleep 2
        return 0
    fi
    return 1
}

dismiss_anr() {
    local xml; xml=$(dump_ui 2>/dev/null || true)
    dismiss_anr_from "$xml"
}

# wait_for_node: poll for a UI node by resource-id. Bounded by max polls,
# not wall-clock. Each poll does ONE dump_ui and inspects the result for
# BOTH ANR dialogs (dismissed if present) and the target node. Exits 1
# with a clear error if max is reached, so the script never silently
# spins forever when uiautomator keeps failing under RAM pressure.
wait_for_node() {
    local rid="$1" max="${2:-20}"
    local consecutive_dumps_failed=0
    for i in $(seq 1 "$max"); do
        local xml; xml=$(dump_ui 2>/dev/null || true)
        if [ -z "$xml" ]; then
            consecutive_dumps_failed=$((consecutive_dumps_failed + 1))
            # If uiautomator keeps failing (OOM under RAM pressure), bail
            # early with a clear error instead of spinning for max*10s.
            if [ "$consecutive_dumps_failed" -ge 5 ]; then
                echo "FAIL: uiautomator dump failed 5× in a row (host RAM too low?); aborting wait_for_node $rid" >&2
                return 1
            fi
            sleep 2
            continue
        fi
        consecutive_dumps_failed=0
        dismiss_anr_from "$xml" || true
        if echo "$xml" | grep -q "resource-id=\"$rid\""; then return 0; fi
        sleep 1
    done
    echo "FAIL: node $rid not found within $max polls" >&2
    return 1
}

launch_magisk() {
    # Force-stop first so we always start from Magisk home, not whatever
    # screen was left over from a previous failed/partial run.
    adb shell am force-stop com.topjohnwu.magisk 2>/dev/null || true
    sleep 1
    dismiss_anr || true
    # Retry am start until Magisk home is actually in focus. Under RAM
    # pressure the launcher can steal focus or Magisk can ANR immediately,
    # leaving the launcher (nexuslauncher) on screen instead of Magisk.
    for attempt in 1 2 3; do
        adb shell am start -n com.topjohnwu.magisk/.ui.MainActivity >/dev/null 2>&1
        # Under RAM pressure, Magisk home can take 5-8s to render. Wait
        # longer than the previous 3s to avoid uiautomator dump hitting a
        # null root node.
        sleep 6
        dismiss_anr || true
        # Dismiss notification permission dialog (Android 13 first launch).
        if dump_ui 2>/dev/null | grep -q "permission_allow_button"; then
            tap 540 1304; sleep 2
        fi
        # Dismiss "Requires Additional Setup" dialog (OK button =
        # dialog_base_button_1 at (890,1348)). This dialog blocks the
        # home view, so home_magisk_button won't be visible until dismissed.
        if dump_ui 2>/dev/null | grep -q "dialog_base_button_1"; then
            tap 890 1348; sleep 2
        fi
        # Verify Magisk took focus. Accept either home_magisk_button OR
        # home_magisk_title (the title is always visible on Magisk home).
        if dump_ui 2>/dev/null | grep -qE "com.topjohnwu.magisk:id/home_magisk_button|com.topjohnwu.magisk:id/home_magisk_title"; then
            return 0
        fi
        echo "WARN: Magisk home not in focus (attempt $attempt); relaunching" >&2
        adb shell am force-stop com.topjohnwu.magisk 2>/dev/null || true
        sleep 2
    done
    echo "WARN: Magisk did not take focus after 3 attempts; proceeding anyway" >&2
    return 0
}

is_rooted() {
    adb shell su -c id 2>/dev/null | grep -q 'uid=0(root)'
}

# Fast path: already fully rooted (Step A + B done).
if is_rooted; then
    echo "Already rooted (su -c id returns uid=0); skipping Magisk setup."
    verify
    exit 0
fi

echo "== Step A: Magisk Direct Install =="

# Ensure Magisk.apk is installed (rootAVD installs it, but it can be missing
# after a cold boot if userdata was wiped). Fall back to the apk in rootAVD/Apps.
if ! adb shell pm path com.topjohnwu.magisk >/dev/null 2>&1; then
    APK="${ROOTAVD_DIR:-$HOME/rootAVD}/Apps/Magisk.apk"
    if [ -f "$APK" ]; then
        echo "Magisk.apk not installed; installing from $APK"
        adb install "$APK" >/dev/null 2>&1 || { echo "FAIL: adb install $APK" >&2; exit 1; }
    else
        echo "FAIL: Magisk.apk not installed and not found at $APK" >&2; exit 1
    fi
fi

launch_magisk

# Dismiss ANR / "Requires Additional Setup" dialog if present.
dismiss_anr || true
if dump_ui 2>/dev/null | grep -q "dialog_base_button_1"; then
    tap 890 1348; sleep 2
fi

# Idempotency check: the real signal that Direct Install completed is
# /data/adb/magisk/util_functions.sh existing on device. The
# home_magisk_installed_version UI element appears just from the apk being
# installed (rootAVD does pm install), NOT from Direct Install completing.
# Skipping Step A when /data/adb/magisk/ is empty leaves Magisk in
# "Incomplete Magisk install" state → magisk --install-module fails.
if adb shell test -f /data/adb/magisk/util_functions.sh 2>/dev/null; then
    echo "Magisk Direct Install already complete (/data/adb/magisk populated); skipping Step A."
else
    # Tap Install on Magisk home.
    wait_for_node "com.topjohnwu.magisk:id/home_magisk_button" 30 || {
        echo "WARN: Install button not found; trying relaunch" >&2
        launch_magisk
        wait_for_node "com.topjohnwu.magisk:id/home_magisk_button" 20 || {
            echo "FAIL: cannot locate Install button" >&2; exit 1
        }
    }
    tap 869 641; sleep 2

    # Wait for Method sheet (Direct Install option).
    wait_for_node "com.topjohnwu.magisk:id/method_direct" 20 || {
        echo "FAIL: Direct Install option not found" >&2; exit 1
    }
    tap 540 611; sleep 1
    # LET'S GO button has no resource-id; match by text.
    if ! dump_ui 2>/dev/null | grep -q 'text="LET'\''S GO"'; then
        echo "WARN: LET'S GO button not found in UI; retrying with known coords" >&2
    fi
    tap 885 401; sleep 3
    # Wait for "All done!" / Reboot button.
    wait_for_node "com.topjohnwu.magisk:id/restart_btn" 60 || {
        echo "FAIL: reboot button never appeared; Direct Install may have failed" >&2
        exit 1
    }
    tap 878 2231
    echo "Waiting for emulator to shut down after Direct Install reboot..."
    # Direct Install triggers a device reboot. The emulator was launched
    # detached (setsid nohup ... &), so `adb reboot` / Magisk's reboot
    # shuts it down WITHOUT auto-restart. Detect shutdown, then relaunch
    # via 05-boot-emulator.sh (cold boot, no wipe, no -read-only).
    for i in $(seq 1 30); do
        adb get-state 2>/dev/null | grep -q device || { echo "Emulator shut down."; break; }
        sleep 2
    done
    # Force-kill any lingering emulator + stale adb state.
    adb emu kill 2>/dev/null || true
    sleep 2
    adb kill-server 2>/dev/null || true
    sleep 1
    echo "Cold booting emulator after Direct Install..."
    WIPE_DATA=0 "$(dirname "$0")/05-boot-emulator.sh"
    wait_device_ready
    sleep 3
    launch_magisk
    sleep 3
fi

# After Step A, check if shell su already works (unlikely but possible).
if is_rooted; then
    echo "Root already active after Step A; skipping Step B."
    verify
    exit 0
fi

echo "== Step B: Grant Shell su via Magisk Superuser UI =="
# Settle in case the device is in a transient state.
wait_device_ready
sleep 3
# Trigger an su request so the Shell entry appears in the Superuser list.
# The request is rejected (expected) — it just registers Shell as a known
# su requester so we can toggle its policy below.
for i in $(seq 1 3); do
    adb shell su -c id >/dev/null 2>&1 || true
    sleep 1
done
sleep 2

# Launch Magisk fresh and navigate to Superuser.
launch_magisk
sleep 2

# Tap Superuser bottom-nav. Retry the tap a few times — under RAM pressure
# the fragment transition can swallow the first tap, or the device can be
# transiently offline right after cold boot. Then wait for the Superuser
# fragment to render (policy_indicator appears) before proceeding.
for nav_attempt in 1 2 3; do
    tap 405 2263 || true
    sleep 5
    if dump_ui 2>/dev/null | grep -q "com.topjohnwu.magisk:id/policy_indicator\|superuserFragment"; then
        break
    fi
    echo "WARN: Superuser fragment not rendered (attempt $nav_attempt); retrying nav tap" >&2
done

wait_for_node "com.topjohnwu.magisk:id/policy_indicator" 30 || {
    echo "FAIL: Shell policy toggle not found" >&2; exit 1
}
tap 933 401; sleep 2

echo "== Step C: Set Automatic Response = Grant (optional, for headless su) =="
wait_for_node "com.topjohnwu.magisk:id/action_settings" 15 || {
    echo "WARN: settings gear not found; skipping auto-grant setting" >&2
    verify
    exit 0
}
tap 1016 201; sleep 2
tap 540 1850; sleep 1
tap 540 1317; sleep 1

echo "Magisk setup complete."
verify
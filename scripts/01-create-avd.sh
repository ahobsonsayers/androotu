#!/usr/bin/env bash
# Create the a36 AVD (A36 x86_64 Play Store image, pixel_6, headless config).
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
AVD="${AVD:-a36}"

# avdmanager lives under cmdline-tools/latest/bin in modern SDKs, tools/bin in older ones.
AVDMANAGER=""
for d in "$AH/cmdline-tools/latest/bin" "$AH/cmdline-tools/tools/bin"; do
  [ -x "$d/avdmanager" ] && AVDMANAGER="$d/avdmanager" && break
done
[ -n "$AVDMANAGER" ] || { echo "FAIL: avdmanager not found under \$ANDROID_HOME/cmdline-tools" >&2; exit 1; }

echo no | "$AVDMANAGER" create avd \
  --name "$AVD" \
  --package "system-images;android-36;google_apis_playstore;x86_64" \
  --device "pixel_6" \
  --force

# avdmanager may write the AVD under $ANDROID_AVD_HOME, ~/.android/avd,
# $ANDROID_HOME/.android/avd, or (XDG layout) ~/.config/.android/avd
# depending on version. Resolve the real location.
AVD_DIR=""
for base in "${ANDROID_AVD_HOME:-}" "$HOME/.android/avd" "$AH/.android/avd" "$HOME/.config/.android/avd"; do
  [ -n "$base" ] && [ -d "$base/$AVD.avd" ] && AVD_DIR="$base/$AVD.avd" && break
done
[ -n "$AVD_DIR" ] || { echo "FAIL: AVD dir for '$AVD' not found after create" >&2; exit 1; }

CONFIG="$AVD_DIR/config.ini"
python3 - "$CONFIG" << 'PY'
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
echo "AVD $AVD ready."

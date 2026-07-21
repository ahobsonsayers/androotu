#!/usr/bin/env bash
# Create AVD rooted33 (pixel_6, 1536MB RAM, headless config).
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
AVD=rooted33

echo no | "$AH/cmdline-tools/tools/bin/avdmanager" create avd \
  --name "$AVD" \
  --package "system-images;android-33;google_apis_playstore;x86_64" \
  --device "pixel_6" \
  --force

CONFIG="$HOME/.android/avd/$AVD.avd/config.ini"
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
    "disk.dataPartition.size": "4096M",
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
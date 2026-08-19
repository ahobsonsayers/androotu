#!/usr/bin/env bash
# Boot the a36 AVD headless with the custom KSU/SUSFS kernel (foreground for supervisor).
set -euo pipefail

AH="${ANDROID_HOME:-/opt/android-sdk}"
AVD="${AVD:-a36}"

# Forward the emulator's localhost ADB to eth0 so other containers/host can reach :5555.
LOCAL_IP=$(ip addr list eth0 2>/dev/null | grep "inet " | cut -d' ' -f6 | cut -d/ -f1)
if [ -n "$LOCAL_IP" ]; then
  socat tcp-listen:5555,bind="$LOCAL_IP",fork tcp:127.0.0.1:5555 &
fi

export ANDROID_HOME="$AH"
export ANDROID_AVD_HOME=/data
export FOREGROUND=1
export WAIT_FOR_INI=1
export DATA_IMG="/data/$AVD.avd/userdata-qemu.img"
export SKIP_ADB_AUTH=1
export KERNEL="${KERNEL:-/opt/kernel/bzImage-a36-btf}"
exec bash /root/scripts/02-boot-emulator.sh

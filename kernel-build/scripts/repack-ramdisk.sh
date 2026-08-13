#!/usr/bin/env bash
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
RAMDISK_SRC="${RAMDISK_SRC:-$AH/system-images/android-33/google_apis_playstore/x86_64/ramdisk.img}"
MODULES_DIR="${1:-/work/out/modules/lib/modules/5.15.119-android13-8-Pixel10+/kernel}"
OUT="${2:-/work/out/ramdisk.img}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Extracting original ramdisk"
cp "$RAMDISK_SRC" "$WORK/ramdisk.img.lz4"
lz4 -d -f "$WORK/ramdisk.img.lz4" "$WORK/ramdisk.cpio"

echo "==> Extracting cpio archive"
mkdir -p "$WORK/extract"
( cd "$WORK/extract" && cpio -idmu < "$WORK/ramdisk.cpio" 2>/dev/null )

echo "==> Swapping kernel modules"
for ko in "$MODULES_DIR"/**/*.ko; do
  name="$(basename "$ko")"
  dest="$(find "$WORK/extract/lib/modules" -name "$name" -type f || true)"
  if [ -n "$dest" ]; then
    cp -f "$ko" "$dest"
    echo "  replaced: $name"
  else
    echo "  WARNING: $name not found in ramdisk, skipping"
  fi
done

echo "==> Running depmod"
KVER="$(basename "$(dirname "$(dirname "$MODULES_DIR")")")"
depmod -b "$WORK/extract" "$KVER" || true

echo "==> Repacking cpio"
( cd "$WORK/extract" && find . | cpio -o -H newc > "$WORK/ramdisk-new.cpio" 2>/dev/null )

echo "==> Compressing with LZ4 legacy format"
lz4 -f -9 -l "$WORK/ramdisk-new.cpio" "$OUT"

echo "==> Done: $OUT"
ls -la "$OUT"
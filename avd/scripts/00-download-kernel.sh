#!/usr/bin/env bash
# Download the prebuilt KSU/SUSFS kernel from the kernel-latest rolling GitHub
# release into kernel/dist/bzImage-a36-btf. AVD users run this instead of
# building the kernel themselves.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/kernel/dist"
mkdir -p "${OUT}"

REPO="${REPO:-ahobsonsayers/androotu}"
TAG="${TAG:-kernel-latest}"
DEST="${OUT}/bzImage-a36-btf"

echo "Downloading kernel from ${REPO} release ${TAG}"
if command -v gh >/dev/null 2>&1; then
  gh release download "$TAG" --repo "$REPO" --pattern bzImage --dir "$OUT"
else
  # Fallback: fetch the release asset URL via the GitHub API (no gh needed).
  URL="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/tags/${TAG}" |
    python3 -c 'import sys,json; a=json.load(sys.stdin)["assets"]; print(next(x["browser_download_url"] for x in a if x["name"]=="bzImage"))')"
  curl -fsSL -o "$DEST" "$URL"
fi

# gh writes to $OUT/bzImage; normalize to the expected name.
if [ -f "${OUT}/bzImage" ] && [ ! -f "$DEST" ]; then
  mv "${OUT}/bzImage" "$DEST"
fi

[ -f "$DEST" ] || {
  echo "FAIL: kernel not found at $DEST" >&2
  exit 1
}
echo "Kernel ready at $DEST"
ls -la "$DEST"

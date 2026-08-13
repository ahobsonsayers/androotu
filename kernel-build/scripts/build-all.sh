#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== 1/3 fetch sources ==="
bash "${ROOT}/scripts/fetch-sources.sh"

echo "=== 2/3 apply patches ==="
bash "${ROOT}/scripts/apply-patches.sh"

echo "=== 3/3 build kernel ==="
bash "${ROOT}/scripts/build.sh"

echo
echo "==> Done. Kernel image at: kernel-build/out/bzImage"
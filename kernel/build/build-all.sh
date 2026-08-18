#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== 1/3 fetch sources ==="
bash "${HERE}/fetch-sources.sh"

echo "=== 2/3 apply patches ==="
bash "${HERE}/apply-patches.sh"

echo "=== 3/3 build kernel ==="
bash "${HERE}/build.sh"

echo
echo "Done. Kernel image at: kernel/dist/bzImage"

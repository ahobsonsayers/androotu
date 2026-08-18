#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/sources"
mkdir -p "${SRC}"

KERNEL_URL="https://android.googlesource.com/kernel/common"
KERNEL_TAG="android15-6.6-2025-02_r19"
KERNEL_DIR="${SRC}/kernel"
if [[ ! -d "${KERNEL_DIR}/.git" ]]; then
  echo "Cloning AOSP common kernel @ ${KERNEL_TAG}"
  git clone --depth 1 --branch "${KERNEL_TAG}" "${KERNEL_URL}" "${KERNEL_DIR}"
else
  cur=$(cd "${KERNEL_DIR}" && git describe --tags --exact-match HEAD 2>/dev/null || echo NONE)
  if [[ "${cur}" != "${KERNEL_TAG}" ]]; then
    echo "kernel/ at ${cur}, need ${KERNEL_TAG}; rewiping"
    rm -rf "${KERNEL_DIR}"
    git clone --depth 1 --branch "${KERNEL_TAG}" "${KERNEL_URL}" "${KERNEL_DIR}"
  else
    echo "kernel/ already at ${KERNEL_TAG}"
  fi
fi

KSU_URL="https://github.com/KernelSU-Next/KernelSU-Next.git"
KSU_COMMIT="5a4a71874caaad06aa126f761c93391de1d32361"
KSU_DIR="${SRC}/kernelsu"
if [[ ! -d "${KSU_DIR}/.git" ]]; then
  echo "Cloning KernelSU-Next (full history, ~30 MB)"
  git clone "${KSU_URL}" "${KSU_DIR}"
fi
(
  cd "${KSU_DIR}"
  cur=$(git rev-parse HEAD 2>/dev/null || echo NONE)
  if [[ "${cur}" != "${KSU_COMMIT}" ]]; then
    echo "kernelsu/ at ${cur:0:12}, need ${KSU_COMMIT:0:12}"
    if [[ -f .git/shallow ]]; then
      git fetch --unshallow || git fetch --depth=10000
    else
      git fetch
    fi
    git checkout "${KSU_COMMIT}"
  else
    echo "kernelsu/ at ${KSU_COMMIT:0:12}"
  fi
)

SUSFS_URL="https://gitlab.com/simonpunk/susfs4ksu.git"
SUSFS_BRANCH="gki-android15-6.6"
SUSFS_COMMIT="2df41de"
SUSFS_DIR="${SRC}/susfs"
if [[ ! -d "${SUSFS_DIR}/.git" ]]; then
  echo "Cloning SUSFS ${SUSFS_BRANCH} (full history)"
  git clone --branch "${SUSFS_BRANCH}" "${SUSFS_URL}" "${SUSFS_DIR}"
fi
(
  cd "${SUSFS_DIR}"
  cur=$(git rev-parse --short HEAD 2>/dev/null || echo NONE)
  if [[ "${cur}" != "${SUSFS_COMMIT}" ]]; then
    echo "susfs/ at ${cur}, need ${SUSFS_COMMIT}"
    if [[ -f .git/shallow ]]; then
      git fetch --unshallow || git fetch --depth=10000
    else
      git fetch
    fi
    git checkout "${SUSFS_COMMIT}"
  else
    echo "susfs/ at ${SUSFS_COMMIT}"
  fi
)

WILD_URL="https://github.com/WildKernels/kernel_patches.git"
WILD_DIR="${SRC}/wild-patches"
if [[ ! -d "${WILD_DIR}/.git" ]]; then
  echo "Cloning Wild patches"
  git clone --depth 1 "${WILD_URL}" "${WILD_DIR}"
else
  echo "wild-patches/ already present"
fi

echo
echo "All sources fetched into ${SRC}"
du -sh "${SRC}"/* 2>/dev/null || true

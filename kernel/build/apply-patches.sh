#!/usr/bin/env bash
# Apply, in order matching Wild Kernels' build pipeline exactly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="${ROOT}/sources/kernel"
KSU_DIR="${ROOT}/sources/kernelsu"
SUSFS_DIR="${ROOT}/sources/susfs"
WILD_DIR="${ROOT}/sources/wild-patches"

if [[ ! -d "${KERNEL_DIR}" ]]; then
  echo "ERROR: ${KERNEL_DIR} not found. Run build/fetch-sources.sh first." >&2
  exit 1
fi

echo "Resetting kernel tree to clean state"
(cd "${KERNEL_DIR}" &&
  git reset --hard HEAD >/dev/null &&
  git clean -fdx >/dev/null)

cd "${KERNEL_DIR}"

# KernelSU-Next. Pre-copy our clone so setup.sh doesn't re-clone over network.
KSU_COMMIT="5a4a71874caaad06aa126f761c93391de1d32361"
echo "Integrating KernelSU-Next @ ${KSU_COMMIT:0:12}"
if [[ ! -d "${KERNEL_DIR}/KernelSU-Next" ]]; then
  cp -a "${KSU_DIR}" "${KERNEL_DIR}/KernelSU-Next"
fi
bash "${KSU_DIR}/kernel/setup.sh" "${KSU_COMMIT}"

# Wild's KSU<->SUSFS integration patch.
WILD_KSU_PATCH="${WILD_DIR}/wild/ksun-5a4a718-susfs-f7ae19ef-gki-android14-6.1.patch"
if [[ ! -f "${WILD_KSU_PATCH}" ]]; then
  echo "ERROR: ${WILD_KSU_PATCH} missing -- re-run fetch-sources.sh" >&2
  exit 1
fi
echo "Applying Wild KSU<->SUSFS integration patch"
(cd drivers/kernelsu && patch -p2 -F 3 -N --no-backup-if-mismatch \
  -r /tmp/wild-ksu.rej -i "${WILD_KSU_PATCH}")

# SUSFS source files into the tree.
echo "Staging SUSFS files into kernel tree"
cp -v "${SUSFS_DIR}/kernel_patches/fs/"*.c fs/
cp -v "${SUSFS_DIR}/kernel_patches/include/linux/"*.h include/linux/

# SUSFS kernel patch (name differs per branch).
SUSFS_KERNEL_PATCH="$(find "${SUSFS_DIR}/kernel_patches" -name '50_add_susfs_*.patch' 2>/dev/null | head -n1 || true)"
if [[ -z "${SUSFS_KERNEL_PATCH}" ]]; then
  echo "ERROR: no 50_add_susfs_*.patch in ${SUSFS_DIR}/kernel_patches/" >&2
  exit 1
fi
echo "Applying SUSFS kernel patch: ${SUSFS_KERNEL_PATCH##*/}"
patch -p1 -F 3 -N --no-backup-if-mismatch -r /tmp/susfs.rej \
  -i "${SUSFS_KERNEL_PATCH}" || true

# Module vermagic bypass so KSU modules load regardless of version string.
echo "Applying module vermagic bypass hack"
if grep -q "bad_version:" kernel/module.c; then
  sed -i '/bad_version:/{:a;n;/return 0;/{s/return 0;/return 1;/;b};ba}' kernel/module.c
  if grep -A 5 "bad_version:" kernel/module.c | grep -q "return 1;"; then
    echo "  - bypass hack applied to kernel/module.c"
  else
    echo "ERROR: bypass hack didn't apply" >&2
    grep -A 10 "bad_version:" kernel/module.c
    exit 1
  fi
else
  if grep -q "bad_version:" kernel/module/version.c 2>/dev/null; then
    sed -i '/bad_version:/{:a;n;/return 0;/{s/return 0;/return 1;/;b};ba}' kernel/module/version.c
    echo "  - bypass hack applied to kernel/module/version.c"
  else
    echo "ERROR: bad_version not found in either location" >&2
    exit 1
  fi
fi

# Empty GKI protected-exports so out-of-tree symbols are freely usable.
echo "Emptying GKI protected-exports list"
if ls android/abi_gki_protected_exports_* >/dev/null 2>&1; then
  for f in android/abi_gki_protected_exports_*; do
    : >"$f"
  done
else
  echo "  - no protected_exports files found (ok)"
fi

# selinux_hide.c (6.6 branch) uses kallsyms_lookup_name but lacks its header.
SELINUX_HIDE_C="${KERNEL_DIR}/drivers/kernelsu/feature/selinux_hide.c"
if grep -q "kallsyms_lookup_name" "${SELINUX_HIDE_C}" 2>/dev/null && ! grep -q "linux/kallsyms.h" "${SELINUX_HIDE_C}" 2>/dev/null; then
  sed -i 's/#include <linux\/version.h>/#include <linux\/version.h>\n#include <linux\/kallsyms.h>/' "${SELINUX_HIDE_C}"
fi

# KSU-Next x86_64 compatibility fixes.
echo "Fixing KSU-Next x86_64 compatibility"

# compat_uptr_t needs linux/compat.h.
KSUD_H="${KERNEL_DIR}/drivers/kernelsu/runtime/ksud.h"
if grep -q "compat_uptr_t" "${KSUD_H}" 2>/dev/null && ! grep -q "linux/compat.h" "${KSUD_H}" 2>/dev/null; then
  sed -i '/#include <asm\/syscall.h>/a #include <linux/compat.h>' "${KSUD_H}"
fi

# strncpy_from_user unused-result warning under clang-18 -Werror.
SUCOMPAT="${KERNEL_DIR}/drivers/kernelsu/feature/sucompat.c"
if grep -q "strncpy_from_user(path, \*filename_user" "${SUCOMPAT}" 2>/dev/null; then
  sed -i 's/^\(\s*\)strncpy_from_user(path, \*filename_user/\1(void)strncpy_from_user(path, *filename_user/' "${SUCOMPAT}"
fi

# TIF_SECCOMP undefined on x86_64 (use test_syscall_work on GENERIC_ENTRY).
APP_PROFILE="${KERNEL_DIR}/drivers/kernelsu/policy/app_profile.c"
if grep -q "test_thread_flag(TIF_SECCOMP)" "${APP_PROFILE}" 2>/dev/null; then
  sed -i 's/test_thread_flag(TIF_SECCOMP)/test_syscall_work(SECCOMP)/' "${APP_PROFILE}"
fi

# Our anti-emulator source customizations.
echo "Customizing kernel source for AVD anti-detection"
bash "${ROOT}/build/customize-kernel.sh" "${KERNEL_DIR}"

touch "${KERNEL_DIR}/.avd-patches-applied"
echo
echo "All patches applied successfully."
echo "    Next: build/build.sh"

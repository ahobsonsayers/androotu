#!/usr/bin/env bash
# Apply, in order matching Wild Kernels' build pipeline exactly:
#   1. Reset kernel tree
#   2. KernelSU-Next setup (drops drivers/kernelsu into the tree)
#   3. Wild's KSU<->SUSFS integration patch
#   4. Copy SUSFS source files into kernel tree
#   5. Pre-SUSFS sublevel-specific sed fixes (not needed for sublevel 119)
#   6. Apply SUSFS kernel patch (|| true; sublevel fixes may already absorb)
#   7. Revert the pre-SUSFS sed fixes
#   8. Module vermagic bypass hack
#   9. Empty GKI protected-exports
#   10. KSU-Next x86_64 compatibility fixes (compat_uptr_t, strncpy, TIF_SECCOMP)
#   11. Our anti-emulator source customizations
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="${ROOT}/sources/kernel"
KSU_DIR="${ROOT}/sources/kernelsu"
SUSFS_DIR="${ROOT}/sources/susfs"
WILD_DIR="${ROOT}/sources/wild-patches"

if [[ ! -d "${KERNEL_DIR}" ]]; then
    echo "ERROR: ${KERNEL_DIR} not found. Run scripts/fetch-sources.sh first." >&2
    exit 1
fi

# 1. Reset kernel tree
echo "==> Resetting kernel tree to clean state"
( cd "${KERNEL_DIR}" \
    && git reset --hard HEAD >/dev/null \
    && git clean -fdx >/dev/null )

cd "${KERNEL_DIR}"
SUBLEVEL=$(grep -m1 '^SUBLEVEL' Makefile | awk '{print $3}')
echo "==> Kernel sublevel: ${SUBLEVEL}"

# 2. KernelSU-Next
KSU_COMMIT="5a4a71874caaad06aa126f761c93391de1d32361"
echo "==> Integrating KernelSU-Next @ ${KSU_COMMIT:0:12}"
# setup.sh clones fresh into ${KERNEL_DIR}/KernelSU-Next; pre-copy our clone
# so it doesn't re-clone from network (it git-pulls anyway, but offline-safe).
if [[ ! -d "${KERNEL_DIR}/KernelSU-Next" ]]; then
    cp -a "${KSU_DIR}" "${KERNEL_DIR}/KernelSU-Next"
fi
bash "${KSU_DIR}/kernel/setup.sh" "${KSU_COMMIT}"

# 3. Wild's KSU<->SUSFS integration patch
WILD_KSU_PATCH="${WILD_DIR}/wild/ksun-5a4a718-susfs-f7ae19ef-gki-android14-6.1.patch"
if [[ ! -f "${WILD_KSU_PATCH}" ]]; then
    echo "ERROR: ${WILD_KSU_PATCH} missing -- re-run fetch-sources.sh" >&2
    exit 1
fi
echo "==> Applying Wild KSU<->SUSFS integration patch"
( cd drivers/kernelsu && patch -p2 -F 3 -N --no-backup-if-mismatch \
    -r /tmp/wild-ksu.rej -i "${WILD_KSU_PATCH}" )

# 4. Stage SUSFS source files
echo "==> Staging SUSFS files into kernel tree"
cp -v "${SUSFS_DIR}/kernel_patches/fs/"*.c                fs/
cp -v "${SUSFS_DIR}/kernel_patches/include/linux/"*.h     include/linux/

# 5. Pre-SUSFS sublevel-specific fixes (only for sublevel <= 92/57/58)
echo "==> Pre-SUSFS sublevel-specific fixes"
if [ "${SUBLEVEL}" -le 92 ] 2>/dev/null; then
    echo "  - sublevel<=92: add dma-buf.h to fs/proc/base.c"
    sed -i '/^#include <linux\/cpufreq_times.h>$/a #include <linux/dma-buf.h>' fs/proc/base.c
fi
if [ "${SUBLEVEL}" -le 57 ] 2>/dev/null; then
    echo "  - sublevel<=57: add zswap.h to mm/memory.c"
    sed -i '/^#include <linux\/sched\/sysctl.h>$/a #include <linux/zswap.h>' mm/memory.c
fi

# 6. Apply SUSFS kernel patch (find by glob — name differs per kernel branch)
SUSFS_KERNEL_PATCH="$(ls ${SUSFS_DIR}/kernel_patches/50_add_susfs_*.patch 2>/dev/null | head -n1 || true)"
if [[ -z "${SUSFS_KERNEL_PATCH}" ]]; then
    echo "ERROR: no 50_add_susfs_*.patch in ${SUSFS_DIR}/kernel_patches/" >&2
    exit 1
fi
echo "==> Applying SUSFS kernel patch: ${SUSFS_KERNEL_PATCH##*/}"
patch -p1 -F 3 -N --no-backup-if-mismatch -r /tmp/susfs.rej \
    -i "${SUSFS_KERNEL_PATCH}" || true

# 7. Revert the pre-SUSFS sed fixes
echo "==> Reverting pre-SUSFS sed fixes"
if [ "${SUBLEVEL}" -le 92 ] 2>/dev/null; then
    sed -i '/^#include <linux\/dma-buf.h>$/d' fs/proc/base.c
fi
if [ "${SUBLEVEL}" -le 57 ] 2>/dev/null; then
    sed -i '/^#include <linux\/zswap.h>$/d' mm/memory.c
fi

# 8. Module vermagic bypass hack (kernel/module.c single file in 5.15)
echo "==> Applying module vermagic bypass hack"
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
    echo "WARNING: bad_version not found in kernel/module.c — checking kernel/module/version.c"
    if grep -q "bad_version:" kernel/module/version.c 2>/dev/null; then
        sed -i '/bad_version:/{:a;n;/return 0;/{s/return 0;/return 1;/;b};ba}' kernel/module/version.c
        echo "  - bypass hack applied to kernel/module/version.c"
    else
        echo "ERROR: bad_version not found in either location" >&2
        exit 1
    fi
fi

# 9. Empty GKI protected-exports
echo "==> Emptying GKI protected-exports list"
if ls android/abi_gki_protected_exports_* >/dev/null 2>&1; then
    for f in android/abi_gki_protected_exports_*; do
        : > "$f"
        echo "  - emptied $f"
    done
else
    echo "  - no protected_exports files found (ok)"
fi

# 9b. SUSFS a13-5.15 fix: VMA_PAD_START is a 6.6+ macro, undefined in 5.15.
#     5.15 has no VMA padding, so fall back to vm_end (matches normal maps path).
echo "==> Defining VMA_PAD_START fallback for 5.15"
SUSFS_DEF_H="${KERNEL_DIR}/include/linux/susfs_def.h"
if grep -q "VMA_PAD_START" fs/proc/task_mmu.c 2>/dev/null \
    && ! grep -q "define VMA_PAD_START" "${SUSFS_DEF_H}" 2>/dev/null; then
    sed -i '/#endif \/\/ #ifndef KSU_SUSFS_DEF_H/i \
#ifndef VMA_PAD_START\n#define VMA_PAD_START(vma) ((vma)->vm_end)\n#endif' "${SUSFS_DEF_H}"
    echo "  - added VMA_PAD_START fallback to susfs_def.h"
else
    echo "  - VMA_PAD_START not needed or already defined (skipping)"
fi

# 9c. SUSFS a13-5.15 fix: Wild's combined 6.1 patch only defines fake_status /
#     initialize_fake_status under LINUX_VERSION_CODE >= 6.6, but the SUSFS
#     kernel patch wires selinuxfs.c to call them unconditionally under
#     CONFIG_KSU_SUSFS. On 5.15 that leaves them undefined -> link error.
#     Inject the <6.6 definitions into the #else branch.
echo "==> Defining fake_status / initialize_fake_status for <6.6"
SELINUX_HIDE_C="${KERNEL_DIR}/drivers/kernelsu/feature/selinux_hide.c"
if grep -q "initialize_fake_status" "${SELINUX_HIDE_C}" 2>/dev/null; then
    echo "  - already present (skipping)"
else
    # 9c-i. ksu_selinux_hide_enabled/running are static here, but the SUSFS
    #      kernel patch declares them extern in selinuxfs.c -> make non-static.
    sed -i 's/^static bool ksu_selinux_hide_enabled/bool ksu_selinux_hide_enabled/' "${SELINUX_HIDE_C}"
    sed -i 's/^static bool ksu_selinux_hide_running/bool ksu_selinux_hide_running/' "${SELINUX_HIDE_C}"
    python3 - "${SELINUX_HIDE_C}" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
needle = "#else\nstruct selinux_state fake_state;\n#endif"
inject = """#else
struct selinux_state fake_state;
DEFINE_STATIC_KEY_FALSE(fake_status_initialize_key);
struct page *fake_status = NULL;

void initialize_fake_status()
{
	mutex_lock(&selinux_state.status_lock);
	if (fake_status)
		goto out;
	if (!selinux_state.status_page) {
		pr_warn("initialize_fake_status: status_page not exist\\n");
		goto out;
	}

	struct selinux_kernel_status *status = page_address(selinux_state.status_page);
	if (!status->enforcing) {
		pr_warn("initialize_fake_status: skip not enforcing\\n");
		goto out;
	}

	struct page *new_page = alloc_page(GFP_KERNEL | __GFP_ZERO);
	if (!new_page) {
		pr_err("initialize_fake_status: failed to allocate page\\n");
		goto out;
	}

	struct selinux_kernel_status *new_status = page_address(new_page);
	memcpy(new_status, status, sizeof(*status));

	fake_status = new_page;
	pr_info("initialize_fake_status initialized: sequence=%d, policyload=%d, enforcing=%d\\n",
		new_status->sequence, new_status->policyload, new_status->enforcing);

out:
	mutex_unlock(&selinux_state.status_lock);
}
#endif"""
if needle not in src:
    sys.exit("ERROR: #else fake_state block not found")
src = src.replace(needle, inject, 1)
# ensure jump_label.h (DEFINE_STATIC_KEY_FALSE) is included
if "#include <linux/jump_label.h>" not in src:
    src = src.replace("#include <linux/mutex.h>", "#include <linux/mutex.h>\n#include <linux/jump_label.h>\n#include <linux/gfp.h>\n#include <linux/highmem.h>", 1)
open(path, "w").write(src)
print("  - injected fake_status block + includes")
PYEOF
fi

# 9d. selinux_hide.c uses kallsyms_lookup_name (>=6.6 branch) but lacks the header.
if grep -q "kallsyms_lookup_name" "${SELINUX_HIDE_C}" 2>/dev/null && ! grep -q "linux/kallsyms.h" "${SELINUX_HIDE_C}" 2>/dev/null; then
    sed -i 's/#include <linux\/version.h>/#include <linux\/version.h>\n#include <linux\/kallsyms.h>/' "${SELINUX_HIDE_C}"
    echo "  - added #include <linux/kallsyms.h> to selinux_hide.c"
else
    echo "  - selinux_hide.c kallsyms.h already handled (skipping)"
fi

# 10. KSU-Next x86_64 compatibility fixes
echo "==> Fixing KSU-Next x86_64 compatibility"

# 10a. compat_uptr_t missing include (CONFIG_COMPAT=y needs linux/compat.h)
KSUD_H="${KERNEL_DIR}/drivers/kernelsu/runtime/ksud.h"
if grep -q "compat_uptr_t" "${KSUD_H}" 2>/dev/null && ! grep -q "linux/compat.h" "${KSUD_H}" 2>/dev/null; then
    sed -i '/#include <asm\/syscall.h>/a #include <linux/compat.h>' "${KSUD_H}"
    echo "  - added #include <linux/compat.h> to ksud.h"
else
    echo "  - ksud.h already has compat.h or no compat_uptr_t (skipping)"
fi

# 10b. strncpy_from_user warn_unused_result (clang-18 -Werror)
SUCOMPAT="${KERNEL_DIR}/drivers/kernelsu/feature/sucompat.c"
if grep -q "strncpy_from_user(path, \*filename_user" "${SUCOMPAT}" 2>/dev/null; then
    sed -i 's/^\(\s*\)strncpy_from_user(path, \*filename_user/\1(void)strncpy_from_user(path, *filename_user/' "${SUCOMPAT}"
    echo "  - cast strncpy_from_user to (void) in sucompat.c"
else
    echo "  - sucompat.c already patched or pattern not found (skipping)"
fi

# 10c. TIF_SECCOMP undefined on x86_64 (use test_syscall_work on GENERIC_ENTRY)
APP_PROFILE="${KERNEL_DIR}/drivers/kernelsu/policy/app_profile.c"
if grep -q "test_thread_flag(TIF_SECCOMP)" "${APP_PROFILE}" 2>/dev/null; then
    sed -i 's/test_thread_flag(TIF_SECCOMP)/test_syscall_work(SECCOMP)/' "${APP_PROFILE}"
    echo "  - replaced test_thread_flag(TIF_SECCOMP) with test_syscall_work(SECCOMP)"
else
    echo "  - app_profile.c already patched or pattern not found (skipping)"
fi

# 11. Anti-emulator customizations
echo "==> Customizing kernel source for AVD anti-detection"
bash "${ROOT}/scripts/customize-kernel.sh" "${KERNEL_DIR}"

touch "${KERNEL_DIR}/.avd-patches-applied"
echo
echo "==> All patches applied successfully."
echo "    Next: scripts/build.sh"

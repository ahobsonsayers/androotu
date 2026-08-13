#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="${ROOT}/sources/kernel"

if [[ ! -f "${KERNEL_DIR}/.avd-patches-applied" ]]; then
    echo "ERROR: patches not yet applied. Run scripts/apply-patches.sh first." >&2
    exit 1
fi

cd "${KERNEL_DIR}"

export ARCH=x86_64
export LLVM=1
export LLVM_IAS=1
export CC=clang
export HOSTCC=clang
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export STRIP=llvm-strip

JOBS="${JOBS:-$(nproc)}"

echo "==> defconfig"
make -j "${JOBS}" gki_defconfig

# Append config overrides: KSU + SUSFS features + LOCALVERSION
cat >> .config <<'EOF'
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_LSM="landlock,lockdown,yama,loadpin,safesetid,selinux,smack,tomoyo,apparmor,bpf"
CONFIG_LOCALVERSION="-android16-5-Pixel10Pro"
# CONFIG_LOCALVERSION_AUTO is not set
CONFIG_DEFAULT_HOSTNAME="localhost"
EOF

# Disable full LTO (needs 5GB+ for vmlinux link → OOM on 8GB host). Use ThinLTO (~2GB).
./scripts/config --disable CONFIG_LTO_CLANG_FULL
./scripts/config --enable CONFIG_LTO_CLANG_THIN
# Keep BTF ENABLED (do NOT disable): CONFIG_DEBUG_INFO_BTF_MODULES=y (selected by
# BTF) changes `struct module` size (2 extra fields). Stock A36 vendor DLKMs
# expect that layout — disabling BTF breaks loading every vendor module with
# ".gnu.linkonce.this_module section size must match" → boot hang. Requires
# pahole/dwarves (installed in kbuild Dockerfile).
# Enable KSU debug mode so allow_shell=true by default (shell uid can use su)
./scripts/config --enable CONFIG_KSU_DEBUG
# Enable AVD virtio modules. A36 x86_64 ramdisk ships NO modules (stock kernel
# has them built-in), so they MUST be =y here or rootfs won't mount.
./scripts/config --enable CONFIG_PCI
./scripts/config --enable CONFIG_VIRTIO_BLK
./scripts/config --enable CONFIG_VIRTIO_CONSOLE
./scripts/config --enable CONFIG_VIRTIO_PCI
./scripts/config --enable CONFIG_HW_RANDOM_VIRTIO
./scripts/config --enable CONFIG_VIRTIO_DMA_SHARED_BUFFER
./scripts/config --enable CONFIG_VIRTIO_VSOCKETS
./scripts/config --enable CONFIG_VIRTIO_VSOCKETS_COMMON
./scripts/config --enable CONFIG_VIRTIO_BALLOON

make -j "${JOBS}" olddefconfig
echo "==> Build (parallel jobs=${JOBS})"
time make -j "${JOBS}" bzImage modules

echo
echo "==> Build complete"
ls -la arch/x86/boot/bzImage | sed 's|^|    |'

OUTDIR="${ROOT}/out"
mkdir -p "${OUTDIR}"
cp -fv arch/x86/boot/bzImage "${OUTDIR}/bzImage"
echo
echo "==> Kernel image copied to kernel-build/out/bzImage"

# Install modules to out/modules/
echo "==> Installing modules to out/modules/"
rm -rf "${OUTDIR}/modules"
make -j "${JOBS}" INSTALL_MOD_PATH="${OUTDIR}/modules" modules_install
echo "==> Modules installed to kernel-build/out/modules/"

echo
echo "Kernel build version banner:"
( strings arch/x86/boot/bzImage || true ) | grep -m1 "Linux version" | sed 's|^|    |' || true
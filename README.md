# rooted-android-emulator

A rooted Android 16 (API 36, x86_64, Google Play) emulator that passes
**MEETS_DEVICE_INTEGRITY** on the Play Integrity API, using
[Integrity Box](https://github.com/MeowDump/Integrity-Box) on a
KernelSU-Next + SUSFS kernel. Driven by [Taskfile](https://taskfile.dev).

**Result:** the emulator boots a real `google_apis_playstore` A36 image (not a
bare AOSP build) rooted with KSU, with GMS/DroidGuard fully functional and
`deviceIntegrity = MEETS_DEVICE_INTEGRITY`.

## Prerequisites

- Linux x86_64 host with KVM (`/dev/kvm`)
- ~3 GB free RAM (emulator bumps 1536 → ~2048 MB internally), ~6 GB disk
- `task`, `python3`, `curl`, `git`
- `ANDROID_HOME` (default `$HOME/Android/Sdk`) with:
  - the **android-36 `google_apis_playstore` x86_64** system image
    (`system-images;android-36;google_apis_playstore;x86_64` via sdkmanager)
  - a prebuilt KSU/SUSFS kernel at `kernel-build/out/bzImage-a36-btf`
    (build it once with `kernel-build/scripts/build-all.sh`, see below)

## Quick start

```sh
task install          # one-time: create the a36 AVD
task run              # create → boot → install modules → configure → verify
```

`task run` runs the full flow. On a fresh emulator use `WIPE_DATA=1` for the
first boot (the AVD is created clean, so this is usually unnecessary):

```sh
WIPE_DATA=1 task boot
```

## What each step does

1. **`01-create-avd.sh`** — create AVD `a36` (pixel_6, 1536 MB, headless
   config) from the A36 Play Store image.
2. **`02-boot-emulator.sh`** — boot headless with the custom kernel
   `bzImage-a36-btf` + stock ramdisk. Polls `sys.boot_completed` and waits for
   adb to come responsive.
3. **`03-install-modules.sh`** — push and `ksud module install` Integrity Box
   v40 (its installer auto-fetches a valid keybox), install KsuWebUIStandalone
   + KernelSU-Next manager **v3.2.0** (must match the kernel's embedded ksud),
   reboot.
4. **`04-configure.sh`** — set the Integrity Box **Supreme** profile (Pixel 8
   `shiba` CANARY), write the canonical `custom.pif.prop` toggle combo
   (`spoofProvider=1` + `spoofPixel=1` + `spoofSignature=1`), restart GMS.
5. **`05-verify-integrity.sh`** — check module presence, GMS, and that
   TEESimulator is in GENERATE mode (fresh key per request).

To verify the actual verdict, install [SPIC](https://github.com/herzhenr/spic-android)
and run a request:

```sh
adb install spic-v1.4.0.apk
adb shell am start -n com.henrikherzig.playintegritychecker/.MainActivity
# tap "Make Play Integrity Request" → expect "Device Integrity: MEETS_DEVICE_INTEGRITY"
```

## Result matrix

| Image | Profile | deviceIntegrity |
|---|---|---|
| A13 | tokay / panther (PIFork) | `UNEVALUATED` |
| A36 | tokay (PIFork) | `NO_INTEGRITY` |
| A36 | shiba (Integrity Box) | **`MEETS_DEVICE_INTEGRITY`** |

## Why not STRONG

`MEETS_DEVICE_INTEGRITY` is the realistic x86_64 ceiling. The keybox chain
roots to a self-signed TEE root, not Google's genuine hardware attestation
root — Google grants DEVICE but refuses STRONG. Passing STRONG requires a
keybox chaining to a real Google hardware root (real device TEE or genuine
leak), which means an arm64 host (Apple Silicon) or a physical Pixel. See
`docs/LEARNINGS.md` for the full analysis.

## Building the kernel (one-time)

The custom kernel adds KernelSU-Next (kernel-level root + ksud) and SUSFS
(hiding), plus AVD anti-detection tweaks:

```sh
cd kernel-build
./scripts/build-all.sh    # fetch sources → apply patches → build
```

Output: `kernel-build/out/bzImage-a36-btf` (also `out/bzImage`), plus modules
in `kernel-build/out/modules/`. Requires a Linux x86_64 host with clang-18+,
lld, llvm, `dwarves` (pahole) and ~8 GB RAM for the link step. The included
`kernel-build/Dockerfile` provides the full toolchain.

## Clean up

```sh
task clean          # remove the a36 AVD (keeps SDK + kernel)
```

## Credits

This project builds on several excellent open-source projects:

- [MeowDump/Integrity-Box](https://github.com/MeowDump/Integrity-Box) — the PIF
  module + WebUI that gets `MEETS_DEVICE_INTEGRITY` via its Supreme profile and
  Attestation API / Pixelify Playstore toggles. The keybox is auto-fetched by
  its installer.
- [tanishmeh/AVD_Rooted_Integrity](https://github.com/tanishmeh/AVD_Rooted_Integrity)
  — the reference repository for rooted STRONG-integrity AVDs (KSU-Next +
  SUSFS + TEESimulator + PIF on an arm64 android-36 AVD); its
  `REPRODUCTION.md` and `INTEGRITY_CHAIN.md` guided our stack.
- [KernelSU-Next/KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)
  — kernel root + `ksud` module manager.
- [simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) — SUSFS hiding
  (SUS_PATH/SUS_MOUNT/SUS_KSTAT/SUS_MAP/OPEN_REDIRECT) and the
  [WildKernels/kernel_patches](https://github.com/WildKernels/kernel_patches)
  KSU↔SUSFS integration patch.
- [5ec1cff/TrickyStore](https://github.com/5ec1cff/TrickyStore) — TEESimulator:
  keybox-based key generation/attestation on emulator hardware (no real TEE).
- [RevokeForCash/ReZygisk](https://github.com/RevokeForCash/ReZygisk) — Zygisk
  runtime required by Integrity Box.
- [5ec1cff/KsuWebUIStandalone](https://github.com/5ec1cff/KsuWebUIStandalone) —
  WebUI host for managing Integrity Box.
- [herzhenr/spic-android](https://github.com/herzhenr/spic-android) — SPIC,
  the Play Integrity verdict checker.
- [AOSP kernel/common](https://android.googlesource.com/kernel/common)
  `android15-6.6` — the base kernel; the android-36 `google_apis_playstore`
  system image.
- [newbit1/rootAVD](https://github.com/newbit1/rootAVD) — the original Magisk
  AVD rooting approach (superseded here by KSU).
- [remote-android/redroid](https://github.com/remote-android/redroid) —
  Android-in-Docker route evaluated but not chosen.

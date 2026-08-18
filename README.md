# Rooted Android 16 AVD · Play Integrity

**A reproducible recipe for a rooted Android 16 (API 36, x86_64) emulator that passes Google Play Integrity with `MEETS_DEVICE_INTEGRITY`.**

[![Verdict](https://img.shields.io/badge/Play_Integrity-MEETS__DEVICE__INTEGRITY-3fd07f?style=flat-square)](docs/LEARNINGS.md)
[![Device](https://img.shields.io/badge/device-Pixel_8_·_android--36_·_x86__64-4f8cff?style=flat-square)](avd/config/custom.pif.prop)
[![Kernel](https://img.shields.io/badge/kernel-custom_6.6_·_KSU--Next_+_SUSFS-7c5cff?style=flat-square)](kernel/)
[![Type](https://img.shields.io/badge/contents-source_+_scripts_only-6b7689?style=flat-square)](#scope)

---

A reproducible recipe for a **rooted Pixel-class Android emulator (AVD) that
passes Google Play Integrity to `MEETS_DEVICE_INTEGRITY`** and presents as a
real Pixel 8 (`shiba`) to Play Services. It combines a custom kernel
(KernelSU-Next + SUSFS + AVD anti-detection patches) with
[Integrity Box](https://github.com/MeowDump/Integrity-Box), whose WebUI toggles
drive the PIF profile and whose installer auto-fetches the attestation keybox —
TEESimulator forges the hardware attestation chain from that keybox.

> **This is a development/testing tool** for reproducing device-integrity
> behavior on an emulator. `MEETS_DEVICE_INTEGRITY` is the realistic x86_64
> ceiling — see [Why not STRONG](#why-not-strong).

## What's here

| Path | What |
|---|---|
| [`avd/scripts/`](avd/scripts/) | `00-download-kernel.sh` (fetch the prebuilt kernel from the rolling release), `01-create-avd.sh` (AVD from the A36 Play Store image), `02-boot-emulator.sh` (cold-boot with the custom kernel), `03-install-modules.sh` (Integrity Box + TEESimulator + ReZygisk + SUSFS + manager + WebUI), `04-configure.sh` (Supreme profile + toggle combo), `05-verify-integrity.sh` (read-only health check, incl. the GENERATE-vs-PATCH mode check). |
| [`avd/config/custom.pif.prop`](avd/config/custom.pif.prop) | The single source of truth for the spoofed device identity — Pixel 8 (`shiba`) CANARY profile + the toggle combo that passes. |
| [`kernel/`](kernel/) | Docker + scripts that build AOSP `common-android15-6.6` with KSU-Next, SUSFS, module-vermagic bypass, and AVD anti-detection tweaks. Output: `out/bzImage-a36-btf`. |
| [`docker/`](docker/) | A self-contained Docker image (multi-stage: compiles the kernel, bakes it in) that runs the same rooted AVD in a container, published to GHCR. |
| [`Taskfile.yml`](Taskfile.yml) | Thin wrapper over `avd/scripts/` (`task install` → `task run` → `task verify`). |
| [`docs/LEARNINGS.md`](docs/LEARNINGS.md) | The full journey and every pitfall. |

## Quick start

There are **two ways to run** this — a native AVD on your host, or a Docker
image. Both use the same custom kernel and module stack; neither requires
building the kernel yourself.

### Option A — Docker image (recommended, self-contained)

The image compiles the kernel and bakes it in, so there's nothing to build:

```bash
docker pull ghcr.io/ahobsonsayers/androotu:latest
docker run -d --name a36-integrity \
  --device /dev/kvm --privileged \
  -p 5555:5555 \
  -v "$PWD/data:/data" \
  ghcr.io/ahobsonsayers/androotu:latest
```

First boot provisions the AVD (~10-20 min; watch `docker logs -f a36-integrity`
for `Success !!`). See [`docker/README.md`](docker/README.md) for the full
build/run/use guide.

### Option B — Native AVD on your host

```bash
# 0. One-time prerequisites:
#    ANDROID_HOME with system-images;android-36;google_apis_playstore;x86_64
#    + a prebuilt kernel at kernel/dist/bzImage-a36-btf

avd/scripts/00-download-kernel.sh   # fetch the prebuilt kernel from the rolling release
task install                    # create the a36 AVD
task run                        # create → boot → install modules → configure → verify
```

Full walkthrough: the five numbered steps under [Taskfile](#taskfile).

## ⚠️ The traps that waste hours (read before debugging)

1. **NEVER restart `keymint` / `keystore2` / `TEESimulator` after boot.** It
   flips TEESimulator from **GENERATE** mode (fresh attested key per request)
   into **PATCH** mode (a cached chain Google rejects) → empty verdict. To
   apply any change, **cold reboot**. Recovery from a broken verdict is also
   just a cold reboot — never a service restart.
2. **Never hand-edit `/data/adb/tricky_store/keybox.xml`.** Integrity Box's
   installer auto-fetches and manages it. Backing it up or restoring one flips
   the verdict — a fresh install auto-fetches a working keybox.

After a clean boot, confirm TEESimulator is in GENERATE mode:

```bash
task verify    # read-only; checks GENERATE-vs-PATCH, modules, props
```

The full story is in [`docs/LEARNINGS.md`](docs/LEARNINGS.md).

## The keybox (read this)

TEESimulator forges the hardware attestation chain from
`/data/adb/tricky_store/keybox.xml`. **You never touch this file.** Integrity
Box's installer fetches a working keybox at install time (and its WebUI's
"Integrity Downloader" can refresh it). A keybox committed to a public repo
gets harvested and revoked by Google within hours — which is exactly why the
repo vendors **none** and auto-fetches instead. Because that keybox's chain
roots to a self-signed TEE root (not Google's genuine hardware attestation
root), Google grants **DEVICE** but refuses **STRONG**.

## Scope

- ✅ **`MEETS_DEVICE_INTEGRITY`** on a rooted x86_64 AVD: custom kernel, KSU
  root, SUSFS hiding, Integrity Box profile/toggle spoofing, TEESimulator
  attestation forging, GMS/DroidGuard fully functional.
- ✅ **arm64 apps run** via the image's native-bridge translation
  (`x86_64,arm64-v8a` abilist, `libndk_translation.so`) — slower than native
  x86_64, fine for most apps. Doesn't affect the device verdict.
- ❌ **No `MEETS_STRONG_INTEGRITY`** — requires a keybox rooted in Google's
  genuine hardware attestation root (real device TEE or genuine leak), i.e. an
  arm64 host (Apple Silicon) or a physical Pixel.
- ✅ **Prebuilt kernel + Docker image published** to GitHub (rolling release +
  GHCR) — no one builds the kernel themselves.

## Validated configuration

Pixel 8 (`shiba`) CANARY profile, android-36 `google_apis_playstore x86_64`,
custom 6.6 kernel. Verified verdicts:

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

## Taskfile

| Task | Runs |
|---|---|
| `task install` | `01-create-avd.sh` |
| `task boot` | `02-boot-emulator.sh` |
| `task install:modules` | `03-install-modules.sh` |
| `task configure` | `04-configure.sh` |
| `task verify` | `05-verify-integrity.sh` |
| `task run` | the full chain above |
| `task clean` | remove the `a36` AVD (keeps SDK + kernel) |

## Building the kernel (optional)

The custom kernel adds KernelSU-Next (kernel-level root + ksud) and SUSFS
(hiding), plus AVD anti-detection tweaks. **You usually don't need to build it** —
the prebuilt kernel is published to the `kernel-latest` rolling GitHub release
and fetched by `avd/scripts/00-download-kernel.sh` (or baked into the Docker image).

To build it yourself:

```sh
cd kernel
./build/build-all.sh    # fetch sources → apply patches → build
```
Output: `kernel/dist/bzImage-a36-btf` (also `dist/bzImage`), plus modules
in `kernel/dist/modules/`. Requires a Linux x86_64 host with clang-18+,
lld, llvm, `dwarves` (pahole) and ~8 GB RAM for the link step. The included
`kernel/Dockerfile` provides the full toolchain and is published to GHCR as
`ghcr.io/ahobsonsayers/androotu-kernel`.

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

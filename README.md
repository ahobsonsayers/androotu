# androotu

**A rooted Android emulator — run it in Docker or natively — that passes Google Play Integrity with `MEETS_DEVICE_INTEGRITY`.**

[![Verdict](https://img.shields.io/badge/Play_Integrity-MEETS__DEVICE__INTEGRITY-3fd07f?style=flat-square)](LEARNINGS.md)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A reproducible recipe for a rooted Android 16 (API 36, x86_64) emulator that
presents as a real Pixel 8 to Play Services and passes device integrity. It
combines a custom kernel (KernelSU-Next + SUSFS) with
[Integrity Box](https://github.com/MeowDump/Integrity-Box), whose installer
auto-fetches the attestation keybox and whose WebUI drives the PIF profile.

> [!WARNING]
> This is a **development/testing tool**. `MEETS_DEVICE_INTEGRITY` is the
> realistic x86_64 ceiling — see [Why not STRONG](#why-not-strong).

## Quick start

There are two ways to run it. Neither requires building the kernel — a prebuilt
KSU/SUSFS kernel is published to a rolling GitHub release and fetched
automatically.

### Option A — Docker (recommended)

Requires Docker with KVM passthrough (`/dev/kvm`). x86_64 host only.

```bash
docker pull ghcr.io/ahobsonsayers/androotu:latest
docker run -d --name androotu \
  --device /dev/kvm \
  --privileged \
  -p 5555:5555 \
  -v "$PWD/data:/data" \
  ghcr.io/ahobsonsayers/androotu:latest
```

First boot provisions the AVD (creates it, installs the module stack, configures
the profile, verifies) — ~10-20 min. Watch it with `docker logs -f androotu`;
you'll know it's done when you see `Success !!`.

The Play Store image forces `ro.adb.secure=1`, so external ADB clients must
present the image's baked-in key:

```bash
docker run --rm --entrypoint cat androotu:latest /root/.android/adbkey > adbkey
ADB_VENDOR_KEYS=$PWD/adbkey adb connect localhost:5555
```

Browser control is available at `http://localhost:8000` (scrcpy-web).

### Option B — Native AVD

Requires `ANDROID_HOME` with the `system-images;android-36;google_apis_playstore;x86_64`
image, plus [Task](https://taskfile.dev).

```bash
avd/scripts/00-download-kernel.sh   # fetch the prebuilt kernel
task install                        # create the a36 AVD
task run                            # boot → install modules → configure → verify
```

## The traps that waste hours

1. **Never restart `keymint` / `keystore2` / `TEESimulator` after boot.** It
   flips TEESimulator from GENERATE to PATCH mode and drops the verdict. To
   apply any change, **cold reboot**.
2. **Never hand-edit `/data/adb/tricky_store/keybox.xml`.** Integrity Box's
   installer auto-fetches and manages it. A fresh install auto-fetches a
   working keybox.

After a clean boot, confirm TEESimulator is in GENERATE mode with `task verify`.

## Why not STRONG

`MEETS_DEVICE_INTEGRITY` is the realistic x86_64 ceiling. The keybox chain roots
to a self-signed TEE root, not Google's genuine hardware attestation root — so
Google grants DEVICE but refuses STRONG. Passing STRONG requires a keybox
chaining to a real Google hardware root, which means an arm64 host (Apple
Silicon) or a physical Pixel.

## Taskfile

| Task | Runs |
|---|---|
| `task install` | create the `a36` AVD |
| `task boot` | boot with the custom kernel |
| `task install:modules` | install Integrity Box + WebUI/manager, reboot |
| `task configure` | Supreme profile + toggles, restart GMS |
| `task verify` | check the stack + TEESimulator GENERATE mode |
| `task run` | the full chain above |
| `task lint` | shfmt + shellcheck + `bash -n` all scripts |
| `task clean` | remove the `a36` AVD (keeps SDK + kernel) |

## Credits

Built on [dockerify-android](https://github.com/Shmayro/dockerify-android),
[Integrity Box](https://github.com/MeowDump/Integrity-Box),
[KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next),
[susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu),
[TrickyStore](https://github.com/5ec1cff/TrickyStore), and
[ReZygisk](https://github.com/RevokeForCash/ReZygisk). See
[`LEARNINGS.md`](LEARNINGS.md) for the full journey and every pitfall.

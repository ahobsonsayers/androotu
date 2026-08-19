# androotu

**A rooted Android emulator — run it in Docker or natively — that passes Google Play Integrity with `MEETS_DEVICE_INTEGRITY` and Automatic Integrity Protection (AIP).**

[![Verdict](https://img.shields.io/badge/Play_Integrity-MEETS__DEVICE__INTEGRITY-3fd07f?style=flat-square)](LEARNINGS.md)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A reproducible recipe for a rooted Android 16 (API 36, x86_64) emulator that
presents as a real Pixel 8 to Play Services and passes device integrity. It
combines a custom kernel (KernelSU-Next + SUSFS) with
[Integrity Box](https://github.com/MeowDump/Integrity-Box), whose installer
auto-fetches the attestation keybox and whose WebUI drives the PIF profile.

The focus is Play Integrity, but the stack also does **best-effort root hiding**
(SUSFS kernel-level hiding + ReZygisk) to try to get past other root-detection
methods apps may use. It's not a guarantee — treat it as a bonus, not a promise.

It also passes **Automatic Integrity Protection (AIP / PairIP)**, so apps that
check whether they were installed from the Play Store (via `com.pairip.licensecheck`)
won't flag this image as a sideloaded install. This is handled by
[BetterKnownInstalled](https://github.com/Pixel-Props/BetterKnownInstalled), which
patches `packages.xml` to present every app as Play Store–installed.

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

#### Custom startup scripts

To install extra apps or modules on first boot, drop `.sh` scripts into a
directory and mount it at `/opt/scripts`. They run in sorted order after the
stack is up, so `adb` and `su` are available:

```bash
docker run -d --name androotu \
  --device /dev/kvm \
  --privileged \
  -p 5555:5555 \
  -v "$PWD/data:/data" \
  -v "$PWD/extensions:/opt/scripts" \
  ghcr.io/ahobsonsayers/androotu:latest
```

The repo ships three working examples in [`extensions/`](extensions/):

- `install-module.sh` — installs the [bindhosts](https://github.com/bindhosts/bindhosts) module (systemless hosts / ad blocking) via `ksud module install`, then reboots to activate it.
- `install-app-github.sh` — installs the [AdAway](https://github.com/AdAway/AdAway) app (open-source ad blocker) via `adb install`.
- `install-app-gplay.sh` — installs [Integrity Check](https://play.google.com/store/apps/details?id=gr.nikolasspyr.integritycheck) from the Play Store via [gplaydl](https://github.com/rehmatworks/gplaydl), using the anonymous [Aurora dispenser](https://auroraoss.com) instead of a Google login, then reboots so [BetterKnownInstalled](https://github.com/Pixel-Props/BetterKnownInstalled) marks it as a Play Store install.

> [!NOTE]
> The A36 x86_64 Play Store image runs ARM apps through NDK translation
> (`ro.dalvik.vm.native.bridge=libndk_translation.so`), so ARM builds fetched
> from the Play Store install and run normally. The gplaydl example downloads
> the `arm64` build for this reason.
>
> The Aurora dispenser (`https://auroraoss.com/api/auth`) is a shared,
> rate-limited service run by the Aurora Store community. It's fine for a demo,
> but don't rely on it for heavy or repeated use.

> [!NOTE]
> `ksud module install` only stages a module — it activates on the **next boot**.
> The bindhosts example reboots the emulator to activate it. Apps installed via
> `adb install` are active immediately, but the gplay example reboots anyway so
> [BetterKnownInstalled](https://github.com/Pixel-Props/BetterKnownInstalled) can
> re-mark the newly installed app as a Play Store install.

Scripts run once per `/data` volume (first boot only). To re-run them, wipe the
volume or remove `/data/.first-boot-done`.

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

- [dockerify-android](https://github.com/Shmayro/dockerify-android) — the Docker/AVD architecture this is built on
- [Integrity Box](https://github.com/MeowDump/Integrity-Box) — PIF profile + WebUI toggles + keybox
- [BetterKnownInstalled](https://github.com/Pixel-Props/BetterKnownInstalled) — patches `packages.xml` so installed apps present as Play Store installs (helps AIP/PairIP)
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) — kernel-level root
- [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) — kernel-level root hiding
- [TrickyStore](https://github.com/5ec1cff/TrickyStore) — TEESimulator attestation forging
- [ReZygisk](https://github.com/RevokeForCash/ReZygisk) — Zygisk runtime for the module hooks

See [`LEARNINGS.md`](LEARNINGS.md) for the full journey and every pitfall.

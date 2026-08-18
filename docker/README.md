# Dockerized A36 Integrity Box emulator

A dockerify-style container for the rooted Android 16 (API 36, x86_64) AVD
that passes **MEETS_DEVICE_INTEGRITY**. Two containers, mirroring
[dockerify-android](https://github.com/Shmayro/dockerify-android):

> **Credits:** This project is built on the architecture, Dockerfile layout, and
> first-boot provisioning model of
> [Shmayro/dockerify-android](https://github.com/Shmayro/dockerify-android)
> (supervisord programs, socat ADB forwarding, `/data` volume, first-boot
> marker). Where dockerify runs a plain AOSP AVD, this project swaps in the
> custom KSU/SUSFS kernel and the Integrity Box module stack so the emulator
> passes device integrity. Everything here is layered on top of dockerify's
> approach — big thanks to that project.

- **`a36-integrity`** — the emulator, booted with the custom KSU/SUSFS kernel.
  Exposes ADB on `:5555`. The AVD + userdata live in a persistent `/data`
  volume.
- **`scrcpy-web`** — browser control of the emulator at `:8000`.

## Prerequisites

- Docker with **KVM** passthrough (`/dev/kvm`). x86_64 host only — the custom
  kernel is x86_64, so this does **not** run on arm64/Apple Silicon.

## Build

The image is **self-contained**: a multi-stage build compiles the KSU/SUSFS
kernel from source (stage 1) and bakes it in (stage 2). No prebuilt kernel is
needed in the build context.

```bash
cd docker
docker compose build
```

The build bakes in the A36 system image, the custom kernel, and the module
zips/APKs. Rebuild to refresh the modules (e.g. when a keybox is revoked).

## Run

```bash
cd docker
docker compose up -d
```

First boot provisions the AVD (creates it, installs Integrity Box +
TEESimulator + ReZygisk + SUSFS + WebUI, configures the Supreme profile,
verifies). This takes ~10-20 min. Watch it:

```bash
docker logs -f a36-integrity
```

You'll know it's done when you see `Success !!`.

## Pull from GHCR

The image is published to GitHub Container Registry. Pull it instead of
building:

```bash
docker pull ghcr.io/ahobsonsayers/androotu:latest
docker run -d --name a36-integrity \
  --device /dev/kvm --privileged \
  -p 5555:5555 \
  -v "$PWD/data:/data" \
  ghcr.io/ahobsonsayers/androotu:latest
```

## Use

The Play Store image forces `ro.adb.secure=1`, so external ADB clients must
present the image's baked-in key. The image ships a deterministic adb keypair
at `/root/.android/adbkey` (generated at build time). Point your host adb at it
via `ADB_VENDOR_KEYS`:

```bash
# Extract the baked key once (it's identical for every container instance).
docker run --rm --entrypoint cat a36-integrity:latest /root/.android/adbkey > adbkey

# Connect with that key.
ADB_VENDOR_KEYS=$PWD/adbkey adb connect localhost:5555
ADB_VENDOR_KEYS=$PWD/adbkey adb devices
```

`scrcpy-web` uses the container's own adb, so it needs no key setup.

Browser UI: open `http://localhost:8000`.

## Notes

- **Keybox is not baked in.** Integrity Box's installer auto-fetches it at
  first boot into `/data/adb/tricky_store/keybox.xml`. Never hand-edit it.
- **User data persists** in `./data` (the AVD's data partition is pinned to
  `./data/a36.avd/userdata-qemu.img` via `-data`). To start clean, delete the
  volume and re-run (a fresh install auto-fetches a working keybox).
  **Persistence is optional:** mount `./data` as a volume (as in
  `compose.yml`) to keep user data across restarts, or omit the mount to
  run a stateless ephemeral emulator.
- **Never restart `keymint`/`keystore2`/`TEESimulator`** after boot — it flips
  TEESimulator from GENERATE to PATCH mode and drops the verdict. Cold reboot
  to recover.
- The emulator bumps RAM to 2048MB internally regardless of `-memory`.

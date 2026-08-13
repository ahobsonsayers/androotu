# rooted-android-emulator

A rooted Android 13 (API 33, x86_64, Google Play) emulator with Magisk, runnable natively or in Docker. Driven by [Taskfile](https://taskfile.dev).

Root via [rootAVD](https://github.com/newbit1/rootAVD): it patches the AVD's `ramdisk.img` with Magisk while the emulator is online, then a UI-automation script finishes Magisk's "Direct Install" and grants `shell` superuser so `adb shell su` works headlessly.

For Play Integrity work (android-36 A16 x86_64, KSU-Next stack), see `docs/LEARNINGS.md`.

## Prerequisites

- Linux x86_64 host with KVM (`/dev/kvm`)
- ~3 GB free RAM (emulator bumps 1536 → ~2048 MB internally), ~6 GB disk
- `task`, `docker` + `docker compose` (Docker path only), `python3`, `wget`, `unzip`, `git`

## Native

```sh
task install:native      # one-time: SDK + AVD + rootAVD clone
task run:native          # boot unrooted → patch ramdisk → cold boot → finish Magisk → verify
task verify              # su -c id, magisk -v, Play Store + GMS
```

### What `run:native` does

1. **`step:4-root`** — boot unrooted with `-wipe-data`, clean stale Magisk workspace, run `rootAVD.sh` (`echo 1 |` selects Magisk Stable). Patches ramdisk, installs `Magisk.apk`, shuts down.
2. **`step:5-boot`** — cold boot (no wipe, keeps `Magisk.apk`). Polls `sys.boot_completed`.
3. **`step:6-setup-magisk`** — UI automation: Direct Install + reboot, then grant `shell` su via the Superuser screen.
4. **`step:7-verify`** — checks root, Magisk, Play Store + GMS.

### Individual steps

```sh
task step:1-setup-sdk      # install Android SDK + API 33 Play Store image
task step:2-create-avd     # create AVD rooted33 (pixel_6, 1536 MB, headless)
task step:3-clone-rootavd  # clone rootAVD repo
task step:4-root           # boot unrooted + patch ramdisk
task step:5-boot           # cold-boot (WIPE_DATA=1 for clean boot)
task step:6-setup-magisk   # finish Magisk env + grant shell su
task step:7-verify         # check root + Magisk + Play Store
```

### Interact

```sh
adb shell su -c id         # uid=0(root) ... context=u:r:magisk:s0
```

### Clean up

```sh
task clean:native          # remove AVD + rootAVD clone (keeps SDK)
```

## Docker

```sh
task install:docker     # build image
task run:docker         # compose up -d; entrypoint runs the full flow
task docker:logs        # tail container logs
task docker:verify      # verify-root inside container
task docker:adb         # adb shell in container
task docker:down        # stop container
task clean:docker       # remove image + avd-data volume
```

Notes:
- Container mounts `/dev/kvm`, exposes `5554`/`5555`.
- `avd-data` volume persists the AVD — re-run skips re-patching if ramdisk already modified.
- Base image [`halimqarroum/docker-android:api-33-playstore`](https://hub.docker.com/r/halimqarroum/docker-android).

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `ANDROID_HOME` | `$HOME/Android/Sdk` | SDK location (host) or `/opt/android` (Docker) |
| `ROOTAVD_DIR` | `$HOME/rootAVD` | rootAVD clone location |
| `ANDROID_SERIAL` | `emulator-5554` | adb serial for multi-device hosts |
| `EMULATOR_RAM` | `1536` | emulator RAM in MB (Docker bumps to 2048 internally) |
| `AVD_NAME` | `rooted33` | AVD name |
| `WIPE_DATA` | `0` | `1` = pass `-wipe-data` to `boot` |

## How root works

1. `rootAVD.sh` runs **while the emulator is online** (needs ADB). It pushes Magisk binaries, patches `ramdisk.img` in place, streams `Magisk.apk` onto the device, shuts down.
2. Cold boot loads the patched ramdisk → `magisk -v` reports `25.2:MAGISK:R`.
3. `06-setup-magisk.sh` runs Magisk's "Direct Install" (writes Magisk into the ramdisk) and grants `shell` su by toggling the `policy_indicator` switch on the Superuser screen.
4. After that, `adb shell su -c <cmd>` runs as root.

UI-automation coordinates target `pixel_6` at `1080×2400`. Other device skins: re-derive with `adb shell uiautomator dump /sdcard/ui.xml && adb shell cat /sdcard/ui.xml`.

# rooted-android-emulator

A rooted Android 13 (API 33, x86_64, Google Play) emulator with Magisk, runnable natively or in Docker. Automation is driven by [Taskfile](https://taskfile.dev).

Root is achieved via [rootAVD](https://github.com/newbit1/rootAVD), which patches the AVD's `ramdisk.img` with Magisk while the emulator is online, then reboots. A UI-automation script finishes Magisk's "Direct Install" and grants the `shell` app superuser permission so `adb shell su` works headlessly.

## Prerequisites

- Linux x86_64 host with KVM (`/dev/kvm`)
- ~3 GB free RAM for the emulator (it bumps 1536 MB up to ~2048 MB internally)
- ~6 GB disk for the SDK + system image + AVD
- `task` (Taskfile) — install via `brew install go-task` or see [taskfile.dev/install](https://taskfile.dev/installation/)
- `docker` + `docker compose` (only for the Docker path)
- `python3` (used by `02-create-avd.sh` to dedup `config.ini`)
- `wget`, `unzip`, `git`

## Native (run on the host)

One-time setup — install the SDK, create the AVD, clone rootAVD:

```sh
task install:native
```

Run the full root flow — boot unrooted, patch ramdisk, cold boot, finish Magisk, verify:

```sh
task run:native
```

That's it. When it finishes, verify root:

```sh
task verify
```

Expected output:

```
Checking root...      PASS: rooted
Checking Magisk...    PASS: 25.2:MAGISK:R
Checking Play Store + GMS...  PASS: com.android.vending
                        PASS: com.google.android.gms
All checks passed.
```

### What `run:native` does

1. **`step:4-root`** — boots the emulator unrooted with `-wipe-data`, cleans any stale Magisk workspace on the device, runs `rootAVD.sh` (auto-selects Magisk Stable via `echo 1 |`). rootAVD patches `ramdisk.img`, installs `Magisk.apk`, and shuts the emulator down.
2. **`step:5-boot`** — cold-boots the patched emulator (no wipe, so `Magisk.apk` stays in userdata). Polls `sys.boot_completed`.
3. **`step:6-setup-magisk`** — UI automation: skips Step A if Magisk is already installed; otherwise taps Install → Direct Install → LET'S GO → Reboot. Then grants `shell` su via Magisk's Superuser screen (toggles the `policy_indicator` switch for `com.android.shell`).
4. **`step:7-verify`** — checks `su -c id`, `magisk -v`, and Play Store + GMS packages.

### Individual steps

```sh
task step:1-setup-sdk      # install Android SDK + API 33 Play Store image
task step:2-create-avd     # create AVD rooted33 (pixel_6, 1536 MB, headless config)
task step:3-clone-rootavd  # clone rootAVD repo
task step:4-root           # boot unrooted + patch ramdisk
task step:5-boot           # cold-boot the patched emulator (WIPE_DATA=1 for clean boot)
task step:6-setup-magisk   # finish Magisk env + grant shell su
task step:7-verify         # check root + Magisk + Play Store
```

### Interact with the running emulator

```sh
adb shell              # shell as the shell user
adb shell su -c id     # should return uid=0(root) ... context=u:r:magisk:s0
```

### Clean up native state

```sh
task clean:native      # removes the AVD + rootAVD clone (keeps the SDK)
```

## Docker

One-time setup — build the image:

```sh
task install:docker
```

Run the full flow in a container (the entrypoint does the same steps as `run:native`):

```sh
task run:docker
```

Tail logs or verify inside the running container:

```sh
task docker:logs
task docker:verify
```

Open an adb shell inside the container:

```sh
task docker:adb
```

Stop the container:

```sh
task docker:down
```

Clean up Docker state (removes the image + the `avd-data` volume):

```sh
task clean:docker
```

### Notes

- The container mounts `/dev/kvm` and exposes ports `5554`/`5555`.
- The `avd-data` named volume persists the AVD across container restarts, so re-running `task run:docker` skips re-patching if the ramdisk is already modified (delete the volume with `task clean:docker` to start fresh).
- The base image is [`halimqarroum/docker-android:api-33-playstore`](https://hub.docker.com/r/halimqarroum/docker-android), which already contains the SDK + API 33 Play Store system image.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `ANDROID_HOME` | `$HOME/Android/Sdk` | SDK location (host) or `/opt/android` (Docker) |
| `ROOTAVD_DIR` | `$HOME/rootAVD` | Where the rootAVD clone lives |
| `ANDROID_SERIAL` | `emulator-5554` | adb serial for multi-device hosts |
| `EMULATOR_RAM` | `1536` | Emulator RAM in MB (Docker bumps to 2048 internally) |
| `AVD_NAME` | `rooted33` | AVD name |
| `WIPE_DATA` | `0` | Set to `1` for `boot` to pass `-wipe-data` |

## How root works

1. `rootAVD.sh` is invoked **while the emulator is running** (it needs an ADB connection). It pushes Magisk binaries to the device, patches `ramdisk.img` in-place (pulling it back as `ramdiskpatched4AVD.img` and replacing the system-image `ramdisk.img`), streams `Magisk.apk` onto the device, and shuts the emulator down.
2. A cold boot loads the patched ramdisk — Magisk init runs and `magisk -v` reports `25.2:MAGISK:R`.
3. `06-setup-magisk.sh` finishes Magisk's in-app "Direct Install" (writes Magisk into the ramdisk slot via the app) and grants the `shell` app superuser permission by toggling the `policy_indicator` switch on Magisk's Superuser screen.
4. After this, `adb shell su -c <cmd>` runs as root.

The UI-automation coordinates target `pixel_6` at `1080×2400`. If you use a different device skin, re-derive the tap coordinates with `adb shell uiautomator dump /sdcard/ui.xml && adb shell cat /sdcard/ui.xml`.
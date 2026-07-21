# AGENTS.md

Taskfile-driven rooted Android 13 (API 33) emulator with Magisk. Native + Docker paths.

## Commands

```sh
task install:native     # one-time: step:1 + step:2 + step:3
task run:native         # full root flow: step:4 → step:5 → step:6 → step:7
task step:7-verify      # check su -c id, magisk -v, Play Store + GMS

task install:docker     # build docker image
task run:docker         # docker compose up -d (entrypoint does full flow)
task docker:logs        # tail container logs
task docker:verify      # run verify-root inside container
task docker:adb         # adb shell in container
task docker:down        # stop container
task clean:native       # remove AVD + rootAVD clone (keeps SDK)
task clean:docker       # remove image + volume
```

Scripts are numbered `scripts/01-setup-sdk.sh` … `scripts/07-verify-root.sh` in execution order. Tasks mirror them as `step:1-setup-sdk` … `step:7-verify`. The Taskfile is thin — just calls scripts. Don't inline logic into Taskfile.yml.

## Critical root flow (don't get wrong)

1. **rootAVD requires the emulator ONLINE** (needs ADB connection). Flow: boot unrooted (`-wipe-data`) → run `rootAVD.sh` while running → rootAVD patches ramdisk, installs `Magisk.apk`, shuts emulator down → cold boot (NO wipe).
2. **`-wipe-data` wipes Magisk.apk from userdata.** Only use for the first unrooted boot. Never after Magisk is installed.
3. **`rootAVD.sh` prepends `$ANDROID_HOME` to its first arg.** Pass a RELATIVE path: `system-images/android-33/google_apis_playstore/x86_64/ramdisk.img`. Absolute paths double-prepend and rootAVD silently prints help + exits.
4. **`echo 1 |` before `rootAVD.sh`** auto-selects Magisk Stable from the interactive version menu. Without it, rootAVD prints help and exits.
5. **Clean `/data/data/com.android.shell/Magisk` on device before each rootAVD run.** Stale files from a prior failed run cause `ramdisk.img uses UNKNOWN compression` → abort. Both `scripts/04-root-avd.sh` and `docker/entrypoint.sh` do this.
6. After rootAVD + cold boot, `su -c id` returns "Permission denied" — Magisk env not complete. `scripts/06-setup-magisk.sh` finishes it via UI automation (Direct Install + grant shell su).

## Emulator boot gotchas

- **Detach with `setsid nohup ... < /dev/null &`** — plain `&` gets killed when the launcher shell exits. `disown` is bash-only and NOT available in dash (Taskfile runs cmds with `/bin/sh`).
- **`adb wait-for-device` returns before authorization.** Poll `getprop sys.boot_completed` in a loop (120×3s).
- **After `boot_completed=1`, adb shell can still return "device offline" for several seconds.** Poll `adb shell true` until it succeeds (30×2s). See `wait_device_ready()` in `06-setup-magisk.sh` and `wait_boot()` in entrypoint.sh.
- **`-avd rooted33`** (space) not `-avd-rooted33`.
- Emulator bumps 1536MB → 2048MB internally regardless of `-memory` flag.

## setup-magisk.sh (06-setup-magisk.sh) UI automation

- Coordinates target **pixel_6 @ 1080×2400**. For other devices, re-derive via `adb shell uiautomator dump /sdcard/ui.xml && adb shell cat /sdcard/ui.xml`.
- **Fragile under RAM pressure** (<~1GB free host RAM): `uiautomator dump` gets OOM-killed, producing a phantom "dumped" message with no file. `dump_ui()` retries 5× and bails out after 5 consecutive failures. On hosts with ~3GB+ free RAM, the full automated flow works without intervention.
- **"Requires Additional Setup" dialog blocks `home_magisk_button`** — dismiss with `dialog_base_button_1` at (890,1348) before checking if Magisk is installed.
- **Shell entry only appears in Magisk Superuser list AFTER `su -c id` has been triggered (and rejected) at least once** — it registers shell as a known su requester. `06-setup-magisk.sh` does this 3× before looking for `policy_indicator`.
- **Idempotency signal:** `home_magisk_installed_version` LinearLayout is present on Magisk home ONLY when Magisk is already installed. The Install button always shows "Install" regardless of state — not a reliable signal.
- **LET'S GO button has empty resource-id** — match by `text="LET'S GO"`, not by resource-id.
- Step C (Automatic Response = Grant) is optional and non-blocking. Root works without it.

## Docker

- Base image `halimqarroum/docker-android:api-33-playstore`: **SDK at `/opt/android`** (not `/opt/android-sdk`), **AVD home at `/data`** (not `~/.android/avd`).
- **Dockerfile build context is repo ROOT** (not `docker/`), because Dockerfile COPYs `scripts/` and `docker/entrypoint.sh`. Build from repo root: `docker build -t docker-emulator:latest -f docker/Dockerfile .`
- Container needs `/dev/kvm` mounted (docker-compose handles this).
- `avd-data` named volume persists AVD across restarts — re-running skips re-patching. Delete with `task clean:docker` to start fresh.
- Image CMD is `bash /entrypoint.sh` — args passed via `docker run ... bash -c '...'` are IGNORED.

## Style / conventions

- Scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, chmod +x.
- No comments unless asked (per global AGENTS.md). Existing `ponytail:`-style comments in scripts mark intentional simplifications.
- Verify scripts with `bash -n scripts/*.sh docker/entrypoint.sh` after edits.

## Git

- **Never commit without explicit user instruction** (override rule from global AGENTS.md).
- No commits exist yet on `main` — the entire project is uncommitted working tree.
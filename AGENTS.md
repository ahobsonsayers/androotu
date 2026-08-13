# AGENTS.md

Taskfile-driven rooted Android 13 (API 33) emulator with Magisk. Native + Docker paths.

The Magisk/A13 flow below is *legacy*. Current work — Play Integrity on a rooted emulator — is in `docs/LEARNINGS.md`: the KSU-Next + SUSFS + ReZygisk + PIFork + TEESimulator stack on an **android-36 (A16) x86_64** AVD, the `UNEVALUATED`→`NO_INTEGRITY` journey, and the x86_64 ceiling. Read it before touching that stack.

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

Scripts numbered `scripts/01-setup-sdk.sh` … `scripts/07-verify-root.sh`. Tasks mirror them as `step:1-setup-sdk` … `step:7-verify`. Taskfile is thin — just calls scripts.

## Root flow (don't get wrong)

1. **rootAVD needs the emulator ONLINE.** Boot unrooted (`-wipe-data`) → run `rootAVD.sh` while running → it patches ramdisk, installs `Magisk.apk`, shuts down → cold boot (NO wipe).
2. **`-wipe-data` wipes Magisk.apk from userdata.** Only for the first unrooted boot.
3. **`rootAVD.sh` prepends `$ANDROID_HOME` to arg 1.** Pass a RELATIVE path: `system-images/android-33/google_apis_playstore/x86_64/ramdisk.img`. Absolute → double-prepend → silent help + exit.
4. **`echo 1 |` before `rootAVD.sh`** selects Magisk Stable. Without it, help + exit.
5. **Clean `/data/data/com.android.shell/Magisk` before each run.** Stale files → `ramdisk.img uses UNKNOWN compression` → abort.
6. After rootAVD + cold boot, `su -c id` = "Permission denied" — Magisk env incomplete. `scripts/06-setup-magisk.sh` finishes via UI automation (Direct Install + grant shell su).

## Boot gotchas

- **Detach with `setsid nohup ... < /dev/null &`** — plain `&` dies with the launcher shell. `disown` is bash-only; Taskfile runs `/bin/sh`.
- **`adb wait-for-device` returns before authorization.** Poll `getprop sys.boot_completed` (120×3s).
- **After `boot_completed=1`, adb may return "device offline"** for a few seconds. Poll `adb shell true` (30×2s).
- **`-avd rooted33`** (space), not `-avd-rooted33`.
- Emulator bumps 1536MB → 2048MB internally regardless of `-memory`.

## setup-magisk.sh UI automation (06)

- Targets **pixel_6 @ 1080×2400**. Other devices: re-derive coords via `adb shell uiautomator dump /sdcard/ui.xml && adb shell cat /sdcard/ui.xml`.
- **Fragile under RAM pressure** (<~1GB free): `uiautomator dump` gets OOM-killed, phantom "dumped" with no file. `dump_ui()` retries 5×.
- **"Requires Additional Setup" dialog blocks `home_magisk_button`** — dismiss via `dialog_base_button_1` at (890,1348) first.
- **Shell su entry appears only AFTER `su -c id` is triggered (and rejected) at least once.** `06` does this 3×.
- **Idempotency signal:** `home_magisk_installed_version` present only when Magisk installed. Install button always shows "Install" — not reliable.
- **LET'S GO button has empty resource-id** — match by `text="LET'S GO"`.
- Step C (auto-grant) optional and non-blocking.

## Docker

- Base `halimqarroum/docker-android:api-33-playstore`: **SDK at `/opt/android`**, **AVD home at `/data`**.
- **Dockerfile build context is repo ROOT** (COPYs `scripts/` + `docker/entrypoint.sh`): `docker build -t docker-emulator:latest -f docker/Dockerfile .`
- Container needs `/dev/kvm` (docker-compose handles).
- `avd-data` volume persists AVD — re-run skips re-patching. Delete with `task clean:docker` to reset.
- Image CMD is `bash /entrypoint.sh` — `docker run ... bash -c '...'` args are IGNORED.

## Style

- Scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, chmod +x.
- No comments unless asked. `ponytail:` comments mark intentional simplifications.
- Verify scripts: `bash -n scripts/*.sh docker/entrypoint.sh`.

## Git

- **Never commit without explicit user instruction** (override rule from global AGENTS.md).
- No commits on `main` yet — entire project is uncommitted working tree.

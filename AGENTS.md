# AGENTS.md

Taskfile-driven rooted Android 16 (API 36, x86_64) emulator passing **MEETS_DEVICE_INTEGRITY** via Integrity Box on a KSU-Next + SUSFS kernel.

Read `LEARNINGS.md` before touching the stack — it has the full `UNEVALUATED`→`NO_INTEGRITY`→`MEETS_DEVICE_INTEGRITY` journey, the x86_64 ceiling, and every pitfall.

## Commands

```sh
task install          # one-time: create the a36 AVD (avd/scripts/01)
task boot             # boot headless with custom kernel (avd/scripts/02)
task install:modules  # Integrity Box + WebUI/manager, reboot (avd/scripts/03)
task configure        # Supreme profile + toggles + GMS restart (avd/scripts/04)
task verify           # stack + TEESimulator GENERATE check (avd/scripts/05)
task run              # install → boot → install:modules → configure → verify
task clean            # remove a36 AVD (keeps SDK + kernel)
```

Scripts: `avd/scripts/00-download-kernel.sh` (fetch prebuilt kernel from rolling release — AVD users don't build it), `avd/scripts/01-create-avd.sh` … `05-verify-integrity.sh`, and `avd/scripts/06-check-verdict.sh` (install SPIC, run a request, assert `MEETS_DEVICE_INTEGRITY`). Taskfile is thin — just calls `01`…`05`. `00` and `06` are standalone (not in the Taskfile chain).

## The stack (don't get wrong)

1. **Kernel** `kernel/dist/bzImage-a36-btf` is required — stock A36 kernel has no KSU/SUSFS. Boot command needs `-kernel ... -ramdisk <system-image>/ramdisk.img`.
2. **Module install** = `adb shell su -c 'ksud module install /path.zip'` (KSU root, not Magisk). `su` works via `adb shell su -c` once the custom kernel boots.
3. **Keybox is auto-managed** by the Integrity Box installer (GitHub auto-fetch). Never hand-edit `/data/adb/tricky_store/keybox.xml` or back it up — the module owns it.
4. **Integrity Box module id = `playintegrityfix`** — cannot coexist with a separate PIF module.
5. **Manager APK must be KernelSU-Next v3.2.0** (matches kernel ksud 33150). v3.3.0 refuses to work.
6. **WebUI access:** `adb shell am start -n io.github.a13e300.ksuwebui/.WebUIActivity -e id "playintegrityfix"`.

## The toggle combo that passes (canonical)

`avd/config/custom.pif.prop` is the single source of truth. The working combo:
`spoofProvider=1` + `spoofPixel=1` + `spoofSignature=1` (+ `spoofBuild=1`, `spoofProps=1`, `spoofVendingFinger=1`, `spoofVendingSdk=0`). After editing, restart GMS: `am force-stop com.google.android.gms.unstable; am force-stop com.android.vending`. **Supreme profile marker** = `/data/adb/Box-Brain/advanced` exists.

## Boot gotchas

- **Detach with `setsid nohup ... < /dev/null &`** — plain `&` dies with the launcher shell. `disown` is bash-only; Taskfile runs `/bin/sh`.
- **`adb wait-for-device` returns before authorization.** Poll `getprop sys.boot_completed` (120×3s), then `adb shell true` (30×2s) for the offline-race.
- **`-avd a36`** (space), not `-avd-a36`.
- Emulator bumps 1536MB → 2048MB internally regardless of `-memory`.
- Never run the emulator in a long bash call — tool timeout kills it.

## WebUI gotchas

- KsuWebUI root process crashes intermittently (`ClassNotFoundException: RootServerMain`) and button taps stop navigating. Fix: `am force-stop io.github.a13e300.ksuwebui` + relaunch, wait 8–12 s.
- Some WebUI buttons open Chrome externally (e.g. Set Profile) — go back and relaunch WebUIActivity.

## Style

- Scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, chmod +x.
- No comments unless asked.
- Verify scripts: `bash -n avd/scripts/*.sh`.

## Git

- **Never commit without explicit user instruction** (override rule from global AGENTS.md).
- Working tree on `main`; keep it clean. `06-check-verdict.sh` and the Docker/CI setup are part of the committed history — don't assume a clean tree is a fresh checkout.

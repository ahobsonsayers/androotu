# Play Integrity on a rooted x86_64 AVD — learnings

The KSU-Next + SUSFS + ReZygisk + Integrity Box + TEESimulator stack on an
android-36 (A16) x86_64 AVD. We went `UNEVALUATED` → `NO_INTEGRITY` →
`MEETS_DEVICE_INTEGRITY`. This is the distilled record — read before touching
the stack.

## Verdicts along the way

| Image | Profile | deviceIntegrity | Why |
|---|---|---|---|
| A13 | tokay (A16) | `UNEVALUATED` | forged osVersion 130000 ≠ tokay A16 fingerprint |
| A13 | panther (A13) | `UNEVALUATED` | osVersion consistent, still refused |
| A36 (A16) | tokay (PIFork) | `NO_INTEGRITY` | Google evaluates + rejects |
| A36 (A16) | shiba (Integrity Box) | `MEETS_DEVICE_INTEGRITY` | spoofProvider + spoofPixel toggles |

Key lever: **TEESimulator hardcodes attestation osVersion from
`Build.VERSION.SDK_INT`** (`TIRAMISU`=130000, `BAKLAVA`=160000), not
overridable. Fingerprint OS must match the image's real SDK or you get
`UNEVALUATED`.

## The breakthrough: Integrity Box toggles

Installing Integrity Box alone changed nothing (`NO_INTEGRITY`). The win came
from **toggling settings in its WebUI**:

- Profile **Supreme** (marker file `/data/adb/Box-Brain/advanced`) → shiba /
  Pixel 8 CANARY fingerprint.
- **Attestation API ON** (`spoofProvider=1`) + **Pixelify Playstore ON**
  (`spoofPixel=1`) + **ROM Signature ON** (`spoofSignature=1`) in
  `custom.pif.prop`, then restart GMS.

That flipped the verdict `NO_INTEGRITY` → `MEETS_DEVICE_INTEGRITY` on x86_64 —
the first time this project beat `NO_INTEGRITY`. TEESimulator stays in GENERATE
mode throughout; the keybox chain is valid, Google just grants DEVICE not
STRONG.

WebUI access: install **KsuWebUIStandalone** (`io.github.a13e300.ksuwebui`) +
**KernelSU-Next manager v3.2.0** (must match kernel 33129; v3.3.0 manager
refuses to work). Launch directly:

```sh
adb shell am start -n io.github.a13e300.ksuwebui/.WebUIActivity -e id "playintegrityfix"
```

Gotcha: the KsuWebUI root process crashes intermittently
(`ClassNotFoundException: RootServerMain`) and button taps stop navigating.
Fix: `am force-stop io.github.a13e300.ksuwebui` + relaunch, wait 8–12 s.

## Proven NOT the blocker (don't re-chase)

- Keybox: broken placeholder and genuine CRL-clean Yurikey give identical verdict on A36
- TEESimulator mode: confirmed GENERATE, still rejected
- ABI props arm64-first, GSF re-register as tokay, leaked qemu/vport props, per-partition props + /proc bind + DMI spoof + security_patch.txt (reference verify-setup.sh passes all its checks on our device)

## The wall: x86_64 vs arm64

- Reference (tanishmeh/AVD_Rooted_Integrity) passes MEETS_STRONG on arm64-v8a android-36. Author: "x86 detection is not something we can bypass, since apps can natively check for this."
- GMS ships x86_64 native libs on our device; a real Pixel 9 runs arm64 GMS. DroidGuard can check its own process arch — no prop/chain/bind mount changes that.
- Emulator hard-blocks arm64 guests on x86_64 at API ≥ 28: `FATAL | Avd's CPU Architecture 'arm64' is not supported by the QEMU2 emulator on x86_64 host` (no flag bypasses). Reference was tested on Apple Silicon.
- **Running arm64 *apps* is a separate matter from the arm64-*guest* wall**: the A36 x86_64 playstore image ships native-bridge translation (`ro.product.cpu.abilist=x86_64,arm64-v8a`, `ro.enable.native.bridge.exec=1`, `/system/lib64/libndk_translation.so`), so arm64-only apps install and run via the translator on the x86_64 core. This is what dockerify-android enables via ndk_translation too. It doesn't affect the device verdict — GMS itself runs x86_64.
- **`MEETS_DEVICE_INTEGRITY` is the realistic x86_64 ceiling. STRONG requires a keybox chaining to Google's genuine hardware attestation root** (real device TEE or genuine leak). Both keyboxes we have (Yurikey57, Megatron/IntegrityBox) chain to the same self-signed TEE root `f92009e853b6b045` — Google grants DEVICE but refuses STRONG. Passing STRONG requires an arm64 host.

## Pitfalls

1. **`modules_update/` wipes the module at boot.** Seed it with partial content and ksud replaces the whole module dir. Symptom: PIFork scripts gone, 0-byte `custom.pif.prop`, `WARN: no PIF`, empty `ro.build.fingerprint` → `system_server` crash loop (`failed to set system property ... error code: 0xb`). Write config only into `/data/adb/modules/<mod>/`.
2. **NEVER restart keymint/keystore2/TEESimulator after boot** — flips GENERATE→PATCH → empty verdict. Cold reboot only. Never run `autopif` (overwrites pinned fingerprint).
3. **`target.txt` `!` goes at line-END** (not start). Integrity Box/Tricky Store rewrites it — re-add `!` after the module manages it.
4. **Don't delete `ro.boot.qemu.virtiowifi`/`adbpubkey`/`vsock`** — kills `wlan0` → Finsky `IntegrityException: no network`.
5. **BTF must stay enabled (x86_64).** `CONFIG_DEBUG_INFO_BTF_MODULES` adds 2 fields to `struct module`; disabling it makes every vendor DLKM fail (`.gnu.linkonce.this_module section size mismatch`) → boot hang. Install `dwarves` (pahole). arm64 defconfig has BTF off, so reference Dockerfile needs no pahole.
6. **A36 ramdisk ships no modules** — build virtio =y. (A13 ramdisk carried modules needing an LZ4-legacy `-l` repack.)
7. **ksud must match kernel uapi** — mismatch logs `Kernel and userspace uapi version mismatch! skip on_post_fs_data` and NO boot scripts run. Use `lib/x86_64/libksud.so` from the matching manager APK.
8. **Never run the emulator in a long bash call** — tool timeout kills it. Use `setsid bash -c '... > log 2>&1' < /dev/null &` then poll `sys.boot_completed`.
9. **`custom.pif.prop` 0-byte trap** — `cp` from a stale `/data/local/tmp/custom.pif.prop`. Always re-push from host first.
10. **Don't disable ModemSimulator** — `-feature -ModemSimulator` kills the host modem simulator, but the guest `android.hardware.radio-service.ranchu` still spawns from init and SIGABRTs every ~5s with no peer. The modem simulator runs fine in containers (dockerify-android uses plain defaults). Match dockerify-android; don't add the flag.

## Commands

```sh
setsid bash -c 'AVD=a36 API=36 KERNEL=.../bzImage-a36-btf GPU=swiftshader_indirect bash .../02-boot-emulator.sh > /tmp/a36-boot.log 2>&1' < /dev/null & disown
adb shell getprop sys.boot_completed          # poll until 1
adb logcat -d | grep -c "Generating new attested key pair for alias: 'integrity.api.key.alias'"   # >0 = GENERATE
adb logcat -d | grep -c "patched certificate chain for KeyIdentifier(uid=10146"                    # 0 = good
adb shell am start -n com.henrikherzig.playintegritychecker/.MainActivity
adb shell uiautomator dump /sdcard/ui.xml && adb shell cat /sdcard/ui.xml   # read SPIC verdict
```

## Artifacts

- Kernel: `kernel/dist/bzImage-a36-btf` (x86_64, working), `Image.gz-arm64` (built, unbootable on this host)
- On-device: `/data/adb/{modules/{playintegrityfix,rezygisk,susfs4ksu,tricky_store,Yurikey}, Box-Brain/{advanced,tricky_store/keybox.xml,target.txt,tee_status.txt,security_patch.txt}}`
- Host: `avd/config/custom.pif.prop` (canonical toggle combo)

## FAQ

**Why `MEETS_DEVICE_INTEGRITY` but not STRONG?** The keybox chain roots to a
self-signed TEE root (`f92009e853b6b045`), not Google's genuine hardware
attestation root. Google validates the chain (DEVICE) but refuses STRONG.
Only a genuine Google-rooted keybox (real device TEE or genuine leak) reaches
STRONG.

**Why `NO_INTEGRITY` with everything spoofed?** DroidGuard sees x86_64 GMS binaries; a real Pixel 9 is arm64. Fix: Integrity Box Supreme profile + `spoofProvider=1` + `spoofPixel=1` + `spoofSignature=1` (see "The breakthrough" above).

**Why `UNEVALUATED`?** Google refused to evaluate. Usually osVersion mismatch (image SDK vs profile OS) or PATCH mode.

**Keybox requirements?** None manual — the Integrity Box installer auto-fetches
a valid keybox from GitHub at install time. Never hand-edit
`/data/adb/tricky_store/keybox.xml` or back it up; the module owns it. (If you
ever do manage one: valid TEE-class keybox, `0644` world-readable so
TEESimulator can inject it, never commit a real one publicly, and check CRL at
`https://android.googleapis.com/attestation/status` first.)

**Empty verdict after reboot?** Cold-reboot rule violated (service restart, autopif, or `security_patch.txt` truncated). Rewrite + `chattr +i`, cold reboot.

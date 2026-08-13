# Play Integrity on a rooted x86_64 AVD — learnings

The KSU-Next + SUSFS + ReZygisk + PIFork + TEESimulator stack on an android-36
(A16) x86_64 AVD. We got `UNEVALUATED` → `NO_INTEGRITY` and stopped there. This
is the distilled record — read before touching the stack.

## Verdicts along the way

| Image | Profile | deviceIntegrity | Why |
|---|---|---|---|
| A13 | tokay (A16) | `UNEVALUATED` | forged osVersion 130000 ≠ tokay A16 fingerprint |
| A13 | panther (A13) | `UNEVALUATED` | osVersion consistent, still refused |
| A36 (A16) | tokay | `NO_INTEGRITY` | Google evaluates + rejects |

Key lever: **TEESimulator hardcodes attestation osVersion from
`Build.VERSION.SDK_INT`** (`TIRAMISU`=130000, `BAKLAVA`=160000), not
overridable. Fingerprint OS must match the image's real SDK or you get
`UNEVALUATED`.

## Proven NOT the blocker (don't re-chase)

- Keybox: broken placeholder and genuine CRL-clean Yurikey give identical verdict on A36
- TEESimulator mode: confirmed GENERATE, still rejected
- ABI props arm64-first, GSF re-register as tokay, leaked qemu/vport props, per-partition props + /proc bind + DMI spoof + security_patch.txt (reference verify-integrity.sh passes all its checks on our device)

## The wall: x86_64 vs arm64

- Reference (tanishmeh/AVD_Rooted_Integrity) passes MEETS_STRONG on arm64-v8a android-36. Author: "x86 detection is not something we can bypass, since apps can natively check for this."
- GMS ships x86_64 native libs on our device; a real Pixel 9 runs arm64 GMS. DroidGuard can check its own process arch — no prop/chain/bind mount changes that.
- Emulator hard-blocks arm64 guests on x86_64 at API ≥ 28: `FATAL | Avd's CPU Architecture 'arm64' is not supported by the QEMU2 emulator on x86_64 host` (no flag bypasses). Reference was tested on Apple Silicon.
- **`NO_INTEGRITY` is the documented x86_64 ceiling. Passing requires an arm64 host.** If asked to "make it pass", ask first: is the host arm64?

## Pitfalls

1. **`modules_update/` wipes the module at boot.** Seed it with partial content and ksud replaces the whole module dir. Symptom: PIFork scripts gone, 0-byte `custom.pif.prop`, `WARN: no PIF`, empty `ro.build.fingerprint` → `system_server` crash loop (`failed to set system property ... error code: 0xb`). Write config only into `/data/adb/modules/<mod>/`.
2. **NEVER restart keymint/keystore2/TEESimulator after boot** — flips GENERATE→PATCH → empty verdict. Cold reboot only. Never run `autopif` (overwrites pinned fingerprint).
3. **`target.txt` `!` goes at line-END** (not start). Yurikey `action.sh` rewrites and strips it — re-add after running.
4. **Don't delete `ro.boot.qemu.virtiowifi`/`adbpubkey`/`vsock`** — kills `wlan0` → Finsky `IntegrityException: no network`.
5. **BTF must stay enabled (x86_64).** `CONFIG_DEBUG_INFO_BTF_MODULES` adds 2 fields to `struct module`; disabling it makes every vendor DLKM fail (`.gnu.linkonce.this_module section size mismatch`) → boot hang. Install `dwarves` (pahole). arm64 defconfig has BTF off, so reference Dockerfile needs no pahole.
6. **A36 ramdisk ships no modules** — build virtio =y. (A13 ramdisk carried modules needing an LZ4-legacy `-l` repack.)
7. **ksud must match kernel uapi** — mismatch logs `Kernel and userspace uapi version mismatch! skip on_post_fs_data` and NO boot scripts run. Use `lib/x86_64/libksud.so` from the matching manager APK.
8. **Never run the emulator in a long bash call** — tool timeout kills it. Use `setsid bash -c '... > log 2>&1' < /dev/null &` then poll `sys.boot_completed`.
9. **`custom.pif.prop` 0-byte trap** — `cp` from a stale `/data/local/tmp/custom.pif.prop`. Always re-push from host first.

## Commands

```sh
setsid bash -c 'AVD=a36 API=36 KERNEL=.../bzImage-a36-btf GPU=swiftshader_indirect bash .../05-boot-emulator.sh > /tmp/a36-boot.log 2>&1' < /dev/null & disown
adb shell getprop sys.boot_completed          # poll until 1
adb logcat -d | grep -c "Generating new attested key pair for alias: 'integrity.api.key.alias'"   # >0 = GENERATE
adb logcat -d | grep -c "patched certificate chain for KeyIdentifier(uid=10146"                    # 0 = good
adb shell am start -n com.henrikherzig.playintegritychecker/.MainActivity
adb shell uiautomator dump /sdcard/ui.xml && adb shell cat /sdcard/ui.xml   # read SPIC verdict
```

## Artifacts

- Kernel: `kernel-build/out/bzImage-a36-btf` (x86_64, working), `Image.gz-arm64` (built, unbootable on this host)
- On-device: `/data/adb/{modules/{playintegrityfix,rezygisk,susfs4ksu,tricky_store,Yurikey}, post-fs-data.d, service.d, avd-fake, tricky_store/{keybox.xml,target.txt,tee_status.txt,security_patch.txt}, ksu/bin/ksu_susfs}`
- Reference repo: `/tmp/avd-integrity/` — `docs/REPRODUCTION.md`, `docs/INTEGRITY_CHAIN.md`
- Build pipeline: `kernel-build/scripts/{fetch-sources,apply-patches,build,customize-kernel}.sh`, Docker `kbuild:latest`, volume `kernel-build`

## FAQ

**Why `NO_INTEGRITY` with everything spoofed?** DroidGuard sees x86_64 GMS binaries; a real Pixel 9 is arm64.

**Why `UNEVALUATED`?** Google refused to evaluate. Usually osVersion mismatch (image SDK vs profile OS) or PATCH mode.

**Keybox requirements?** Valid TEE-class keybox, `0644` (world-readable — TEESimulator injects into keystore2, not root). Never commit a real one publicly. Check CRL (`https://android.googleapis.com/attestation/status`) before debugging anything else.

**Empty verdict after reboot?** Cold-reboot rule violated (service restart, autopif, or `security_patch.txt` truncated). Rewrite + `chattr +i`, cold reboot.

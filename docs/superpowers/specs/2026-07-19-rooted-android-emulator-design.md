# Rooted Android 13 (API 33) Emulator with Play Store

## Goal

A rooted Android 13 (API 33) x86_64 emulator running in Docker, using the
`google_apis_playstore` system image (official Play Store). Root via Magisk.

## Approach

- **rootAVD** for rooting (handles ramdisk caching edge case)
- **Local-first** iteration (faster), then **port to Docker**
- **Startup-time patching** in Docker (ramdisk cache is per-instance)
- **Headless** emulator (`-no-window -no-audio`)

## File Layout

```
rooted-android-emulator/
├── scripts/
│   ├── setup-sdk.sh         # Install Android SDK + API 33 Play Store image
│   ├── create-avd.sh        # Create the AVD
│   ├── root-avd.sh          # Run rootAVD to patch ramdisk with Magisk
│   ├── boot-emulator.sh     # Boot the emulator headless
│   └── verify-root.sh       # adb shell su -c id
├── docker/
│   ├── Dockerfile           # Based on halimqarroum/docker-android:api-33-playstore
│   ├── entrypoint.sh        # Container startup: create AVD → root → boot
│   └── docker-compose.yml   # KVM device, port mapping, volume
└── Makefile                 # make local-setup, make local-root, make docker-build, etc.
```

## Local Setup Flow

1. **`setup-sdk.sh`** — Downloads `commandlinetools`, runs `sdkmanager` to install:
   - `platforms;android-33`
   - `system-images;android-33;google_apis_playstore;x86_64`
   - `emulator`
   - `platform-tools`
   - Sets `ANDROID_HOME` and adds to `PATH`

2. **`create-avd.sh`** — Creates AVD named `rooted33` with:
   - `system-images;android-33;google_apis_playstore;x86_64`
   - 1536MB RAM, 512MB heap
   - No skin, no GPU (headless)

3. **`root-avd.sh`** — Clones rootAVD, runs `./rootAVD.sh <path-to-ramdisk.img>`
   to patch ramdisk with Magisk. Handles `/data/android.avd/initrd` cache issue.

4. **`boot-emulator.sh`** — Starts emulator headless with
   `-no-window -no-audio -no-snapshot -memory 1536`, waits for
   `adb wait-for-device`.

5. **`verify-root.sh`** — Runs `adb shell su -c id`, checks for `uid=0(root)`.

## Docker Setup

- **Base image:** `halimqarroum/docker-android:api-33-playstore`
- **Adds:** rootAVD cloned into image
- **Entrypoint:** create AVD → rootAVD → boot emulator → keep alive
- **KVM device** passed from host, **adb port 5555** exposed
- **RAM:** 1536MB for emulator (leaves ~2GB for host)

### Entrypoint sequence (every container start)

1. Check `/dev/kvm` is accessible
2. Create AVD if not already created (persisted via volume)
3. Run rootAVD to patch ramdisk
4. Boot emulator headless
5. Foreground the emulator process (container stays alive)

### Why not pre-root at build time

The ramdisk cache (`/data/android.avd/initrd`) is generated per-AVD-instance.
rootAVD must run after the AVD is created but before first boot. Startup-time
patching adds ~30s but is reliable.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Rooting tool | rootAVD | Handles ramdisk caching, battle-tested for AVDs |
| Patching time | Startup | Ramdisk is per-instance; build-time would break |
| Docker base | halimqarroum/docker-android:api-33-playstore | Saves ~3GB download, has exact image |
| Emulator RAM | 1536MB | Leaves ~2GB for host on 7.6GB system |
| Display | Headless | No GUI needed, saves resources |

## Verification

- `adb shell su -c id` returns `uid=0(root)`
- `adb shell pm list packages | grep playstore` shows Play Store installed
- Emulator boots and is responsive within 120s

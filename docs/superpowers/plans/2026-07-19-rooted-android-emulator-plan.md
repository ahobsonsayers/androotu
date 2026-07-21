# Rooted Android Emulator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A rooted Android 13 (API 33) x86_64 emulator with Play Store, running locally and in Docker.

**Architecture:** Linear pipeline: install SDK → create AVD → rootAVD patch ramdisk → boot emulator → verify root. Docker wraps the same pipeline in a container entrypoint.

**Tech Stack:** Bash scripts, Android SDK (commandlinetools), rootAVD, Magisk, Docker

## Global Constraints

- ANDROID_HOME defaults to `$HOME/Android/Sdk`
- AVD name: `rooted33`
- System image: `system-images;android-33;google_apis_playstore;x86_64`
- Emulator RAM: 1536MB
- Headless mode: `-no-window -no-audio -no-snapshot`
- Docker base: `halimqarroum/docker-android:api-33-playstore`
- rootAVD invocation: `./rootAVD.sh <path-to-ramdisk.img>`

---

### Task 1: setup-sdk.sh

**Files:**
- Create: `scripts/setup-sdk.sh`

**Interfaces:**
- Consumes: nothing
- Produces: `$ANDROID_HOME` with SDK installed, `adb` and `emulator` in PATH

- [ ] **Step 1: Write setup-sdk.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
CMDLINE_TOOLS_DIR="$ANDROID_HOME/cmdline-tools"

if [ ! -f "$CMDLINE_TOOLS_DIR/tools/bin/sdkmanager" ]; then
    mkdir -p "$CMDLINE_TOOLS_DIR"
    wget -q "$CMDLINE_TOOLS_URL" -O /tmp/cmdline-tools.zip
    unzip -q /tmp/cmdline-tools.zip -d "$CMDLINE_TOOLS_DIR"
    mv "$CMDLINE_TOOLS_DIR/cmdline-tools" "$CMDLINE_TOOLS_DIR/tools"
    rm /tmp/cmdline-tools.zip
fi

export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$CMDLINE_TOOLS_DIR/tools/bin:$PATH"

yes | sdkmanager --sdk_root="$ANDROID_HOME" \
    "platforms;android-33" \
    "system-images;android-33;google_apis_playstore;x86_64" \
    "emulator" \
    "platform-tools"

echo "export ANDROID_HOME=$ANDROID_HOME" >> ~/.bashrc
echo 'export PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/tools/bin:$PATH' >> ~/.bashrc
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/setup-sdk.sh
```

- [ ] **Step 3: Run and verify**

```bash
./scripts/setup-sdk.sh
adb --version
emulator -version
```

Expected: adb and emulator binaries found and report versions.

---

### Task 2: create-avd.sh

**Files:**
- Create: `scripts/create-avd.sh`

**Interfaces:**
- Consumes: `$ANDROID_HOME` with system image installed (Task 1)
- Produces: AVD `rooted33` ready for booting

- [ ] **Step 1: Write create-avd.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
AVD_NAME="rooted33"
SYSTEM_IMAGE="system-images;android-33;google_apis_playstore;x86_64"

echo no | avdmanager create avd \
    --name "$AVD_NAME" \
    --package "$SYSTEM_IMAGE" \
    --device "pixel_6" \
    --force

# Write config.ini with headless settings
AVD_DIR="$HOME/.android/avd/${AVD_NAME}.avd"
cat >> "$AVD_DIR/config.ini" << EOF
hw.ramSize=1536
hw.heapSize=512
hw.gpu.enabled=no
hw.gpu.mode=host
hw.gpu.blacklisted=yes
hw.gltransport=pipe
hw.camera=no
hw.sensors.proximity=no
hw.sensors.light=no
hw.battery=no
hw.audioInput=no
hw.audioOutput=no
hw.mainKeys=no
hw.keyboard=yes
skin.dynamic=no
showDeviceFrame=no
disk.dataPartition.size=4096M
fastboot.forceColdBoot=yes
EOF
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/create-avd.sh
```

- [ ] **Step 3: Run and verify**

```bash
./scripts/create-avd.sh
avdmanager list avd | grep rooted33
```

Expected: AVD `rooted33` listed.

---

### Task 3: root-avd.sh

**Files:**
- Create: `scripts/root-avd.sh`

**Interfaces:**
- Consumes: AVD `rooted33` created (Task 2), system image installed (Task 1)
- Produces: Patched ramdisk with Magisk

- [ ] **Step 1: Write root-avd.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
ROOTAVD_DIR="$HOME/rootAVD"

if [ ! -d "$ROOTAVD_DIR" ]; then
    git clone https://github.com/newbit1/rootAVD.git "$ROOTAVD_DIR"
fi

RAMDISK_PATH="$ANDROID_HOME/system-images/android-33/google_apis_playstore/x86_64/ramdisk.img"

cd "$ROOTAVD_DIR"
chmod +x rootAVD.sh
./rootAVD.sh "$RAMDISK_PATH"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/root-avd.sh
```

- [ ] **Step 3: Run and verify**

```bash
./scripts/root-avd.sh
```

Expected: Script completes without error, ramdisk.img backup created alongside patched version.

---

### Task 4: boot-emulator.sh

**Files:**
- Create: `scripts/boot-emulator.sh`

**Interfaces:**
- Consumes: AVD `rooted33` with patched ramdisk (Tasks 2+3)
- Produces: Running emulator, adb connected

- [ ] **Step 1: Write boot-emulator.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
AVD_NAME="rooted33"
EMULATOR="$ANDROID_HOME/emulator/emulator"
ADB="$ANDROID_HOME/platform-tools/adb"

# Kill any existing emulator
"$ADB" emu kill 2>/dev/null || true

# Boot headless
"$EMULATOR" \
    -avd "$AVD_NAME" \
    -no-window \
    -no-audio \
    -no-snapshot \
    -memory 1536 \
    -no-boot-anim \
    -gpu off \
    -read-only \
    &

EMULATOR_PID=$!

echo "Waiting for device..."
"$ADB" wait-for-device
echo "Waiting for boot to complete..."
"$ADB" shell 'while [[ $(getprop sys.boot_completed) != 1 ]]; do sleep 1; done'

echo "Emulator booted (PID: $EMULATOR_PID)"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/boot-emulator.sh
```

- [ ] **Step 3: Run and verify**

```bash
./scripts/boot-emulator.sh
adb shell getprop sys.boot_completed
```

Expected: `1` printed, emulator responsive.

---

### Task 5: verify-root.sh

**Files:**
- Create: `scripts/verify-root.sh`

**Interfaces:**
- Consumes: Running emulator with Magisk root (Tasks 3+4)
- Produces: Exit code 0 if rooted, 1 if not

- [ ] **Step 1: Write verify-root.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"

echo "Checking root access..."
ROOT_CHECK=$("$ADB" shell su -c id 2>&1)

if echo "$ROOT_CHECK" | grep -q "uid=0(root)"; then
    echo "PASS: Device is rooted"
    echo "$ROOT_CHECK"
else
    echo "FAIL: Device is NOT rooted"
    echo "Got: $ROOT_CHECK"
    exit 1
fi

echo "Checking Play Store..."
PLAY_STORE=$("$ADB" shell pm list packages 2>&1 | grep -i playstore || true)
if [ -n "$PLAY_STORE" ]; then
    echo "PASS: Play Store installed"
    echo "$PLAY_STORE"
else
    echo "WARN: Play Store packages not found (may need first boot setup)"
fi
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/verify-root.sh
```

- [ ] **Step 3: Run and verify**

```bash
./scripts/verify-root.sh
```

Expected: `PASS: Device is rooted` and `uid=0(root)`.

---

### Task 6: Makefile

**Files:**
- Create: `Makefile`

**Interfaces:**
- Consumes: All scripts (Tasks 1-5)
- Produces: Convenience targets for local and Docker workflows

- [ ] **Step 1: Write Makefile**

```makefile
ANDROID_HOME ?= $(HOME)/Android/Sdk
ADB = $(ANDROID_HOME)/platform-tools/adb

.PHONY: help setup-sdk create-avd root boot verify all local docker-build docker-up

help:
	@echo "Targets:"
	@echo "  make setup-sdk    - Install Android SDK + API 33 Play Store image"
	@echo "  make create-avd   - Create AVD 'rooted33'"
	@echo "  make root         - Patch ramdisk with Magisk via rootAVD"
	@echo "  make boot         - Boot emulator headless"
	@echo "  make verify       - Check root access"
	@echo "  make all          - Full local pipeline: setup → create → root → boot → verify"
	@echo "  make docker-build - Build Docker image"
	@echo "  make docker-up    - Start Docker container"

setup-sdk:
	./scripts/setup-sdk.sh

create-avd:
	./scripts/create-avd.sh

root:
	./scripts/root-avd.sh

boot:
	./scripts/boot-emulator.sh

verify:
	./scripts/verify-root.sh

all: setup-sdk create-avd root boot verify

docker-build:
	docker compose -f docker/docker-compose.yml build

docker-up:
	docker compose -f docker/docker-compose.yml up -d

docker-down:
	docker compose -f docker/docker-compose.yml down

docker-logs:
	docker compose -f docker/docker-compose.yml logs -f

docker-adb:
	docker compose -f docker/docker-compose.yml exec emulator adb shell
```

- [ ] **Step 2: Verify Makefile works**

```bash
make help
```

Expected: All targets listed.

---

### Task 7: Docker Setup

**Files:**
- Create: `docker/Dockerfile`
- Create: `docker/entrypoint.sh`
- Create: `docker/docker-compose.yml`

**Interfaces:**
- Consumes: `halimqarroum/docker-android:api-33-playstore` base image
- Produces: Docker container with rooted emulator

- [ ] **Step 1: Write Dockerfile**

```dockerfile
FROM halimqarroum/docker-android:api-33-playstore

ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/tools/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    unzip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/newbit1/rootAVD.git /opt/rootAVD

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5554 5555

ENTRYPOINT ["/entrypoint.sh"]
```

- [ ] **Step 2: Write entrypoint.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
AVD_NAME="${AVD_NAME:-rooted33}"
EMULATOR_RAM="${EMULATOR_RAM:-1536}"
SYSTEM_IMAGE="system-images;android-33;google_apis_playstore;x86_64"
RAMDISK_PATH="$ANDROID_HOME/$(echo $SYSTEM_IMAGE | tr ';' '/')/ramdisk.img"
ROOTAVD_DIR="/opt/rootAVD"
ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"

# Check KVM
if [ ! -e /dev/kvm ]; then
    echo "FATAL: /dev/kvm not found. Mount it with --device /dev/kvm"
    exit 1
fi

# Create AVD if not already created
if ! avdmanager list avd 2>/dev/null | grep -q "$AVD_NAME"; then
    echo "Creating AVD $AVD_NAME..."
    echo no | avdmanager create avd \
        --name "$AVD_NAME" \
        --package "$SYSTEM_IMAGE" \
        --device "pixel_6" \
        --force

    AVD_DIR="$HOME/.android/avd/${AVD_NAME}.avd"
    cat >> "$AVD_DIR/config.ini" << EOF
hw.ramSize=$EMULATOR_RAM
hw.heapSize=512
hw.gpu.enabled=no
hw.camera=no
hw.audioInput=no
hw.audioOutput=no
hw.mainKeys=no
hw.keyboard=yes
skin.dynamic=no
showDeviceFrame=no
disk.dataPartition.size=4096M
fastboot.forceColdBoot=yes
EOF
fi

# Root with rootAVD
echo "Patching ramdisk with Magisk via rootAVD..."
cd "$ROOTAVD_DIR"
./rootAVD.sh "$RAMDISK_PATH"

# Boot emulator
echo "Booting emulator..."
"$EMULATOR" \
    -avd "$AVD_NAME" \
    -no-window \
    -no-audio \
    -no-snapshot \
    -memory "$EMULATOR_RAM" \
    -no-boot-anim \
    -gpu off \
    -read-only \
    &

EMULATOR_PID=$!

echo "Waiting for device..."
"$ADB" wait-for-device
echo "Waiting for boot to complete..."
"$ADB" shell 'while [[ $(getprop sys.boot_completed) != 1 ]]; do sleep 1; done'

echo "Emulator booted (PID: $EMULATOR_PID)"

# Keep container alive
wait $EMULATOR_PID
```

- [ ] **Step 3: Write docker-compose.yml**

```yaml
services:
  emulator:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    devices:
      - /dev/kvm
    ports:
      - "5555:5555"
      - "5554:5554"
    volumes:
      - avd-data:/root/.android/avd
    environment:
      - EMULATOR_RAM=1536
      - AVD_NAME=rooted33
    stdin_open: true
    tty: true

volumes:
  avd-data:
```

- [ ] **Step 4: Build and test Docker image**

```bash
make docker-build
make docker-up
sleep 120
adb devices
adb shell su -c id
```

Expected: Device listed in adb, `uid=0(root)` returned.

---

### Task 8: Full Local Pipeline Test

**Files:**
- Modify: none (integration test)

- [ ] **Step 1: Run full pipeline**

```bash
make all
```

Expected: SDK installed, AVD created, ramdisk patched, emulator boots, root verified.

- [ ] **Step 2: Clean up emulator**

```bash
adb emu kill
```

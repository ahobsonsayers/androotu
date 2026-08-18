# Stage 1: build the KSU/SUSFS kernel from source so the image is fully
# self-contained (no prebuilt bzImage needed in the build context). Reuses the
# same toolchain + scripts as kernel/Dockerfile.
FROM ubuntu:24.04 AS kernel-builder

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget git xz-utils unzip \
        build-essential bc bison flex \
        libssl-dev openssl libelf-dev \
        kmod cpio rsync \
        python3 \
        device-tree-compiler \
        zstd lz4 \
        dwarves \
        ccache \
        clang lld llvm llvm-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git config --global user.email "kbuild@local" \
 && git config --global user.name "kbuild" \
 && git config --global init.defaultBranch main \
 && git config --global advice.detachedHead false

ENV CCACHE_DIR=/work/.ccache
ENV PATH="/usr/lib/ccache:${PATH}"

WORKDIR /work
COPY kernel/build /work/scripts
RUN bash /work/scripts/build-all.sh
RUN mkdir -p /kernel && cp /work/dist/bzImage /kernel/bzImage

# Stage 2: the emulator runtime.
FROM ubuntu:20.04

# Base tooling (mirrors dockerify-android).
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libegl1 \
        openjdk-17-jdk-headless \
        wget \
        curl \
        git \
        unzip \
        supervisor \
        qemu-kvm \
        iproute2 \
        socat \
        tzdata \
        python3 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Android SDK: cmdline-tools, emulator, platform-tools, A36 x86_64 Play Store image.
RUN mkdir -p /opt/android-sdk/cmdline-tools && \
    cd /opt/android-sdk/cmdline-tools && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip -O cmdline-tools.zip && \
    unzip -q cmdline-tools.zip -d latest && \
    rm cmdline-tools.zip && \
    mv latest/cmdline-tools/* latest/ || true && \
    rm -rf latest/cmdline-tools || true

ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_AVD_HOME=/data
ENV ADB_DIR="$ANDROID_HOME/platform-tools"
ENV PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ADB_DIR:$PATH"

RUN mkdir -p /root/.android && \
    touch /root/.android/repositories.cfg && \
    mkdir -p /data /extras /opt/kernel /opt/modules /opt/scripts

# Bake in the A36 x86_64 Play Store system image (multi-GB, one-time).
RUN yes | sdkmanager --sdk_root=$ANDROID_HOME \
        "emulator" "platform-tools" "platforms;android-36" \
        "system-images;android-36;google_apis_playstore;x86_64" && \
    rm -f /opt/android-sdk/emulator/crashpad_handler

# Bake a deterministic adb keypair into the image. The Play Store image forces
# ro.adb.secure=1 (adbd ignores -prop ro.adb.secure=0), so external ADB clients
# must present a trusted key via ADB_VENDOR_KEYS. Starting the adb server once
# generates ~/.android/adbkey + adbkey.pub in adb's native format; baking it in
# means every container instance shares the same key and stays pre-authorized.
RUN adb start-server && adb kill-server

# Bake in the custom KSU/SUSFS kernel (required for root), built in stage 1.
COPY --from=kernel-builder /kernel/bzImage /opt/kernel/bzImage-a36-btf

# Bake in the module zips + manager/WebUI APKs (rebuilt to refresh).
ARG TEE_URL="https://github.com/JingMatrix/TEESimulator/releases/download/v3.2/TEESimulator-v3.2-67-Release.zip"
ARG REZYGISK_URL="https://raw.githubusercontent.com/ThePedroo/RemoteFiles/refs/heads/main/ReZygisk/ReZygisk.zip"
ARG SUSFS_URL="https://github.com/sidex15/susfs4ksu-module/releases/download/v1.5.2%2B_R27/ksu_module_susfs_1.5.2%2B.zip"
ARG IB_URL="https://github.com/MeowDump/Integrity-Box/releases/download/v40/v40-Integrity-Box-05-08-2026.zip"
ARG KSU_WEBUI_URL="https://github.com/5ec1cff/KsuWebUIStandalone/releases/download/v1.0/KsuWebUI-1.0-34-release.apk"
ARG KSU_NEXT_URL="https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v3.2.0/KernelSU_Next_v3.2.0_33129-release.apk"
RUN curl -fsSL -o /opt/modules/teesimulator.zip "$TEE_URL" && \
    curl -fsSL -o /opt/modules/rezygisk.zip "$REZYGISK_URL" && \
    curl -fsSL -o /opt/modules/susfs.zip "$SUSFS_URL" && \
    curl -fsSL -o /opt/modules/integrity-box.zip "$IB_URL" && \
    curl -fsSL -o /opt/modules/ksuwebui.apk "$KSU_WEBUI_URL" && \
    curl -fsSL -o /opt/modules/ksunext.apk "$KSU_NEXT_URL"

# Bake in the canonical PIF profile (Supreme toggle combo).
COPY avd/config/custom.pif.prop /opt/modules/custom.pif.prop

# Supervisor + boot scripts. first-boot.sh orchestrates the shared avd/scripts.
COPY docker/config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/scripts/start-emulator.sh /root/start-emulator.sh
COPY docker/scripts/first-boot.sh /root/first-boot.sh
COPY avd/scripts /root/scripts
RUN chmod +x /root/start-emulator.sh /root/first-boot.sh /root/scripts/*.sh

EXPOSE 5554 5555

HEALTHCHECK --interval=10s --timeout=10s --retries=600 \
  CMD adb devices | grep emulator-5554 && test -f /data/.first-boot-done || exit 1

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

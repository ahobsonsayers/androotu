# Emulator runtime. Kernel comes from the -kernel image built by build-kernel.yml.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# Base tooling (mirrors dockerify-android).
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        curl \
        git \
        iproute2 \
        libegl1 \
        libx11-6 \
        libx11-xcb1 \
        libxext6 \
        openjdk-17-jdk-headless \
        python3 \
        python3-pip \
        qemu-system-x86 \
        socat \
        supervisor \
        tzdata \
        unzip \
        wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_AVD_HOME=/data
ENV ADB_DIR="$ANDROID_HOME/platform-tools"
ENV PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ADB_DIR:$PATH"

# Android SDK: cmdline-tools, emulator, platform-tools, A36 x86_64 Play Store image.
RUN mkdir -p /opt/android-sdk/cmdline-tools && \
    cd /opt/android-sdk/cmdline-tools && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip -O cmdline-tools.zip && \
    unzip -q cmdline-tools.zip -d latest && \
    rm cmdline-tools.zip && \
    mv latest/cmdline-tools/* latest/ || true && \
    rm -rf latest/cmdline-tools || true

RUN mkdir -p /root/.android && \
    touch /root/.android/repositories.cfg && \
    mkdir -p /data /extras /opt/kernel /root/modules /opt/scripts

# Multi-GB Play Store system image, baked once.
RUN yes | sdkmanager --sdk_root=$ANDROID_HOME \
        "emulator" "platform-tools" "platforms;android-36" \
        "system-images;android-36;google_apis_playstore;x86_64" && \
    rm -f /opt/android-sdk/emulator/crashpad_handler

# Bake a deterministic adb keypair (Play Store image forces ro.adb.secure=1; clients need a trusted ADB_VENDOR_KEY).
RUN adb start-server && adb kill-server

# KSU/SUSFS kernel baked in from the kernel-builder image.
ARG KERNEL_BUILDER_IMAGE=ghcr.io/ahobsonsayers/androotu-kernel:latest
COPY --from=${KERNEL_BUILDER_IMAGE} /kernel/bzImage /opt/kernel/bzImage-a36-btf

# uv: self-contained static binary; runs CLI tools from PyPI in an isolated venv.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Module zips + manager/WebUI APKs (rebuilt to refresh).
ARG TEE_URL="https://github.com/JingMatrix/TEESimulator/releases/download/v3.2/TEESimulator-v3.2-67-Release.zip"
ARG REZYGISK_URL="https://raw.githubusercontent.com/ThePedroo/RemoteFiles/refs/heads/main/ReZygisk/ReZygisk.zip"
ARG SUSFS_URL="https://github.com/sidex15/susfs4ksu-module/releases/download/v1.5.2%2B_R27/ksu_module_susfs_1.5.2%2B.zip"
ARG IB_URL="https://github.com/MeowDump/Integrity-Box/releases/download/v40/v40-Integrity-Box-05-08-2026.zip"
ARG BKI_URL="https://github.com/Pixel-Props/BetterKnownInstalled/releases/download/1500/BetterKnownInstalled-v1.5.0.zip"
ARG KSU_WEBUI_URL="https://github.com/5ec1cff/KsuWebUIStandalone/releases/download/v1.0/KsuWebUI-1.0-34-release.apk"
ARG KSU_NEXT_URL="https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v3.2.0/KernelSU_Next_v3.2.0_33129-release.apk"
RUN curl -fsSL -o /root/modules/teesimulator.zip "$TEE_URL" && \
    curl -fsSL -o /root/modules/rezygisk.zip "$REZYGISK_URL" && \
    curl -fsSL -o /root/modules/susfs.zip "$SUSFS_URL" && \
    curl -fsSL -o /root/modules/integrity-box.zip "$IB_URL" && \
    curl -fsSL -o /root/modules/better-known-installed.zip "$BKI_URL" && \
    curl -fsSL -o /root/modules/ksuwebui.apk "$KSU_WEBUI_URL" && \
    curl -fsSL -o /root/modules/ksunext.apk "$KSU_NEXT_URL"

# Canonical PIF profile (Supreme toggle combo).
COPY avd/config/custom.pif.prop /root/modules/custom.pif.prop

# Supervisor + boot scripts. first-boot.sh runs avd/scripts once per /data.
COPY docker/config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/scripts/start-emulator.sh /root/start-emulator.sh
COPY docker/scripts/first-boot.sh /root/first-boot.sh
COPY avd/scripts /root/scripts
RUN chmod +x /root/start-emulator.sh /root/first-boot.sh /root/scripts/*.sh

EXPOSE 5554 5555

HEALTHCHECK --interval=10s --timeout=10s --retries=600 \
  CMD adb devices | grep emulator-5554 && test -f /data/.first-boot-done || exit 1

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

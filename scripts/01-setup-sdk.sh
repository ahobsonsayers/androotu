#!/usr/bin/env bash
# Install Android SDK + API 33 Play Store system image.
set -euo pipefail

AH="${ANDROID_HOME:-$HOME/Android/Sdk}"
CMD="$AH/cmdline-tools"

if [ ! -f "$CMD/tools/bin/sdkmanager" ]; then
  mkdir -p "$CMD"
  wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/cmdline-tools.zip
  unzip -q /tmp/cmdline-tools.zip -d "$CMD"
  mv "$CMD/cmdline-tools" "$CMD/tools"
  rm /tmp/cmdline-tools.zip
fi

export PATH="$AH/platform-tools:$AH/emulator:$CMD/tools/bin:$PATH"
# `yes |` can SIGPIPE (exit 141) when sdkmanager closes stdin after install; tolerate it.
yes | sdkmanager --sdk_root="$AH" \
  "platforms;android-33" \
  "system-images;android-33;google_apis_playstore;x86_64" \
  "emulator" \
  "platform-tools" || [ $? -eq 141 ]

grep -q "export ANDROID_HOME=" ~/.bashrc || {
  echo "export ANDROID_HOME=$AH" >> ~/.bashrc
  echo 'export PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/tools/bin:$PATH' >> ~/.bashrc
}
echo "SDK installed at $AH"
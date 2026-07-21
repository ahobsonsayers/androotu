FROM halimqarroum/docker-android:api-33-playstore

# Base image has SDK at /opt/android and AVD home at /data.
ENV ANDROID_HOME=/opt/android
ENV ANDROID_AVD_HOME=/data
ENV PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/tools/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    unzip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/newbit1/rootAVD.git /opt/rootAVD

COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5554 5555

ENTRYPOINT ["/entrypoint.sh"]
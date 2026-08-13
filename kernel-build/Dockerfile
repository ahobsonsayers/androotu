FROM ubuntu:24.04

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
    && rm -rf /var/lib/apt/lists/* \
    && clang --version \
    && ld.lld --version

RUN git config --global user.email "kbuild@local" \
 && git config --global user.name "kbuild" \
 && git config --global init.defaultBranch main \
 && git config --global advice.detachedHead false

ENV CCACHE_DIR=/work/.ccache
ENV PATH="/usr/lib/ccache:${PATH}"

WORKDIR /work
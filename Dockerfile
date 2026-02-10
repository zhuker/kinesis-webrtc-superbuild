FROM ubuntu:22.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    pkg-config \
    perl \
    patch \
    && rm -rf /var/lib/apt/lists/*

COPY . /src
WORKDIR /src

# Build OpenSSL from submodule source (not system libssl-dev).
# Done as a separate step for Docker layer caching and QEMU stability.
RUN cp -r openssl /tmp/openssl-build && \
    cd /tmp/openssl-build && \
    ./config no-asm --prefix=/opt/deps --openssldir=/opt/deps && \
    make -j$(nproc) && \
    make install_sw

# jsmn has no upstream CMakeLists.txt; a patch from the WebRTC SDK adds one.
# The root CMakeLists.txt applies it via `git apply`, which requires a git repo.
# In Docker (no .git context), pre-apply with `patch` so cmake skips that step.
RUN test -f jsmn/CMakeLists.txt || \
    (cd jsmn && patch -p1 < \
      ../amazon-kinesis-video-streams-webrtc-sdk-c/CMake/Dependencies/libjsmn-add-cmakelists.patch)

RUN cmake -B build-linux-amd64 \
    -DUSE_SYSTEM_OPENSSL=ON \
    -DOPENSSL_ROOT_DIR=/opt/deps
RUN cmake --build build-linux-amd64 -j2

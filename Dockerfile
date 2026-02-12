FROM ubuntu:22.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    pkg-config \
    perl \
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

RUN cmake -B build-linux-arm64 \
    -DUSE_SYSTEM_OPENSSL=ON \
    -DOPENSSL_ROOT_DIR=/opt/deps \
    -DBUILD_TEST=ON
RUN cmake --build build-linux-arm64 -j$(nproc)

ENV LD_LIBRARY_PATH=/src/build-linux-arm64/amazon-kinesis-video-streams-webrtc-sdk-c:/src/build-linux-arm64/amazon-kinesis-video-streams-producer-c:/opt/deps/lib
WORKDIR /src/amazon-kinesis-video-streams-webrtc-sdk-c/tst
CMD ["/src/build-linux-arm64/amazon-kinesis-video-streams-webrtc-sdk-c/tst/webrtc_client_test"]

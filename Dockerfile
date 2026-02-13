FROM ubuntu:22.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    pkg-config \
    perl \
    && rm -rf /var/lib/apt/lists/*

COPY . /src
WORKDIR /src

RUN cmake -B build-linux-arm64 \
    -DBUILD_TEST=ON \
    -DBUILD_SAMPLE=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DENABLE_SIGNALING=OFF
RUN cmake --build build-linux-arm64 -j$(nproc)

WORKDIR /src/amazon-kinesis-video-streams-webrtc-sdk-c/tst
CMD ["/src/build-linux-arm64/amazon-kinesis-video-streams-webrtc-sdk-c/tst/webrtc_client_test", "--gtest_break_on_failure"]

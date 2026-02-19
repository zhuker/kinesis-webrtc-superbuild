FROM ubuntu:22.04 AS builder

ARG ADDRESS_SANITIZER=OFF
ARG UNDEFINED_BEHAVIOR_SANITIZER=OFF
ARG THREAD_SANITIZER=OFF
ARG BUILD_DIR=build-linux-arm64
ENV BUILD_DIR=${BUILD_DIR}

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    pkg-config \
    perl && rm -rf /var/lib/apt/lists/*

COPY . /src
WORKDIR /src

RUN cmake -B ${BUILD_DIR} \
    -DBUILD_TEST=ON \
    -DBUILD_SAMPLE=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DENABLE_SIGNALING=OFF \
    -DADDRESS_SANITIZER=${ADDRESS_SANITIZER} \
    -DUNDEFINED_BEHAVIOR_SANITIZER=${UNDEFINED_BEHAVIOR_SANITIZER} \
    -DTHREAD_SANITIZER=${THREAD_SANITIZER}
RUN cmake --build ${BUILD_DIR} -j$(nproc)

WORKDIR /src/amazon-kinesis-video-streams-webrtc-sdk-c/tst
CMD /src/${BUILD_DIR}/amazon-kinesis-video-streams-webrtc-sdk-c/tst/webrtc_client_test --gtest_break_on_failure

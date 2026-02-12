#!/bin/bash
set -e

PLATFORM="linux/arm64"
IMAGE="kinesis-test"
TIMEOUT=300
TEST_BIN="/src/build-linux-arm64/amazon-kinesis-video-streams-webrtc-sdk-c/tst/webrtc_client_test"
LOG="docker-test.log"
CONTAINER_NAME="kinesis-tests"

cleanup() {
    docker kill "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

docker_build() {
    echo "Building Docker image..."
    docker build --platform "$PLATFORM" -t "$IMAGE" .
}

docker_run() {
    echo "Running tests (${TIMEOUT}s timeout)..."
    timeout "$TIMEOUT" docker run --platform "$PLATFORM" --init \
        --name "$CONTAINER_NAME" \
        --sysctl net.ipv6.conf.all.disable_ipv6=0 \
        "$IMAGE" "$TEST_BIN" --gtest_break_on_failure 2>&1 | tee "$LOG"
    RC=${PIPESTATUS[0]}
    echo "Test log saved to $LOG"
    exit "$RC"
}

case "${1:-}" in
    build)
        docker_build
        ;;
    run)
        shift
        docker_run "$@"
        ;;
    *)
        docker_build
        docker_run "$@"
        ;;
esac

#!/bin/bash
set -e

PLATFORM="linux/arm64"
IMAGE="kinesis-test"
TIMEOUT=300
ASAN=false
BUILD_DIR="build-${PLATFORM//\//-}"
TEST_BIN="/src/${BUILD_DIR}/amazon-kinesis-video-streams-webrtc-sdk-c/tst/webrtc_client_test"
LOG="docker-test.log"
CONTAINER_NAME="kinesis-tests"

cleanup() {
    docker kill "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

docker_build() {
    echo "Building Docker image..."
    local build_args=()
    if [[ "$ASAN" == true ]]; then
        build_args+=(--build-arg ADDRESS_SANITIZER=ON --build-arg "BUILD_DIR=${BUILD_DIR}")
    fi
    docker build --platform "$PLATFORM" "${build_args[@]}" -t "$IMAGE" .
}

docker_run() {
    echo "Running tests (${TIMEOUT}s timeout)..."
    local asan_env=()
    if [[ "$ASAN" == true ]]; then
        local asan_opts="${ASAN_OPTIONS:-halt_on_error=0:detect_stack_use_after_return=1:strict_string_checks=1:max_free_fill_size=4096:detect_invalid_pointer_pairs=2}"
        asan_env=(-e "ASAN_OPTIONS=${asan_opts}")
        echo "ASAN_OPTIONS=${asan_opts}"
    fi
    timeout "$TIMEOUT" docker run --platform "$PLATFORM" --init \
        --name "$CONTAINER_NAME" \
        --sysctl net.ipv6.conf.all.disable_ipv6=0 \
        -e AWS_KVS_LOG_LEVEL="${AWS_KVS_LOG_LEVEL:-}" \
        "${asan_env[@]}" \
        "$IMAGE" "$TEST_BIN" --gtest_break_on_failure 2>&1 | tee "$LOG"
    RC=${PIPESTATUS[0]}
    echo "Test log saved to $LOG"
    exit "$RC"
}

# Parse flags before subcommand
while [[ $# -gt 0 ]]; do
    case "$1" in
        --asan) ASAN=true; shift ;;
        *)      break ;;
    esac
done

if [[ "$ASAN" == true ]]; then
    BUILD_DIR="build-${PLATFORM//\//-}-asan"
    TEST_BIN="/src/${BUILD_DIR}/amazon-kinesis-video-streams-webrtc-sdk-c/tst/webrtc_client_test"
fi

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

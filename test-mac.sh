#!/usr/bin/env bash
#
# Build and run WebRTC SDK unit tests on macOS (arm64).
#
# Usage:
#   ./test-mac.sh                          # build and run all tests
#   ./test-mac.sh --skip-build             # reuse existing build
#   ./test-mac.sh --filter 'StunApiTest.*' # run specific tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build-mac-arm64"
CMAKE="${CMAKE:-cmake}"

SKIP_BUILD=false
GTEST_FILTER="*"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=true; shift ;;
        --filter)     GTEST_FILTER="$2"; shift 2 ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Build ──────────────────────────────────────────────────────────────
if [[ "$SKIP_BUILD" == false ]]; then
    echo "=== Building for macOS arm64 ==="
    ${CMAKE} -B "$BUILD_DIR" -S "$SCRIPT_DIR" \
        -DBUILD_TEST=ON \
        -DBUILD_SAMPLE=OFF \
        -DBUILD_STATIC_LIBS=ON \
        -DENABLE_SIGNALING=OFF
    ${CMAKE} --build "$BUILD_DIR" -j"$(sysctl -n hw.ncpu)"
fi

# ── Copy sample H264 frames needed by tests ──────────────────────────
SAMPLES_DIR="${BUILD_DIR}/amazon-kinesis-video-streams-webrtc-sdk-c/samples"
mkdir -p "$SAMPLES_DIR"
for d in girH264 bbbH264 h264SampleFrames h265SampleFrames opusSampleFrames; do
    src="${SCRIPT_DIR}/amazon-kinesis-video-streams-webrtc-sdk-c/samples/${d}"
    if [[ -d "$src" && ! -d "${SAMPLES_DIR}/${d}" ]]; then
        cp -a "$src" "$SAMPLES_DIR/"
    fi
done

# ── Run tests ──────────────────────────────────────────────────────────
echo ""
echo "=== Running tests ==="
cd "${BUILD_DIR}/amazon-kinesis-video-streams-webrtc-sdk-c/tst"
./webrtc_client_test \
    --gtest_filter="${GTEST_FILTER}" \
    --gtest_break_on_failure
echo ""
echo "=== Done ==="

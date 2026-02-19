#!/usr/bin/env bash
#
# Build and run WebRTC SDK unit tests on macOS (arm64).
#
# Usage:
#   ./test-mac.sh                          # build and run all tests
#   ./test-mac.sh --skip-build             # reuse existing build
#   ./test-mac.sh --filter 'StunApiTest.*' # run specific tests
#   ./test-mac.sh --asan                   # build with AddressSanitizer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CMAKE="${CMAKE:-cmake}"

SKIP_BUILD=false
GTEST_FILTER="*"
ASAN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=true; shift ;;
        --filter)     GTEST_FILTER="$2"; shift 2 ;;
        --asan)       ASAN=true; shift ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ "$ASAN" == true ]]; then
    BUILD_DIR="${SCRIPT_DIR}/build-mac-arm64-asan"
else
    BUILD_DIR="${SCRIPT_DIR}/build-mac-arm64"
fi

# ── Build ──────────────────────────────────────────────────────────────
if [[ "$SKIP_BUILD" == false ]]; then
    echo "=== Building for macOS arm64 ==="
    ASAN_FLAG=""
    if [[ "$ASAN" == true ]]; then
        ASAN_FLAG="-DADDRESS_SANITIZER=ON"
    fi
    ${CMAKE} -B "$BUILD_DIR" -S "$SCRIPT_DIR" \
        -DBUILD_TEST=ON \
        -DBUILD_SAMPLE=OFF \
        -DBUILD_STATIC_LIBS=ON \
        -DENABLE_SIGNALING=OFF \
        $ASAN_FLAG
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
if [[ "$ASAN" == true ]]; then
    export ASAN_OPTIONS="${ASAN_OPTIONS:-halt_on_error=0:detect_stack_use_after_return=1:alloc_dealloc_mismatch=1:strict_string_checks=1:max_free_fill_size=4096:detect_invalid_pointer_pairs=2}"
    echo "ASAN_OPTIONS=${ASAN_OPTIONS}"
fi

echo ""
echo "=== Running tests ==="
cd "${BUILD_DIR}/amazon-kinesis-video-streams-webrtc-sdk-c/tst"
./webrtc_client_test \
    --gtest_filter="${GTEST_FILTER}" \
    --gtest_break_on_failure
echo ""
echo "=== Done ==="

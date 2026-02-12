#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build-nosig"
CMAKE=/Applications/CMake.app/Contents/bin/cmake
GTEST_FILTER="${1:-*}"

echo "=== Building with ENABLE_SIGNALING=OFF ==="

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

${CMAKE} "${SCRIPT_DIR}" \
    -DUSE_SYSTEM_OPENSSL=ON \
    -DBUILD_TEST=ON \
    -DENABLE_SIGNALING=OFF

${CMAKE} --build . -j"$(sysctl -n hw.ncpu)"

echo ""
echo "=== Running tests ==="
cd "${BUILD_DIR}/amazon-kinesis-video-streams-webrtc-sdk-c/tst"
./webrtc_client_test \
    --gtest_filter="${GTEST_FILTER}" \
    --gtest_break_on_failure
echo ""
echo "=== Done ==="

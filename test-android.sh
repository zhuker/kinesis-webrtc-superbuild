#!/usr/bin/env bash
#
# Build and run WebRTC SDK unit tests on a connected Android device or emulator.
#
# Requires a device/emulator to already be running. Use restart-emulator.sh
# to start an emulator before running this script.
#
# Usage:
#   ./test-android.sh                             # build arm64, auto-detect device
#   ./test-android.sh --skip-build                # push and run only (reuse build)
#   ./test-android.sh --filter 'StunApiTest.*'    # run specific tests
#   ./test-android.sh --abi armeabi-v7a           # build arm32, find matching device
#   ./test-android.sh --serial emulator-5554      # target specific device, detect its ABI
#   ./test-android.sh --serial XXXX --abi arm64-v8a  # target device with explicit ABI
#
# Prerequisites:
#   - Android SDK with NDK 28.2.13676358 (or set ANDROID_NDK)
#   - A running device or emulator matching the target ABI
#
# Device directory layout:
#   /data/local/tmp/
#   ├── samples/              # sample data (h264/h265/opus frames)
#   │   ├── h264SampleFrames/
#   │   ├── h265SampleFrames/
#   │   ├── opusSampleFrames/
#   │   ├── girH264/
#   │   └── bbbH264/
#   ├── tst/
#   │   └── webrtc_client_test
#   └── run-tests-on-device.sh  # test runner (pushed by this script)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAMPLES_SRC="${SCRIPT_DIR}/amazon-kinesis-video-streams-webrtc-sdk-c/samples"

# Android SDK paths
ANDROID_SDK="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
ANDROID_NDK="${ANDROID_NDK:-${ANDROID_SDK}/ndk/28.2.13676358}"
ADB="${ANDROID_SDK}/platform-tools/adb"

DEVICE_DIR="/data/local/tmp"

SKIP_BUILD=false
GTEST_FILTER="*"
SERIAL=""
ABI=""
ABI_SET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=true; shift ;;
        --filter)     GTEST_FILTER="$2"; shift 2 ;;
        --serial)     SERIAL="$2"; shift 2 ;;
        --abi)        ABI="$2"; ABI_SET=true; shift 2 ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Find a connected device ───────────────────────────────────────────
find_device_for_abi() {
    local target_abi="$1"
    local serials
    serials=$("$ADB" devices | grep -v "^$" | grep -v "^List" | awk '{print $1}')

    for s in $serials; do
        local device_abi
        device_abi=$("$ADB" -s "$s" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r') || continue
        if [[ "$device_abi" == "$target_abi" ]]; then
            echo "$s"
            return 0
        fi
    done
    return 1
}

if [[ -n "$SERIAL" && "$ABI_SET" == false ]]; then
    # --serial given without --abi: detect the device's primary ABI
    ABI=$("$ADB" -s "$SERIAL" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')
    if [[ -z "$ABI" ]]; then
        echo "ERROR: Could not detect ABI from device ${SERIAL}."
        exit 1
    fi
    echo "=== Detected ABI '${ABI}' from device ${SERIAL} ==="
elif [[ -z "$SERIAL" ]]; then
    echo "=== Looking for a connected ${ABI} device ==="
    if FOUND=$(find_device_for_abi "$ABI"); then
        SERIAL="$FOUND"
    else
        echo "ERROR: No ${ABI} device found. Start an emulator or connect a device first."
        echo "  To start an emulator: ./emulator.sh start"
        exit 1
    fi
fi

# ── Verify ABI compatibility ──────────────────────────────────────────
DEVICE_ABILIST=$("$ADB" -s "$SERIAL" shell getprop ro.product.cpu.abilist 2>/dev/null | tr -d '\r')
if [[ -z "$DEVICE_ABILIST" ]]; then
    echo "ERROR: Could not query ABI list from device ${SERIAL}."
    exit 1
fi
if [[ ",$DEVICE_ABILIST," != *",$ABI,"* ]]; then
    echo "ERROR: Device ${SERIAL} does not support ABI '${ABI}'."
    echo "  Device supports: ${DEVICE_ABILIST}"
    exit 1
fi

BUILD_DIR="${SCRIPT_DIR}/build-android-${ABI}"

echo "=== Using device: ${SERIAL} (ABI: ${ABI}) ==="

adb_cmd() {
    if [[ -n "$SERIAL" ]]; then
        "$ADB" -s "$SERIAL" "$@"
    else
        "$ADB" "$@"
    fi
}

# ── Build ──────────────────────────────────────────────────────────────
if [[ "$SKIP_BUILD" == false ]]; then
    echo "=== Building for Android ${ABI} ==="
    cmake -B "$BUILD_DIR" -S "$SCRIPT_DIR" \
        -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK}/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="${ABI}" \
        -DANDROID_PLATFORM=android-26 \
        -DBUILD_SAMPLE=OFF \
        -DBUILD_STATIC_LIBS=ON \
        -DBUILD_TEST=ON \
        -DENABLE_SIGNALING=OFF
    cmake --build "$BUILD_DIR" -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
fi



# ── Push binaries and data ────────────────────────────────────────────
echo "=== Pushing test binary ==="
adb_cmd shell mkdir -p "${DEVICE_DIR}/tst"
adb_cmd push "${BUILD_DIR}/amazon-kinesis-video-streams-webrtc-sdk-c/tst/webrtc_client_test" "${DEVICE_DIR}/tst/"
adb_cmd shell chmod +x "${DEVICE_DIR}/tst/webrtc_client_test"

echo "=== Pushing sample data ==="
adb_cmd shell mkdir -p "${DEVICE_DIR}/samples"
for dir in h264SampleFrames h265SampleFrames opusSampleFrames girH264 bbbH264; do
    if [[ -d "${SAMPLES_SRC}/${dir}" ]]; then
        echo "  ${dir}/"
        adb_cmd push --sync "${SAMPLES_SRC}/${dir}" "${DEVICE_DIR}/samples/"
    fi
done

# ── Run tests ──────────────────────────────────────────────────────────
echo "=== Pushing test runner script ==="
adb_cmd push "${SCRIPT_DIR}/run-tests-on-device.sh" "${DEVICE_DIR}/"
adb_cmd shell chmod +x "${DEVICE_DIR}/run-tests-on-device.sh"

TEST_LOG="${BUILD_DIR}/test-output-${SERIAL}.log"

echo ""
echo "=== Running tests (log: ${TEST_LOG}) ==="
echo ""
set +e
adb_cmd shell "${DEVICE_DIR}/run-tests-on-device.sh '${GTEST_FILTER}'" | tee "$TEST_LOG"
TEST_EXIT=${PIPESTATUS[0]}
set -e

echo ""
echo "Log saved to ${TEST_LOG}"

exit $TEST_EXIT

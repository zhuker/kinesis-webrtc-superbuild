#!/usr/bin/env bash
#
# Build and run WebRTC SDK unit tests on an Android emulator.
#
# Usage:
#   ./test-android.sh              # build, push, and run tests
#   ./test-android.sh --skip-build # push and run only (reuse existing build)
#   ./test-android.sh --filter 'StunApiTest.*'  # run specific tests
#
# Prerequisites:
#   - Android SDK with NDK 25.2.9519653 (or set ANDROID_NDK)
#   - AVD named "test-android26-arm64" (created automatically if missing)
#   - System image: system-images;android-26;default;arm64-v8a
#
# To create the AVD and system image manually:
#   sdkmanager "system-images;android-26;default;arm64-v8a"
#   avdmanager create avd -n test-android26-arm64 \
#     -k "system-images;android-26;default;arm64-v8a" -f <<< "no"
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
#   ├── run-tests-on-device.sh  # test runner (pushed by this script)
#   ├── test-output.log         # test output from last run
#   ├── libkvsCommonLws.so
#   └── libwebsockets.so

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build-android-arm64"
SAMPLES_SRC="${SCRIPT_DIR}/amazon-kinesis-video-streams-webrtc-sdk-c/samples"

# Android SDK paths
ANDROID_SDK="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
ANDROID_NDK="${ANDROID_NDK:-${ANDROID_SDK}/ndk/25.2.9519653}"
ADB="${ANDROID_SDK}/platform-tools/adb"
EMULATOR="${ANDROID_SDK}/emulator/emulator"
SDKMANAGER="${ANDROID_SDK}/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="${ANDROID_SDK}/cmdline-tools/latest/bin/avdmanager"

AVD_NAME="test-android26-arm64"
SYSTEM_IMAGE="system-images;android-26;default;arm64-v8a"
DEVICE_DIR="/data/local/tmp"

SKIP_BUILD=false
GTEST_FILTER="*"
SERIAL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=true; shift ;;
        --filter)     GTEST_FILTER="$2"; shift 2 ;;
        --serial)     SERIAL="$2"; shift 2 ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

adb_cmd() {
    if [[ -n "$SERIAL" ]]; then
        "$ADB" -s "$SERIAL" "$@"
    else
        "$ADB" "$@"
    fi
}

# ── Build ──────────────────────────────────────────────────────────────
if [[ "$SKIP_BUILD" == false ]]; then
    echo "=== Building for Android arm64-v8a ==="
    cmake -B "$BUILD_DIR" -S "$SCRIPT_DIR" \
        -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK}/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI=arm64-v8a \
        -DANDROID_PLATFORM=android-26 \
        -DBUILD_SAMPLE=OFF \
        -DBUILD_STATIC_LIBS=ON \
        -DBUILD_TEST=ON
    cmake --build "$BUILD_DIR" -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
fi

# ── Ensure emulator is running ─────────────────────────────────────────
ensure_emulator() {
    # Check if an emulator is already connected
    if adb_cmd shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; then
        echo "=== Emulator already running ==="
        return
    fi

    # Ensure system image is installed
    if [[ ! -d "${ANDROID_SDK}/system-images/android-26/default/arm64-v8a" ]]; then
        echo "=== Installing system image ==="
        echo "y" | "$SDKMANAGER" "$SYSTEM_IMAGE"
    fi

    # Ensure AVD exists
    if ! "$EMULATOR" -list-avds 2>/dev/null | grep -q "^${AVD_NAME}$"; then
        echo "=== Creating AVD: ${AVD_NAME} ==="
        "$AVDMANAGER" create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" -f <<< "no"
    fi

    echo "=== Starting emulator ==="
    "$EMULATOR" -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim \
        -gpu swiftshader_indirect &>/tmp/emulator-test.log &
    EMULATOR_PID=$!

    echo "Waiting for emulator to boot (PID: ${EMULATOR_PID})..."
    adb_cmd wait-for-device
    # Wait for boot_completed
    for i in $(seq 1 120); do
        if adb_cmd shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; then
            echo "Emulator booted."
            return
        fi
        sleep 2
    done
    echo "ERROR: Emulator failed to boot within 240 seconds"
    exit 1
}

# If no serial specified, try to auto-detect emulator
if [[ -z "$SERIAL" ]]; then
    EMU_SERIAL=$("$ADB" devices | grep "^emulator-" | head -1 | awk '{print $1}')
    if [[ -n "$EMU_SERIAL" ]]; then
        SERIAL="$EMU_SERIAL"
    else
        ensure_emulator
        EMU_SERIAL=$("$ADB" devices | grep "^emulator-" | head -1 | awk '{print $1}')
        SERIAL="$EMU_SERIAL"
    fi
fi

echo "=== Using device: ${SERIAL} ==="

# ── Push binaries and data ────────────────────────────────────────────
echo "=== Pushing shared libraries ==="
adb_cmd push "${BUILD_DIR}/amazon-kinesis-video-streams-producer-c/libkvsCommonLws.so" "${DEVICE_DIR}/"
adb_cmd push "${BUILD_DIR}/libwebsockets/lib/libwebsockets.so" "${DEVICE_DIR}/"

echo "=== Pushing test binary ==="
adb_cmd shell mkdir -p "${DEVICE_DIR}/tst"
adb_cmd push "${BUILD_DIR}/amazon-kinesis-video-streams-webrtc-sdk-c/tst/webrtc_client_test" "${DEVICE_DIR}/tst/"
adb_cmd shell chmod +x "${DEVICE_DIR}/tst/webrtc_client_test"

echo "=== Pushing sample data ==="
adb_cmd shell mkdir -p "${DEVICE_DIR}/samples"
for dir in h264SampleFrames h265SampleFrames opusSampleFrames girH264 bbbH264; do
    if [[ -d "${SAMPLES_SRC}/${dir}" ]]; then
        echo "  ${dir}/"
        adb_cmd push "${SAMPLES_SRC}/${dir}" "${DEVICE_DIR}/samples/"
    fi
done

# ── Run tests ──────────────────────────────────────────────────────────
echo "=== Pushing test runner script ==="
adb_cmd push "${SCRIPT_DIR}/run-tests-on-device.sh" "${DEVICE_DIR}/"
adb_cmd shell chmod +x "${DEVICE_DIR}/run-tests-on-device.sh"

echo ""
echo "=== Running tests (log: ${DEVICE_DIR}/test-output.log) ==="
echo ""
adb_cmd shell "${DEVICE_DIR}/run-tests-on-device.sh '${GTEST_FILTER}'"
TEST_EXIT=$?

echo ""
echo "=== Pulling test log ==="
adb_cmd pull "${DEVICE_DIR}/test-output.log" "${BUILD_DIR}/test-output.log"
echo "Log saved to ${BUILD_DIR}/test-output.log"

exit $TEST_EXIT

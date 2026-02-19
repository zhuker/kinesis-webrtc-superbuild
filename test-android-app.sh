#!/usr/bin/env bash
#
# Build, install, and run instrumented tests for android-test-app.
#
# android-test-app is a self-contained Gradle project that builds the
# WebRTC SDK native code via AGP's CMake integration, packages the JNI
# library and sample assets into an APK, and runs native gtest tests
# through Android instrumentation (untrusted_app SELinux domain).
#
# Requires a connected device or running emulator.
#
# Usage:
#   ./test-android-app.sh                          # build + run, auto-detect device
#   ./test-android-app.sh --skip-build             # reuse previous build
#   ./test-android-app.sh --filter 'StunApiTest.*' # gtest filter
#   ./test-android-app.sh --abi armeabi-v7a        # find matching device
#   ./test-android-app.sh --serial emulator-5554   # target specific device, detect its ABI
#   ./test-android-app.sh --serial XXXX --abi arm64-v8a  # target device with explicit ABI
#   ./test-android-app.sh --asan                        # build with AddressSanitizer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${SCRIPT_DIR}/android-test-app"

APP_APK="${APP_DIR}/app/build/outputs/apk/debug/app-debug.apk"
TEST_APK="${APP_DIR}/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"

APP_ID="com.kvs.webrtctest"
TEST_PKG="${APP_ID}.test"
INSTRUMENT_RUNNER="androidx.test.runner.AndroidJUnitRunner"

LOG_DIR="${SCRIPT_DIR}/build-android-app-logs"

# Android SDK paths
ANDROID_SDK="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
ADB="${ANDROID_SDK}/platform-tools/adb"

SKIP_BUILD=false
GTEST_FILTER="*"
SERIAL=""
ABI="arm64-v8a"
ABI_SET=false
ASAN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=true; shift ;;
        --filter)     GTEST_FILTER="$2"; shift 2 ;;
        --serial)     SERIAL="$2"; shift 2 ;;
        --abi)        ABI="$2"; ABI_SET=true; shift 2 ;;
        --asan)       ASAN=true; shift ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Find a connected device ───────────────────────────────────────────
find_device_for_abi() {
    local target_abi="$1"
    local serials
    serials=$("$ADB" devices | grep -v "^$" | grep -v "^List" | awk '{print $1}')

    while read -r s; do
        [[ -z "$s" ]] && continue
        local device_abi
        device_abi=$("$ADB" -s "$s" shell getprop ro.product.cpu.abi </dev/null 2>/dev/null | tr -d '\r') || continue
        if [[ "$device_abi" == "$target_abi" ]]; then
            echo "$s"
            return 0
        fi
    done <<< "$serials"
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

echo "=== Using device: ${SERIAL} (ABI: ${ABI}) ==="

adb_cmd() {
    "$ADB" -s "$SERIAL" "$@"
}

# ── Build via Gradle ─────────────────────────────────────────────────
if [[ "$SKIP_BUILD" == false ]]; then
    echo "=== Building android-test-app via Gradle ==="
    GRADLE_PROPS=()
    if [[ "$ASAN" == true ]]; then
        GRADLE_PROPS+=(-PenableAsan=true)
    fi
    "${APP_DIR}/gradlew" -p "$APP_DIR" "${GRADLE_PROPS[@]}" assembleDebug assembleDebugAndroidTest

    if [[ ! -f "$APP_APK" ]]; then
        echo "ERROR: App APK not found at ${APP_APK}"
        exit 1
    fi
    if [[ ! -f "$TEST_APK" ]]; then
        echo "ERROR: Test APK not found at ${TEST_APK}"
        exit 1
    fi
    echo "=== Build complete ==="
    echo "  App APK:  ${APP_APK}"
    echo "  Test APK: ${TEST_APK}"
fi


# ── Uninstall previous versions (clean state) ───────────────────────
echo "=== Cleaning previous installation ==="
adb_cmd uninstall "$APP_ID" 2>/dev/null || true
adb_cmd uninstall "$TEST_PKG" 2>/dev/null || true

# ── Install APKs ─────────────────────────────────────────────────────
echo "=== Installing app APK ==="
adb_cmd install -r -t "$APP_APK"

echo "=== Installing test APK ==="
adb_cmd install -r -t "$TEST_APK"

# ── Prepare log directory ────────────────────────────────────────────
mkdir -p "$LOG_DIR"

# ── Clear logcat for clean capture ───────────────────────────────────
adb_cmd logcat -c || true

# ── Run instrumented tests ───────────────────────────────────────────
echo ""
echo "=== Running instrumented tests ==="
echo "  Package:  ${APP_ID}"
echo "  Runner:   ${INSTRUMENT_RUNNER}"
echo "  Filter:   ${GTEST_FILTER}"
echo ""

INSTRUMENT_OUTPUT="${LOG_DIR}/instrument-output-${SERIAL}.log"
set +o pipefail
timeout 300 "$ADB" -s "$SERIAL" shell "am instrument -w -r \
    -e gtest_filter '${GTEST_FILTER}' \
    -e class com.kvs.webrtctest.WebRtcNativeTest \
    ${TEST_PKG}/${INSTRUMENT_RUNNER}" | tr -d '\r' | tee "$INSTRUMENT_OUTPUT"
TIMEOUT_EXIT=${PIPESTATUS[0]}
set -o pipefail

# ── Capture logcat ───────────────────────────────────────────────────
echo ""
echo "=== Saving logcat ==="
LOGCAT_FILE="${LOG_DIR}/logcat-${SERIAL}.log"
adb_cmd logcat -d -s "webrtc_test_jni:*" "WebRtcNativeTest:*" "TestRunner:*" > "$LOGCAT_FILE" 2>/dev/null || true
echo "Logcat saved to ${LOGCAT_FILE}"

# ── Parse result ─────────────────────────────────────────────────────
INST_CODE=$(grep '^INSTRUMENTATION_CODE:' "$INSTRUMENT_OUTPUT" | tail -1 | awk '{print $2}' || echo "")

echo ""
echo "Instrument output saved to ${INSTRUMENT_OUTPUT}"

if [[ "$TIMEOUT_EXIT" -eq 124 ]]; then
    echo "=== TIMEOUT (exceeded 300s) ==="
    exit 1
elif [[ "$INST_CODE" == "-1" ]]; then
    echo "=== PASSED ==="
    exit 0
else
    echo "=== FAILED (INSTRUMENTATION_CODE: ${INST_CODE}) ==="
    echo ""
    echo "Check logcat for details:"
    echo "  ${LOGCAT_FILE}"
    echo ""
    echo "Or run: adb -s ${SERIAL} logcat -d -s webrtc_test_jni:*"
    exit 1
fi

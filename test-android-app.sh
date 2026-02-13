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
#   ./test-android-app.sh                          # build + run
#   ./test-android-app.sh --skip-build             # reuse previous build
#   ./test-android-app.sh --filter 'StunApiTest.*' # gtest filter
#   ./test-android-app.sh --serial emulator-5554   # target specific device

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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=true; shift ;;
        --filter)     GTEST_FILTER="$2"; shift 2 ;;
        --serial)     SERIAL="$2"; shift 2 ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

# If no serial specified, auto-detect
if [[ -z "$SERIAL" ]]; then
    SERIAL=$("$ADB" devices | grep -v "^$" | grep -v "^List" | head -1 | awk '{print $1}' || true)
fi

if [[ -z "$SERIAL" ]]; then
    echo "ERROR: No connected device found. Start an emulator or connect a device first."
    exit 1
else
    echo "=== Using device: ${SERIAL} ==="
fi

adb_cmd() {
    "$ADB" -s "$SERIAL" "$@"
}

# Verify a device is connected
if ! adb_cmd shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; then
    echo "ERROR: No connected device found. Start an emulator or connect a device first."
    exit 1
fi

# ── Build via Gradle ─────────────────────────────────────────────────
if [[ "$SKIP_BUILD" == false ]]; then
    echo "=== Building android-test-app via Gradle ==="
    "${APP_DIR}/gradlew" -p "$APP_DIR" assembleDebug assembleDebugAndroidTest

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

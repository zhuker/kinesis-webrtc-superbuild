#!/usr/bin/env bash

GTEST_FILTER="*"
APP_DIR="./android-test-app"
APP_APK="${APP_DIR}/app/build/outputs/apk/debug/app-debug.apk"
TEST_APK="${APP_DIR}/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --filter)     GTEST_FILTER="$2"; shift 2 ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

build_app() {
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
}


build_app

LOG_DIR="./build-android-app-logs"

SERIALS=$(adb devices | awk 'NR > 1 && NF > 0 {print $1}')

if [[ -z "$SERIALS" ]]; then
    echo "ERROR: No connected devices found."
    exit 1
fi

echo "$SERIALS" | xargs -IDEVICEID -P0 sh -c "./test-android-app.sh --skip-build --serial DEVICEID --filter \"${GTEST_FILTER}\" 2>&1 | tee \"${LOG_DIR}/output-DEVICEID.log\"" || true

echo ""
echo "=== Results ==="
ANY_FAIL=false
for SERIAL in $SERIALS; do
    INST_LOG="${LOG_DIR}/instrument-output-${SERIAL}.log"
    LOGCAT="${LOG_DIR}/logcat-${SERIAL}.log"

    # Extract INSTRUMENTATION_CODE from instrument output
    INST_CODE=""
    if [[ -f "$INST_LOG" ]]; then
        INST_CODE=$(grep '^INSTRUMENTATION_CODE:' "$INST_LOG" | tail -1 | awk '{print $2}')
    fi

    if [[ -z "$INST_CODE" ]]; then
        # No instrumentation code: timeout killed the process before completion
        echo "${SERIAL}: TIMEOUT"
        ANY_FAIL=true
    elif [[ "$INST_CODE" == "-1" ]]; then
        # Check logcat for gtest failures as a cross-check
        if [[ -f "$LOGCAT" ]] && grep -q '\[  FAILED  \]' "$LOGCAT" 2>/dev/null; then
            echo "${SERIAL}: FAILED"
            ANY_FAIL=true
        else
            echo "${SERIAL}: PASSED"
        fi
    else
        echo "${SERIAL}: FAILED"
        ANY_FAIL=true
    fi
done

if [[ "$ANY_FAIL" == true ]]; then
    exit 1
fi


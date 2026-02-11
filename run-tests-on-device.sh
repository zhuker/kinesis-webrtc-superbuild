#!/system/bin/sh
#
# Test runner script executed on the Android device/emulator.
# Pushed and invoked by test-android.sh.
#
# Usage: ./run-tests-on-device.sh [gtest_filter]
#
# Output is saved to /data/local/tmp/test-output.log via tee.

DEVICE_DIR="/data/local/tmp"
GTEST_FILTER="${1:-*}"
LOG_FILE="${DEVICE_DIR}/test-output.log"

cd "${DEVICE_DIR}/tst"
export LD_LIBRARY_PATH="${DEVICE_DIR}"

echo "=== Test run started: $(date) ===" | tee "$LOG_FILE"
echo "Filter: ${GTEST_FILTER}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

timeout 300 ./webrtc_client_test \
    --gtest_filter="${GTEST_FILTER}" \
    --gtest_break_on_failure 2>&1 | tee -a "$LOG_FILE"

EXIT_CODE=$?
echo "" | tee -a "$LOG_FILE"
echo "=== Test run finished: $(date), exit code: ${EXIT_CODE} ===" | tee -a "$LOG_FILE"
exit $EXIT_CODE

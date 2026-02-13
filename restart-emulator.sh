#!/usr/bin/env bash
#
# Restart the Android emulator. Kills any running emulator first.
#
# Usage:
#   ./restart-emulator.sh                # restart API 26 emulator
#   ./restart-emulator.sh --api 29       # restart API 29 emulator
#

set -euo pipefail

ANDROID_SDK="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
ADB="${ANDROID_SDK}/platform-tools/adb"
EMULATOR="${ANDROID_SDK}/emulator/emulator"
SDKMANAGER="${ANDROID_SDK}/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="${ANDROID_SDK}/cmdline-tools/latest/bin/avdmanager"

API_LEVEL=26

while [[ $# -gt 0 ]]; do
    case "$1" in
        --api) API_LEVEL="$2"; shift 2 ;;
        *)     echo "Unknown option: $1"; exit 1 ;;
    esac
done

AVD_NAME="test-android${API_LEVEL}-arm64"
SYSTEM_IMAGE="system-images;android-${API_LEVEL};default;arm64-v8a"

# ── Kill running emulator if any ─────────────────────────────────────
EMU_SERIAL=$("$ADB" devices | grep "^emulator-" | head -1 | awk '{print $1}' || true)
if [[ -n "$EMU_SERIAL" ]]; then
    echo "=== Killing running emulator: ${EMU_SERIAL} ==="
    "$ADB" -s "$EMU_SERIAL" emu kill 2>/dev/null || true
    # Wait for the emulator process to exit
    for i in $(seq 1 30); do
        if ! "$ADB" devices | grep -q "^emulator-"; then
            break
        fi
        sleep 1
    done
    echo "Emulator stopped."
else
    echo "=== No running emulator found ==="
fi

# ── Ensure system image is installed ─────────────────────────────────
if [[ ! -d "${ANDROID_SDK}/system-images/android-${API_LEVEL}/default/arm64-v8a" ]]; then
    echo "=== Installing system image: ${SYSTEM_IMAGE} ==="
    echo "y" | "$SDKMANAGER" "$SYSTEM_IMAGE"
fi

# ── Ensure AVD exists ────────────────────────────────────────────────
if ! "$EMULATOR" -list-avds 2>/dev/null | grep -q "^${AVD_NAME}$"; then
    echo "=== Creating AVD: ${AVD_NAME} ==="
    "$AVDMANAGER" create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" -f <<< "no"
fi

# ── Start emulator ───────────────────────────────────────────────────
echo "=== Starting emulator: ${AVD_NAME} ==="
"$EMULATOR" -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim \
    -gpu swiftshader_indirect &>/tmp/emulator-test.log &
EMULATOR_PID=$!

echo "Waiting for emulator to boot (PID: ${EMULATOR_PID})..."
"$ADB" wait-for-device
for i in $(seq 1 120); do
    if "$ADB" shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; then
        EMU_SERIAL=$("$ADB" devices | grep "^emulator-" | head -1 | awk '{print $1}' || true)
        echo "Emulator booted: ${EMU_SERIAL}"
        exit 0
    fi
    sleep 2
done

echo "ERROR: Emulator failed to boot within 240 seconds"
exit 1

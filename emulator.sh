#!/usr/bin/env bash
#
# Manage the Android emulator for testing.
#
# Usage:
#   ./emulator.sh start                  # start API 26 emulator (error if already running)
#   ./emulator.sh start -f               # start emulator (no-op if already running)
#   ./emulator.sh start --api 30         # start API 30 emulator
#   ./emulator.sh stop                   # stop emulator (error if 0 or >1 running)
#   ./emulator.sh restart                # stop + start
#   ./emulator.sh restart --api 30       # stop + start API 30
#   ./emulator.sh status                 # list running emulators with API levels

set -euo pipefail

ANDROID_SDK="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
ADB="${ANDROID_SDK}/platform-tools/adb"
EMULATOR_BIN="${ANDROID_SDK}/emulator/emulator"
SDKMANAGER="${ANDROID_SDK}/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="${ANDROID_SDK}/cmdline-tools/latest/bin/avdmanager"

# ── Helpers ───────────────────────────────────────────────────────────

# List running emulator serials (one per line)
running_emulators() {
    "$ADB" devices 2>/dev/null | grep "^emulator-" | awk '{print $1}' || true
}

do_status() {
    local devices
    devices=$("$ADB" devices 2>/dev/null | grep -v "^$" | grep -v "^List" | awk '{print $1}')

    if [[ -z "$devices" ]]; then
        echo "No connected devices."
        return
    fi

    printf "%-20s  %-10s  %-6s  %s\n" "SERIAL" "TYPE" "API" "ABIs"
    echo "$devices" | while read -r s; do
        local api abi type
        api=$("$ADB" -s "$s" shell getprop ro.build.version.sdk </dev/null 2>/dev/null | tr -d '\r') || api="?"
        abi=$("$ADB" -s "$s" shell getprop ro.product.cpu.abilist </dev/null 2>/dev/null | tr -d '\r') || abi="?"
        if [[ "$s" == emulator-* ]]; then
            type="emulator"
        else
            type="device"
        fi
        printf "%-20s  %-10s  %-6s  %s\n" "$s" "$type" "$api" "$abi"
    done
}

do_stop() {
    local emulators
    emulators=$(running_emulators)
    local count
    count=$(echo "$emulators" | grep -c . || true)

    if [[ "$count" -eq 0 ]]; then
        echo "ERROR: No running emulator to stop."
        exit 1
    elif [[ "$count" -gt 1 ]]; then
        echo "ERROR: Multiple emulators running. Stop them manually:"
        echo "$emulators" | while read -r s; do echo "  adb -s $s emu kill"; done
        exit 1
    fi

    local serial
    serial=$(echo "$emulators" | head -1)
    echo "=== Stopping emulator: ${serial} ==="
    "$ADB" -s "$serial" emu kill 2>/dev/null || true
    for i in $(seq 1 30); do
        if [[ -z "$(running_emulators)" ]]; then
            break
        fi
        sleep 1
    done
    echo "Emulator stopped."
}

do_start() {
    local api_level=26
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --api) api_level="$2"; shift 2 ;;
            -f)    force=true; shift ;;
            *)     echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    local avd_name="test-android${api_level}-arm64"
    local system_image="system-images;android-${api_level};default;arm64-v8a"

    # Check if already running
    local running
    running=$(running_emulators | head -1)
    if [[ -n "$running" ]]; then
        if [[ "$force" == true ]]; then
            echo "Emulator already running: ${running}"
            exit 0
        else
            echo "ERROR: Emulator already running: ${running}"
            echo "  Use -f to ignore, or stop it first: ./emulator.sh stop"
            exit 1
        fi
    fi

    # Ensure system image is installed
    if [[ ! -d "${ANDROID_SDK}/system-images/android-${api_level}/default/arm64-v8a" ]]; then
        echo "=== Installing system image: ${system_image} ==="
        echo "y" | "$SDKMANAGER" "$system_image"
    fi

    # Ensure AVD exists
    if ! "$EMULATOR_BIN" -list-avds 2>/dev/null | grep -q "^${avd_name}$"; then
        echo "=== Creating AVD: ${avd_name} ==="
        "$AVDMANAGER" create avd -n "$avd_name" -k "$system_image" -f <<< "no"
    fi

    # Start
    echo "=== Starting emulator: ${avd_name} ==="
    "$EMULATOR_BIN" -avd "$avd_name" -no-window -no-audio -no-boot-anim \
        -gpu swiftshader_indirect &>/tmp/emulator-test.log &
    local pid=$!

    echo "Waiting for emulator to boot (PID: ${pid})..."
    "$ADB" wait-for-device
    for i in $(seq 1 120); do
        if "$ADB" shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; then
            local serial
            serial=$(running_emulators | head -1)
            echo "Emulator booted: ${serial}"
            exit 0
        fi
        sleep 2
    done

    echo "ERROR: Emulator failed to boot within 240 seconds"
    exit 1
}

# ── Main ──────────────────────────────────────────────────────────────
COMMAND="${1:-}"
shift || true

case "$COMMAND" in
    start)
        do_start "$@"
        ;;
    status)
        do_status
        ;;
    stop)
        do_stop
        ;;
    restart)
        # stop may fail if nothing is running — that's fine for restart
        do_stop 2>/dev/null || true
        do_start "$@"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart} [options]"
        echo ""
        echo "Commands:"
        echo "  start              Start emulator (error if already running)"
        echo "  start -f           Start emulator (no-op if already running)"
        echo "  start --api N      Start emulator with API level N (default: 26)"
        echo "  status             List running emulators with API levels"
        echo "  stop               Stop running emulator"
        echo "  restart            Stop + start"
        exit 1
        ;;
esac

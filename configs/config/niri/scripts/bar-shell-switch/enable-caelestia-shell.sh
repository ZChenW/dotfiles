#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/bar-shell-switch"
MODE_FILE="$STATE_DIR/current"
LOG_DIR="$STATE_DIR/logs"
CAELESTIA_LOG="$LOG_DIR/caelestia-shell.log"

mkdir -p "$STATE_DIR" "$LOG_DIR"

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Bar shell switch" "$1" >/dev/null 2>&1 || true
    fi
}

stop_waybar() {
    pkill -x waybar >/dev/null 2>&1 || true
}

caelestia_running() {
    pgrep -x caelestia-shell >/dev/null 2>&1 && return 0
    pgrep -f "caelestia shell" >/dev/null 2>&1 && return 0
    pgrep -f "qs .*caelestia" >/dev/null 2>&1 && return 0
    pgrep -f "quickshell .*caelestia" >/dev/null 2>&1 && return 0
    return 1
}

find_qs_path() {
    local candidate
    for candidate in \
        "${CAELESTIA_QS_PATH:-}" \
        "$HOME/.config/quickshell/caelestia" \
        "$HOME/waybar_or_squickshell/shell" \
        "$SCRIPT_DIR/../shell" \
        "$SCRIPT_DIR/../../shell" \
        "/etc/xdg/quickshell/caelestia" \
        "/usr/share/caelestia-shell"
    do
        if [[ -n "$candidate" && -f "$candidate/shell.qml" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

start_detached() {
    : > "$CAELESTIA_LOG"
    if command -v setsid >/dev/null 2>&1; then
        setsid -f "$@" >>"$CAELESTIA_LOG" 2>&1
    else
        nohup "$@" >>"$CAELESTIA_LOG" 2>&1 &
    fi
}

start_caelestia() {
    local qs_path

    if caelestia_running; then
        echo "Caelestia/Quickshell shell is already running."
        return 0
    fi

    if command -v caelestia >/dev/null 2>&1; then
        echo "Starting with: caelestia shell -d"
        start_detached caelestia shell -d
        return 0
    fi

    if command -v caelestia-shell >/dev/null 2>&1; then
        echo "Starting with: caelestia-shell -d"
        start_detached caelestia-shell -d
        return 0
    fi

    if qs_path="$(find_qs_path)" && command -v qs >/dev/null 2>&1; then
        echo "Starting with: qs -d -p $qs_path"
        start_detached qs -d -p "$qs_path"
        return 0
    fi

    if qs_path="$(find_qs_path)" && command -v quickshell >/dev/null 2>&1; then
        echo "Starting with: quickshell -d -p $qs_path"
        start_detached quickshell -d -p "$qs_path"
        return 0
    fi

    echo "ERROR: no Caelestia launcher found." >&2
    echo "Install caelestia-shell, or set CAELESTIA_QS_PATH to a folder containing shell.qml." >&2
    notify "Failed: Caelestia shell launcher not found."
    return 1
}

printf 'caelestia\n' > "$MODE_FILE"
stop_waybar
start_caelestia

echo "Enabled Caelestia shell. Desired mode recorded in $MODE_FILE."
notify "Caelestia shell enabled"

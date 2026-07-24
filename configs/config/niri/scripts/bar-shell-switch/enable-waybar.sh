#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/bar-shell-switch"
MODE_FILE="$STATE_DIR/current"
LOG_DIR="$STATE_DIR/logs"
WAYBAR_LOG="$LOG_DIR/waybar.log"

mkdir -p "$STATE_DIR" "$LOG_DIR"

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Bar shell switch" "$1" >/dev/null 2>&1 || true
    fi
}

stop_caelestia() {
    if command -v qs >/dev/null 2>&1; then
        qs kill -c caelestia >/dev/null 2>&1 || true
    fi

    pkill -x caelestia-shell >/dev/null 2>&1 || true
    pkill -f "caelestia shell" >/dev/null 2>&1 || true
    pkill -f "qs .*caelestia" >/dev/null 2>&1 || true
    pkill -f "quickshell .*caelestia" >/dev/null 2>&1 || true
}

start_waybar() {
    if pgrep -x waybar >/dev/null 2>&1; then
        echo "waybar is already running."
        return 0
    fi

    if ! command -v waybar >/dev/null 2>&1; then
        echo "ERROR: waybar is not installed or not in PATH." >&2
        notify "Failed: waybar is not installed."
        return 1
    fi

    : > "$WAYBAR_LOG"
    if command -v setsid >/dev/null 2>&1; then
        setsid -f waybar >>"$WAYBAR_LOG" 2>&1
    else
        nohup waybar >>"$WAYBAR_LOG" 2>&1 &
    fi
}

printf 'waybar\n' > "$MODE_FILE"
stop_caelestia
start_waybar

echo "Enabled Waybar. Desired mode recorded in $MODE_FILE."
notify "Waybar enabled"

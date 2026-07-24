#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/bar-shell-switch"
MODE_FILE="$STATE_DIR/current"

desired="waybar"
if [[ -f "$MODE_FILE" ]]; then
    desired="$(tr -d '[:space:]' < "$MODE_FILE")"
fi

waybar_status="stopped"
waybar_pids=""
if waybar_pids="$(pgrep -x waybar 2>/dev/null || true)" && [[ -n "$waybar_pids" ]]; then
    waybar_status="running"
fi

caelestia_status="stopped"
caelestia_lines=""
if caelestia_lines="$(
    {
        pgrep -af "caelestia shell" 2>/dev/null || true
        pgrep -af "caelestia-shell" 2>/dev/null || true
        pgrep -af "qs .*caelestia" 2>/dev/null || true
        pgrep -af "quickshell .*caelestia" 2>/dev/null || true
    } | awk '!seen[$0]++'
)" && [[ -n "$caelestia_lines" ]]; then
    caelestia_status="running"
fi

summary="desired: $desired | waybar: $waybar_status | caelestia: $caelestia_status"

echo "$summary"
echo
echo "Waybar PIDs:"
if [[ -n "$waybar_pids" ]]; then
    echo "$waybar_pids"
else
    echo "none"
fi

echo
echo "Caelestia/Quickshell processes:"
if [[ -n "$caelestia_lines" ]]; then
    echo "$caelestia_lines"
else
    echo "none"
fi

if [[ "${1:-}" == "--notify" || ! -t 1 ]] && command -v notify-send >/dev/null 2>&1; then
    notify-send "Bar shell status" "$summary" >/dev/null 2>&1 || true
fi

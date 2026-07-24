#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/bar-shell-switch"
MODE_FILE="$STATE_DIR/current"

mode="waybar"
if [[ -f "$MODE_FILE" ]]; then
    mode="$(tr -d '[:space:]' < "$MODE_FILE" || true)"
fi

case "$mode" in
    caelestia)
        exec "$SCRIPT_DIR/enable-caelestia-shell.sh"
        ;;
    *)
        exec "$SCRIPT_DIR/enable-waybar.sh"
        ;;
esac

#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
BACKUP_BASE="$STATE_HOME/bar-shell-switch/backups"
INCLUDE_WAYBAR=false

usage() {
    echo "Usage: $0 [--include-waybar]"
    echo
    echo "By default, this preview leaves ~/.config/waybar untouched."
    echo "Pass --include-waybar to preview copying waybar/ into ~/.config/waybar/."
}

for arg in "$@"; do
    case "$arg" in
        --include-waybar)
            INCLUDE_WAYBAR=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            usage >&2
            exit 2
            ;;
    esac
done

echo "Preview only. No files will be copied."
echo
echo "Repository: $REPO_DIR"
echo "Backup base: $BACKUP_BASE/<timestamp>"
echo
if [[ "$INCLUDE_WAYBAR" == true ]]; then
    echo "Waybar copy: enabled by --include-waybar."
else
    echo "Waybar copy: disabled by default; existing $CONFIG_HOME/waybar will not be overwritten."
fi
echo
echo "Would copy:"
if [[ "$INCLUDE_WAYBAR" == true ]]; then
    echo "  $REPO_DIR/waybar/ -> $CONFIG_HOME/waybar/"
else
    echo "  (skipped by default) $REPO_DIR/waybar/ -> $CONFIG_HOME/waybar/"
fi
echo "  $REPO_DIR/config.kdl -> $CONFIG_HOME/niri/config.kdl"
echo "  $REPO_DIR/scripts/*.sh -> $CONFIG_HOME/niri/scripts/bar-shell-switch/"
echo "  $REPO_DIR/caelestia/shell.json -> $CONFIG_HOME/caelestia/shell.json"
echo
echo "Would not copy:"
echo "  $REPO_DIR/shell/ (Caelestia source is left untouched)"
echo
echo "Existing targets:"
for target in \
    "$CONFIG_HOME/waybar" \
    "$CONFIG_HOME/niri/config.kdl" \
    "$CONFIG_HOME/niri/scripts/bar-shell-switch" \
    "$CONFIG_HOME/caelestia/shell.json"
do
    if [[ -e "$target" ]]; then
        echo "  exists:  $target"
    else
        echo "  missing: $target"
    fi
done

echo
if [[ -x "$SCRIPT_DIR/check-deps.sh" ]]; then
    "$SCRIPT_DIR/check-deps.sh"
else
    echo "Run scripts/check-deps.sh after it is made executable for dependency details."
fi

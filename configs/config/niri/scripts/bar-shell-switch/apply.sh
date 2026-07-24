#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$STATE_HOME/bar-shell-switch/backups/$TIMESTAMP"
INCLUDE_WAYBAR=false

usage() {
    echo "Usage: $0 [--include-waybar]"
    echo
    echo "By default, this script does not copy waybar/ and will not overwrite ~/.config/waybar."
    echo "Pass --include-waybar to back up and copy waybar/ into ~/.config/waybar/."
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

backup_path() {
    local src="$1"
    local name="$2"
    if [[ -e "$src" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$src" "$BACKUP_DIR/$name"
        echo "Backed up $src -> $BACKUP_DIR/$name"
    fi
}

install_dir_contents() {
    local src_dir="$1"
    local dst_dir="$2"
    mkdir -p "$dst_dir"
    cp -a "$src_dir/." "$dst_dir/"
}

install_file() {
    local src="$1"
    local dst="$2"
    mkdir -p "$(dirname -- "$dst")"
    cp -a "$src" "$dst"
}

echo "Applying bar/shell switch configuration."
echo "Repository: $REPO_DIR"
echo "Backup dir: $BACKUP_DIR"
if [[ "$INCLUDE_WAYBAR" == true ]]; then
    echo "Waybar copy: enabled by --include-waybar."
else
    echo "Waybar copy: disabled by default; $CONFIG_HOME/waybar will not be overwritten."
fi
echo

if [[ "$INCLUDE_WAYBAR" == true ]]; then
    backup_path "$CONFIG_HOME/waybar" "waybar"
fi
backup_path "$CONFIG_HOME/niri/config.kdl" "niri-config.kdl"
backup_path "$CONFIG_HOME/niri/scripts/bar-shell-switch" "bar-shell-switch-scripts"
backup_path "$CONFIG_HOME/caelestia/shell.json" "caelestia-shell.json"

if [[ "$INCLUDE_WAYBAR" == true ]]; then
    install_dir_contents "$REPO_DIR/waybar" "$CONFIG_HOME/waybar"
else
    echo "Skipped Waybar copy. Re-run with --include-waybar to copy $REPO_DIR/waybar/."
fi
install_file "$REPO_DIR/config.kdl" "$CONFIG_HOME/niri/config.kdl"
install_dir_contents "$REPO_DIR/scripts" "$CONFIG_HOME/niri/scripts/bar-shell-switch"
install_file "$REPO_DIR/caelestia/shell.json" "$CONFIG_HOME/caelestia/shell.json"
chmod +x "$CONFIG_HOME/niri/scripts/bar-shell-switch/"*.sh

echo
echo "Copied files. No services were started or stopped."
echo "Run one of these after reloading niri if desired:"
echo "  $CONFIG_HOME/niri/scripts/bar-shell-switch/enable-waybar.sh"
echo "  $CONFIG_HOME/niri/scripts/bar-shell-switch/enable-caelestia-shell.sh"
echo
echo "Rollback from this backup:"
if [[ "$INCLUDE_WAYBAR" == true ]]; then
    echo "  cp -a \"$BACKUP_DIR/waybar/.\" \"$CONFIG_HOME/waybar/\""
else
    echo "  # Waybar was not copied by this run."
fi
echo "  cp -a \"$BACKUP_DIR/niri-config.kdl\" \"$CONFIG_HOME/niri/config.kdl\""
echo "  cp -a \"$BACKUP_DIR/caelestia-shell.json\" \"$CONFIG_HOME/caelestia/shell.json\""

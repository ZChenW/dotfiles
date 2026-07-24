#!/usr/bin/env bash
# Pick a matugen scheme type and regenerate waybar colors from the current wallpaper.
set -euo pipefail

types=(
    scheme-tonal-spot
    scheme-content
    scheme-expressive
    scheme-fidelity
    scheme-fruit-salad
    scheme-monochrome
    scheme-neutral
    scheme-rainbow
    scheme-vibrant
)

if ! command -v matugen >/dev/null 2>&1; then
    notify-send "matugen" "matugen is not installed" 2>/dev/null || true
    echo "matugen not found" >&2
    exit 1
fi

picker=()
if command -v fuzzel >/dev/null 2>&1; then
    picker=(fuzzel --dmenu --prompt "matugen type> ")
elif command -v wofi >/dev/null 2>&1; then
    picker=(wofi --dmenu --prompt "matugen type")
else
    notify-send "matugen" "Need fuzzel or wofi to pick a scheme type" 2>/dev/null || true
    echo "No dmenu launcher found (fuzzel/wofi)" >&2
    exit 1
fi

selected="$(printf '%s\n' "${types[@]}" | "${picker[@]}")"
[[ -n "${selected:-}" ]] || exit 0

wallpaper=""
if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/waypaper/config.ini" ]]; then
    wallpaper="$(
        awk -F' *= *' '/^wallpaper *=/{print $2; exit}' \
            "${XDG_CONFIG_HOME:-$HOME/.config}/waypaper/config.ini"
    )"
    wallpaper="${wallpaper/#\~/$HOME}"
fi

if [[ -z "$wallpaper" || ! -f "$wallpaper" ]]; then
    notify-send "matugen" "Current wallpaper not found" 2>/dev/null || true
    echo "wallpaper missing: ${wallpaper:-}" >&2
    exit 1
fi

matugen image "$wallpaper" -t "$selected" -m dark --prefer darkness

if pgrep -x waybar >/dev/null 2>&1; then
    pkill -x waybar 2>/dev/null || true
    sleep 0.15
    nohup waybar >/dev/null 2>&1 &
    disown || true
fi

notify-send "matugen" "Applied $selected" 2>/dev/null || true

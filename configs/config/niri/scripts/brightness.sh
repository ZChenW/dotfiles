#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: ${0##*/} {+PERCENT%|PERCENT%-}" >&2
}

adjustment="${1:-}"
if [[ "$adjustment" =~ ^([0-9]+)%-$ ]]; then
    adjustment="-${BASH_REMATCH[1]}%"
fi
if [[ ! "$adjustment" =~ ^[+-][0-9]+%$ ]]; then
    usage
    exit 2
fi

backlight_root="${BRIGHTNESS_SYSFS_ROOT:-/sys/class/backlight}"
drm_root="${BRIGHTNESS_DRM_SYSFS_ROOT:-/sys/class/drm}"

normalize_connector() {
    local name="${1##*/}"
    if [[ "$name" =~ ^card[0-9]+-(.+)$ ]]; then
        name="${BASH_REMATCH[1]}"
    fi
    printf '%s\n' "$name"
}

path_is_within() {
    local parent="${1%/}"
    local candidate="${2%/}"
    [[ -n "$parent" && -n "$candidate" ]] || return 1
    [[ "$candidate" == "$parent" || "$candidate" == "$parent/"* ]]
}

focused_connector=""
if focused_output="$(niri msg focused-output 2>/dev/null)" \
    && [[ "$focused_output" =~ \(([^()]*)\) ]]; then
    focused_connector="$(normalize_connector "${BASH_REMATCH[1]}")"
fi

declare -a backlight_names=()
declare -a backlight_paths=()
shopt -s nullglob
for entry in "$backlight_root"/*; do
    device_path="$(readlink -f -- "$entry/device" 2>/dev/null || true)"
    [[ -n "$device_path" ]] || continue
    backlight_names+=("${entry##*/}")
    backlight_paths+=("$device_path")
done

if ((${#backlight_names[@]} == 0)); then
    echo "No backlight device is available" >&2
    exit 1
fi

connector_path=""
connector_gpu_path=""
if [[ -n "$focused_connector" ]]; then
    for entry in "$drm_root"/card*-*; do
        [[ -f "$entry/status" ]] || continue
        [[ "$(<"$entry/status")" == connected ]] || continue
        [[ "$(normalize_connector "$entry")" == "$focused_connector" ]] || continue
        connector_path="$(readlink -f -- "$entry" 2>/dev/null || true)"
        connector_gpu_path="$(readlink -f -- "$entry/device/device" 2>/dev/null || true)"
        break
    done
fi

declare -a matches=()
if [[ -n "$connector_path" ]]; then
    for index in "${!backlight_names[@]}"; do
        if path_is_within "$connector_path" "${backlight_paths[$index]}"; then
            matches+=("${backlight_names[$index]}")
        fi
    done
fi

if ((${#matches[@]} > 1)); then
    echo "Multiple backlights are attached to $focused_connector; refusing an ambiguous write" >&2
    exit 1
fi

if ((${#matches[@]} == 0)) && [[ -n "$connector_gpu_path" ]]; then
    for index in "${!backlight_names[@]}"; do
        if path_is_within "$connector_gpu_path" "${backlight_paths[$index]}" \
            || path_is_within "${backlight_paths[$index]}" "$connector_gpu_path"; then
            matches+=("${backlight_names[$index]}")
        fi
    done
fi

if ((${#matches[@]} > 1)); then
    echo "Multiple backlights match the GPU for $focused_connector; refusing an ambiguous write" >&2
    exit 1
fi

if ((${#matches[@]} == 1)); then
    selected="${matches[0]}"
elif ((${#backlight_names[@]} == 1)); then
    selected="${backlight_names[0]}"
else
    echo "Could not map $focused_connector to one backlight; refusing to use an arbitrary default" >&2
    exit 1
fi

brightness_helper="${BRIGHTNESS_HELPER:-${QUICKSHELL_CONFIG_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/clavis}/scripts/system/brightness.sh}"
if [[ -x "$brightness_helper" ]]; then
    exec "$brightness_helper" --device "$selected" --adjust "$adjustment"
fi

fallback_adjustment="$adjustment"
if [[ "$adjustment" =~ ^-([0-9]+)%$ ]]; then
    fallback_adjustment="${BASH_REMATCH[1]}%-"
fi
exec brightnessctl --device "$selected" set "$fallback_adjustment"

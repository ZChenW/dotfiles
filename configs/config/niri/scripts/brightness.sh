#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: ${0##*/} [--output CONNECTOR|--output internal|--external] {--get|+PERCENT%|-PERCENT%|PERCENT%-|--set-percent PERCENT}" >&2
}

explicit_output=""
if [[ "${1:-}" == --output ]]; then
    [[ "$#" -ge 3 && "$2" =~ ^[A-Za-z0-9._:-]+$ ]] || { usage; exit 2; }
    explicit_output="$2"
    shift 2
fi
external_only=false
if [[ "${1:-}" == --external ]]; then
    external_only=true
    shift
fi
adjustment=""
percent=""
get_only=false
if [[ "${1:-}" == --get && "$#" == 1 ]]; then
    get_only=true
elif [[ "${1:-}" == --set-percent ]]; then
    [[ "$#" == 2 && "$2" =~ ^[0-9]{1,3}$ ]] || { usage; exit 2; }
    percent=$((10#$2))
    ((percent <= 100)) || { usage; exit 2; }
else
    [[ "$#" == 1 ]] || { usage; exit 2; }
    adjustment="$1"
    if [[ "$adjustment" =~ ^([0-9]+)%-$ ]]; then
        adjustment="-${BASH_REMATCH[1]}%"
    fi
    [[ "$adjustment" =~ ^[+-][0-9]{1,3}%$ ]] || { usage; exit 2; }
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

# The laptop panel is eDP-1 on the iGPU in hybrid mode and eDP-2 on the dGPU
# in discrete mode; "internal" lets callers avoid hard-coding either.
if [[ "$explicit_output" == internal ]]; then
    shopt -s nullglob
    for entry in "$drm_root"/card*-*; do
        [[ "$(normalize_connector "$entry")" =~ ^(eDP|LVDS|DSI)- ]] || continue
        [[ -f "$entry/status" && "$(<"$entry/status")" == connected ]] || continue
        explicit_output="$(normalize_connector "$entry")"
        break
    done
    shopt -u nullglob
    [[ "$explicit_output" != internal ]] || { echo "No internal panel is connected" >&2; exit 1; }
fi

focused_connector="$(normalize_connector "$explicit_output")"
if [[ -z "$focused_connector" ]]; then
    if focused_output="$(niri msg focused-output 2>/dev/null)" \
        && [[ "$focused_output" =~ \(([^()]*)\) ]]; then
        focused_connector="$(normalize_connector "${BASH_REMATCH[1]}")"
    else
        echo "Cannot determine the output for brightness control" >&2
        exit 1
    fi
fi

# GPU backlight nodes do not control external DP/HDMI monitors. Resolve DDC
# before any backlight fallback. Cache the I2C bus (and VCP max) per connector
# so drag/scroll does not pay for a full ddcutil detect on every step.
if [[ "$external_only" == true ]] || { [[ -n "$focused_connector" ]] && [[ ! "$focused_connector" =~ ^(eDP|LVDS|DSI)- ]]; }; then
    cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/brightness"
    mkdir -p "$cache_root"

    cache_key="${focused_connector//\//_}"
    [[ "$cache_key" =~ ^[A-Za-z0-9._:-]+$ ]] || cache_key="unknown"
    bus_cache="$cache_root/bus-$cache_key"
    selected_bus=""
    cached_maximum=""
    if [[ -f "$bus_cache" ]]; then
        {
            IFS= read -r selected_bus || true
            IFS= read -r cached_maximum || true
        } <"$bus_cache"
        [[ "$selected_bus" =~ ^[0-9]+$ ]] || selected_bus=""
        [[ "$cached_maximum" =~ ^[1-9][0-9]*$ ]] || cached_maximum=""
    fi

    # Scroll bursts spawn one process per wheel step. Each one only records the
    # newest wanted raw value ("VALUE SEQ") and the first to own the DDC lock
    # writes it; the rest find their request already applied and exit.
    target_file="$cache_root/target-$cache_key"
    applied_file="$cache_root/applied-$cache_key"
    state_value=""
    state_seq=0
    read_state() {
        local value="" seq=""
        state_value=""
        state_seq=0
        [[ -f "$1" ]] && read -r value seq <"$1" || true
        [[ "$value" =~ ^[0-9]+$ && "$seq" =~ ^[0-9]+$ ]] || return 1
        state_value=$((10#$value))
        state_seq=$((10#$seq))
    }
    write_state() {
        local tmp
        tmp="$(mktemp "$cache_root/state.XXXXXX")"
        printf '%s %s\n' "$2" "$3" >"$tmp"
        mv -f "$tmp" "$1"
    }
    # queue_target MAXIMUM [BASE]: without BASE, a relative step builds on the
    # last requested value, which is only trusted for a minute.
    queue_target() {
        local maximum="$1" base="${2:-}" target age
        exec 9>"$cache_root/target.lock"
        flock 9
        read_state "$target_file" || true
        if [[ -n "$percent" ]]; then
            target=$(((maximum * percent + 50) / 100))
        else
            if [[ -z "$base" && -n "$state_value" ]]; then
                age=$(($(date +%s) - $(stat -c %Y "$target_file")))
                ((age < 60)) && base="$state_value"
            fi
            [[ -n "$base" ]] || { flock -u 9; return 1; }
            [[ "$adjustment" =~ ^([+-])([0-9]+)%$ ]]
            target=$(((maximum * 10#${BASH_REMATCH[2]} + 50) / 100))
            if [[ "${BASH_REMATCH[1]}" == + ]]; then target=$((base + target)); else target=$((base - target)); fi
        fi
        ((target < 0)) && target=0
        ((target > maximum)) && target="$maximum"
        write_state "$target_file" "$target" $((state_seq + 1))
        flock -u 9
    }

    queued=false
    if [[ "$get_only" == false && -n "$selected_bus" && -n "$cached_maximum" ]] && queue_target "$cached_maximum"; then
        queued=true
    fi

    exec 8>"$cache_root/ddc.lock"
    flock -w 5 8 || { echo "External brightness control is busy" >&2; exit 1; }

    discover_ddc_bus() {
        local detection line bus connector match_count index
        local -a ddc_names=() ddc_buses=()
        local valid_display=false
        detection="$(LC_ALL=C ddcutil detect --brief)" || return 1
        bus=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^Display[[:space:]][0-9]+ ]]; then
                valid_display=true
                bus=""
            elif [[ "$line" =~ ^Invalid[[:space:]]display ]]; then
                valid_display=false
                bus=""
            elif [[ "$valid_display" == true && "$line" =~ I2C[[:space:]]bus:.*\/dev\/i2c-([0-9]+) ]]; then
                bus="${BASH_REMATCH[1]}"
            elif [[ "$valid_display" == true && "$line" =~ DRM[[:space:]]connector:[[:space:]]*([^[:space:]]+) ]]; then
                connector="$(normalize_connector "${BASH_REMATCH[1]}")"
                if [[ -n "$bus" && ! "$connector" =~ ^(eDP|LVDS|DSI)- ]]; then
                    ddc_names+=("$connector")
                    ddc_buses+=("$bus")
                fi
            fi
        done <<<"$detection"
        selected_bus=""
        match_count=0
        for index in "${!ddc_names[@]}"; do
            if [[ "${ddc_names[$index]}" == "$focused_connector" ]]; then
                selected_bus="${ddc_buses[$index]}"
                match_count=$((match_count + 1))
            fi
        done
        if ((match_count == 0)) && [[ "$external_only" == true ]] && ((${#ddc_buses[@]} == 1)); then
            selected_bus="${ddc_buses[0]}"
            match_count=1
        fi
        ((match_count == 1)) || return 1
        return 0
    }

    write_bus_cache() {
        local tmp
        tmp="$(mktemp "$cache_root/bus.XXXXXX")"
        {
            printf '%s\n' "$selected_bus"
            [[ -n "$cached_maximum" ]] && printf '%s\n' "$cached_maximum"
        } >"$tmp"
        mv -f "$tmp" "$bus_cache"
    }

    read_vcp() {
        local vcp
        vcp="$(LC_ALL=C ddcutil -b "$selected_bus" --skip-ddc-checks getvcp 10 --brief)" || return 1
        [[ "$vcp" =~ ^VCP[[:space:]]+10[[:space:]]+C[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)[[:space:]]*$ ]] || return 1
        current=$((10#${BASH_REMATCH[1]}))
        maximum=$((10#${BASH_REMATCH[2]}))
        ((maximum > 0 && current <= maximum)) || return 1
        cached_maximum="$maximum"
        write_bus_cache
        return 0
    }

    if [[ -z "$selected_bus" ]]; then
        discover_ddc_bus || {
            echo "No unambiguous DDC monitor for $focused_connector; focus the external monitor and retry" >&2
            exit 1
        }
        write_bus_cache
    fi

    current=""
    maximum="$cached_maximum"
    # A queued request already knows the bus, the max and its base value; skip
    # the slow getvcp round trip.
    if [[ "$queued" == true ]]; then
        :
    elif ! read_vcp; then
        rm -f "$bus_cache"
        selected_bus=""
        cached_maximum=""
        discover_ddc_bus || {
            echo "No unambiguous DDC monitor for $focused_connector; focus the external monitor and retry" >&2
            exit 1
        }
        write_bus_cache
        read_vcp || {
            echo "External monitor returned invalid brightness data" >&2
            exit 1
        }
    fi

    if [[ "$get_only" == true ]]; then
        # A real reading is the new base for relative steps unless one is pending.
        exec 9>"$cache_root/target.lock"
        flock 9
        read_state "$target_file" || true
        pending_seq="$state_seq"
        if ! read_state "$applied_file" || [[ "$state_seq" == "$pending_seq" ]]; then
            write_state "$target_file" "$current" "$pending_seq"
            write_state "$applied_file" "$current" "$pending_seq"
        fi
        flock -u 9
        printf '%s,%s,%s,%s,%s\n' "$focused_connector" "$current" "$current" "$(((current * 100 + maximum / 2) / maximum))" "$maximum"
        exit 0
    fi
    [[ "$queued" == true ]] || queue_target "$maximum" "$current"
    read_state "$target_file"
    target="$state_value"
    target_seq="$state_seq"
    if read_state "$applied_file" && [[ "$state_seq" == "$target_seq" ]]; then
        exit 0
    fi
    # Verification and capability probing triple the DDC round trip.
    if ! LC_ALL=C ddcutil -b "$selected_bus" --noverify --skip-ddc-checks setvcp 10 "$target"; then
        rm -f "$bus_cache"
        exit 1
    fi
    write_state "$applied_file" "$target" "$target_seq"
    exit 0
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

if [[ -n "$explicit_output" && -z "$connector_path" ]]; then
    echo "Output $focused_connector is disconnected; refusing brightness control" >&2
    exit 1
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
elif [[ -z "$explicit_output" ]] && ((${#backlight_names[@]} == 1)); then
    selected="${backlight_names[0]}"
else
    echo "Could not map $focused_connector to one backlight; refusing to use an arbitrary default" >&2
    exit 1
fi

brightness_helper="${BRIGHTNESS_HELPER:-${QUICKSHELL_CONFIG_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/clavis}/scripts/system/brightness.sh}"
if [[ -x "$brightness_helper" ]]; then
    if [[ "$get_only" == true ]]; then
        exec "$brightness_helper" --device "$selected" --get
    fi
    if [[ -n "$percent" ]]; then
        exec "$brightness_helper" --device "$selected" --set-percent "$percent"
    fi
    exec "$brightness_helper" --device "$selected" --adjust "$adjustment"
fi

if [[ "$get_only" == true ]]; then
    raw="$(brightnessctl --device "$selected" get)"
    maximum="$(brightnessctl --device "$selected" max)"
    [[ "$raw" =~ ^[0-9]+$ && "$maximum" =~ ^[1-9][0-9]*$ ]] || exit 1
    printf '%s,%s,%s,%s,%s\n' "$selected" "$raw" "$raw" "$(((raw * 100 + maximum / 2) / maximum))" "$maximum"
    exit 0
fi

fallback_adjustment="${adjustment:-${percent}%}"
if [[ "$adjustment" =~ ^-([0-9]+)%$ ]]; then
    fallback_adjustment="${BASH_REMATCH[1]}%-"
fi
exec brightnessctl --device "$selected" set "$fallback_adjustment"

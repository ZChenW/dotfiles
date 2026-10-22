#!/usr/bin/env bash
# Empty JSON text hides the module when no external display supports DDC/CI.
set -euo pipefail
helper="${XDG_CONFIG_HOME:-$HOME/.config}/niri/scripts/brightness.sh"
if reading="$("$helper" --external --get 2>/dev/null)"; then
    IFS=, read -r _ _ _ percent _ <<<"$reading"
    if [[ "$percent" =~ ^[0-9]+$ ]]; then
        printf '{"text":"󰃠 %s%%","tooltip":"External display brightness"}\n' "$percent"
        exit 0
    fi
fi
printf '{"text":""}\n'

#!/usr/bin/bash

set -euo pipefail

open_idleflow() {
    idle-control-desktop >/dev/null 2>&1 &
}

refresh_waybar() {
    pkill -RTMIN+8 -x waybar 2>/dev/null || true
}

if ! status_json="$(idlectl status 2>/dev/null)"; then
    open_idleflow
    exit 0
fi

enabled="$(jq -r '.enabled' <<<"$status_json")"
inhibited="$(jq -r '.inhibited' <<<"$status_json")"

if [[ "$enabled" != true ]]; then
    open_idleflow
elif [[ "$inhibited" == true ]]; then
    idlectl uninhibit >/dev/null
else
    idlectl inhibit >/dev/null
fi

refresh_waybar

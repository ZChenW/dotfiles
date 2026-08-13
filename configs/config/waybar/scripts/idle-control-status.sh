#!/usr/bin/bash

set -euo pipefail

if ! status_json="$(idlectl status 2>/dev/null)"; then
    jq -nc '{text:"", class:"unavailable", tooltip:"IdleFlow 不可用\n左键：打开 IdleFlow\n右键：打开 IdleFlow"}'
    exit 0
fi

enabled="$(jq -r '.enabled' <<<"$status_json")"
inhibited="$(jq -r '.inhibited' <<<"$status_json")"
source="$(jq -r 'if .power_source == "battery" then "电池" else "交流电" end' <<<"$status_json")"

if [[ "$inhibited" == true ]]; then
    class_name=inhibited
    icon=""
    state_text="IdleFlow 已暂停"
    action_text="左键：恢复自动锁屏、熄屏和休眠"
elif [[ "$enabled" == true ]]; then
    class_name=managed
    icon="󰒲"
    state_text="IdleFlow 运行中"
    action_text="左键：暂停自动锁屏、熄屏和休眠"
else
    class_name=observe
    icon=""
    state_text="IdleFlow 未接管"
    action_text="左键：打开 IdleFlow"
fi

tooltip="$(printf '%s · %s\n%s\n%s' \
    "$state_text" \
    "$source" \
    "$action_text" \
    '右键：打开 IdleFlow')"

jq -nc \
    --arg text "$icon" \
    --arg class "$class_name" \
    --arg tooltip "$tooltip" \
    '{text:$text, class:$class, tooltip:$tooltip}'

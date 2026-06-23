#!/bin/bash

# === 配置部分 ===
CACHE_FILE="$HOME/.cache/waybar-updates.json"

# === 函数定义 ===
generate_json() {
    local updates=$1
    local count
    
    if [ -z "$updates" ]; then
        count=0
    else
        count=$(echo "$updates" | wc -l)
    fi

    if [ "$count" -gt 0 ]; then
        local tooltip=$(echo "$updates" | awk '{printf "%s\\n", $0}' | sed 's/"/\\"/g' | head -c -2)
        printf '{"text": "%s", "alt": "has-updates", "tooltip": "%s"}\n' "$count" "$tooltip"
    else
        printf '{"text": "", "alt": "updated", "tooltip": "System is up to date"}\n'
    fi
}

# === 主逻辑 ===

# 尝试获取更新
# 捕获输出
NEW_UPDATES=$(checkupdates 2>/dev/null)
STATUS=$?

# === 关键修正 ===
# checkupdates 退出代码说明：
# 0 = 有更新
# 2 = 无更新 (这是正常情况，不是错误！)
# 1 = 发生错误 (如网络断开、锁被占用)

if [ $STATUS -eq 0 ]; then
    # --- 情况A：发现更新 ---
    OUTPUT=$(generate_json "$NEW_UPDATES")
    echo "$OUTPUT" > "$CACHE_FILE"
    echo "$OUTPUT"

elif [ $STATUS -eq 2 ]; then
    # --- 情况B：正常运行，但没有更新 ---
    # 必须清空缓存或者写入 0 状态，而不是读取旧缓存
    OUTPUT=$(generate_json "")
    echo "$OUTPUT" > "$CACHE_FILE"
    echo "$OUTPUT"

else
    # --- 情况C：真的出错了 (Exit 1) ---
    # 比如没网，或者 pacman 锁死
    # 只有这种时候才读取旧缓存来保底
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
    else
        printf '{"text": "?", "alt": "updated", "tooltip": "Check failed"}\n'
    fi
fi

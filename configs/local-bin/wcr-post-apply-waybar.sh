#!/usr/bin/env bash
# Post-apply：统一主题管线 + 通知 QuickShell 外部所有权
#
# Used by wallpaper-console-rust:
#   post_apply_enabled=on
#   post_apply_command=~/.local/bin/wcr-post-apply-waybar.sh
#
# Env from Wallpaper Console:
#   WCR_STILL / WCR_WALLPAPER / WCR_BACKEND / WCR_OUTPUTS
#
# 主题管线：clavis 拥有 scheme/mode 真相源（统一入口 generate_themes.sh），
# 本脚本零 matugen 参数知识。

set -euo pipefail

still="${WCR_STILL:-${1:-}}"
if [[ -z "$still" || ! -f "$still" ]]; then
  echo "wcr-post-apply-waybar: still missing: '${still:-}'" >&2
  exit 1
fi

pipeline="${QUICKSHELL_THEME_PIPELINE:-${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/clavis/scripts/theme/generate_themes.sh}"
if [[ -x "$pipeline" ]]; then
  "$pipeline" --image "$still" \
    || echo "wcr-post-apply-waybar: theme pipeline failed" >&2
else
  echo "wcr-post-apply-waybar: generate_themes.sh not found at $pipeline" >&2
fi

# Notify QuickShell (clavis) that an external renderer now owns the background.
if command -v qs >/dev/null 2>&1; then
  quickshell_config="${QUICKSHELL_CONFIG_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/clavis}"
  qs ipc --path "$quickshell_config" call wallpaper externalApplied \
    "$still" "${WCR_BACKEND:-}" >/dev/null 2>&1 || true
fi

exit 0

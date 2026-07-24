#!/usr/bin/env bash
# Post-apply: extract theme from wallpaper still → waybar colors.css
#
# Used by wallpaper-console-rust:
#   post_apply_enabled=on
#   post_apply_command=~/.local/bin/wcr-post-apply-waybar.sh
#
# Env from Wallpaper Console:
#   WCR_STILL / WCR_WALLPAPER / WCR_BACKEND / WCR_OUTPUTS

set -euo pipefail

still="${WCR_STILL:-${1:-}}"
if [[ -z "$still" || ! -f "$still" ]]; then
  echo "wcr-post-apply-waybar: still missing: '${still:-}'" >&2
  exit 1
fi

if ! command -v matugen >/dev/null 2>&1; then
  echo "wcr-post-apply-waybar: matugen not found" >&2
  exit 1
fi

# --prefer avoids interactive prompts when multiple seed colors exist
matugen image "$still" -m dark --prefer darkness

# Do NOT use `killall -SIGUSR2` — on this system it can terminate waybar
# instead of reloading, which makes the bar disappear.
# Restart only if waybar was already running (matches niri spawn-at-startup).
if pgrep -x waybar >/dev/null 2>&1; then
  pkill -x waybar 2>/dev/null || true
  # Brief wait so the compositor releases the layer-shell surface
  sleep 0.15
  nohup waybar >/dev/null 2>&1 &
  disown || true
fi

exit 0

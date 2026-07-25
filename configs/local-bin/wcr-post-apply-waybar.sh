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

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
matugen_config="$config_home/matugen/config.toml"
matugen_template="$config_home/matugen/templates/waybar-colors.css"
waybar_colors="$config_home/waybar/colors.css"
lock_dir="$state_home/wallpaper-console"

if [[ ! -f "$matugen_config" ]]; then
  echo "wcr-post-apply-waybar: matugen config missing: $matugen_config" >&2
  exit 1
fi
if [[ ! -f "$matugen_template" ]]; then
  echo "wcr-post-apply-waybar: matugen template missing: $matugen_template" >&2
  exit 1
fi

matugen_bin="${MATUGEN_BIN:-}"
if [[ -z "$matugen_bin" ]]; then
  matugen_bin="$(command -v matugen 2>/dev/null || true)"
fi
if [[ -z "$matugen_bin" && -x /usr/bin/matugen ]]; then
  matugen_bin=/usr/bin/matugen
fi
if [[ -z "$matugen_bin" ]]; then
  echo "wcr-post-apply-waybar: matugen not found" >&2
  exit 1
fi

mkdir -p "$lock_dir"
exec 9>"$lock_dir/waybar-theme.lock"
if command -v flock >/dev/null 2>&1; then
  flock -w 10 9 || {
    echo "wcr-post-apply-waybar: timed out waiting for theme lock" >&2
    exit 1
  }
fi

# An explicit config makes the hook independent of the GUI or compositor
# working directory and supports non-default XDG_CONFIG_HOME values.
"$matugen_bin" \
  --config "$matugen_config" \
  image "$still" \
  --mode dark \
  --prefer darkness

if [[ ! -s "$waybar_colors" ]]; then
  echo "wcr-post-apply-waybar: matugen did not generate $waybar_colors" >&2
  exit 1
fi

# Do NOT use `killall -SIGUSR2` — on this system it can terminate waybar
# instead of reloading, which makes the bar disappear.
# Restart only if waybar was already running (matches niri spawn-at-startup).
if pgrep -x waybar >/dev/null 2>&1; then
  waybar_bin="$(command -v waybar 2>/dev/null || true)"
  if [[ -z "$waybar_bin" && -x /usr/bin/waybar ]]; then
    waybar_bin=/usr/bin/waybar
  fi
  if [[ -z "$waybar_bin" ]]; then
    echo "wcr-post-apply-waybar: running Waybar cannot be restarted; binary not found" >&2
    exit 1
  fi

  pkill -x waybar 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x waybar >/dev/null 2>&1 || break
    sleep 0.05
  done

  # setsid prevents the hook runner's process group from owning the new bar.
  if command -v setsid >/dev/null 2>&1; then
    setsid -f "$waybar_bin" >/dev/null 2>&1 9>&-
  else
    nohup "$waybar_bin" >/dev/null 2>&1 9>&- &
    disown || true
  fi
fi

exit 0

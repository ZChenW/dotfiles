#!/usr/bin/env bash
# Requires a live Wayland session with two outputs. Never writes real hardware.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
read -r -a gtk_flags <<<"$(pkg-config --cflags --libs gtk+-3.0 gtk-layer-shell-0)"
cc -O1 -g -Wall -Wextra -Werror "$repo_root/tests/test_waybar_brightness.c" \
    -o "$tmp_dir/probe" "${gtk_flags[@]}" -lm
mkdir -p "$tmp_dir/config/niri/scripts"
cat >"$tmp_dir/config/niri/scripts/brightness.sh" <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == --output ]]
output="$2"
shift 2
state="$XDG_CONFIG_HOME/$output.value"
[[ -f "$state" ]] || printf '50\n' >"$state"
sleep 0.2
if [[ "$1" == --get ]]; then
    value="$(cat "$state")"
    printf '%s,%s,%s,%s,100\n' "$output" "$value" "$value" "$value"
else
    [[ "$1" == --set-percent ]]
    printf '%s\n' "$2" >"$state"
    printf '%s %s\n' "$output" "$2" >>"$XDG_CONFIG_HOME/writes.log"
fi
HELPER
chmod +x "$tmp_dir/config/niri/scripts/brightness.sh"
XDG_CONFIG_HOME="$tmp_dir/config" timeout 20s "$tmp_dir/probe"
[[ "$(wc -l <"$tmp_dir/config/writes.log")" == 4 ]]

#!/usr/bin/env bash
# Real GTK callbacks and a slow fake helper; never changes hardware brightness.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
read -r -a gtk_flags <<<"$(pkg-config --cflags --libs gtk+-3.0 gtk-layer-shell-0)"
cc -O1 -g -Wall -Wextra -Werror "$repo_root/tests/test_waybar_brightness_latency.c" \
    -o "$tmp_dir/probe" "${gtk_flags[@]}" -lm
mkdir -p "$tmp_dir/config/niri/scripts"
cat >"$tmp_dir/config/niri/scripts/brightness.sh" <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail
sleep 0.2
if [[ "$3" == --get ]]; then
    printf '%s,50,50,50,100\n' "$2"
else
    printf '%s\n' "$4" >>"$TEST_WRITES"
fi
HELPER
chmod +x "$tmp_dir/config/niri/scripts/brightness.sh"
TEST_WRITES="$tmp_dir/writes" XDG_CONFIG_HOME="$tmp_dir/config" timeout 8s "$tmp_dir/probe"
[[ "$(tail -n 1 "$tmp_dir/writes")" == 74 ]]

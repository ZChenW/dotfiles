#!/usr/bin/env bash
# Requires a live Niri/Wayland session with at least one application window.
# Creates a temporary bottom overlay and a short-lived window to verify IPC.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
library="${1:-$repo_root/configs/config/waybar/libniri_taskbar.so}"
style="${2:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar/style.css}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
read -r -a gtk_flags <<<"$(pkg-config --cflags --libs gtk+-3.0)"
cc -shared -fPIC -Wall -Wextra -Werror \
    "$repo_root/tests/test_waybar_taskbar_size.c" \
    -o "$tmp_dir/probe.so" "${gtk_flags[@]}"
python3 - "$tmp_dir/config.json" "$library" <<'PY'
import json
import pathlib
import subprocess
import sys

outputs = json.loads(subprocess.check_output(['niri', 'msg', '--json', 'outputs']))
output = next(name for name, data in outputs.items() if data.get('logical'))
config = {
    'output': output, 'layer': 'overlay', 'position': 'bottom',
    'exclusive': False, 'height': 29,
    'modules-left': ['cffi/niri-taskbar'],
    'cffi/niri-taskbar': {
        'module_path': str(pathlib.Path(sys.argv[2]).resolve(strict=True)),
        'show_all_outputs': True, 'icon-size': 18,
    },
}
pathlib.Path(sys.argv[1]).write_text(json.dumps(config))
PY
result=0
timeout 8s env LD_PRELOAD="$tmp_dir/probe.so" \
    waybar -c "$tmp_dir/config.json" -s "$style" > "$tmp_dir/run.log" 2>&1 || result=$?
if [[ "$result" -ne 0 ]]; then
    cat "$tmp_dir/run.log"
    exit "$result"
fi
grep -E 'TASKBAR_SIZE|PASS:' "$tmp_dir/run.log"
grep -q '^PASS:' "$tmp_dir/run.log"
if grep -qE 'Niri (IPC error|taskbar window stream error)' "$tmp_dir/run.log"; then
    cat "$tmp_dir/run.log"
    exit 1
fi

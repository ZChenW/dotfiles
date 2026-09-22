#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
build_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/brightness"
mkdir -p "$build_dir" "$config_dir"
exec 8>"$build_dir/build.lock"
flock 8
library="$build_dir/brightness.so"
if [[ ! -f "$library" || "$source_dir/brightness.c" -nt "$library" || "$source_dir/build.sh" -nt "$library" ]]; then
    temporary="$(mktemp "$build_dir/brightness.XXXXXX.so")"
    trap 'rm -f -- "$temporary"' EXIT
    read -r -a gtk_flags <<<"$(pkg-config --cflags --libs gtk+-3.0 gtk-layer-shell-0)"
    cc -shared -fPIC -O2 -Wall -Wextra -Werror "$source_dir/brightness.c" \
        -o "$temporary" "${gtk_flags[@]}" -lm
    mv -f -- "$temporary" "$library"
    trap - EXIT
fi
python3 - "$config_dir/brightness-module.json" "$library" <<'PY'
import json, os, pathlib, sys, tempfile
path = pathlib.Path(sys.argv[1])
content = json.dumps({'cffi/brightness': {'module_path': sys.argv[2]}}, indent=2) + '\n'
if not path.exists() or path.read_text() != content:
    fd, temporary = tempfile.mkstemp(prefix='.brightness-module-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
PY

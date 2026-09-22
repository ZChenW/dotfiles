# Per-output Waybar brightness (inside native group/ddcutil)

The bar keeps the original `group/ddcutil` drawer and powerline dividers on every
output. Laptop (`eDP-1`) uses the native `backlight` slider. External (`DP-8`)
swaps only the slider + moon-phase icon for a small CFFI widget that talks to
`brightness.sh --output DP-8`. Day / sleep / night presets stay native custom
modules with per-output commands from `brightness-edp.jsonc` /
`brightness-dp.jsonc`.

`desktop-shell` runs `cffi/build.sh` before starting Waybar. The script compiles
only after a source change, stores the library under the user cache, and writes
an absolute runtime-only path into `waybar/brightness-module.json` (included by
the DP-8 bar only). Waybar merges includes with first-write-wins semantics, so
`brightness-*.jsonc` must appear before `bar-common.jsonc` in each bar's include
list; never define `group/ddcutil` in `modules.jsonc`.

Build dependencies: `cc`, `pkg-config`, GTK 3 and gtk-layer-shell headers.
Runtime: Waybar CFFI ABI 1, GTK 3, gtk-layer-shell, the existing brightness
helper, and `timeout`.

Checks: `bash tests/test_brightness.sh`, `python3 tests/test_brightness_ddc.py`,
`bash tests/test_desktop_shell.sh`, `bash tests/test_waybar_brightness.sh`.

#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/configs/config/niri/scripts/brightness.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
backlight_root="$tmp_dir/sys/class/backlight"
drm_root="$tmp_dir/sys/class/drm"
hardware_root="$tmp_dir/sys/devices"
command_log="$tmp_dir/brightnessctl.log"
mkdir -p "$fake_bin" "$backlight_root" "$drm_root" \
    "$hardware_root/integrated/drm/card7/card7-eDP-9" \
    "$hardware_root/discrete"

ln -s "$hardware_root/integrated/drm/card7/card7-eDP-9" \
    "$drm_root/card7-eDP-9"
printf 'connected\n' >"$hardware_root/integrated/drm/card7/card7-eDP-9/status"
ln -s "$hardware_root/integrated/drm/card7" \
    "$hardware_root/integrated/drm/card7/card7-eDP-9/device"
ln -s "$hardware_root/integrated" \
    "$hardware_root/integrated/drm/card7/device"

mkdir -p "$backlight_root/panel_backlight" "$backlight_root/discrete_backlight"
ln -s "$hardware_root/integrated/drm/card7/card7-eDP-9" \
    "$backlight_root/panel_backlight/device"
ln -s "$hardware_root/discrete" \
    "$backlight_root/discrete_backlight/device"
printf '900\n' >"$backlight_root/panel_backlight/brightness"
printf '900\n' >"$backlight_root/panel_backlight/actual_brightness"
printf '1000\n' >"$backlight_root/panel_backlight/max_brightness"

cat >"$fake_bin/niri" <<'EOF'
#!/usr/bin/env bash
printf 'Output "Internal panel" (eDP-9)\n'
EOF

cat >"$fake_bin/brightnessctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$BRIGHTNESS_TEST_LOG"

device=""
value=""
while (($# > 0)); do
    case "$1" in
        --device)
            device="$2"
            shift 2
            ;;
        set)
            value="$2"
            break
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -n "$device" && "$value" =~ ^[0-9]+$ ]]; then
    device_root="$BRIGHTNESS_SYSFS_ROOT/$device"
    printf '%s\n' "$value" >"$device_root/brightness"
    if ((value <= BRIGHTNESS_TEST_SAFE_MAX)); then
        printf '%s\n' "$value" >"$device_root/actual_brightness"
    else
        printf '0\n' >"$device_root/actual_brightness"
    fi
fi
EOF
chmod +x "$fake_bin/niri" "$fake_bin/brightnessctl"

PATH="$fake_bin:/usr/bin" \
    BRIGHTNESS_SYSFS_ROOT="$backlight_root" \
    BRIGHTNESS_DRM_SYSFS_ROOT="$drm_root" \
    BRIGHTNESS_HELPER="$tmp_dir/missing-helper" \
    BRIGHTNESS_TEST_SAFE_MAX=980 \
    BRIGHTNESS_TEST_LOG="$command_log" \
    "$script" +10%

grep -Fxq -- '--device panel_backlight set +10%' "$command_log"
if grep -Fq discrete_backlight "$command_log"; then
    echo "Brightness helper selected the unrelated GPU backlight" >&2
    exit 1
fi

cat >"$fake_bin/shared-brightness" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BRIGHTNESS_SHARED_HELPER_LOG"
EOF
chmod +x "$fake_bin/shared-brightness"
shared_helper_log="$tmp_dir/shared-helper.log"
PATH="$fake_bin:/usr/bin" \
    BRIGHTNESS_SYSFS_ROOT="$backlight_root" \
    BRIGHTNESS_DRM_SYSFS_ROOT="$drm_root" \
    BRIGHTNESS_HELPER="$fake_bin/shared-brightness" \
    BRIGHTNESS_SHARED_HELPER_LOG="$shared_helper_log" \
    "$script" -10%
grep -Fxq -- '--device panel_backlight --adjust -10%' "$shared_helper_log"

mkdir -p "$backlight_root/second_panel_backlight"
ln -s "$hardware_root/integrated/drm/card7/card7-eDP-9" \
    "$backlight_root/second_panel_backlight/device"
commands_before="$(wc -l <"$command_log")"
if PATH="$fake_bin:/usr/bin" \
    BRIGHTNESS_SYSFS_ROOT="$backlight_root" \
    BRIGHTNESS_DRM_SYSFS_ROOT="$drm_root" \
    BRIGHTNESS_HELPER="$tmp_dir/missing-helper" \
    BRIGHTNESS_TEST_SAFE_MAX=980 \
    BRIGHTNESS_TEST_LOG="$command_log" \
    "$script" 10%- 2>/dev/null; then
    echo "Brightness helper accepted an ambiguous connector mapping" >&2
    exit 1
fi
commands_after="$(wc -l <"$command_log")"
if [[ "$commands_after" != "$commands_before" ]]; then
    echo "Brightness helper wrote to a device after detecting ambiguity" >&2
    exit 1
fi

# Brightness keeps the native group/ddcutil drawer. Waybar include merge is
# first-write-wins, so brightness-* overlays must be listed before bar-common.
waybar_config="$repo_root/configs/config/waybar/config.jsonc"
waybar_common="$repo_root/configs/config/waybar/bar-common.jsonc"
if grep -Eq '^[[:space:]]*"group/ddcutil"[[:space:]]*:' "$waybar_common"; then
    echo "group/ddcutil definition must not be in bar-common; it would block per-output overlays" >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*"group/ddcutil"[[:space:]]*:' "$repo_root/configs/config/waybar/modules.jsonc"; then
    echo "group/ddcutil definition must not be in modules.jsonc; Waybar cannot override it later" >&2
    exit 1
fi
grep -Fq '"output": "eDP-1"' "$waybar_config"
grep -Fq '"output": "DP-8"' "$waybar_config"
grep -Fq 'brightness-edp.jsonc' "$waybar_config"
grep -Fq 'brightness-dp.jsonc' "$waybar_config"
grep -Fq '"cffi/brightness"' "$repo_root/configs/config/waybar/brightness-dp.jsonc"
grep -Fq '"backlight/slider"' "$repo_root/configs/config/waybar/brightness-edp.jsonc"
grep -Fq -- '--output eDP-1' "$repo_root/configs/config/waybar/brightness-edp.jsonc"
grep -Fq -- '--output DP-8' "$repo_root/configs/config/waybar/brightness-dp.jsonc"
python3 - "$repo_root/configs/config/waybar/config.jsonc" <<'PY'
import json, re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
out = []
for line in text.splitlines():
    if "//" in line and "http" not in line:
        line = line[: line.find("//")]
    out.append(line)
cfg = json.loads(re.sub(r"/\*.*?\*/", "", "\n".join(out), flags=re.S))
for bar in cfg:
    inc = bar["include"]
    bright = next(
        i
        for i, name in enumerate(inc)
        if name.startswith("brightness-") and name.endswith(".jsonc") and "module" not in name
    )
    common = inc.index("bar-common.jsonc")
    assert bright < common, (bar.get("output"), inc)
print("include order ok")
PY
printf 'Waybar and QuickShell-compatible brightness tests passed\n'

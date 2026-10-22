#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
fake_repo="$test_root/configs/repo"
mkdir -p "$fake_repo"
rsync -a --exclude=/.git --exclude=/.jj --exclude=/.tmp --exclude=/.review \
    --exclude=/configs/Pictures "$REPO_ROOT/" "$fake_repo/"
mkdir -p "$fake_repo/configs/Pictures/wallpapers"
# No package managers, downloads, user services or live compositor calls.
fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
for name in sudo pacman waybar; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/$name"
    chmod +x "$fake_bin/$name"
done
export PATH="$fake_bin:$PATH"
export HOME="$test_root/residents/al ex.[1]"
export USER=alex LOGNAME=alex
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export DOTFILES_HOSTNAME="fresh-host"
mkdir -p "$HOME"

echo '==> public restore: a different home gets generic desktop defaults'
bash "$fake_repo/install.sh" --yes --restore-only --ascii --no-color >"$test_root/install.log" 2>&1 || {
    cat "$test_root/install.log"; exit 1;
}
python3 - "$REPO_ROOT" <<'PY'
from pathlib import Path
import os, sys
root = Path(sys.argv[1])
home = Path.home()
owner = (root / 'tests/fixtures/portability/owner-home').read_text().strip()
managed = [home / '.zshrc', home / '.config', home / '.local/bin']
paths = [p for base in managed for p in ([base] if base.is_file() else base.rglob('*'))]
for path in paths:
    if not path.is_file():
        continue
    data = path.read_bytes()
    # HOME itself is under the owner's worktree in this restricted test. Strip
    # that legitimate rendered value before looking for stale owner paths.
    data = data.replace(str(home).encode(), b'@TEST_HOME@')
    if b'\0' not in data:
        assert owner.encode() not in data, path
        assert b'@HOME@' not in data and b'@CONFIG_HOME@' not in data, path
assert 'render-drm-device' not in (home / '.config/niri/config.kdl').read_text()
assert 'output "' not in (home / '.config/niri/outputs.kdl').read_text()
assert 'render-drm-device' not in (home / '.config/niri/machine.kdl').read_text()
assert '"module_path": "' + str(home) + '/.config/waybar/libniri_taskbar.so"' in (
    home / '.config/waybar/modules.jsonc').read_text()
assert (home / '.config/waybar/libniri_taskbar.so').read_bytes() == (
    root / 'configs/config/waybar/libniri_taskbar.so').read_bytes()
qt = (home / '.config/qt5ct/qt5ct.conf').read_text()
assert str(home) + '/.local/share/color-schemes' in qt
PY

# shellcheck source=scripts/sync-configs.sh
source "$REPO_ROOT/scripts/sync-configs.sh"
# shellcheck source=scripts/snapshot.sh
source "$REPO_ROOT/scripts/snapshot.sh"
backup="$test_root/backups"
mkdir -p "$backup"
echo '==> CHAKEW uses shared main/modules plus hardware fragments, independent of USER'
export DOTFILES_HOSTNAME=CHAKEW
sync_configs "$fake_repo" "$backup" false desktop >/dev/null
python3 - "$REPO_ROOT" <<'PY'
from pathlib import Path
import os, sys
import re
root = Path(sys.argv[1])
fixture = root / 'tests/fixtures/portability'
owner = (fixture / 'owner-home').read_text().strip().encode()
for name in ('niri/outputs.kdl', 'waybar/config.jsonc',
             'waybar/brightness-edp.jsonc', 'waybar/brightness-dp.jsonc'):
    expected = (fixture / name).read_bytes().replace(owner, os.environ['HOME'].encode())
    assert (Path(os.environ['XDG_CONFIG_HOME']) / name).read_bytes() == expected, name
config = Path(os.environ['XDG_CONFIG_HOME'])
for name in ('niri/config.kdl', 'waybar/modules.jsonc'):
    expected = (root / 'configs/config' / name).read_text().replace(
        '@CONFIG_HOME@', str(config)).replace('@HOME@', os.environ['HOME'])
    assert (config / name).read_text() == expected, name
main = (config / 'niri/config.kdl').read_text()
assert 'include optional=true "machine.kdl"' in main
assert 'include optional=true "outputs.kdl"' in main
assert owner not in main.replace(os.environ['HOME'], '@TEST_HOME@').encode()
device = re.search(r'render-drm-device "([^"]+)"', (fixture / 'niri/config.kdl').read_text())[1]
assert device in (config / 'niri/machine.kdl').read_text()
assert 'render-drm-device' not in main
print('Shared main/modules and original CHAKEW output/brightness/GPU behavior preserved')
PY
cmp "$XDG_CONFIG_HOME/waybar/libniri_taskbar.so" \
    "$REPO_ROOT/configs/config/waybar/libniri_taskbar.so"
if command -v niri >/dev/null 2>&1; then
    niri validate -c "$XDG_CONFIG_HOME/niri/config.kdl"
fi
# Compare the effective tree, after rendering, so a repeated update is a no-op.
sync_configs "$fake_repo" "$backup" false desktop >/dev/null
[[ "$SYNC_BACKUP_COUNT" == 0 && "$SYNC_DIR_COUNT" == 0 && "$SYNC_FILE_COUNT" == 0 ]]
echo '==> CHAKEW snapshot publishes shared edits while retaining only machine fragments'
mkdir -p "$test_root/shared-before"
cp -a "$fake_repo/configs/config/." "$test_root/shared-before/"
SNAPSHOT_MAPPINGS=(
    "dir|$XDG_CONFIG_HOME/niri|configs/config/niri|required"
    "dir|$XDG_CONFIG_HOME/waybar|configs/config/waybar|required"
)
snapshot_capture_configs "$fake_repo" false >/dev/null
shared_diff="$(rsync -rnic --delete "$test_root/shared-before/" "$fake_repo/configs/config/")"
if [[ -n "$shared_diff" ]]; then
    printf 'Preserved-host snapshot changed shared content:\n%s\n' "$shared_diff" >&2
    exit 1
fi
printf '\n// owner binding edit\n' >>"$XDG_CONFIG_HOME/niri/config.kdl"
printf '\n// owner module edit\n' >>"$XDG_CONFIG_HOME/waybar/modules.jsonc"
# Simulate a legacy inline selector/output as well as normal shared edits.
printf '\ndebug { render-drm-device "/dev/dri/renderD135"; }\noutput "HDMI-A-3" { scale 1.25; }\n' >>"$XDG_CONFIG_HOME/niri/config.kdl"
snapshot_capture_configs "$fake_repo" false >/dev/null
grep -Fq '// owner binding edit' "$fake_repo/configs/config/niri/config.kdl"
grep -Fq '// owner module edit' "$fake_repo/configs/config/waybar/modules.jsonc"
grep -Fq renderD135 "$fake_repo/configs/hosts/CHAKEW/config/niri/machine.kdl"
grep -Fq HDMI-A-3 "$fake_repo/configs/hosts/CHAKEW/config/niri/machine.kdl"
if rg -n 'render-drm-device|HDMI-A-3' "$fake_repo/configs/config/niri"; then
    echo 'CHAKEW snapshot leaked hardware into shared files' >&2; exit 1
fi
[[ ! -e "$fake_repo/configs/hosts/CHAKEW/config/niri/config.kdl" ]]
[[ ! -e "$fake_repo/configs/hosts/CHAKEW/config/waybar/modules.jsonc" ]]
[[ ! -e "$fake_repo/configs/hosts/CHAKEW/config/waybar/libniri_taskbar.so" ]]
cmp "$fake_repo/configs/config/waybar/libniri_taskbar.so" \
    "$REPO_ROOT/configs/config/waybar/libniri_taskbar.so"
sync_configs "$fake_repo" "$backup" false desktop >/dev/null
if command -v niri >/dev/null 2>&1; then
    niri validate -c "$XDG_CONFIG_HOME/niri/config.kdl"
fi
export DOTFILES_HOSTNAME=chakew
sync_configs "$fake_repo" "$backup" false desktop >/dev/null
cmp "$XDG_CONFIG_HOME/niri/outputs.kdl" "$fake_repo/configs/config/niri/outputs.kdl"

echo '==> snapshot routes legacy hardware to this host and reverse-renders text'
export DOTFILES_HOSTNAME="new-machine"
printf '\ndebug { render-drm-device "/dev/dri/renderD135"; }\noutput "HDMI-A-3" { scale 1.25; }\n' >>"$XDG_CONFIG_HOME/niri/config.kdl"
printf 'output "HDMI-A-3" { mode "1920x1080@60"; }\n' >"$XDG_CONFIG_HOME/niri/outputs.kdl"
printf '{"output":"HDMI-A-3","include":["brightness-edp.jsonc","bar-common.jsonc"]}\n' >"$XDG_CONFIG_HOME/waybar/config.jsonc"
printf '{"backlight":{"device":"intel_backlight"}}\n' >"$XDG_CONFIG_HOME/waybar/brightness-edp.jsonc"
printf '{"module_path":"%s/cache/brightness.so"}\n' "$HOME" >"$XDG_CONFIG_HOME/waybar/brightness-module.json"
SNAPSHOT_MAPPINGS=(
    "dir|$XDG_CONFIG_HOME/niri|configs/config/niri|required"
    "dir|$XDG_CONFIG_HOME/waybar|configs/config/waybar|required"
    "dir|$XDG_CONFIG_HOME/qt5ct|configs/config/qt5ct|required"
)
snapshot_capture_configs "$fake_repo" false >/dev/null
host="$fake_repo/configs/hosts/$DOTFILES_HOSTNAME"
grep -Fq renderD135 "$host/config/niri/machine.kdl"
grep -Fq HDMI-A-3 "$host/config/niri/outputs.kdl"
grep -Fq intel_backlight "$host/config/waybar/brightness-edp.jsonc"
grep -Fq '@HOME@/' "$fake_repo/configs/config/qt5ct/qt5ct.conf"
if rg -n 'renderD135|HDMI-A-3|intel_backlight' "$fake_repo/configs/config"; then
    echo 'Snapshot leaked hardware into shared defaults' >&2; exit 1
fi
[[ ! -e "$fake_repo/configs/config/waybar/brightness-module.json" ]]
snapshot_path_is_managed "$fake_repo" "configs/hosts/new-machine/config/niri/outputs.kdl"
if snapshot_path_is_managed "$fake_repo" "configs/hosts/another/config/niri/outputs.kdl"; then
    echo 'Snapshot accepted changes belonging to another host' >&2; exit 1
fi

echo '==> the captured machine restores, and the next new host stays generic'
sync_configs "$fake_repo" "$backup" false desktop >/dev/null
grep -Fq renderD135 "$XDG_CONFIG_HOME/niri/machine.kdl"
export DOTFILES_HOSTNAME="another"
sync_configs "$fake_repo" "$backup" false desktop >/dev/null
if rg -n 'render-drm-device|HDMI-A-3|intel_backlight' "$XDG_CONFIG_HOME/niri" "$XDG_CONFIG_HOME/waybar"; then
    echo 'Another host received machine-specific settings' >&2; exit 1
fi
if command -v niri >/dev/null 2>&1; then
    niri validate -c "$XDG_CONFIG_HOME/niri/config.kdl"
fi
echo '==> custom XDG config root is used for restore, verification and snapshot'
export XDG_CONFIG_HOME="$HOME/settings"
sync_configs "$fake_repo" "$backup" false desktop >/dev/null
[[ -f "$XDG_CONFIG_HOME/niri/config.kdl" ]]
build_snapshot_mappings
[[ "${SNAPSHOT_MAPPINGS[0]}" == "dir|$XDG_CONFIG_HOME/niri|configs/config/niri|required" ]]

echo 'All portability integration tests passed.'

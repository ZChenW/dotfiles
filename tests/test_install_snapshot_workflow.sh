#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

fake_home="$tmp_dir/home"
fake_repo="$tmp_dir/repo"
fake_bin="$tmp_dir/bin"
mkdir -p "$fake_home/.config" "$fake_home/.local/bin" "$fake_bin"
cp -a "$REPO_ROOT" "$fake_repo"

mkdir -p \
    "$fake_home/.config/niri" \
    "$fake_home/.config/waybar" \
    "$fake_home/.config/kitty" \
    "$fake_home/.config/fastfetch" \
    "$fake_home/.config/waypaper" \
    "$fake_home/.config/fcitx5" \
    "$fake_home/.config/mako" \
    "$fake_home/.config/environment.d" \
    "$fake_home/.config/qt5ct" \
    "$fake_home/.config/qt6ct" \
    "$fake_home/.config/cava" \
    "$fake_home/.config/Thunar" \
    "$fake_home/.config/git" \
    "$fake_home/.config/Code/User/snippets" \
    "$fake_home/.config/Cursor/User/snippets"

printf 'test\n' >"$fake_home/.config/niri/config.kdl"
printf 'test\n' >"$fake_home/.config/waybar/config"
printf 'test\n' >"$fake_home/.config/kitty/kitty.conf"
printf 'test\n' >"$fake_home/.config/fastfetch/config.jsonc"
printf 'test\n' >"$fake_home/.config/waypaper/config.ini"
printf 'test\n' >"$fake_home/.config/fcitx5/profile"
printf 'test\n' >"$fake_home/.config/mako/config"
printf 'test\n' >"$fake_home/.config/environment.d/env.conf"
printf 'test\n' >"$fake_home/.config/qt5ct/qt5ct.conf"
printf 'test\n' >"$fake_home/.config/qt6ct/qt6ct.conf"
printf 'test\n' >"$fake_home/.config/cava/config"
printf 'test\n' >"$fake_home/.config/Thunar/uca.xml"
printf 'test\n' >"$fake_home/.zshrc"
printf 'test\n' >"$fake_home/.config/git/ignore"
printf 'test\n' >"$fake_home/.config/mimeapps.list"
printf 'test\n' >"$fake_home/.config/user-dirs.dirs"
printf '{}\n' >"$fake_home/.config/Code/User/settings.json"
printf '[]\n' >"$fake_home/.config/Code/User/keybindings.json"
printf '{}\n' >"$fake_home/.config/Cursor/User/settings.json"
printf '[]\n' >"$fake_home/.config/Cursor/User/keybindings.json"
printf '#!/usr/bin/env bash\n' >"$fake_home/.local/bin/inir"
printf '#!/usr/bin/env bash\n' >"$fake_home/.local/bin/toggle-niri-shell"

cat >"$fake_bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -Qqen)
        printf '%s\n' git zsh kitty niri waybar fastfetch
        ;;
    -Qqem)
        ;;
    -Si)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$fake_bin/pacman"

output="$(HOME="$fake_home" PATH="$fake_bin:$PATH" "$fake_repo/install.sh" --snapshot 2>&1)"

assert_count() {
    local needle="$1"
    local expected="$2"
    local actual
    actual="$(grep -F -c -- "$needle" <<<"$output" || true)"
    if [[ "$actual" != "$expected" ]]; then
        echo "Expected '$needle' count $expected, got $actual" >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi
}

assert_contains() {
    local needle="$1"
    if [[ "$output" != *"$needle"* ]]; then
        echo "Expected output to contain: $needle" >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi
}

assert_count "Dotfiles Installer" 1
assert_count "  Log" 1
assert_count "Result" 1
assert_contains "snapshot + dry-run"
assert_contains "1/5 Snapshot"
assert_contains "2/5 Package manifests"
assert_contains "3/5 Package plan"
assert_contains "4/5 Config plan"
assert_contains "5/5 Verification"
assert_contains "Text files normalized"
assert_contains "Safety check passed"
assert_contains "Pacman packages"
assert_contains "Existing paths to back up"
assert_contains "zsh syntax"
assert_contains "No changes were made"

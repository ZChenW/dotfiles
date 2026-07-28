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
mkdir -p \
    "$fake_home/.config" \
    "$fake_home/.local/bin" \
    "$fake_home/.local/share/zsh/site-functions" \
    "$fake_home/Pictures/wallpapers" \
    "$fake_bin"
cp -a "$REPO_ROOT" "$fake_repo"
rm -rf "$fake_repo/.git"
/usr/bin/git -C "$fake_repo" init -q
/usr/bin/git -C "$fake_repo" config user.email "test@example.com"
/usr/bin/git -C "$fake_repo" config user.name "Test User"
/usr/bin/git -C "$fake_repo" add -A
/usr/bin/git -C "$fake_repo" commit -qm "test baseline"

mkdir -p \
    "$fake_home/.config/niri" \
    "$fake_home/.config/waybar" \
    "$fake_home/.config/kitty" \
    "$fake_home/.config/fastfetch" \
    "$fake_home/.config/waypaper" \
    "$fake_home/.config/matugen" \
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
printf 'test\n' >"$fake_home/.config/matugen/config.toml"
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
printf '#!/usr/bin/env bash\n' >"$fake_home/.local/bin/toggle-wlsunset"
printf '#!/usr/bin/env bash\n' >"$fake_home/.local/bin/wcr-post-apply-waybar.sh"
printf '#!/usr/bin/env bash\n' >"$fake_home/.local/bin/desktop-shell"
printf '#compdef desktop-shell\n' >"$fake_home/.local/share/zsh/site-functions/_desktop-shell"
printf 'wallpaper\n' >"$fake_home/Pictures/wallpapers/test-wallpaper.txt"

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

cat >"$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" pull --ff-only "* ]]; then
    exit 0
fi
exec /usr/bin/git "$@"
EOF
chmod +x "$fake_bin/git"

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
assert_contains "snapshot"
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
assert_contains "Home directory unchanged"
assert_contains "Repo files may have been updated"
assert_contains "Preflight"

echo "==> no-op snapshot skips commit and push"
/usr/bin/git -C "$fake_repo" config user.email "test@example.com"
/usr/bin/git -C "$fake_repo" config user.name "Test User"
/usr/bin/git -C "$fake_repo" add -A
/usr/bin/git -C "$fake_repo" commit -q -m "snapshot baseline"

echo "==> Lightweight snapshot updates only arch-lightweight.txt"
mkdir -p "$fake_home/.local/state/dotfiles"
printf 'lightweight\n' >"$fake_home/.local/state/dotfiles/install-profile"
standard_hash_before="$(
    /usr/bin/git -C "$fake_repo" hash-object \
        packages/arch-essential.txt \
        packages/arch-desktop.txt \
        packages/arch-apps.txt \
        packages/arch-aur.txt \
        packages/arch-machine-local.txt \
        packages/arch-exclude.txt
)"
lightweight_output="$(
    HOME="$fake_home" PATH="$fake_bin:$PATH" \
        "$fake_repo/install.sh" --snapshot --no-commit 2>&1
)"
standard_hash_after="$(
    /usr/bin/git -C "$fake_repo" hash-object \
        packages/arch-essential.txt \
        packages/arch-desktop.txt \
        packages/arch-apps.txt \
        packages/arch-aur.txt \
        packages/arch-machine-local.txt \
        packages/arch-exclude.txt
)"
if [[ "$standard_hash_before" != "$standard_hash_after" ]]; then
    echo "Lightweight public Snapshot changed Standard manifests" >&2
    exit 1
fi
if [[ "$lightweight_output" != *"Lightweight export complete"* ]]; then
    echo "Expected public Snapshot to use saved Lightweight profile" >&2
    printf '%s\n' "$lightweight_output" >&2
    exit 1
fi
/usr/bin/git -C "$fake_repo" add -A
/usr/bin/git -C "$fake_repo" commit -q -m "lightweight snapshot baseline"

push_log="$tmp_dir/push.log"
cat >"$fake_bin/git" <<EOF
#!/usr/bin/env bash
if [[ " \$* " == *" pull --ff-only "* ]]; then
    exit 0
fi
if [[ " \$* " == *" push "* ]]; then
    printf 'push %s\n' "\$*" >>"$push_log"
    exit 99
fi
exec /usr/bin/git "\$@"
EOF
chmod +x "$fake_bin/git"

set +e
noop_output="$(
    HOME="$fake_home" PATH="$fake_bin:$PATH" \
        "$fake_repo/install.sh" --snapshot --push --yes 2>&1
)"
noop_rc=$?
set -e

if ((noop_rc != 0)); then
    echo "No-op snapshot unexpectedly failed" >&2
    printf '%s\n' "$noop_output" >&2
    exit 1
fi
if [[ -s "$push_log" ]]; then
    echo "No-op snapshot unexpectedly attempted to push" >&2
    cat "$push_log" >&2
    exit 1
fi
if [[ "$noop_output" != *"No changes detected"* ]]; then
    echo "No-op snapshot did not report that the repository is current" >&2
    printf '%s\n' "$noop_output" >&2
    exit 1
fi

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
mkdir -p "$fake_home" "$fake_bin"
cp -a "$REPO_ROOT" "$fake_repo"

# Stub only optional tools; core host tools stay from the real PATH.
for cmd in zsh niri waybar quickshell qs kitty fastfetch paru yay; do
    cat >"$fake_bin/$cmd" <<EOF
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$fake_bin/$cmd"
done

mkdir -p \
    "$fake_home/.local/state/dotfiles" \
    "$fake_home/.local/share/quickshell/clavis" \
    "$fake_home/.local/lib/qt6/qml/Clavis" \
    "$fake_home/.local/lib/qt6/qml/M3Shapes" \
    "$fake_home/.local/bin"
printf 'quickshell\n' >"$fake_home/.local/state/dotfiles/desktop-shell-profile"
printf 'qml\n' >"$fake_home/.local/share/quickshell/clavis/shell.qml"
printf '#!/usr/bin/env bash\n' >"$fake_home/.local/bin/key"
chmod +x "$fake_home/.local/bin/key"
git -C "$fake_home/.local/share/quickshell/clavis" init -q
git -C "$fake_home/.local/share/quickshell/clavis" \
    remote add origin https://github.com/ZChenW/quickshell.git
git -C "$fake_home/.local/share/quickshell/clavis" add shell.qml
git -C "$fake_home/.local/share/quickshell/clavis" \
    -c user.name=Test -c user.email=test@example.invalid \
    commit -qm initial
quickshell_head="$(git -C "$fake_home/.local/share/quickshell/clavis" rev-parse HEAD)"
printf '%s\n' "$fake_home/.local/share/quickshell/clavis" \
    >"$fake_home/.local/state/dotfiles/quickshell-managed-root"
printf '%s\n' "$quickshell_head" \
    >"$fake_home/.local/state/dotfiles/quickshell-install-ref"

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "Expected output to contain: $needle" >&2
        printf '%s\n' "$haystack" >&2
        exit 1
    fi
}

# --- preflight ---
# shellcheck source=scripts/ui.sh
source "$REPO_ROOT/scripts/ui.sh"
ui_init
# shellcheck source=scripts/preflight.sh
source "$REPO_ROOT/scripts/preflight.sh"

if ! run_preflight install >/dev/null; then
    echo "Expected preflight install to succeed on this host" >&2
    exit 1
fi

missing_output="$(preflight_missing_cmds definitely-not-a-real-cmd-xyz 2>/dev/null || true)"
if [[ "$missing_output" != *definitely-not-a-real-cmd-xyz* ]]; then
    echo "Expected preflight_missing_cmds to report the missing command" >&2
    exit 1
fi

# --- doctor ---
doctor_output="$(
    HOME="$fake_home" PATH="$fake_bin:$PATH" \
        "$fake_repo/install.sh" --doctor --ascii --no-color 2>&1 || true
)"
assert_contains "$doctor_output" "Doctor"
assert_contains "$doctor_output" "Preflight"
assert_contains "$doctor_output" "Tool"
assert_contains "$doctor_output" "Desktop tool"
assert_contains "$doctor_output" "quickshell"
if [[ "$doctor_output" == *"Desktop tool"*"waybar"* ]]; then
    echo "QuickShell-only doctor still checks Waybar" >&2
    printf '%s\n' "$doctor_output" >&2
    exit 1
fi

# --- uninstall dry-run (safe) ---
mkdir -p "$fake_home/.config/niri" "$fake_home/.local/bin"
printf 'niri\n' >"$fake_home/.config/niri/config.kdl"
printf '#!/usr/bin/env bash\n' >"$fake_home/.local/bin/toggle-wlsunset"
printf 'private\n' >"$fake_home/.zshrc.local"

uninstall_output="$(
    HOME="$fake_home" DOTFILES_BACKUP_BASE="$tmp_dir/backups" \
        "$fake_repo/install.sh" --uninstall safe --dry-run --ascii --no-color --verbose 2>&1
)"
assert_contains "$uninstall_output" "Safe uninstall"
assert_contains "$uninstall_output" "Dry-run uninstall planned"
assert_contains "$uninstall_output" "zshrc.local"

# Managed path must still exist after dry-run.
if [[ ! -f "$fake_home/.config/niri/config.kdl" ]]; then
    echo "Dry-run uninstall must not remove managed paths" >&2
    exit 1
fi
if [[ ! -f "$fake_home/.zshrc.local" ]]; then
    echo "\$HOME/.zshrc.local must be preserved" >&2
    exit 1
fi
if [[ ! -d "$fake_home/.local/share/quickshell/clavis/.git" ]]; then
    echo "Dry-run uninstall must not remove the managed QuickShell checkout" >&2
    exit 1
fi

# --- uninstall safe (real, isolated HOME) ---
uninstall_real="$(
    HOME="$fake_home" DOTFILES_BACKUP_BASE="$tmp_dir/backups" \
        "$fake_repo/install.sh" --uninstall safe --yes --ascii --no-color 2>&1
)"
assert_contains "$uninstall_real" "Safe uninstall complete"

if [[ -e "$fake_home/.config/niri" ]]; then
    echo "Expected managed niri config to be removed" >&2
    exit 1
fi
if [[ ! -f "$fake_home/.zshrc.local" ]]; then
    echo "Expected ~/.zshrc.local to survive uninstall" >&2
    exit 1
fi
if [[ -e "$fake_home/.local/share/quickshell/clavis" \
    || -e "$fake_home/.local/state/dotfiles/desktop-shell-profile" ]]; then
    echo "Expected managed QuickShell source and profile state to be removed" >&2
    exit 1
fi

archive="$(find "$tmp_dir/backups" -name 'uninstall-archive-*.tar.gz' | head -n 1 || true)"
if [[ -z "$archive" ]]; then
    echo "Expected uninstall archive under backup base" >&2
    exit 1
fi

echo "preflight/doctor/uninstall tests passed"

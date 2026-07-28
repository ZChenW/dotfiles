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
fake_bin="$tmp_dir/bin"
fake_pacman_db="$tmp_dir/pacman-local"
mkdir -p "$fake_home" "$fake_bin" "$fake_pacman_db"

cat >"$fake_bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -Slq)
        sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' \
            "$DOTFILES_TEST_REPO/packages/arch-lightweight.txt" |
            grep -Ev '^(rime-ice-pinyin-git|visual-studio-code-bin|waypaper-git)$'
        ;;
    -Qq)
        printf '%s\n' git firefox
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$fake_bin/pacman"
cat >"$fake_bin/sudo" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fake_bin/sudo"

echo "==> lightweight profile is selectable through the public installer"
output="$(
    HOME="$fake_home" \
    DOTFILES_TEST_REPO="$REPO_ROOT" \
    PATH="$fake_bin:$PATH" \
        "$REPO_ROOT/install.sh" \
        --install-profile lightweight --yes --dry-run --no-aur \
        --ascii --no-color 2>&1
)"

if [[ "$output" != *"Installation profile"*"Lightweight"* ]]; then
    echo "Expected dry-run plan to identify the Lightweight installation profile" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi
if ! grep -Fq 'folder = ~/Pictures/wallpapers' \
    "$REPO_ROOT/configs/config/waypaper/config.ini"; then
    echo "Expected the installed Waypaper config to use the managed wallpaper directory" >&2
    exit 1
fi

profile_state="$fake_home/.local/state/dotfiles/install-profile"
if [[ -e "$profile_state" ]]; then
    echo "Dry-run must not save installation profile state" >&2
    exit 1
fi

echo "==> lightweight package scope keeps daily tools and excludes heavy apps"
package_output="$(
    HOME="$fake_home" \
    DOTFILES_TEST_REPO="$REPO_ROOT" \
    DOTFILES_PACMAN_DB_ROOT="$fake_pacman_db" \
    PATH="$fake_bin:$PATH" \
        "$REPO_ROOT/install.sh" \
        --install-profile lightweight --packages-only --yes --dry-run \
        --debug --ascii --no-color 2>&1
)"

for required in firefox kitty neovim vim openai-codex visual-studio-code-bin; do
    if [[ "$package_output" != *"$required"* ]]; then
        echo "Expected Lightweight package plan to include: $required" >&2
        printf '%s\n' "$package_output" >&2
        exit 1
    fi
done

echo "==> successful real install persists the profile and later runs reuse it"
HOME="$fake_home" \
DOTFILES_TEST_REPO="$REPO_ROOT" \
DOTFILES_PACMAN_DB_ROOT="$fake_pacman_db" \
PATH="$fake_bin:$PATH" \
    "$REPO_ROOT/install.sh" \
    --install-profile lightweight --packages-only --yes --no-aur \
    --ascii --no-color >/dev/null

if [[ "$(<"$profile_state")" != lightweight ]]; then
    echo "Expected successful install to save the Lightweight profile" >&2
    exit 1
fi

saved_output="$(
    HOME="$fake_home" \
    DOTFILES_TEST_REPO="$REPO_ROOT" \
    DOTFILES_PACMAN_DB_ROOT="$fake_pacman_db" \
    PATH="$fake_bin:$PATH" \
        "$REPO_ROOT/install.sh" --packages-only --yes --dry-run --no-aur \
        --ascii --no-color 2>&1
)"
if [[ "$saved_output" != *"Installation profile"*"Lightweight"* ]]; then
    echo "Expected unattended install to reuse the saved profile" >&2
    printf '%s\n' "$saved_output" >&2
    exit 1
fi

if command -v script >/dev/null 2>&1; then
    echo "==> interactive install is profile-first and offers Automatic"
    interactive_home="$tmp_dir/interactive-home"
    mkdir -p "$interactive_home"
    pty_command="HOME=\"$interactive_home\" DOTFILES_TEST_REPO=\"$REPO_ROOT\" DOTFILES_PACMAN_DB_ROOT=\"$fake_pacman_db\" PATH=\"$fake_bin:$PATH\" TERM=xterm DOTFILES_COLOR=never \"$REPO_ROOT/install.sh\" --menu --dry-run --no-aur --ascii --no-color"
    interactive_output="$(
        printf '1\n2\n1\n1\n' |
            script -qec "$pty_command" /dev/null
    )"
    if [[ "$interactive_output" != *"Installation profile"* \
        || "$interactive_output" != *"Lightweight"* \
        || "$interactive_output" != *"Automatic"* \
        || "$interactive_output" != *"Preview complete"* ]]; then
        echo "Expected profile-first Automatic interactive workflow" >&2
        printf '%q\n' "$interactive_output" >&2
        exit 1
    fi
    if [[ -e "$interactive_home/.local/state/dotfiles/install-profile" ]]; then
        echo "Interactive dry-run must not persist profile state" >&2
        exit 1
    fi
else
    echo "script(1) unavailable; interactive profile check skipped"
fi

for excluded in quickshell steam libreoffice-still chromium cursor-bin; do
    if [[ "$package_output" == *"$excluded"* ]]; then
        echo "Expected Lightweight package plan to exclude: $excluded" >&2
        printf '%s\n' "$package_output" >&2
        exit 1
    fi
done

if [[ "$package_output" != *"No packages will be removed"* ]]; then
    echo "Expected package plan to state the no-removal guarantee" >&2
    printf '%s\n' "$package_output" >&2
    exit 1
fi

echo "==> disabling AUR explains degraded Lightweight capabilities"
no_aur_output="$(
    HOME="$fake_home" \
    DOTFILES_TEST_REPO="$REPO_ROOT" \
    DOTFILES_PACMAN_DB_ROOT="$fake_pacman_db" \
    PATH="$fake_bin:$PATH" \
        "$REPO_ROOT/install.sh" \
        --install-profile lightweight --packages-only --yes --dry-run \
        --no-aur --ascii --no-color 2>&1
)"
if [[ "$no_aur_output" != *"Unavailable without AUR"* \
    || "$no_aur_output" != *"visual-studio-code-bin"* ]]; then
    echo "Expected --no-aur to list degraded Lightweight capabilities" >&2
    printf '%s\n' "$no_aur_output" >&2
    exit 1
fi

echo "==> Lightweight rejects incompatible package and desktop-shell choices"
invalid_combinations=(
    "--install-profile lightweight --full-packages"
    "--install-profile lightweight --desktop-shell quickshell"
    "--install-profile lightweight --desktop-shell dual"
)
for flags in "${invalid_combinations[@]}"; do
    # shellcheck disable=SC2086
    if HOME="$fake_home" PATH="$fake_bin:$PATH" \
        "$REPO_ROOT/install.sh" $flags --yes --dry-run >/dev/null 2>&1; then
        echo "Expected invalid Lightweight combination to fail: $flags" >&2
        exit 1
    fi
done

echo "==> Standard remains the default portable package scope"
standard_home="$tmp_dir/standard-home"
mkdir -p "$standard_home"
standard_output="$(
    HOME="$standard_home" \
    DOTFILES_TEST_REPO="$REPO_ROOT" \
    DOTFILES_PACMAN_DB_ROOT="$fake_pacman_db" \
    PATH="$fake_bin:$PATH" \
        "$REPO_ROOT/install.sh" --packages-only --yes --dry-run --debug \
        --ascii --no-color 2>&1
)"
if [[ "$standard_output" != *"Installation profile"*"Standard"* \
    || "$standard_output" != *"steam"* \
    || "$standard_output" != *"libreoffice-still"* ]]; then
    echo "Expected default Standard profile to preserve portable packages" >&2
    printf '%s\n' "$standard_output" >&2
    exit 1
fi

echo "Installation profile tests passed."

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

echo "==> test 1: unchanged config mappings skip backup and copy"
fake_home="$tmp_dir/home"
fake_repo="$tmp_dir/repo"
backup_root="$tmp_dir/backup"
mkdir -p "$fake_home/.config/example" "$fake_repo/configs/example" "$backup_root"
printf 'same\n' >"$fake_home/.config/example/config"
cp -a "$fake_home/.config/example/config" "$fake_repo/configs/example/config"

export HOME="$fake_home"
# shellcheck source=scripts/ui.sh
source "$REPO_ROOT/scripts/ui.sh"
# shellcheck source=scripts/backup.sh
source "$REPO_ROOT/scripts/backup.sh"
# shellcheck source=scripts/sync-configs.sh
source "$REPO_ROOT/scripts/sync-configs.sh"

backup_log="$tmp_dir/backup.log"
backup_path() {
    printf '%s\n' "$1" >>"$backup_log"
}
remove_symlink_dest() {
    :
}
record_manifest_entry() {
    :
}

SYNC_SKIPPED_COUNT=0
sync_mapping_entry \
    "$backup_root" false "$backup_root/.restore-manifest" \
    "apps|$fake_repo/configs/example|$fake_home/.config/example|dir|required"

if [[ -s "$backup_log" ]]; then
    echo "Unchanged directory was backed up instead of skipped" >&2
    cat "$backup_log" >&2
    exit 1
fi
if [[ "${SYNC_SKIPPED_COUNT:-0}" != 1 ]]; then
    echo "Expected unchanged mapping to increment the skip counter" >&2
    exit 1
fi

mkdir -p "$fake_home/.config/waybar" "$fake_repo/configs/config/waybar"
printf 'style\n' >"$fake_home/.config/waybar/style.css"
printf 'style\n' >"$fake_repo/configs/config/waybar/style.css"
printf 'generated\n' >"$fake_home/.config/waybar/colors.css"
printf 'seed\n' >"$fake_repo/configs/config/waybar/colors.css"
: >"$backup_log"
sync_mapping_entry \
    "$backup_root" false "$backup_root/.restore-manifest" \
    "desktop|$fake_repo/configs/config/waybar|$fake_home/.config/waybar|dir|required"
if [[ -s "$backup_log" ]]; then
    echo "Generated Waybar colors caused an otherwise unchanged config to be backed up" >&2
    cat "$backup_log" >&2
    exit 1
fi
if [[ "$(cat "$fake_home/.config/waybar/colors.css")" != generated ]]; then
    echo "Config sync overwrote runtime-generated Waybar colors" >&2
    exit 1
fi

printf 'private\n' >"$fake_home/.zshrc.local"
mkdir -p "$fake_repo/templates"
printf 'template\n' >"$fake_repo/templates/zshrc.local.example"
: >"$backup_log"
sync_zshrc_local "$fake_repo" "$backup_root" false "$backup_root/.restore-manifest"
if [[ -s "$backup_log" ]]; then
    echo "Preserved private config was backed up even though it is never changed" >&2
    cat "$backup_log" >&2
    exit 1
fi

echo "==> test 2: install exposes a top-level operation menu"
menu_output="$(
    printf '7\n' |
        HOME="$fake_home" "$REPO_ROOT/install.sh" --menu --ascii --no-color 2>&1
)"
if [[ "$menu_output" != *"Choose an operation"* || "$menu_output" != *"Exit"* ]]; then
    echo "Expected top-level installer operation menu" >&2
    printf '%s\n' "$menu_output" >&2
    exit 1
fi

echo "==> test 2b: installer exposes desktop shell profiles"
if HOME="$fake_home" "$REPO_ROOT/install.sh" \
    --yes --skip-packages --dry-run --desktop-shell invalid \
    >"$tmp_dir/invalid-profile.out" 2>&1; then
    echo "Invalid desktop shell profile unexpectedly succeeded" >&2
    exit 1
fi
grep -Fq "waybar, quickshell, or dual" "$tmp_dir/invalid-profile.out"

dual_plan="$(
    HOME="$fake_home" \
        "$REPO_ROOT/install.sh" \
        --yes --skip-packages --dry-run --desktop-shell dual \
        2>&1
)"
if [[ "$dual_plan" != *"Desktop shell"*"dual"* ]]; then
    echo "Dual desktop shell profile is missing from the installation plan" >&2
    printf '%s\n' "$dual_plan" >&2
    exit 1
fi
if [[ "$dual_plan" != *"waybar available"* || "$dual_plan" != *"QuickShell source checkout"* ]]; then
    echo "Dual profile verification does not cover both desktop shells" >&2
    printf '%s\n' "$dual_plan" >&2
    exit 1
fi
if [[ "$dual_plan" != *"QuickShell source: https://github.com/ZChenW/quickshell.git"* \
    || "$dual_plan" != *"QuickShell destination: $fake_home/.local/share/quickshell/clavis"* ]]; then
    echo "Dual profile does not plan the pinned QuickShell source" >&2
    printf '%s\n' "$dual_plan" >&2
    exit 1
fi

waybar_plan="$(
    HOME="$fake_home" \
        "$REPO_ROOT/install.sh" \
        --yes --skip-packages --dry-run --desktop-shell waybar \
        2>&1
)"
if [[ "$waybar_plan" != *"QuickShell"* || "$waybar_plan" != *"skipped (Waybar profile)"* ]]; then
    echo "Waybar profile does not skip QuickShell source installation" >&2
    printf '%s\n' "$waybar_plan" >&2
    exit 1
fi
if [[ "$waybar_plan" != *"waybar available"* || "$waybar_plan" == *"QuickShell source checkout"* ]]; then
    echo "Waybar profile verification is not profile-aware" >&2
    printf '%s\n' "$waybar_plan" >&2
    exit 1
fi

mkdir -p "$fake_home/.local/state/dotfiles"
printf 'dual\n' >"$fake_home/.local/state/dotfiles/desktop-shell-profile"
saved_plan="$(
    HOME="$fake_home" \
        "$REPO_ROOT/install.sh" \
        --yes --skip-packages --dry-run \
        2>&1
)"
if [[ "$saved_plan" != *"Desktop shell"*"dual"* ]]; then
    echo "Installer did not reuse the saved desktop shell profile" >&2
    printf '%s\n' "$saved_plan" >&2
    exit 1
fi

# shellcheck source=scripts/desktop-shell-profile.sh
source "$REPO_ROOT/scripts/desktop-shell-profile.sh"
DESKTOP_SHELL_PROFILE=""
prompt_desktop_shell_profile <<<"2" >"$tmp_dir/profile-menu.out"
if [[ "$DESKTOP_SHELL_PROFILE" != quickshell ]]; then
    echo "Interactive desktop shell menu did not select QuickShell" >&2
    cat "$tmp_dir/profile-menu.out" >&2
    exit 1
fi
grep -Fq "Waybar + QuickShell" "$tmp_dir/profile-menu.out"

DESKTOP_SHELL_PROFILE=quickshell
build_sync_mappings "$REPO_ROOT"
if printf '%s\n' "${SYNC_MAPPINGS[@]}" \
    | grep -F -e '/waybar|' -e 'wcr-post-apply-waybar' >/dev/null; then
    echo "QuickShell-only profile still manages Waybar configuration" >&2
    exit 1
fi
DESKTOP_SHELL_PROFILE=dual

echo "==> test 3: Wallpaper Console hook is configured during sync"
fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin" "$fake_home/.local/bin" "$fake_home/.config/matugen"
printf 'config\n' >"$fake_home/.config/matugen/config.toml"
wcr_log="$tmp_dir/wcr.log"
cat >"$fake_home/.local/bin/wallpaper-console-rust" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$wcr_log"
EOF
chmod +x "$fake_home/.local/bin/wallpaper-console-rust"
printf '#!/usr/bin/env bash\n' >"$fake_home/.local/bin/wcr-post-apply-waybar.sh"
chmod +x "$fake_home/.local/bin/wcr-post-apply-waybar.sh"

configure_wallpaper_console_theme_hook false
if ! grep -Fxq "config-set post_apply_enabled on" "$wcr_log"; then
    echo "Wallpaper Console hook was not enabled" >&2
    cat "$wcr_log" >&2
    exit 1
fi
if ! grep -Fxq "config-set post_apply_command $fake_home/.local/bin/wcr-post-apply-waybar.sh" "$wcr_log"; then
    echo "Wallpaper Console hook command was not synchronized with an absolute path" >&2
    cat "$wcr_log" >&2
    exit 1
fi

quickshell_hook_plan="$(
    HOME="$fake_home" \
        "$REPO_ROOT/install.sh" \
        --yes --skip-packages --dry-run --desktop-shell quickshell \
        2>&1
)"
if [[ "$quickshell_hook_plan" != *"Wallpaper Console ownership"* \
    || "$quickshell_hook_plan" != *"disable planned"* ]]; then
    echo "QuickShell-only profile does not disable stale Waybar wallpaper ownership" >&2
    printf '%s\n' "$quickshell_hook_plan" >&2
    exit 1
fi
if [[ "$quickshell_hook_plan" != *"QuickShell source checkout"* \
    || "$quickshell_hook_plan" != *"QuickShell QML modules"* \
    || "$quickshell_hook_plan" == *"waybar available"* ]]; then
    echo "QuickShell profile verification is not profile-aware" >&2
    printf '%s\n' "$quickshell_hook_plan" >&2
    exit 1
fi

cat >"$fake_home/.local/bin/wallpaper-console-rust" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$wcr_log"
case "\${1:-}:\${2:-}" in
    config-get:post_apply_enabled) printf 'on\n' ;;
    config-get:post_apply_command) printf '%s\n' "$fake_home/.local/bin/wcr-post-apply-waybar.sh" ;;
    config-get:restore_on_login) printf 'on\n' ;;
esac
EOF
chmod +x "$fake_home/.local/bin/wallpaper-console-rust"
: >"$wcr_log"
configure_wallpaper_console_theme_hook false
if grep -q '^config-set ' "$wcr_log"; then
    echo "Already-current Wallpaper Console settings were rewritten" >&2
    cat "$wcr_log" >&2
    exit 1
fi

: >"$wcr_log"
disable_wallpaper_console_theme_hook false
grep -Fxq "config-set post_apply_enabled off" "$wcr_log"
grep -Fq "config-set post_apply_command" "$wcr_log"
grep -Fxq "config-set restore_on_login off" "$wcr_log"

echo "==> test 4: hook honors XDG config paths"
xdg_config="$tmp_dir/xdg-config"
mkdir -p "$xdg_config/matugen/templates" "$xdg_config/waybar" "$fake_bin"
printf 'config\n' >"$xdg_config/matugen/config.toml"
printf 'template\n' >"$xdg_config/matugen/templates/waybar-colors.css"
printf 'wallpaper\n' >"$tmp_dir/wall.png"
matugen_log="$tmp_dir/matugen.log"
cat >"$fake_bin/matugen" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$matugen_log"
printf 'generated\n' >"$xdg_config/waybar/colors.css"
EOF
cat >"$fake_bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$fake_bin/matugen" "$fake_bin/pgrep"

HOME="$fake_home" XDG_CONFIG_HOME="$xdg_config" PATH="$fake_bin:/usr/bin" \
    WCR_STILL="$tmp_dir/wall.png" \
    "$REPO_ROOT/configs/local-bin/wcr-post-apply-waybar.sh"
if ! grep -Fq -- "--config $xdg_config/matugen/config.toml" "$matugen_log"; then
    echo "Hook did not pass the synchronized matugen config explicitly" >&2
    cat "$matugen_log" >&2
    exit 1
fi
if [[ ! -s "$xdg_config/waybar/colors.css" ]]; then
    echo "Hook did not generate Waybar colors" >&2
    exit 1
fi

echo "==> test 4b: restarted Waybar does not inherit the theme lock"
touch "$tmp_dir/waybar-running"
cat >"$fake_bin/pgrep" <<EOF
#!/usr/bin/env bash
[[ -e "$tmp_dir/waybar-running" ]]
EOF
cat >"$fake_bin/pkill" <<EOF
#!/usr/bin/env bash
rm -f "$tmp_dir/waybar-running"
EOF
cat >"$fake_bin/setsid" <<EOF
#!/usr/bin/env bash
[[ "\${1:-}" == -f ]] && shift
if [[ -e /proc/\$\$/fd/9 ]]; then
    printf 'inherited\n' >"$tmp_dir/inherited-lock"
fi
"\$@"
EOF
cat >"$fake_bin/waybar" <<'EOF'
#!/usr/bin/env bash
:
EOF
chmod +x "$fake_bin/pgrep" "$fake_bin/pkill" "$fake_bin/setsid" "$fake_bin/waybar"
HOME="$fake_home" XDG_CONFIG_HOME="$xdg_config" PATH="$fake_bin:/usr/bin" \
    WCR_STILL="$tmp_dir/wall.png" \
    "$REPO_ROOT/configs/local-bin/wcr-post-apply-waybar.sh"
if [[ -e "$tmp_dir/inherited-lock" ]]; then
    echo "Restarted Waybar inherited the wallpaper theme lock" >&2
    exit 1
fi

echo "==> test 5: niri startup delegates desktop mode restoration once"
niri_config="$REPO_ROOT/configs/config/niri/config.kdl"
if rg -n '/home/[^/]+/.local/bin/wallpaper-console-rust' "$niri_config"; then
    echo "niri config contains a machine-specific Wallpaper Console path" >&2
    exit 1
fi
desktop_shell_start_count="$(rg -c 'desktop-shell start' "$niri_config" || true)"
if [[ "$desktop_shell_start_count" != 1 ]]; then
    echo "Expected niri to restore the selected desktop shell exactly once, found $desktop_shell_start_count entries" >&2
    exit 1
fi
if rg -q '^spawn-at-startup "(waybar|mako)"$|spawn-at-startup ".*swayidle' "$niri_config"; then
    echo "Desktop companion services bypass the desktop-shell mode manager" >&2
    exit 1
fi
if ! rg -q 'desktop-shell toggle' "$niri_config"; then
    echo "niri does not expose the Waybar/QuickShell toggle" >&2
    exit 1
fi

echo "==> test 6: retired shell integrations are removed without removing niri or QuickShell"
mkdir -p "$fake_home/.local/bin"
printf 'legacy\n' >"$fake_home/.local/bin/inir"
printf 'legacy\n' >"$fake_home/.local/bin/toggle-niri-shell"
printf 'keep\n' >"$fake_home/.local/bin/niri"
remove_retired_desktop_shell_paths "$backup_root" false "$backup_root/.restore-manifest"
if [[ -e "$fake_home/.local/bin/inir" || -e "$fake_home/.local/bin/toggle-niri-shell" ]]; then
    echo "Retired iNiR launchers survived config sync" >&2
    exit 1
fi
if [[ "$(cat "$fake_home/.local/bin/niri")" != keep ]]; then
    echo "Retired launcher cleanup removed niri itself" >&2
    exit 1
fi

retired_references="$(
    rg -n -i 'i[n]ir|cae[l]estia|bar-shell-switch' \
    "$REPO_ROOT/install.sh" \
    "$REPO_ROOT/scripts" \
    "$REPO_ROOT/configs" \
    "$REPO_ROOT/packages" \
    "$REPO_ROOT/docs" \
    "$REPO_ROOT/README.md" \
        | grep -vF "$REPO_ROOT/scripts/sync-configs.sh:" \
        || true
)"
if [[ -n "$retired_references" ]]; then
    printf '%s\n' "$retired_references"
    echo "Found a retired shell package, config, script, or install reference" >&2
    exit 1
fi
if ! grep -Fxq niri "$REPO_ROOT/packages/arch-essential.txt"; then
    echo "niri itself must remain in the essential package manifest" >&2
    exit 1
fi
if ! grep -Fxq quickshell "$REPO_ROOT/packages/arch-apps.txt"; then
    echo "QuickShell must remain available for custom shell development" >&2
    exit 1
fi

echo "All integration regression tests passed."

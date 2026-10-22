#!/usr/bin/env bash

set -euo pipefail
# Each fixture supplies its own HOME; its XDG defaults must follow that HOME.
unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME

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
printf '{"generated":true}\n' >"$fake_home/.config/waybar/brightness-module.json"
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
if [[ "$(cat "$fake_home/.config/waybar/brightness-module.json")" != '{"generated":true}' ]]; then
    echo "Config sync removed the runtime CFFI brightness loader" >&2
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

echo "==> test 2b: the desktop shell option is gone"
if HOME="$fake_home" "$REPO_ROOT/install.sh" \
    --yes --skip-packages --dry-run --desktop-shell waybar \
    >"$tmp_dir/removed-option.out" 2>&1; then
    echo "Expected the removed --desktop-shell option to be rejected" >&2
    cat "$tmp_dir/removed-option.out" >&2
    exit 1
fi
if "$REPO_ROOT/install.sh" --help 2>&1 | grep -qi -e 'desktop-shell' -e 'quickshell'; then
    echo "Installer help still mentions desktop shell profiles" >&2
    exit 1
fi

echo "==> test 3: wallpaper-generated colour files survive a restore, and missing ones are seeded"
seed_home="$tmp_dir/seed-home"
seed_repo="$tmp_dir/seed-repo"
seed_backup="$tmp_dir/seed-backup"
mkdir -p "$seed_home/.config/wlogout" "$seed_home/.config/niri" \
    "$seed_repo/configs/config/wlogout" "$seed_repo/configs/config/niri" \
    "$seed_repo/configs/config/waybar" "$seed_backup"
printf 'generated\n' >"$seed_home/.config/wlogout/colors.css"
printf 'generated ring\n' >"$seed_home/.config/niri/theme-colors.kdl"
printf 'seed\n' >"$seed_repo/configs/config/wlogout/colors.css"
printf 'seed\n' >"$seed_repo/configs/config/waybar/colors.css"
printf 'style\n' >"$seed_repo/configs/config/wlogout/style.css"
printf 'config\n' >"$seed_repo/configs/config/niri/config.kdl"
(
    HOME="$seed_home"
    unset XDG_CONFIG_HOME
    sync_mapping_entry "$seed_backup" false "$seed_backup/.restore-manifest" \
        "desktop|$seed_repo/configs/config/wlogout|$seed_home/.config/wlogout|dir|required"
    sync_mapping_entry "$seed_backup" false "$seed_backup/.restore-manifest" \
        "desktop|$seed_repo/configs/config/niri|$seed_home/.config/niri|dir|required"
    sync_waybar_seed_if_missing "$seed_repo" false "$seed_backup/.restore-manifest"
) >/dev/null
if [[ "$(cat "$seed_home/.config/wlogout/colors.css")" != generated \
    || "$(cat "$seed_home/.config/niri/theme-colors.kdl")" != "generated ring" ]]; then
    echo "Restore overwrote or deleted wallpaper-generated colour files" >&2
    exit 1
fi
if [[ "$(cat "$seed_home/.config/wlogout/style.css")" != style \
    || "$(cat "$seed_home/.config/niri/config.kdl")" != config ]]; then
    echo "Restore did not install the managed power menu or niri files" >&2
    exit 1
fi
if [[ "$(cat "$seed_home/.config/waybar/colors.css" 2>/dev/null)" != seed ]]; then
    echo "Missing Waybar colours were not seeded" >&2
    exit 1
fi

echo "==> test 4: a dry-run restore of a directory runs cleanly and changes nothing"
dry_output="$(
    HOME="$seed_home"
    unset XDG_CONFIG_HOME
    sync_mapping_entry "$seed_backup" true "$seed_backup/.restore-manifest" \
        "desktop|$seed_repo/configs/config/waybar|$seed_home/.config/waybar-dry|dir|required" 2>&1
)"
if [[ -n "$dry_output" && "$dry_output" == *"command not found"* ]]; then
    echo "Dry-run directory restore called a missing function" >&2
    printf '%s\n' "$dry_output" >&2
    exit 1
fi
if [[ -e "$seed_home/.config/waybar-dry" ]]; then
    echo "Dry-run restore created the destination" >&2
    exit 1
fi

echo "==> test 5: niri starts the bar and notifications itself, and locks through IdleFlow"
niri_config="$REPO_ROOT/configs/config/niri/config.kdl"
if rg -n -i 'desktop-shell|quickshell|clavis|wallpaper-console' "$niri_config"; then
    echo "niri config still references a retired component" >&2
    exit 1
fi
if ! rg -q 'spawn-sh-at-startup ".*exec waybar"' "$niri_config" \
    || ! rg -q '^spawn-at-startup "mako"$' "$niri_config"; then
    echo "niri no longer starts Waybar and mako at login" >&2
    exit 1
fi
if rg -q 'spawn-at-startup ".*swayidle|swaylock' "$niri_config"; then
    echo "niri runs its own idle or lock command beside IdleFlow" >&2
    exit 1
fi
if ! rg -q 'idlectl" "lock"' "$niri_config"; then
    echo "The lock key does not go through IdleFlow" >&2
    exit 1
fi

echo "==> test 6: retired shell integrations are removed without removing niri"
mkdir -p "$fake_home/.local/bin" "$fake_home/.local/share/zsh/site-functions"
printf 'legacy\n' >"$fake_home/.local/bin/inir"
printf 'legacy\n' >"$fake_home/.local/bin/toggle-niri-shell"
printf 'legacy\n' >"$fake_home/.local/bin/desktop-shell"
printf 'legacy\n' >"$fake_home/.local/bin/wcr-post-apply-waybar.sh"
printf 'legacy\n' >"$fake_home/.local/share/zsh/site-functions/_desktop-shell"
printf 'keep\n' >"$fake_home/.local/bin/niri"
remove_retired_desktop_shell_paths "$backup_root" false "$backup_root/.restore-manifest"
for retired in inir toggle-niri-shell desktop-shell wcr-post-apply-waybar.sh; do
    if [[ -e "$fake_home/.local/bin/$retired" ]]; then
        echo "Retired launcher survived config sync: $retired" >&2
        exit 1
    fi
done
if [[ -e "$fake_home/.local/share/zsh/site-functions/_desktop-shell" ]]; then
    echo "Retired desktop-shell completion survived config sync" >&2
    exit 1
fi
if [[ "$(cat "$fake_home/.local/bin/niri")" != keep ]]; then
    echo "Retired launcher cleanup removed niri itself" >&2
    exit 1
fi

retired_references="$(
    rg -n -i 'i[n]ir|cae[l]estia|bar-shell-switch|quick[s]hell|desktop-[s]hell' \
    "$REPO_ROOT/install.sh" \
    "$REPO_ROOT/scripts" \
    "$REPO_ROOT/configs" \
    "$REPO_ROOT/packages" \
    "$REPO_ROOT/README.md" \
        | grep -vF "$REPO_ROOT/scripts/sync-configs.sh:" \
        | grep -vF "$REPO_ROOT/scripts/uninstall.sh:" \
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

echo "All integration regression tests passed."

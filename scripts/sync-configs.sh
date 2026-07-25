#!/usr/bin/env bash
# Config sync helpers for dotfiles install.

set -euo pipefail

DOTFILES_UI_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ui.sh
source "$DOTFILES_UI_SCRIPT_DIR/ui.sh"

SYNC_MANIFEST_FILE=".restore-manifest"

ALL_CONFIG_GROUPS=(shell desktop terminal apps editors local-bin media)
SYNC_MAPPINGS=()

SYNC_BACKUP_COUNT=0
SYNC_DIR_COUNT=0
SYNC_FILE_COUNT=0
SYNC_TEMPLATE_COUNT=0
SYNC_SKIPPED_COUNT=0

sync_display_path() {
    local path="$1"
    if [[ "$path" == "$HOME"* ]]; then
        printf '~%s\n' "${path#"$HOME"}"
    else
        printf '%s\n' "$path"
    fi
}

sync_count_label() {
    local count="$1"
    local singular="$2"
    local plural="$3"
    if [[ "$count" == 1 ]]; then
        printf '1 %s\n' "$singular"
    else
        printf '%s %s\n' "$count" "$plural"
    fi
}

sync_mapping_entry() {
    local backup_root="$1"
    local dry_run="$2"
    local manifest="$3"
    local mapping="$4"

    local group src dest mode required existed_before
    IFS='|' read -r group src dest mode required <<<"$mapping"
    required="${required:-required}"

    if [[ ! -e "$src" ]]; then
        if [[ "$required" == optional ]]; then
            ui_warn "SKIP optional source: $src"
            return 0
        fi
        ui_error "missing required repo config source: $src"
        return 1
    fi

    if sync_mapping_is_current "$src" "$dest" "$mode"; then
        ((++SYNC_SKIPPED_COUNT))
        verbose_log "current  $(sync_display_path "$dest")"
        debug_log "skip unchanged mapping: $src -> $dest"
        return 0
    fi

    if path_existed "$dest"; then
        existed_before=true
    else
        existed_before=false
    fi

    if path_existed "$dest"; then
        ((++SYNC_BACKUP_COUNT))
        verbose_log "backup   $(sync_display_path "$dest")"
    fi

    backup_path "$dest" "$backup_root" "$dry_run"
    remove_symlink_dest "$dest" "$dry_run"

    if [[ "$dry_run" == true ]]; then
        local action="created"
        [[ "$existed_before" == true ]] && action="backed_up"
        debug_log "[dry-run] manifest: $dest|$action"
        if [[ "$mode" == dir ]]; then
            ((++SYNC_DIR_COUNT))
            verbose_log "rsync    $(sync_display_path "$dest")/"
            if sync_preserves_runtime_waybar_colors "$dest"; then
                debug_log "[dry-run] rsync -a --exclude=/colors.css $src/ -> $dest/"
            else
                debug_log "[dry-run] rsync -a $src/ -> $dest/"
            fi
        else
            ((++SYNC_FILE_COUNT))
            verbose_log "install  $(sync_display_path "$dest")"
            debug_log "[dry-run] install -Dm$mode $src -> $dest"
        fi
        return 0
    fi

    record_manifest_entry "$manifest" "$dest" "$existed_before"
    if [[ "$mode" == dir ]]; then
        ((++SYNC_DIR_COUNT))
        mkdir -p "$dest"
        local -a rsync_args=(-a --delete)
        if sync_preserves_runtime_waybar_colors "$dest"; then
            rsync_args+=(--exclude=/colors.css)
        fi
        rsync "${rsync_args[@]}" -- "$src/" "$dest/"
        verbose_log "rsync    $(sync_display_path "$dest")/"
        debug_log "rsync ${rsync_args[*]} $src/ -> $dest/"
    else
        ((++SYNC_FILE_COUNT))
        install -Dm"$mode" -- "$src" "$dest"
        verbose_log "install  $(sync_display_path "$dest")"
        debug_log "install -Dm$mode $src -> $dest"
    fi
}

sync_preserves_runtime_waybar_colors() {
    local dest="$1"
    [[ "$dest" == "${XDG_CONFIG_HOME:-$HOME/.config}/waybar" ]]
}

sync_mapping_is_current() {
    local src="$1"
    local dest="$2"
    local mode="$3"

    [[ -e "$dest" && ! -L "$dest" ]] || return 1

    if [[ "$mode" == dir ]]; then
        [[ -d "$dest" ]] || return 1
        local -a rsync_args=(-ani --delete --omit-dir-times)
        if sync_preserves_runtime_waybar_colors "$dest"; then
            rsync_args+=(--exclude=/colors.css)
        fi
        [[ -z "$(rsync "${rsync_args[@]}" -- "$src/" "$dest/")" ]]
        return
    fi

    [[ -f "$dest" ]] || return 1
    cmp -s -- "$src" "$dest" || return 1
    [[ "$(stat -c '%a' "$dest")" == "$mode" ]]
}

sync_waybar_seed_if_missing() {
    local repo_root="$1"
    local dry_run="$2"
    local manifest="$3"
    local src="$repo_root/configs/config/waybar/colors.css"
    local dest="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/colors.css"

    [[ -e "$dest" ]] && return 0
    [[ -f "$src" ]] || return 0

    ((++SYNC_FILE_COUNT))
    if [[ "$dry_run" == true ]]; then
        verbose_log "seed     $(sync_display_path "$dest")"
        debug_log "[dry-run] install -Dm644 $src -> $dest (initial colors only)"
        return 0
    fi

    install -Dm644 -- "$src" "$dest"
    record_manifest_entry "$manifest" "$dest" false
    verbose_log "seed     $(sync_display_path "$dest")"
}

group_selected() {
    local target_group="$1"
    shift
    local group
    for group in "$@"; do
        [[ "$group" == "$target_group" ]] && return 0
    done
    return 1
}

sync_zshrc_local() {
    local repo_root="$1"
    local backup_root="$2"
    local dry_run="$3"
    local manifest="$4"

    local zshrc_local="$HOME/.zshrc.local"
    local zshrc_local_template="$repo_root/templates/zshrc.local.example"
    if path_existed "$zshrc_local"; then
        if [[ -L "$zshrc_local" ]]; then
            backup_path "$zshrc_local" "$backup_root" "$dry_run"
            ((++SYNC_BACKUP_COUNT))
            ((++SYNC_TEMPLATE_COUNT))
            verbose_log "backup   $(sync_display_path "$zshrc_local")"
            remove_symlink_dest "$zshrc_local" "$dry_run"
            if [[ "$dry_run" == true ]]; then
                debug_log "[dry-run] manifest: $zshrc_local|backed_up"
                verbose_log "create   $(sync_display_path "$zshrc_local")"
                debug_log "[dry-run] install -Dm644 $zshrc_local_template -> $zshrc_local (replace symlink)"
            else
                record_manifest_entry "$manifest" "$zshrc_local" true
                install -Dm644 -- "$zshrc_local_template" "$zshrc_local"
                verbose_log "create   $(sync_display_path "$zshrc_local")"
                debug_log "install -Dm644 $zshrc_local_template -> $zshrc_local (replace symlink)"
            fi
        else
            ((++SYNC_SKIPPED_COUNT))
            verbose_log "current  $(sync_display_path "$zshrc_local")"
            debug_log "keep existing private config: $zshrc_local"
            ui_warn "Keeping existing" "$(sync_display_path "$zshrc_local")"
        fi
    elif [[ "$dry_run" == true ]]; then
        ((++SYNC_TEMPLATE_COUNT))
        debug_log "[dry-run] manifest: $zshrc_local|created"
        verbose_log "create   $(sync_display_path "$zshrc_local")"
        debug_log "[dry-run] install -Dm644 $zshrc_local_template -> $zshrc_local (new file)"
    else
        ((++SYNC_TEMPLATE_COUNT))
        install -Dm644 -- "$zshrc_local_template" "$zshrc_local"
        record_manifest_entry "$manifest" "$zshrc_local" false
        verbose_log "create   $(sync_display_path "$zshrc_local")"
        debug_log "install -Dm644 $zshrc_local_template -> $zshrc_local (new file)"
    fi
}

remove_retired_desktop_shell_paths() {
    local backup_root="$1"
    local dry_run="$2"
    local manifest="$3"
    local path
    local -a retired_paths=(
        "$HOME/.local/bin/inir"
        "$HOME/.local/bin/toggle-niri-shell"
    )

    for path in "${retired_paths[@]}"; do
        [[ -e "$path" || -L "$path" ]] || continue
        if [[ -d "$path" && ! -L "$path" ]]; then
            ui_warn "Retired launcher kept" "$(sync_display_path "$path") is a directory"
            continue
        fi

        ((++SYNC_BACKUP_COUNT))
        backup_path "$path" "$backup_root" "$dry_run"
        verbose_log "retire   $(sync_display_path "$path")"
        if [[ "$dry_run" == true ]]; then
            debug_log "[dry-run] retire managed launcher: $path"
            continue
        fi

        record_manifest_entry "$manifest" "$path" true
        rm -f -- "$path"
    done
}

# Populate SYNC_MAPPINGS for the given repo root.
# Format: group|src|dest|mode|required
build_sync_mappings() {
    local repo_root="$1"
    local config_root="$repo_root/configs/config"
    local desktop_shell_profile="${DESKTOP_SHELL_PROFILE:-dual}"
    SYNC_MAPPINGS=(
        "shell|$repo_root/configs/home/.zshrc|$HOME/.zshrc|644|required"
        "desktop|$config_root/niri|$HOME/.config/niri|dir|required"
        "desktop|$config_root/fcitx5|$HOME/.config/fcitx5|dir|required"
        "desktop|$config_root/mako|$HOME/.config/mako|dir|required"
        "desktop|$config_root/environment.d|$HOME/.config/environment.d|dir|required"
        "desktop|$config_root/qt5ct|$HOME/.config/qt5ct|dir|required"
        "desktop|$config_root/qt6ct|$HOME/.config/qt6ct|dir|required"
        "terminal|$config_root/kitty|$HOME/.config/kitty|dir|required"
        "terminal|$config_root/fastfetch|$HOME/.config/fastfetch|dir|required"
        "terminal|$config_root/cava|$HOME/.config/cava|dir|required"
        "apps|$config_root/waypaper|$HOME/.config/waypaper|dir|required"
        "apps|$config_root/matugen|$HOME/.config/matugen|dir|required"
        "apps|$config_root/Thunar|$HOME/.config/Thunar|dir|required"
        "apps|$config_root/mimeapps.list|$HOME/.config/mimeapps.list|644|required"
        "apps|$config_root/user-dirs.dirs|$HOME/.config/user-dirs.dirs|644|required"
        "apps|$config_root/git/ignore|$HOME/.config/git/ignore|644|required"
        "editors|$config_root/Code/User/settings.json|$HOME/.config/Code/User/settings.json|644|required"
        "editors|$config_root/Code/User/keybindings.json|$HOME/.config/Code/User/keybindings.json|644|required"
        "editors|$config_root/Code/User/snippets|$HOME/.config/Code/User/snippets|dir|optional"
        "editors|$config_root/Cursor/User/settings.json|$HOME/.config/Cursor/User/settings.json|644|required"
        "editors|$config_root/Cursor/User/keybindings.json|$HOME/.config/Cursor/User/keybindings.json|644|required"
        "editors|$config_root/Cursor/User/snippets|$HOME/.config/Cursor/User/snippets|dir|optional"
        "local-bin|$repo_root/configs/local-bin/toggle-wlsunset|$HOME/.local/bin/toggle-wlsunset|755|required"
        "local-bin|$repo_root/configs/local-bin/desktop-shell|$HOME/.local/bin/desktop-shell|755|required"
        "local-bin|$repo_root/configs/zsh/site-functions/_desktop-shell|$HOME/.local/share/zsh/site-functions/_desktop-shell|644|required"
        "media|$repo_root/configs/Pictures/wallpapers|$HOME/Pictures/wallpapers|dir|required"
    )

    if [[ "$desktop_shell_profile" == waybar || "$desktop_shell_profile" == dual ]]; then
        SYNC_MAPPINGS+=(
            "desktop|$config_root/waybar|$HOME/.config/waybar|dir|required"
            "local-bin|$repo_root/configs/local-bin/wcr-post-apply-waybar.sh|$HOME/.local/bin/wcr-post-apply-waybar.sh|755|required"
        )
    fi
}

# Print managed destination paths (one per line), optionally filtered by groups.
# Does not include ~/.zshrc.local (private overlay — never uninstall-managed).
list_managed_dest_paths() {
    local repo_root="$1"
    shift || true
    local -a selected_groups=("$@")
    local mapping group dest

    if ((${#selected_groups[@]} == 0)); then
        selected_groups=("${ALL_CONFIG_GROUPS[@]}")
    fi

    build_sync_mappings "$repo_root"
    for mapping in "${SYNC_MAPPINGS[@]}"; do
        IFS='|' read -r group _ dest _ _ <<<"$mapping"
        if group_selected "$group" "${selected_groups[@]}"; then
            printf '%s\n' "$dest"
        fi
    done
}

sync_configs() {
    local repo_root="$1"
    local backup_root="$2"
    local dry_run="${3:-false}"
    shift 3 || true
    local -a selected_groups=("$@")

    if ((${#selected_groups[@]} == 0)); then
        selected_groups=("${ALL_CONFIG_GROUPS[@]}")
    fi

    SYNC_BACKUP_COUNT=0
    SYNC_DIR_COUNT=0
    SYNC_FILE_COUNT=0
    SYNC_TEMPLATE_COUNT=0
    SYNC_SKIPPED_COUNT=0

    # shellcheck source=scripts/backup.sh
    source "$repo_root/scripts/backup.sh"

    build_sync_mappings "$repo_root"
    local -a mappings=("${SYNC_MAPPINGS[@]}")

    local manifest="$backup_root/$SYNC_MANIFEST_FILE"
    if [[ "$dry_run" != true ]]; then
        : >"$manifest"
    fi

    local mapping group
    for mapping in "${mappings[@]}"; do
        IFS='|' read -r group _ _ _ _ <<<"$mapping"
        if group_selected "$group" "${selected_groups[@]}"; then
            sync_mapping_entry "$backup_root" "$dry_run" "$manifest" "$mapping"
        fi
    done

    if group_selected desktop "${selected_groups[@]}" \
        && [[ "${DESKTOP_SHELL_PROFILE:-dual}" != quickshell ]]; then
        sync_waybar_seed_if_missing "$repo_root" "$dry_run" "$manifest"
    fi

    if group_selected shell "${selected_groups[@]}"; then
        sync_zshrc_local "$repo_root" "$backup_root" "$dry_run" "$manifest"
    fi

    if group_selected local-bin "${selected_groups[@]}"; then
        remove_retired_desktop_shell_paths \
            "$backup_root" "$dry_run" "$manifest"
        local -a executable_paths=(
            "$HOME/.local/bin/toggle-wlsunset"
            "$HOME/.local/bin/desktop-shell"
        )
        if [[ "${DESKTOP_SHELL_PROFILE:-dual}" != quickshell ]]; then
            executable_paths+=("$HOME/.local/bin/wcr-post-apply-waybar.sh")
        fi
        if [[ "$dry_run" == true ]]; then
            debug_log "[dry-run] chmod +x ${executable_paths[*]}"
        else
            chmod +x "${executable_paths[@]}"
            verbose_log "chmod    profile-managed local-bin scripts"
        fi
    fi

    write_rollback_script "$backup_root" "$dry_run"

    ui_ok "Existing paths to back up" "$(sync_count_label "$SYNC_BACKUP_COUNT" path paths)"
    ui_ok "Directories to sync" "$(sync_count_label "$SYNC_DIR_COUNT" dir dirs)"
    ui_ok "Files to install" "$(sync_count_label "$SYNC_FILE_COUNT" file files)"
    ui_ok "Templates to create" "$(sync_count_label "$SYNC_TEMPLATE_COUNT" file files)"
    ui_ok "Unchanged paths skipped" "$(sync_count_label "$SYNC_SKIPPED_COUNT" path paths)"
    ui_ok "Rollback script planned"
}

configure_wallpaper_console_theme_hook() {
    local dry_run="${1:-false}"
    local wcr_bin=""
    local hook_path="$HOME/.local/bin/wcr-post-apply-waybar.sh"
    local matugen_config="${XDG_CONFIG_HOME:-$HOME/.config}/matugen/config.toml"

    if [[ -x "$HOME/.local/bin/wallpaper-console-rust" ]]; then
        wcr_bin="$HOME/.local/bin/wallpaper-console-rust"
    elif command -v wallpaper-console-rust >/dev/null 2>&1; then
        wcr_bin="$(command -v wallpaper-console-rust)"
    fi

    if [[ -z "$wcr_bin" ]]; then
        ui_warn "Wallpaper Console hook" "binary not installed; configure after installing Wallpaper Console"
        return 0
    fi
    if [[ ! -x "$hook_path" || ! -f "$matugen_config" ]]; then
        ui_warn "Wallpaper Console hook" "helper or matugen config is missing"
        return 0
    fi

    if [[ "$dry_run" == true ]]; then
        debug_log "[dry-run] $wcr_bin config-set post_apply_enabled on"
        debug_log "[dry-run] $wcr_bin config-set post_apply_command $hook_path"
        debug_log "[dry-run] $wcr_bin config-set restore_on_login on"
        ui_ok "Wallpaper Console hook" "configuration planned"
        return 0
    fi

    local changed=0 key expected current
    while IFS='|' read -r key expected; do
        current="$("$wcr_bin" config-get "$key" 2>/dev/null || true)"
        if [[ "$current" == "$expected" ]]; then
            continue
        fi
        "$wcr_bin" config-set "$key" "$expected"
        ((++changed))
    done <<EOF
post_apply_enabled|on
post_apply_command|$hook_path
restore_on_login|on
EOF

    if ((changed == 0)); then
        ui_ok "Wallpaper Console hook" "already current"
    else
        ui_ok "Wallpaper Console hook" "enabled with synchronized Waybar helper"
    fi
}

disable_wallpaper_console_theme_hook() {
    local dry_run="${1:-false}"
    local wcr_bin=""

    if [[ -x "$HOME/.local/bin/wallpaper-console-rust" ]]; then
        wcr_bin="$HOME/.local/bin/wallpaper-console-rust"
    elif command -v wallpaper-console-rust >/dev/null 2>&1; then
        wcr_bin="$(command -v wallpaper-console-rust)"
    fi

    if [[ -z "$wcr_bin" ]]; then
        ui_warn "Wallpaper Console ownership" "binary not installed; nothing to disable"
        return 0
    fi

    if [[ "$dry_run" == true ]]; then
        debug_log "[dry-run] $wcr_bin config-set post_apply_enabled off"
        debug_log "[dry-run] $wcr_bin config-set post_apply_command ''"
        debug_log "[dry-run] $wcr_bin config-set restore_on_login off"
        ui_ok "Wallpaper Console ownership" "disable planned"
        return 0
    fi

    local changed=0 key expected current
    while IFS='|' read -r key expected; do
        current="$("$wcr_bin" config-get "$key" 2>/dev/null || true)"
        if [[ "$current" == "$expected" ]]; then
            continue
        fi
        "$wcr_bin" config-set "$key" "$expected"
        ((++changed))
    done <<'EOF'
post_apply_enabled|off
post_apply_command|
restore_on_login|off
EOF

    if ((changed == 0)); then
        ui_ok "Wallpaper Console ownership" "already disabled"
    else
        ui_ok "Wallpaper Console ownership" "disabled for QuickShell-only profile"
    fi
}

#!/usr/bin/env bash
# Config sync helpers for dotfiles install.

set -euo pipefail

DOTFILES_UI_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ui.sh
source "$DOTFILES_UI_SCRIPT_DIR/ui.sh"

SYNC_MANIFEST_FILE=".restore-manifest"

ALL_CONFIG_GROUPS=(shell desktop terminal apps editors local-bin media)

SYNC_BACKUP_COUNT=0
SYNC_DIR_COUNT=0
SYNC_FILE_COUNT=0
SYNC_TEMPLATE_COUNT=0

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
            debug_log "[dry-run] rsync -a $src/ -> $dest/"
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
        rsync -a --delete -- "$src/" "$dest/"
        verbose_log "rsync    $(sync_display_path "$dest")/"
        debug_log "rsync -a --delete $src/ -> $dest/"
    else
        ((++SYNC_FILE_COUNT))
        install -Dm"$mode" -- "$src" "$dest"
        verbose_log "install  $(sync_display_path "$dest")"
        debug_log "install -Dm$mode $src -> $dest"
    fi
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
        local was_symlink=false
        [[ -L "$zshrc_local" ]] && was_symlink=true

        backup_path "$zshrc_local" "$backup_root" "$dry_run"

        if [[ "$was_symlink" == true ]]; then
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
        elif [[ "$dry_run" == true ]]; then
            ((++SYNC_BACKUP_COUNT))
            verbose_log "backup   $(sync_display_path "$zshrc_local")"
            debug_log "[dry-run] manifest: $zshrc_local|backed_up"
            debug_log "[dry-run] keep existing: $zshrc_local"
        else
            ((++SYNC_BACKUP_COUNT))
            verbose_log "backup   $(sync_display_path "$zshrc_local")"
            record_manifest_entry "$manifest" "$zshrc_local" true
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

    # shellcheck source=scripts/backup.sh
    source "$repo_root/scripts/backup.sh"

    local config_root="$repo_root/configs/config"
    local -a mappings=(
        "shell|$repo_root/configs/home/.zshrc|$HOME/.zshrc|644|required"
        "desktop|$config_root/niri|$HOME/.config/niri|dir|required"
        "desktop|$config_root/waybar|$HOME/.config/waybar|dir|required"
        "desktop|$config_root/fcitx5|$HOME/.config/fcitx5|dir|required"
        "desktop|$config_root/mako|$HOME/.config/mako|dir|required"
        "desktop|$config_root/environment.d|$HOME/.config/environment.d|dir|required"
        "desktop|$config_root/qt5ct|$HOME/.config/qt5ct|dir|required"
        "desktop|$config_root/qt6ct|$HOME/.config/qt6ct|dir|required"
        "terminal|$config_root/kitty|$HOME/.config/kitty|dir|required"
        "terminal|$config_root/fastfetch|$HOME/.config/fastfetch|dir|required"
        "terminal|$config_root/cava|$HOME/.config/cava|dir|required"
        "apps|$config_root/waypaper|$HOME/.config/waypaper|dir|required"
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
        "local-bin|$repo_root/configs/local-bin/inir|$HOME/.local/bin/inir|755|required"
        "local-bin|$repo_root/configs/local-bin/toggle-niri-shell|$HOME/.local/bin/toggle-niri-shell|755|required"
        "media|$repo_root/configs/Pictures/wallpapers|$HOME/Pictures/wallpapers|dir|required"
    )

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

    if group_selected shell "${selected_groups[@]}"; then
        sync_zshrc_local "$repo_root" "$backup_root" "$dry_run" "$manifest"
    fi

    if group_selected local-bin "${selected_groups[@]}"; then
        if [[ "$dry_run" == true ]]; then
            debug_log "[dry-run] chmod +x $HOME/.local/bin/inir $HOME/.local/bin/toggle-niri-shell"
        else
            chmod +x "$HOME/.local/bin/inir" "$HOME/.local/bin/toggle-niri-shell"
            verbose_log "chmod    ~/.local/bin/inir ~/.local/bin/toggle-niri-shell"
        fi
    fi

    write_rollback_script "$backup_root" "$dry_run"

    ui_ok "Existing paths to back up" "$(sync_count_label "$SYNC_BACKUP_COUNT" path paths)"
    ui_ok "Directories to sync" "$(sync_count_label "$SYNC_DIR_COUNT" dir dirs)"
    ui_ok "Files to install" "$(sync_count_label "$SYNC_FILE_COUNT" file files)"
    ui_ok "Templates to create" "$(sync_count_label "$SYNC_TEMPLATE_COUNT" file files)"
    ui_ok "Rollback script planned"
}

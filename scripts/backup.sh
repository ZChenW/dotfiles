#!/usr/bin/env bash
# shellcheck disable=SC2034
# Backup helpers for dotfiles install.

set -euo pipefail

DOTFILES_UI_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ui.sh
source "$DOTFILES_UI_SCRIPT_DIR/ui.sh"

DOTFILES_BACKUP_BASE="${DOTFILES_BACKUP_BASE:-$HOME/.dotfiles-backups}"
SYNC_MANIFEST_FILE=".restore-manifest"

create_backup_dir() {
    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    printf '%s/%s' "$DOTFILES_BACKUP_BASE" "$timestamp"
}

path_existed() {
    local target_path="$1"
    [[ -e "$target_path" || -L "$target_path" ]]
}

record_manifest_entry() {
    local manifest="$1"
    local dest="$2"
    local existed_before="$3"

    local action="created"
    if [[ "$existed_before" == true ]]; then
        action="backed_up"
    fi

    printf '%s|%s\n' "$dest" "$action" >>"$manifest"
}

backup_path() {
    local target_path="$1"
    local backup_root="$2"
    local dry_run="${3:-false}"

    if ! path_existed "$target_path"; then
        return 0
    fi

    local backup_dest
    backup_dest="$backup_root$target_path"

    if [[ "$dry_run" == true ]]; then
        if [[ -L "$target_path" ]]; then
            debug_log "[dry-run] backup symlink: $target_path -> $backup_dest"
            debug_log "[dry-run] write symlink info: ${backup_dest}.symlink-info"
        else
            debug_log "[dry-run] backup: $target_path -> $backup_dest"
        fi
        return 0
    fi

    mkdir -p "$(dirname -- "$backup_dest")"

    if [[ -L "$target_path" ]]; then
        cp -P -- "$target_path" "$backup_dest"
        {
            echo "original=$target_path"
            echo "link_target=$(readlink -- "$target_path")"
            if command -v realpath >/dev/null 2>&1; then
                echo "resolved_target=$(realpath -- "$target_path" 2>/dev/null || true)"
            else
                echo "resolved_target="
            fi
        } >"${backup_dest}.symlink-info"
        debug_log "backup symlink: $target_path -> $backup_dest"
        return 0
    fi

    if [[ -d "$target_path" ]]; then
        rsync -a -- "$target_path/" "$backup_dest/"
    else
        cp -a -- "$target_path" "$backup_dest"
    fi
    debug_log "backup: $target_path -> $backup_dest"
}

remove_symlink_dest() {
    local dest="$1"
    local dry_run="${2:-false}"
    local display_dest="$dest"

    if [[ "$display_dest" == "$HOME"* ]]; then
        display_dest="~${display_dest#"$HOME"}"
    fi

    if [[ ! -L "$dest" ]]; then
        return 0
    fi

    if [[ "$dry_run" == true ]]; then
        debug_log "[dry-run] rm -f $dest  # replace symlink with real path"
    else
        rm -f -- "$dest"
        verbose_log "remove   $display_dest symlink"
        debug_log "rm -f $dest  # replace symlink with real path"
    fi
}

write_rollback_script() {
    local backup_root="$1"
    local dry_run="${2:-false}"
    local rollback_script="$backup_root/rollback.sh"
    local manifest="$backup_root/$SYNC_MANIFEST_FILE"

    if [[ "$dry_run" == true ]]; then
        debug_log "[dry-run] write rollback script: $rollback_script"
        return 0
    fi

    cat >"$rollback_script" <<'ROLLBACK_HEADER'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

restore_path() {
    local original="$1"
    local backup_file="$SCRIPT_DIR${original}"

    if [[ ! -e "$backup_file" && ! -L "$backup_file" ]]; then
        echo "Error: missing backup for $original" >&2
        return 1
    fi

    if [[ -L "$backup_file" ]]; then
        local link_target
        link_target="$(readlink -- "$backup_file")"
        rm -rf -- "$original"
        mkdir -p "$(dirname -- "$original")"
        ln -sfn -- "$link_target" "$original"
        echo "Restored symlink: $original -> $link_target"
        return 0
    fi

    if [[ -d "$backup_file" ]]; then
        rm -rf -- "$original"
        mkdir -p -- "$original"
        rsync -a --delete -- "$backup_file/" "$original/"
    else
        rm -f -- "$original"
        mkdir -p "$(dirname -- "$original")"
        cp -a -- "$backup_file" "$original"
    fi
    echo "Restored: $original"
}

remove_created_path() {
    local original="$1"

    if [[ ! -e "$original" && ! -L "$original" ]]; then
        echo "Skip (already absent): $original"
        return 0
    fi

    if [[ -L "$original" ]]; then
        rm -f -- "$original"
    elif [[ -d "$original" ]]; then
        rm -rf -- "$original"
    else
        rm -f -- "$original"
    fi
    echo "Removed created path: $original"
}

rollback_entry() {
    local original="$1"
    local action="$2"

    case "$action" in
        backed_up)
            restore_path "$original"
            ;;
        created)
            remove_created_path "$original"
            ;;
        *)
            echo "Error: unknown manifest action '$action' for $original" >&2
            return 1
            ;;
    esac
}

ROLLBACK_HEADER

    if [[ -f "$manifest" ]]; then
        while IFS='|' read -r original action || [[ -n "$original" ]]; do
            [[ -n "$original" ]] || continue
            [[ -n "$action" ]] || continue
            printf 'rollback_entry %q %q\n' "$original" "$action" >>"$rollback_script"
        done <"$manifest"
    fi

    chmod +x "$rollback_script"
    verbose_log "rollback $rollback_script"
    debug_log "write rollback script: $rollback_script"
}

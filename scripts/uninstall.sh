#!/usr/bin/env bash
# Uninstall / purge managed configs for the dotfiles installer.
# Never removes OS packages. Never removes ~/.zshrc.local (private overlay).

set -euo pipefail

DOTFILES_UI_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ui.sh
source "$DOTFILES_UI_SCRIPT_DIR/ui.sh"

DOTFILES_BACKUP_BASE="${DOTFILES_BACKUP_BASE:-$HOME/.dotfiles-backups}"

uninstall_prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local hint reply

    if [[ "$default" == y ]]; then
        hint="Y/n"
    else
        hint="y/N"
    fi

    while true; do
        read -r -p "$(ui_prompt "$prompt" "$hint")" reply
        reply="${reply:-$default}"
        case "${reply,,}" in
            y | yes) return 0 ;;
            n | no) return 1 ;;
            *) ui_warn "Please answer y or n." ;;
        esac
    done
}

uninstall_list_rollback_scripts() {
    local backup_base="${1:-$DOTFILES_BACKUP_BASE}"
    if [[ ! -d "$backup_base" ]]; then
        return 0
    fi
    find "$backup_base" -mindepth 2 -maxdepth 2 -type f -name rollback.sh 2>/dev/null | sort -r
}

uninstall_latest_rollback() {
    uninstall_list_rollback_scripts | head -n 1
}

uninstall_archive_managed_paths() {
    local repo_root="$1"
    local archive_path="$2"
    local -a paths=()
    local path_item

    # shellcheck source=scripts/sync-configs.sh
    source "$repo_root/scripts/sync-configs.sh"

    while IFS= read -r path_item; do
        [[ -n "$path_item" ]] || continue
        if [[ -e "$path_item" || -L "$path_item" ]]; then
            paths+=("$path_item")
        fi
    done < <(list_managed_dest_paths "$repo_root")

    if ((${#paths[@]} == 0)); then
        ui_warn "Archive" "no managed paths present to archive"
        return 0
    fi

    mkdir -p "$(dirname -- "$archive_path")"
    # Store as absolute paths under a flat archive rooted at /.
    tar -czf "$archive_path" -C / "${paths[@]/#/}"
    ui_ok "Archived managed configs" "$archive_path"
}

uninstall_remove_managed_paths() {
    local repo_root="$1"
    local dry_run="${2:-false}"
    local path_item display_path removed=0

    # shellcheck source=scripts/sync-configs.sh
    source "$repo_root/scripts/sync-configs.sh"

    while IFS= read -r path_item; do
        [[ -n "$path_item" ]] || continue
        display_path="$path_item"
        if [[ "$display_path" == "$HOME"* ]]; then
            display_path="~${display_path#"$HOME"}"
        fi

        if [[ ! -e "$path_item" && ! -L "$path_item" ]]; then
            verbose_log "skip     $display_path (absent)"
            continue
        fi

        if [[ "$dry_run" == true ]]; then
            verbose_log "remove   $display_path"
            debug_log "[dry-run] rm -rf -- $path_item"
            ((++removed)) || true
            continue
        fi

        rm -rf -- "$path_item"
        verbose_log "remove   $display_path"
        ((++removed)) || true
    done < <(list_managed_dest_paths "$repo_root")

    ui_ok "Removed managed paths" "$removed"
}

uninstall_safe() {
    local repo_root="$1"
    local dry_run="${2:-false}"
    local timestamp archive_path

    timestamp="$(date +%Y%m%d-%H%M%S)"
    archive_path="$DOTFILES_BACKUP_BASE/uninstall-archive-${timestamp}.tar.gz"

    ui_section "Safe uninstall"
    ui_note "Removes managed configs only. Keeps packages, backups, and ~/.zshrc.local."

    if [[ "$dry_run" == true ]]; then
        debug_log "[dry-run] would archive to $archive_path"
        uninstall_remove_managed_paths "$repo_root" true
        ui_result_box "Result" "ok:Dry-run uninstall planned" "ok:Archive would be: $archive_path"
        return 0
    fi

    uninstall_archive_managed_paths "$repo_root" "$archive_path"
    uninstall_remove_managed_paths "$repo_root" false
    ui_result_box "Result" \
        "ok:Safe uninstall complete" \
        "ok:Archive: $archive_path" \
        "ok:~/.zshrc.local preserved" \
        "ok:OS packages left installed"
}

uninstall_restore() {
    local dry_run="${1:-false}"
    local rollback
    rollback="$(uninstall_latest_rollback || true)"

    ui_section "Restore from latest backup"
    if [[ -z "$rollback" ]]; then
        ui_error "No rollback.sh found under $DOTFILES_BACKUP_BASE"
        return 1
    fi

    ui_kv "Rollback" "$rollback"
    if [[ "$dry_run" == true ]]; then
        debug_log "[dry-run] would run: $rollback"
        ui_result_box "Result" "ok:Dry-run restore planned" "ok:Would run $rollback"
        return 0
    fi

    bash "$rollback"
    ui_result_box "Result" "ok:Restored via $rollback"
}

uninstall_purge() {
    local repo_root="$1"
    local dry_run="${2:-false}"
    local assume_yes="${3:-false}"
    local timestamp archive_path

    timestamp="$(date +%Y%m%d-%H%M%S)"
    # Keep the final archive outside the backup base so purge does not delete it.
    archive_path="$HOME/dotfiles-final-backup-${timestamp}.tar.gz"

    ui_section "Purge"
    ui_warn "This removes managed configs AND all install backups under $DOTFILES_BACKUP_BASE"
    ui_note "Still keeps OS packages and ~/.zshrc.local."
    ui_note "A final archive is written to $archive_path"

    if [[ "$assume_yes" != true && "$dry_run" != true ]]; then
        if [[ ! -t 0 || ! -t 1 ]]; then
            ui_error "Purge requires a TTY confirmation or --yes."
            return 1
        fi
        if ! uninstall_prompt_yes_no "Really purge managed configs and all backups?" n; then
            ui_warn "Purge cancelled"
            return 0
        fi
    fi

    if [[ "$dry_run" == true ]]; then
        debug_log "[dry-run] would archive to $archive_path"
        uninstall_remove_managed_paths "$repo_root" true
        debug_log "[dry-run] would remove $DOTFILES_BACKUP_BASE"
        ui_result_box "Result" "ok:Dry-run purge planned" "ok:Final archive would be: $archive_path"
        return 0
    fi

    uninstall_archive_managed_paths "$repo_root" "$archive_path"
    uninstall_remove_managed_paths "$repo_root" false

    if [[ -d "$DOTFILES_BACKUP_BASE" ]]; then
        rm -rf -- "$DOTFILES_BACKUP_BASE"
        ui_ok "Removed backup base" "$DOTFILES_BACKUP_BASE"
    fi

    ui_result_box "Result" \
        "ok:Purge complete" \
        "ok:Final archive: $archive_path" \
        "ok:~/.zshrc.local preserved" \
        "ok:OS packages left installed"
}

run_uninstall() {
    local repo_root="$1"
    local mode="${2:-safe}"
    local dry_run="${3:-false}"
    local assume_yes="${4:-false}"

    case "$mode" in
        safe | uninstall)
            uninstall_safe "$repo_root" "$dry_run"
            ;;
        restore)
            uninstall_restore "$dry_run"
            ;;
        purge)
            uninstall_purge "$repo_root" "$dry_run" "$assume_yes"
            ;;
        *)
            ui_error "Unknown uninstall mode: $mode (use safe, restore, or purge)"
            return 1
            ;;
    esac
}

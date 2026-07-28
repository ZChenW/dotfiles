#!/usr/bin/env bash
# Pull dotfiles updates and apply them to this machine.

set -euo pipefail

DOTFILES_UI_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ui.sh
source "$DOTFILES_UI_SCRIPT_DIR/ui.sh"

update_repo_has_changes() {
    local repo_root="$1"
    [[ -n "$(git -C "$repo_root" status --porcelain)" ]]
}

update_require_clean_repo() {
    local repo_root="$1"
    if update_repo_has_changes "$repo_root"; then
        ui_error "local repo has uncommitted changes. Update will not stash, reset, merge, or publish them."
        return 1
    fi
}

update_pull() {
    local repo_root="$1"
    local dry_run="$2"

    if [[ "$dry_run" == true ]]; then
        echo "[dry-run] git pull --ff-only"
        return 0
    fi

    git -C "$repo_root" pull --ff-only
}

update_apply() {
    local repo_root="$1"
    local dry_run="$2"
    local install_profile="$3"
    local desktop_shell_profile="${4:-}"
    local -a args=(--yes --install-profile "$install_profile")
    if [[ -n "$desktop_shell_profile" ]]; then
        args+=(--desktop-shell "$desktop_shell_profile")
    fi

    if [[ "$dry_run" == true ]]; then
        args+=(--dry-run)
        printf '[dry-run] %s/install.sh' "$repo_root"
        printf ' %q' "${args[@]}"
        printf '\n'
        return 0
    fi

    "$repo_root/install.sh" "${args[@]}"
}

run_update() {
    local repo_root="$1"
    local dry_run="$2"
    local install_profile="$3"
    local desktop_shell_profile="${4:-}"

    ui_step "Updating dotfiles repo ($(tr '[:lower:]' '[:upper:]' <<<"${install_profile:0:1}")${install_profile:1})"
    update_require_clean_repo "$repo_root" || return 1

    if [[ "$dry_run" == true ]]; then
        update_pull "$repo_root" true
        update_apply "$repo_root" true "$install_profile" "$desktop_shell_profile"
        ui_success "Update dry run complete. No changes were made."
        return 0
    fi

    update_pull "$repo_root" false || return 1

    ui_step "Applying updated dotfiles"
    update_apply "$repo_root" false "$install_profile" "$desktop_shell_profile"

    ui_success "Update complete."
}

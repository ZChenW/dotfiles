#!/usr/bin/env bash
# Pull dotfiles updates and apply them to this machine.

set -euo pipefail

update_prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local hint reply

    if [[ "$default" == y ]]; then
        hint="Y/n"
    else
        hint="y/N"
    fi

    while true; do
        read -r -p "$prompt [$hint] " reply
        reply="${reply:-$default}"
        case "${reply,,}" in
            y | yes) return 0 ;;
            n | no) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

update_repo_has_changes() {
    local repo_root="$1"
    [[ -n "$(git -C "$repo_root" status --porcelain)" ]]
}

update_require_clean_repo() {
    local repo_root="$1"
    if update_repo_has_changes "$repo_root"; then
        echo "Error: local repo has uncommitted changes. Commit, stash, or run snapshot before update." >&2
        return 1
    fi
}

update_snapshot_before_pull() {
    local repo_root="$1"
    local dry_run="$2"

    if [[ "$dry_run" == true ]]; then
        echo "[dry-run] ./install.sh --snapshot --push"
        return 0
    fi

    "$repo_root/install.sh" --snapshot --push
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
    local with_packages="$3"
    local -a args=()

    if [[ "$with_packages" == true ]]; then
        args+=(--yes)
    else
        args+=(--skip-packages --yes)
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
    local assume_yes="$3"
    local with_packages="$4"
    local no_snapshot_prompt="$5"

    echo "==> Updating dotfiles repo"

    if [[ "$dry_run" == true ]]; then
        if [[ "$no_snapshot_prompt" != true && "$assume_yes" != true ]]; then
            echo "[dry-run] optional prompt: Snapshot and push this machine before pulling?"
        fi
        update_pull "$repo_root" true
        update_apply "$repo_root" true "$with_packages"
        echo "Update dry run complete. No changes were made."
        return 0
    fi

    if [[ "$assume_yes" == true || "$no_snapshot_prompt" == true ]]; then
        update_require_clean_repo "$repo_root"
    else
        if update_prompt_yes_no "Snapshot and push this machine before pulling?" n; then
            update_snapshot_before_pull "$repo_root" false
        else
            update_require_clean_repo "$repo_root"
        fi
    fi

    update_require_clean_repo "$repo_root"
    update_pull "$repo_root" false

    echo "==> Applying updated dotfiles"
    update_apply "$repo_root" false "$with_packages"

    echo "Update complete."
}

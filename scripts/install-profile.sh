#!/usr/bin/env bash
# Installation profile state and policy.

set -euo pipefail

install_profile_state_file() {
    printf '%s/dotfiles/install-profile\n' \
        "${XDG_STATE_HOME:-$HOME/.local/state}"
}

normalize_install_profile() {
    case "${1,,}" in
        standard)
            printf 'standard\n'
            ;;
        lightweight)
            printf 'lightweight\n'
            ;;
        *)
            return 1
            ;;
    esac
}

load_saved_install_profile() {
    local state_file profile
    state_file="$(install_profile_state_file)"
    [[ -f "$state_file" ]] || return 1
    IFS= read -r profile <"$state_file"
    normalize_install_profile "$profile"
}

resolve_install_profile() {
    local explicit="${1:-}"

    if [[ -n "$explicit" ]]; then
        normalize_install_profile "$explicit"
        return
    fi

    load_saved_install_profile 2>/dev/null || printf 'standard\n'
}

save_install_profile() {
    local profile
    profile="$(normalize_install_profile "$1")" || return 1
    local state_file
    state_file="$(install_profile_state_file)"
    mkdir -p "$(dirname "$state_file")"
    printf '%s\n' "$profile" >"$state_file"
}

install_profile_label() {
    case "$1" in
        lightweight) printf 'Lightweight\n' ;;
        *) printf 'Standard\n' ;;
    esac
}

install_profile_manifest() {
    local repo_root="$1"
    local profile="$2"

    case "$profile" in
        lightweight)
            printf '%s/packages/arch-lightweight.txt\n' "$repo_root"
            ;;
        standard)
            return 1
            ;;
        *)
            return 2
            ;;
    esac
}

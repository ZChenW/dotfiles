#!/usr/bin/env bash
# Preflight dependency checks for the dotfiles installer.

set -euo pipefail

DOTFILES_UI_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ui.sh
source "$DOTFILES_UI_SCRIPT_DIR/ui.sh"

# Required host tools for install / sync / snapshot / update.
PREFLIGHT_REQUIRED_CMDS=(bash sudo pacman rsync install git mkdir date tee)

# Extra tools used by specific modes.
PREFLIGHT_UNINSTALL_CMDS=(tar)

preflight_missing_cmds() {
    local -a required=("$@")
    local -a missing=()
    local cmd
    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if ((${#missing[@]} > 0)); then
        printf '%s\n' "${missing[@]}"
    fi
}

run_preflight() {
    local mode="${1:-install}"
    local -a required=("${PREFLIGHT_REQUIRED_CMDS[@]}")
    local -a missing=()
    local line

    case "$mode" in
        uninstall | purge)
            required+=("${PREFLIGHT_UNINSTALL_CMDS[@]}")
            ;;
        doctor | verify)
            # Doctor reports optional gaps itself; still need core tools.
            ;;
        install | snapshot | update | export | dry-run) ;;
        *)
            ui_warn "Unknown preflight mode '$mode'; checking core tools only."
            ;;
    esac

    while IFS= read -r line; do
        [[ -n "$line" ]] && missing+=("$line")
    done < <(preflight_missing_cmds "${required[@]}")

    if ((${#missing[@]} > 0)); then
        ui_error "Missing required tools: ${missing[*]}"
        echo "Install them with pacman (for example: sudo pacman -S --needed ${missing[*]})" >&2
        return 1
    fi

    ui_ok "Preflight" "required tools present (${mode})"
    return 0
}

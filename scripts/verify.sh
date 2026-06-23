#!/usr/bin/env bash
# Post-install verification for dotfiles.

set -euo pipefail

verify_installation() {
    local dry_run="${1:-false}"
    local status=0

    if [[ "$dry_run" == true ]]; then
        echo "[dry-run] verify: zsh -n \$HOME/.zshrc"
        echo "[dry-run] verify: niri validate -c \$HOME/.config/niri/config.kdl"
        echo "[dry-run] verify: fastfetch --version"
        echo "[dry-run] verify: waybar --version"
        echo "[dry-run] verify: kitty --version"
        echo "[dry-run] verify restored paths are not symlinks"
        return 0
    fi

    if command -v zsh >/dev/null 2>&1; then
        echo "Verifying: zsh -n \$HOME/.zshrc"
        zsh -n "$HOME/.zshrc"
    else
        echo "SKIP: zsh not installed"
    fi

    if command -v niri >/dev/null 2>&1; then
        if [[ -f "$HOME/.config/niri/config.kdl" ]]; then
            echo "Verifying: niri validate"
            niri validate -c "$HOME/.config/niri/config.kdl"
        else
            echo "SKIP: niri config missing"
        fi
    else
        echo "SKIP: niri not installed"
    fi

    for cmd_label in "fastfetch:fastfetch --version" "waybar:waybar --version" "kitty:kitty --version"; do
        local cmd="${cmd_label%%:*}"
        local check="${cmd_label#*:}"
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "Verifying: $check"
            # shellcheck disable=SC2086
            $check >/dev/null
        else
            echo "SKIP: $cmd not installed"
        fi
    done

    local -a paths=(
        "$HOME/.zshrc"
        "$HOME/.config/niri"
        "$HOME/.config/waybar"
        "$HOME/.config/kitty"
        "$HOME/.config/fastfetch"
        "$HOME/.config/waypaper"
        "$HOME/.local/bin/inir"
        "$HOME/.local/bin/toggle-niri-shell"
    )

    local path_item
    for path_item in "${paths[@]}"; do
        if [[ -L "$path_item" ]]; then
            echo "Error: restored path is a symlink: $path_item" >&2
            status=1
        elif [[ ! -e "$path_item" ]]; then
            echo "Error: restored path missing: $path_item" >&2
            status=1
        else
            echo "OK: $path_item is a real file or directory"
        fi
    done

    return "$status"
}

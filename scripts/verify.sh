#!/usr/bin/env bash
# Post-install verification for dotfiles.

set -euo pipefail

group_selected() {
    local target_group="$1"
    shift
    local group
    for group in "$@"; do
        [[ "$group" == "$target_group" ]] && return 0
    done
    return 1
}

verify_installation() {
    local dry_run="${1:-false}"
    shift || true
    local -a selected_groups=("$@")
    local status=0

    if ((${#selected_groups[@]} == 0)); then
        selected_groups=(shell desktop terminal apps editors local-bin)
    fi

    if [[ "$dry_run" == true ]]; then
        if group_selected shell "${selected_groups[@]}"; then
            echo "[dry-run] verify: zsh -n \$HOME/.zshrc"
        fi
        if group_selected desktop "${selected_groups[@]}"; then
            echo "[dry-run] verify: niri validate -c \$HOME/.config/niri/config.kdl"
            echo "[dry-run] verify: waybar --version"
        fi
        if group_selected terminal "${selected_groups[@]}"; then
            echo "[dry-run] verify: fastfetch --version"
            echo "[dry-run] verify: kitty --version"
        fi
        echo "[dry-run] verify restored paths are not symlinks"
        return 0
    fi

    if group_selected shell "${selected_groups[@]}"; then
        if command -v zsh >/dev/null 2>&1; then
            echo "Verifying: zsh -n \$HOME/.zshrc"
            zsh -n "$HOME/.zshrc"
        else
            echo "SKIP: zsh not installed"
        fi
    fi

    if group_selected desktop "${selected_groups[@]}"; then
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
    fi

    if group_selected terminal "${selected_groups[@]}"; then
        for cmd_label in "fastfetch:fastfetch --version" "kitty:kitty --version"; do
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
    fi

    if group_selected desktop "${selected_groups[@]}"; then
        if command -v waybar >/dev/null 2>&1; then
            echo "Verifying: waybar --version"
            waybar --version >/dev/null
        else
            echo "SKIP: waybar not installed"
        fi
    fi

    local -a paths=()
    if group_selected shell "${selected_groups[@]}"; then
        paths+=("$HOME/.zshrc")
    fi
    if group_selected desktop "${selected_groups[@]}"; then
        paths+=(
            "$HOME/.config/niri"
            "$HOME/.config/waybar"
            "$HOME/.config/fcitx5"
            "$HOME/.config/mako"
            "$HOME/.config/environment.d"
            "$HOME/.config/qt5ct"
            "$HOME/.config/qt6ct"
        )
    fi
    if group_selected terminal "${selected_groups[@]}"; then
        paths+=(
            "$HOME/.config/kitty"
            "$HOME/.config/fastfetch"
            "$HOME/.config/cava"
        )
    fi
    if group_selected apps "${selected_groups[@]}"; then
        paths+=(
            "$HOME/.config/waypaper"
            "$HOME/.config/Thunar"
            "$HOME/.config/mimeapps.list"
            "$HOME/.config/user-dirs.dirs"
            "$HOME/.config/git/ignore"
        )
    fi
    if group_selected editors "${selected_groups[@]}"; then
        paths+=(
            "$HOME/.config/Code/User/settings.json"
            "$HOME/.config/Code/User/keybindings.json"
            "$HOME/.config/Cursor/User/settings.json"
            "$HOME/.config/Cursor/User/keybindings.json"
        )
    fi
    if group_selected local-bin "${selected_groups[@]}"; then
        paths+=(
            "$HOME/.local/bin/inir"
            "$HOME/.local/bin/toggle-niri-shell"
        )
    fi

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

    if group_selected editors "${selected_groups[@]}"; then
        for path_item in \
            "$HOME/.config/Code/User/snippets" \
            "$HOME/.config/Cursor/User/snippets"; do
            if [[ -L "$path_item" ]]; then
                echo "Error: restored path is a symlink: $path_item" >&2
                status=1
            elif [[ -e "$path_item" ]]; then
                echo "OK: $path_item is a real file or directory"
            else
                echo "SKIP optional path: $path_item"
            fi
        done
    fi

    return "$status"
}

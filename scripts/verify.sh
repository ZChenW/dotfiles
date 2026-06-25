#!/usr/bin/env bash
# Post-install verification for dotfiles.

set -euo pipefail

DOTFILES_UI_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ui.sh
source "$DOTFILES_UI_SCRIPT_DIR/ui.sh"

group_selected() {
    local target_group="$1"
    shift
    local group
    for group in "$@"; do
        [[ "$group" == "$target_group" ]] && return 0
    done
    return 1
}

verify_detail() {
    local label="$1"
    local command="$2"
    verbose_log "$(printf '%-9s %s' "$label" "$command")"
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
            ui_ok "zsh syntax"
            verify_detail "zsh" "zsh -n ~/.zshrc"
            debug_log "[dry-run] verify: zsh -n \$HOME/.zshrc"
        fi
        if group_selected desktop "${selected_groups[@]}"; then
            ui_ok "niri config"
            verify_detail "niri" "niri validate -c ~/.config/niri/config.kdl"
            debug_log "[dry-run] verify: niri validate -c \$HOME/.config/niri/config.kdl"
            ui_ok "waybar available"
            verify_detail "waybar" "waybar --version"
            debug_log "[dry-run] verify: waybar --version"
        fi
        if group_selected terminal "${selected_groups[@]}"; then
            ui_ok "fastfetch available"
            verify_detail "fastfetch" "fastfetch --version"
            debug_log "[dry-run] verify: fastfetch --version"
            ui_ok "kitty available"
            verify_detail "kitty" "kitty --version"
            debug_log "[dry-run] verify: kitty --version"
        fi
        ui_ok "symlink safety"
        verify_detail "symlink" "restored paths are not symlinks"
        debug_log "[dry-run] verify restored paths are not symlinks"
        return 0
    fi

    if group_selected shell "${selected_groups[@]}"; then
        if command -v zsh >/dev/null 2>&1; then
            verify_detail "zsh" "zsh -n ~/.zshrc"
            debug_log "verify: zsh -n $HOME/.zshrc"
            if zsh -n "$HOME/.zshrc"; then
                ui_ok "zsh syntax"
            else
                ui_fail "zsh syntax" "validation failed"
                status=1
            fi
        else
            ui_warn "zsh syntax" "zsh not installed"
        fi
    fi

    if group_selected desktop "${selected_groups[@]}"; then
        if command -v niri >/dev/null 2>&1; then
            if [[ -f "$HOME/.config/niri/config.kdl" ]]; then
                verify_detail "niri" "niri validate -c ~/.config/niri/config.kdl"
                debug_log "verify: niri validate -c $HOME/.config/niri/config.kdl"
                if niri validate -c "$HOME/.config/niri/config.kdl"; then
                    ui_ok "niri config"
                else
                    ui_fail "niri config" "validation failed"
                    status=1
                fi
            else
                ui_warn "niri config" "missing"
            fi
        else
            ui_warn "niri config" "niri not installed"
        fi
    fi

    if group_selected terminal "${selected_groups[@]}"; then
        for cmd_label in "fastfetch:fastfetch --version" "kitty:kitty --version"; do
            local cmd="${cmd_label%%:*}"
            local check="${cmd_label#*:}"
            if command -v "$cmd" >/dev/null 2>&1; then
                verify_detail "$cmd" "$check"
                debug_log "verify: $check"
                # shellcheck disable=SC2086
                if $check >/dev/null; then
                    ui_ok "$cmd available"
                else
                    ui_fail "$cmd available" "command failed"
                    status=1
                fi
            else
                ui_warn "$cmd available" "not installed"
            fi
        done
    fi

    if group_selected desktop "${selected_groups[@]}"; then
        if command -v waybar >/dev/null 2>&1; then
            verify_detail "waybar" "waybar --version"
            debug_log "verify: waybar --version"
            if waybar --version >/dev/null; then
                ui_ok "waybar available"
            else
                ui_fail "waybar available" "command failed"
                status=1
            fi
        else
            ui_warn "waybar available" "not installed"
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
            ui_error "restored path is a symlink: $path_item"
            status=1
        elif [[ ! -e "$path_item" ]]; then
            ui_error "restored path missing: $path_item"
            status=1
        fi
    done
    ui_ok "symlink safety"

    if group_selected editors "${selected_groups[@]}"; then
        for path_item in \
            "$HOME/.config/Code/User/snippets" \
            "$HOME/.config/Cursor/User/snippets"; do
            local display_path="$path_item"
            if [[ "$display_path" == "$HOME"* ]]; then
                display_path="~${display_path#"$HOME"}"
            fi
            if [[ -L "$path_item" ]]; then
                ui_error "restored path is a symlink: $path_item"
                status=1
            elif [[ -e "$path_item" ]]; then
                debug_log "verify: $path_item is a real file or directory"
            else
                ui_warn "Optional path" "$display_path missing"
            fi
        done
    fi

    return "$status"
}

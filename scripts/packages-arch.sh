#!/usr/bin/env bash
# Arch Linux package installation for dotfiles.

set -euo pipefail

declare -a PACMAN_PACKAGES=(
    git rsync zsh
    kitty lsd yazi fastfetch
    niri waybar fuzzel mako fcitx5 kanshi swayidle brightnessctl playerctl wl-clipboard
    grim slurp wf-recorder ffmpeg
    waypaper matugen
    clipse
)

package_available_in_pacman() {
    local pkg="$1"
    pacman -Si "$pkg" >/dev/null 2>&1
}

install_packages_arch() {
    local dry_run="${1:-false}"
    local assume_yes="${2:-false}"

    local -a pacman_install=()
    local -a aur_install=()
    local pkg

    for pkg in "${PACMAN_PACKAGES[@]}"; do
        if package_available_in_pacman "$pkg"; then
            pacman_install+=("$pkg")
        else
            aur_install+=("$pkg")
        fi
    done

    if ((${#pacman_install[@]} > 0)); then
        if [[ "$dry_run" == true ]]; then
            echo "[dry-run] sudo pacman -S --needed ${pacman_install[*]}"
        else
            local -a pacman_args=(pacman -S --needed)
            if [[ "$assume_yes" == true ]]; then
                pacman_args+=(--noconfirm)
            fi
            echo "Installing official packages: ${pacman_install[*]}"
            sudo "${pacman_args[@]}" "${pacman_install[@]}"
        fi
    fi

    if ((${#aur_install[@]} == 0)); then
        return 0
    fi

    local aur_helper=""
    if command -v paru >/dev/null 2>&1; then
        aur_helper=paru
    elif command -v yay >/dev/null 2>&1; then
        aur_helper=yay
    fi

    if [[ -z "$aur_helper" ]]; then
        echo "Error: required packages unavailable in official repos and no AUR helper found:" >&2
        printf '  %s\n' "${aur_install[@]}" >&2
        echo "Install paru or yay, then re-run the installer." >&2
        return 1
    fi

    if [[ "$dry_run" == true ]]; then
        echo "[dry-run] $aur_helper -S --needed ${aur_install[*]}"
    else
        local -a aur_args=(-S --needed)
        if [[ "$assume_yes" == true ]]; then
            aur_args+=(--noconfirm)
        fi
        echo "Installing AUR packages via $aur_helper: ${aur_install[*]}"
        "$aur_helper" "${aur_args[@]}" "${aur_install[@]}"
    fi
}

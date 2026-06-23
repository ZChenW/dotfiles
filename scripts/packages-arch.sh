#!/usr/bin/env bash
# Arch Linux package manifest helpers for dotfiles.
# shellcheck disable=SC2034,SC2178

set -euo pipefail

declare -a ESSENTIAL_PACKAGES=(
    git rsync zsh
    kitty lsd yazi fastfetch
    niri waybar fuzzel mako fcitx5 kanshi swayidle brightnessctl playerctl wl-clipboard
    grim slurp wf-recorder ffmpeg
    matugen
    clipse
)

package_available_in_pacman() {
    local pkg="$1"
    pacman -Si "$pkg" >/dev/null 2>&1
}

read_package_file() {
    local file="$1"
    local -n _packages_ref="$2"

    _packages_ref=()
    [[ -f "$file" ]] || return 0

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" ]] || continue
        _packages_ref+=("$line")
    done <"$file"
}

dedupe_packages() {
    local -n packages_ref=$1
    if ((${#packages_ref[@]} == 0)); then
        return 0
    fi
    mapfile -t packages_ref < <(printf '%s\n' "${packages_ref[@]}" | awk '!seen[$0]++')
}

sort_packages() {
    local -n packages_ref=$1
    if ((${#packages_ref[@]} == 0)); then
        return 0
    fi
    mapfile -t packages_ref < <(printf '%s\n' "${packages_ref[@]}" | LC_ALL=C sort -u)
}

filter_excluded_packages() {
    local -n _packages_ref="$1"
    local -n _exclude_ref="$2"
    local -A exclude_set=()
    local -a filtered=()
    local pkg exclude_pkg

    for exclude_pkg in "${_exclude_ref[@]}"; do
        exclude_set[$exclude_pkg]=1
    done

    for pkg in "${_packages_ref[@]}"; do
        [[ -n "${exclude_set[$pkg]+x}" ]] && continue
        filtered+=("$pkg")
    done

    _packages_ref=("${filtered[@]}")
}

collect_packages_from_files() {
    local -n _packages_ref="$1"
    shift
    local -a collected=()
    local file

    _packages_ref=()
    for file in "$@"; do
        local -a file_packages=()
        read_package_file "$file" file_packages
        collected+=("${file_packages[@]}")
    done

    _packages_ref=("${collected[@]}")
    dedupe_packages _packages_ref
}

split_official_and_aur() {
    local -n _official_ref="$1"
    local -n _aur_ref="$2"
    shift 2
    local pkg

    _official_ref=()
    _aur_ref=()
    for pkg in "$@"; do
        if package_available_in_pacman "$pkg"; then
            _official_ref+=("$pkg")
        else
            _aur_ref+=("$pkg")
        fi
    done
}

is_machine_local_pkg() {
    local pkg="$1"

    [[ "$pkg" == linux || "$pkg" == linux-firmware ]] && return 0
    [[ "$pkg" =~ ^linux- ]] && return 0
    [[ "$pkg" =~ ^(grub|grub-btrfs|amd-ucode|intel-ucode)$ ]] && return 0
    [[ "$pkg" =~ ^nvidia- ]] && return 0
    [[ "$pkg" =~ ^(networkmanager|btrfs-progs|snapper|wireplumber|sof-firmware|alsa-firmware|efibootmgr|os-prober)$ ]] && return 0
    [[ "$pkg" =~ ^btrfs- ]] && return 0
    [[ "$pkg" == snap-pac ]] && return 0
    [[ "$pkg" =~ ^pipewire ]] && return 0
    [[ "$pkg" =~ ^greetd ]] && return 0
    [[ "$pkg" =~ ^vulkan- ]] && return 0
    [[ "$pkg" =~ ^lib32-vulkan- ]] && return 0
    return 1
}

is_essential_pkg() {
    local pkg="$1"
    local -n _essential_set_ref="$2"
    [[ -n "${_essential_set_ref[$pkg]+x}" ]]
}

is_desktop_pkg() {
    local pkg="$1"

    [[ "$pkg" =~ ^(ttf-|noto-fonts|wqy-|adobe-source-) ]] && return 0
    [[ "$pkg" =~ ^fcitx5- ]] && return 0
    [[ "$pkg" =~ ^(blueman|bluez-utils|bluetui)$ ]] && return 0
    [[ "$pkg" =~ ^(cava|chafa|swappy|hyprpicker|awww|swaybg|swaylock)$ ]] && return 0
    [[ "$pkg" =~ ^(thunar|dolphin|gwenview|ark|mission-center)$ ]] && return 0
    [[ "$pkg" =~ ^power-profiles ]] && return 0
    [[ "$pkg" =~ ^(polkit-gnome|packagekit) ]] && return 0
    [[ "$pkg" =~ ^xdg-desktop-portal ]] && return 0
    [[ "$pkg" =~ ^(qt5-wayland|qt6-wayland|xwayland) ]] && return 0
    [[ "$pkg" =~ ^zsh-(autosuggestions|syntax-highlighting|completions) ]] && return 0
    [[ "$pkg" =~ ^(alacritty|konsole)$ ]] && return 0
    [[ "$pkg" =~ ^(cliphist|wtype|ydotool|xdotool)$ ]] && return 0
    [[ "$pkg" =~ ^(rime-ice|appstream-qt|dialog|kdialog|kdiskmark|qdiskinfo)$ ]] && return 0
    return 1
}

is_app_pkg() {
    local pkg="$1"

    [[ "$pkg" =~ ^(firefox|chromium|neovim|vim|steam|vlc|zathura) ]] && return 0
    [[ "$pkg" =~ ^libreoffice ]] && return 0
    [[ "$pkg" =~ ^(jupyterlab|texlive|texstudio|pandoc) ]] && return 0
    [[ "$pkg" =~ ^(nodejs|npm|pnpm|corepack|nvm) ]] && return 0
    [[ "$pkg" =~ ^(nvtop|tokei|tree|fzf|jq|wget|yt-dlp|uv|scratch|tree-sitter-cli) ]] && return 0
    [[ "$pkg" =~ ^(r$|ghc|cabal|stack|happy|alex|namcap) ]] && return 0
    [[ "$pkg" =~ ^(openai-codex|opencode) ]] && return 0
    [[ "$pkg" =~ ^(quickshell|webkit) ]] && return 0
    [[ "$pkg" =~ ^(python-|gcc-fortran|clang|shellcheck|stylua|unzip) ]] && return 0
    return 1
}

is_default_excluded_pkg() {
    local pkg="$1"

    [[ "$pkg" =~ ^(yay|paru)(-debug)?$ ]] && return 0
    [[ "$pkg" == base || "$pkg" == base-devel ]] && return 0
    [[ "$pkg" == archlinuxcn-keyring ]] && return 0
    return 1
}

write_package_file() {
    local file="$1"
    local header="$2"
    shift 2
    local -a packages=("$@")

    dedupe_packages packages
    sort_packages packages

    {
        printf '%s\n' "$header"
        if ((${#packages[@]} > 0)); then
            printf '%s\n' "${packages[@]}"
        fi
    } >"$file"
}

install_packages_batch() {
    local dry_run="$1"
    local assume_yes="$2"
    local helper="$3"
    shift 3
    local -a packages=("$@")

    if ((${#packages[@]} == 0)); then
        return 0
    fi

    if [[ "$helper" == pacman ]]; then
        if [[ "$dry_run" == true ]]; then
            echo "[dry-run] sudo pacman -S --needed ${packages[*]}"
            return 0
        fi

        local -a pacman_args=(pacman -S --needed)
        if [[ "$assume_yes" == true ]]; then
            pacman_args+=(--noconfirm)
        fi
        echo "Installing official packages: ${packages[*]}"
        sudo "${pacman_args[@]}" "${packages[@]}"
        return 0
    fi

    if [[ "$dry_run" == true ]]; then
        echo "[dry-run] $helper -S --needed ${packages[*]}"
        return 0
    fi

    local -a aur_args=(-S --needed)
    if [[ "$assume_yes" == true ]]; then
        aur_args+=(--noconfirm)
    fi
    echo "Installing AUR packages via $helper: ${packages[*]}"
    "$helper" "${aur_args[@]}" "${packages[@]}"
}

install_package_files() {
    local dry_run="$1"
    local assume_yes="$2"
    local include_machine_local="$3"
    local repo_root="$4"
    local packages_dir="$repo_root/packages"

    local -a package_files=(
        "$packages_dir/arch-essential.txt"
        "$packages_dir/arch-desktop.txt"
        "$packages_dir/arch-apps.txt"
        "$packages_dir/arch-aur.txt"
    )

    if [[ "$include_machine_local" == true ]]; then
        package_files+=("$packages_dir/arch-machine-local.txt")
    else
        local -a machine_local_packages=()
        read_package_file "$packages_dir/arch-machine-local.txt" machine_local_packages
        if ((${#machine_local_packages[@]} > 0)); then
            echo "Machine-local packages skipped. Re-run with --full-packages to include them."
        fi
    fi

    local -a exclude_packages=() all_packages=() official_packages=() aur_packages=()
    read_package_file "$packages_dir/arch-exclude.txt" exclude_packages
    collect_packages_from_files all_packages "${package_files[@]}"
    filter_excluded_packages all_packages exclude_packages
    split_official_and_aur official_packages aur_packages "${all_packages[@]}"

    install_packages_batch "$dry_run" "$assume_yes" pacman "${official_packages[@]}"

    if ((${#aur_packages[@]} == 0)); then
        return 0
    fi

    local aur_helper=""
    if command -v paru >/dev/null 2>&1; then
        aur_helper=paru
    elif command -v yay >/dev/null 2>&1; then
        aur_helper=yay
    fi

    if [[ -z "$aur_helper" ]]; then
        echo "Error: AUR packages require paru or yay:" >&2
        printf '  %s\n' "${aur_packages[@]}" >&2
        return 1
    fi

    install_packages_batch "$dry_run" "$assume_yes" "$aur_helper" "${aur_packages[@]}"
}

export_package_snapshot() {
    local repo_root="$1"
    local packages_dir="$repo_root/packages"
    mkdir -p "$packages_dir"

    local -a native_packages=() foreign_packages=()
    mapfile -t native_packages < <(pacman -Qqen 2>/dev/null || true)
    mapfile -t foreign_packages < <(pacman -Qqem 2>/dev/null || true)

    local -a existing_essential=() existing_exclude=()
    read_package_file "$packages_dir/arch-essential.txt" existing_essential
    read_package_file "$packages_dir/arch-exclude.txt" existing_exclude

    local -A essential_set=() exclude_set=() assigned=()
    local pkg

    for pkg in "${ESSENTIAL_PACKAGES[@]}" "${existing_essential[@]}"; do
        essential_set[$pkg]=1
    done

    for pkg in "${existing_exclude[@]}"; do
        exclude_set[$pkg]=1
    done

    for pkg in "${native_packages[@]}" "${foreign_packages[@]}"; do
        if is_default_excluded_pkg "$pkg"; then
            exclude_set[$pkg]=1
        fi
    done

    local -a essential_packages=() desktop_packages=() app_packages=() aur_packages=() machine_local_packages=()
    local -a manual_review_packages=()

    assign_package() {
        local target_pkg="$1"
        local -n _bucket_ref="$2"

        if [[ -n "${assigned[$target_pkg]+x}" || -n "${exclude_set[$target_pkg]+x}" ]]; then
            return 0
        fi
        assigned[$target_pkg]=1
        _bucket_ref+=("$target_pkg")
    }

    for pkg in "${native_packages[@]}"; do
        if is_machine_local_pkg "$pkg"; then
            assign_package "$pkg" machine_local_packages
            continue
        fi
        if is_essential_pkg "$pkg" essential_set; then
            assign_package "$pkg" essential_packages
            continue
        fi
        if is_desktop_pkg "$pkg"; then
            assign_package "$pkg" desktop_packages
            continue
        fi
        if is_app_pkg "$pkg"; then
            assign_package "$pkg" app_packages
            continue
        fi
        if [[ -z "${assigned[$pkg]+x}" && -z "${exclude_set[$pkg]+x}" ]]; then
            assign_package "$pkg" app_packages
            manual_review_packages+=("$pkg")
        fi
    done

    for pkg in "${foreign_packages[@]}"; do
        if is_machine_local_pkg "$pkg"; then
            assign_package "$pkg" machine_local_packages
            continue
        fi
        if is_essential_pkg "$pkg" essential_set; then
            assign_package "$pkg" essential_packages
            continue
        fi
        assign_package "$pkg" aur_packages
    done

    for pkg in "${ESSENTIAL_PACKAGES[@]}" "${existing_essential[@]}"; do
        assign_package "$pkg" essential_packages
    done

    local -a exclude_packages=()
    for pkg in "${!exclude_set[@]}"; do
        exclude_packages+=("$pkg")
    done

    write_package_file "$packages_dir/arch-essential.txt" \
        "# Installer-required and core shell/desktop packages." \
        "${essential_packages[@]}"

    write_package_file "$packages_dir/arch-desktop.txt" \
        "# Desktop environment, fonts, portals, Bluetooth, and related packages." \
        "${desktop_packages[@]}"

    write_package_file "$packages_dir/arch-apps.txt" \
        "# User applications and tools from official repositories." \
        "${app_packages[@]}"

    write_package_file "$packages_dir/arch-aur.txt" \
        "# AUR and foreign packages (non machine-local)." \
        "${aur_packages[@]}"

    write_package_file "$packages_dir/arch-machine-local.txt" \
        "# Kernel, firmware, boot, GPU, audio stack, and other machine-specific packages." \
        "${machine_local_packages[@]}"

    write_package_file "$packages_dir/arch-exclude.txt" \
        "# Packages excluded from install/export automation." \
        "${exclude_packages[@]}"

    sort_packages manual_review_packages
    dedupe_packages manual_review_packages

    echo "Package export complete:"
    echo "  arch-essential.txt:      $(wc -l <"$packages_dir/arch-essential.txt" | tr -d ' ') lines"
    echo "  arch-desktop.txt:        $(wc -l <"$packages_dir/arch-desktop.txt" | tr -d ' ') lines"
    echo "  arch-apps.txt:           $(wc -l <"$packages_dir/arch-apps.txt" | tr -d ' ') lines"
    echo "  arch-aur.txt:            $(wc -l <"$packages_dir/arch-aur.txt" | tr -d ' ') lines"
    echo "  arch-machine-local.txt:  $(wc -l <"$packages_dir/arch-machine-local.txt" | tr -d ' ') lines"
    echo "  arch-exclude.txt:        $(wc -l <"$packages_dir/arch-exclude.txt" | tr -d ' ') lines"
    echo "  machine-local packages:  ${#machine_local_packages[@]}"
    echo "  manual review suggested: ${#manual_review_packages[@]}"
    if ((${#manual_review_packages[@]} > 0)); then
        echo "  review candidates:"
        printf '    %s\n' "${manual_review_packages[@]}"
    fi
}

# Backward-compatible entrypoint used by install.sh.
install_packages_arch() {
    local dry_run="${1:-false}"
    local assume_yes="${2:-false}"
    local include_machine_local="${3:-false}"
    local repo_root="${4:-}"

    if [[ -z "$repo_root" ]]; then
        repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
    fi

    install_package_files "$dry_run" "$assume_yes" "$include_machine_local" "$repo_root"
}

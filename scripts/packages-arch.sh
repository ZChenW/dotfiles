#!/usr/bin/env bash
# Arch Linux package manifest helpers for dotfiles.
# shellcheck disable=SC2034,SC2178

set -euo pipefail

DOTFILES_UI_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ui.sh
source "$DOTFILES_UI_SCRIPT_DIR/ui.sh"

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

# Populates INSTALLED_NAMES and PROVIDES_INDEX from the local pacman DB.
# INSTALLED_NAMES = exact package names only.
# PROVIDES_INDEX = exact names + Provides targets.
build_installed_package_index() {
    declare -gA INSTALLED_NAMES=()
    declare -gA PROVIDES_INDEX=()
    local kind value

    while IFS=' ' read -r kind value; do
        [[ -n "$value" ]] || continue
        case "$kind" in
            N)
                INSTALLED_NAMES["$value"]=1
                PROVIDES_INDEX["$value"]=1
                ;;
            P)
                PROVIDES_INDEX["${value%%=*}"]=1
                ;;
        esac
    done < <(
        awk '
            FNR == 1 { section = "" }
            /^%/ { section = $0; next }
            /^$/ { section = ""; next }
            section == "%NAME%" { print "N", $0 }
            section == "%PROVIDES%" { print "P", $0 }
        ' /var/lib/pacman/local/*/desc 2>/dev/null || true
    )
}

package_already_satisfied() {
    local pkg="$1"
    if [[ -z "${PROVIDES_INDEX+x}" || ${#PROVIDES_INDEX[@]} -eq 0 ]]; then
        build_installed_package_index
    fi
    [[ -n "${PROVIDES_INDEX[$pkg]+x}" ]]
}

package_installed_exactly() {
    local pkg="$1"
    if [[ -z "${INSTALLED_NAMES+x}" || ${#INSTALLED_NAMES[@]} -eq 0 ]]; then
        build_installed_package_index
    fi
    [[ -n "${INSTALLED_NAMES[$pkg]+x}" ]]
}

filter_satisfied_packages() {
    local -n _packages_ref="$1"
    local -a filtered=()
    local pkg

    build_installed_package_index

    for pkg in "${_packages_ref[@]}"; do
        if package_already_satisfied "$pkg"; then
            debug_log "skip already satisfied: $pkg"
            continue
        fi
        filtered+=("$pkg")
    done

    _packages_ref=("${filtered[@]}")
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
    [[ "$pkg" =~ ^(cava|chafa|swappy|hyprpicker|awww|swaybg|swaylock|wlsunset)$ ]] && return 0
    [[ "$pkg" =~ ^(thunar|dolphin|gwenview|ark|mission-center|pavucontrol|btop)$ ]] && return 0
    [[ "$pkg" =~ ^(gnome-clocks|gnome-calendar|ddcutil)$ ]] && return 0
    [[ "$pkg" =~ ^power-profiles ]] && return 0
    [[ "$pkg" =~ ^(polkit-gnome|packagekit|network-manager-applet) ]] && return 0
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

# ── AUR package resolution ──────────────────────────────────────────────
# Queries the AUR RPC to resolve provider ambiguity and inner conflicts
# before handing the list to paru/yay.  This avoids the interactive prompts
# that break --noconfirm mode.

# Query the AUR RPC search endpoint.  Writes raw JSON to stdout.
# Returns 0 on success, 1 when curl is missing or the request fails.
_aur_rpc_search() {
    local query="$1"
    local response
    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi
    response=$(curl -sS --connect-timeout 5 --max-time 10 \
        "https://aur.archlinux.org/rpc/v5/search/${query}" 2>/dev/null) || return 1
    if [[ -z "$response" ]]; then
        return 1
    fi
    printf '%s\n' "$response"
    return 0
}

# Query the AUR RPC info endpoint for a single package.  Writes raw JSON to stdout.
_aur_rpc_info() {
    local pkg="$1"
    local response
    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi
    response=$(curl -sS --connect-timeout 5 --max-time 10 \
        "https://aur.archlinux.org/rpc/v5/info/${pkg}" 2>/dev/null) || return 1
    if [[ -z "$response" ]]; then
        return 1
    fi
    printf '%s\n' "$response"
    return 0
}

# Extract "Name" values from AUR RPC JSON on stdin (one per line).
_aur_parse_names() {
    grep -oP '"Name":"\K[^"]+'
}

# Extract "Provides" entries from AUR RPC info JSON on stdin.
# Produces one package name per line, stripping version constraints.
_aur_parse_provides() {
    grep -oP '"Provides":\[\K[^\]]*' | grep -oP '(?<=")[^",]+(?=")' || true
}

# Resolve a single AUR package name to its canonical form.
# When multiple providers exist (e.g. wechat → wechat / wechat-appimage),
# the first exact-name match from the AUR is selected so the AUR helper
# never sees an ambiguous name.
resolve_aur_package_name() {
    local pkg="$1"
    local response names first_match

    response=$(_aur_rpc_search "$pkg") || {
        printf '%s\n' "$pkg"
        return 0
    }

    names=$(printf '%s\n' "$response" | _aur_parse_names)

    if [[ -z "$names" ]]; then
        printf '%s\n' "$pkg"
        return 0
    fi

    # Prefer the exact name match (handles wechat vs wechat-appimage, etc.)
    first_match=$(printf '%s\n' "$names" | grep -Fx "$pkg" | head -1)
    if [[ -n "$first_match" ]]; then
        printf '%s\n' "$first_match"
        return 0
    fi

    # Fall back to the first search result.
    printf '%s\n' "$names" | head -1
}

# Get the Provides list for an AUR package (may be empty).
_aur_get_provides() {
    local pkg="$1"
    local response

    response=$(_aur_rpc_info "$pkg") || return 1
    printf '%s\n' "$response" | _aur_parse_provides
}

# Separate packages that declare Provides into a pre-install batch.
# Installing them first satisfies dependency resolution for the main
# batch and avoids inner conflicts when --noconfirm is in use.
# Example: wps-office-cn provides wps-office; if a dependency later
# pulls in wps-office, the resolver sees it as already satisfied and
# does not flag a conflict.
resolve_aur_conflicts() {
    local -n _pkg_list_ref="$1"
    local -n _pre_install_ref="$2"
    local -a remaining=()
    local pkg

    _pre_install_ref=()
    for pkg in "${_pkg_list_ref[@]}"; do
        local provides
        provides=$(_aur_get_provides "$pkg") || { remaining+=("$pkg"); continue; }
        if [[ -n "$provides" ]]; then
            debug_log "aur provider: $pkg — pre-installing"
            _pre_install_ref+=("$pkg")
        else
            remaining+=("$pkg")
        fi
    done

    _pkg_list_ref=("${remaining[@]}")
}

# ── Batch install ───────────────────────────────────────────────────────

install_packages_batch() {
    local dry_run="$1"
    local assume_yes="$2"
    local helper="$3"
    shift 3
    local -a packages=("$@")

    filter_satisfied_packages packages

    if ((${#packages[@]} == 0)); then
        return 0
    fi

    if [[ "$helper" == pacman ]]; then
        if [[ "$dry_run" == true ]]; then
            verbose_log "pacman   ${#packages[@]} packages planned"
            debug_log "[dry-run] sudo pacman -S --needed ${packages[*]}"
            return 0
        fi

        local -a pacman_args=(pacman -S --needed)
        if [[ "$assume_yes" == true ]]; then
            pacman_args+=(--noconfirm)
        fi
        verbose_log "pacman   install started (${#packages[@]} packages)"
        debug_log "sudo ${pacman_args[*]} ${packages[*]}"
        if sudo "${pacman_args[@]}" "${packages[@]}"; then
            ui_ok "Pacman install complete"
        else
            ui_fail "Pacman install failed"
            return 1
        fi
        return 0
    fi

    if [[ "$dry_run" == true ]]; then
        verbose_log "$helper     ${#packages[@]} packages planned"
        debug_log "[dry-run] $helper -S --needed ${packages[*]}"
        return 0
    fi

    # ── Pre-resolve AUR package names ────────────────────────────────
    # Resolve each name through the AUR RPC so that packages with
    # multiple providers (e.g. wechat, ttf-wps-fonts) are unambiguous
    # before we hand them to the AUR helper.
    local -a resolved_packages=()
    local pkg
    for pkg in "${packages[@]}"; do
        local resolved
        resolved=$(resolve_aur_package_name "$pkg")
        if [[ "$resolved" != "$pkg" ]]; then
            debug_log "aur resolved: $pkg → $resolved"
        fi
        resolved_packages+=("$resolved")
    done
    packages=("${resolved_packages[@]}")
    dedupe_packages packages

    # ── Detect and separate conflicting packages ─────────────────────
    # Some packages Provide the name of another package in the list
    # (e.g. wps-office-cn provides wps-office).  Installing the provider
    # first satisfies the dependency so the main batch does not pull in
    # the conflicting package.
    local -a pre_install_packages=()
    resolve_aur_conflicts packages pre_install_packages

    local -a aur_args=(-S --needed)
    if [[ "$assume_yes" == true ]]; then
        aur_args+=(--noconfirm)
    fi

    # Phase 1 — pre-install packages that provide dependency names.
    if ((${#pre_install_packages[@]} > 0)); then
        verbose_log "$helper     pre-install providers (${#pre_install_packages[@]} packages)"
        debug_log "$helper ${aur_args[*]} ${pre_install_packages[*]}"
        if ! "$helper" "${aur_args[@]}" "${pre_install_packages[@]}"; then
            ui_fail "AUR pre-install failed"
            return 1
        fi
        ui_ok "AUR pre-install complete"
    fi

    # Phase 2 — main batch (dependencies satisfied by pre-installed packages).
    if ((${#packages[@]} == 0)); then
        return 0
    fi

    verbose_log "$helper     install started (${#packages[@]} packages)"
    debug_log "$helper ${aur_args[*]} ${packages[*]}"
    if "$helper" "${aur_args[@]}" "${packages[@]}"; then
        ui_ok "AUR install complete"
    else
        ui_fail "AUR install failed"
        return 1
    fi
}

find_aur_helper() {
    if command -v paru >/dev/null 2>&1; then
        printf '%s\n' paru
    elif command -v yay >/dev/null 2>&1; then
        printf '%s\n' yay
    fi
}

package_prompt_yes_no() {
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
            y | yes)
                return 0
                ;;
            n | no)
                return 1
                ;;
            *)
                ui_warn "Please answer y or n."
                ;;
        esac
    done
}

bootstrap_paru() {
    local dry_run="$1"
    local assume_yes="$2"

    if [[ "$dry_run" == true ]]; then
        ui_warn "AUR helper bootstrap" "paru planned"
        verbose_log "bootstrap paru from AUR"
        debug_log "[dry-run] bootstrap AUR helper: paru"
        debug_log "[dry-run] sudo pacman -S --needed git base-devel"
        debug_log "[dry-run] git clone https://aur.archlinux.org/paru.git /tmp/dotfiles-paru-bootstrap/paru"
        debug_log "[dry-run] cd /tmp/dotfiles-paru-bootstrap/paru && makepkg -si --needed"
        return 0
    fi

    if [[ "$assume_yes" != true ]]; then
        if [[ ! -t 0 || ! -t 1 ]]; then
            ui_error "AUR packages require paru or yay, and paru bootstrap needs an interactive TTY or --yes."
            return 1
        fi
        if ! package_prompt_yes_no "No paru/yay found. Bootstrap paru from AUR now?" y; then
            ui_error "AUR packages require paru or yay."
            return 1
        fi
    fi

    local -a pacman_args=(pacman -S --needed git base-devel)
    local -a makepkg_args=(-si --needed)
    if [[ "$assume_yes" == true ]]; then
        pacman_args+=(--noconfirm)
        makepkg_args+=(--noconfirm)
    fi

    local build_root
    build_root="$(mktemp -d)"
    (
        set -euo pipefail
        trap 'rm -rf "$build_root"' EXIT
        sudo "${pacman_args[@]}"
        git clone https://aur.archlinux.org/paru.git "$build_root/paru"
        cd "$build_root/paru"
        makepkg "${makepkg_args[@]}"
    )

    if ! command -v paru >/dev/null 2>&1; then
        ui_error "paru bootstrap completed but paru is still not on PATH."
        return 1
    fi
}

install_package_files() {
    local dry_run="$1"
    local assume_yes="$2"
    local include_machine_local="$3"
    local include_aur="$4"
    local repo_root="$5"
    local packages_dir="$repo_root/packages"

    local -a package_files=(
        "$packages_dir/arch-essential.txt"
        "$packages_dir/arch-desktop.txt"
        "$packages_dir/arch-apps.txt"
        "$packages_dir/arch-aur.txt"
    )

    local -a machine_local_packages=()
    read_package_file "$packages_dir/arch-machine-local.txt" machine_local_packages

    if [[ "$include_machine_local" == true ]]; then
        package_files+=("$packages_dir/arch-machine-local.txt")
    else
        if ((${#machine_local_packages[@]} > 0)); then
            debug_log "Machine-local packages skipped: ${machine_local_packages[*]}"
        fi
    fi

    local -a exclude_packages=() all_packages=() official_packages=() aur_packages=()
    read_package_file "$packages_dir/arch-exclude.txt" exclude_packages
    collect_packages_from_files all_packages "${package_files[@]}"
    filter_excluded_packages all_packages exclude_packages
    split_official_and_aur official_packages aur_packages "${all_packages[@]}"

    if [[ "$dry_run" == true ]]; then
        ui_ok "Pacman packages" "${#official_packages[@]} packages"
        ui_ok "AUR packages" "${#aur_packages[@]} packages"
        if [[ "$include_machine_local" != true && ${#machine_local_packages[@]} -gt 0 ]]; then
            ui_warn "Machine-local skipped" "use --full-packages"
        fi
    else
        ui_ok "Pacman packages" "${#official_packages[@]} packages"
        ui_ok "AUR packages" "${#aur_packages[@]} packages"
    fi

    install_packages_batch "$dry_run" "$assume_yes" pacman "${official_packages[@]}"

    if [[ "$include_aur" != true ]]; then
        if ((${#aur_packages[@]} > 0)); then
            ui_warn "AUR packages skipped" "${#aur_packages[@]} packages"
            debug_log "AUR packages skipped: ${aur_packages[*]}"
        fi
        return 0
    fi

    if ((${#aur_packages[@]} == 0)); then
        return 0
    fi

    local aur_helper=""
    aur_helper="$(find_aur_helper)"

    if [[ -z "$aur_helper" ]]; then
        bootstrap_paru "$dry_run" "$assume_yes"
        aur_helper=paru
    fi

    install_packages_batch "$dry_run" "$assume_yes" "$aur_helper" "${aur_packages[@]}"
}

package_manifest_line_count() {
    local file="$1"
    if [[ -f "$file" ]]; then
        wc -l <"$file" | tr -d ' '
    else
        printf '0\n'
    fi
}

export_package_snapshot() {
    local repo_root="$1"
    local packages_dir="$repo_root/packages"
    mkdir -p "$packages_dir"

    build_installed_package_index

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
        # Keep virtual essential names only when nothing installed already provides them.
        # Example: waybar-cava-git Provides waybar — do not also pin official waybar.
        if package_already_satisfied "$pkg" && ! package_installed_exactly "$pkg"; then
            debug_log "essential provided by installed package: $pkg"
            continue
        fi
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

    ui_ok "Export complete"
    ui_table_header "manifest" "lines"
    ui_table_row "arch-essential.txt" "$(package_manifest_line_count "$packages_dir/arch-essential.txt")"
    ui_table_row "arch-desktop.txt" "$(package_manifest_line_count "$packages_dir/arch-desktop.txt")"
    ui_table_row "arch-apps.txt" "$(package_manifest_line_count "$packages_dir/arch-apps.txt")"
    ui_table_row "arch-aur.txt" "$(package_manifest_line_count "$packages_dir/arch-aur.txt")"
    ui_table_row "arch-machine-local.txt" "$(package_manifest_line_count "$packages_dir/arch-machine-local.txt")"
    ui_table_row "arch-exclude.txt" "$(package_manifest_line_count "$packages_dir/arch-exclude.txt")"
    ui_warn "Machine-local packages" "${#machine_local_packages[@]} packages"
    ui_warn "Manual review suggested" "${#manual_review_packages[@]} packages"
    if ((${#manual_review_packages[@]} > 0)); then
        ui_review_candidates "${manual_review_packages[@]}"
    fi
}

# Backward-compatible entrypoint used by install.sh.
install_packages_arch() {
    local dry_run="${1:-false}"
    local assume_yes="${2:-false}"
    local include_machine_local="${3:-false}"
    local include_aur="${4:-true}"
    local repo_root="${5:-}"

    if [[ -z "$repo_root" ]]; then
        repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
    fi

    install_package_files "$dry_run" "$assume_yes" "$include_machine_local" "$include_aur" "$repo_root"
}

#!/usr/bin/env bash
# System doctor / diagnostics for the dotfiles installer.

set -euo pipefail

DOTFILES_UI_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ui.sh
source "$DOTFILES_UI_SCRIPT_DIR/ui.sh"

DOCTOR_ERRORS=0
DOCTOR_WARNS=0

doctor_ok() {
    ui_ok "$@"
}

doctor_warn() {
    ((++DOCTOR_WARNS)) || true
    ui_warn "$@"
}

doctor_err() {
    ((++DOCTOR_ERRORS)) || true
    ui_fail "$@"
}

doctor_check_os() {
    if [[ ! -f /etc/os-release ]]; then
        doctor_err "OS" "/etc/os-release missing"
        return 0
    fi
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "${ID:-}" == "arch" ]]; then
        doctor_ok "OS" "Arch Linux (${NAME:-Arch})"
    else
        doctor_err "OS" "unsupported '${ID:-unknown}' (Arch only)"
    fi
}

doctor_check_tools() {
    local cmd
    for cmd in bash sudo pacman rsync install git tar; do
        if command -v "$cmd" >/dev/null 2>&1; then
            doctor_ok "Tool" "$cmd"
        else
            doctor_err "Tool" "$cmd missing"
        fi
    done
}

doctor_check_aur_helper() {
    if command -v paru >/dev/null 2>&1; then
        doctor_ok "AUR helper" "paru"
    elif command -v yay >/dev/null 2>&1; then
        doctor_ok "AUR helper" "yay"
    else
        doctor_warn "AUR helper" "neither paru nor yay (installer can bootstrap paru)"
    fi
}

doctor_check_shell() {
    local login_shell
    login_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || true)"
    if [[ "$login_shell" == *zsh ]]; then
        doctor_ok "Login shell" "$login_shell"
    elif [[ -n "$login_shell" ]]; then
        doctor_warn "Login shell" "$login_shell (expected zsh)"
    else
        doctor_warn "Login shell" "could not detect"
    fi

    if [[ -f "$HOME/.zshrc.local" ]]; then
        if [[ -L "$HOME/.zshrc.local" ]]; then
            doctor_warn "Private config" "\$HOME/.zshrc.local is a symlink (install replaces with a real file)"
        else
            doctor_ok "Private config" "\$HOME/.zshrc.local present"
        fi
    else
        doctor_warn "Private config" "\$HOME/.zshrc.local missing (created from template on shell install)"
    fi
}

doctor_check_memory() {
    local proc_root="${DOTFILES_PROC_ROOT:-/proc}"
    local sys_block_root="${DOTFILES_SYS_BLOCK_ROOT:-/sys/block}"
    local meminfo="$proc_root/meminfo"
    local mem_total_kb swap_total_kb
    local memory_threshold_kb=$((8 * 1024 * 1024))
    local has_zram=false

    [[ -r "$meminfo" ]] || return 0
    mem_total_kb="$(awk '/^MemTotal:/ { print $2; exit }' "$meminfo")"
    swap_total_kb="$(awk '/^SwapTotal:/ { print $2; exit }' "$meminfo")"
    [[ "$mem_total_kb" =~ ^[0-9]+$ ]] || return 0
    [[ "$swap_total_kb" =~ ^[0-9]+$ ]] || swap_total_kb=0

    if compgen -G "$sys_block_root/zram*" >/dev/null; then
        has_zram=true
    fi

    if ((mem_total_kb <= memory_threshold_kb && swap_total_kb == 0)) \
        && [[ "$has_zram" != true ]]; then
        doctor_warn "Memory pressure" \
            "8 GB or less without swap/zram; Firefox, VS Code, and Codex may exhaust memory"
    else
        doctor_ok "Memory" "swap/zram or more than 8 GB available"
    fi
}

doctor_check_desktop_tools() {
    local cmd
    local desktop_shell_profile="${DESKTOP_SHELL_PROFILE:-waybar}"
    local -a commands=(zsh niri kitty fastfetch)
    if [[ "$desktop_shell_profile" == waybar || "$desktop_shell_profile" == dual ]]; then
        commands+=(waybar)
    fi
    if [[ "$desktop_shell_profile" == quickshell || "$desktop_shell_profile" == dual ]]; then
        commands+=(quickshell)
    fi

    for cmd in "${commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            doctor_ok "Desktop tool" "$cmd"
        else
            doctor_warn "Desktop tool" "$cmd not installed"
        fi
    done
}

doctor_check_runtime_deps() {
    local cmd path
    local desktop_shell_profile="${DESKTOP_SHELL_PROFILE:-waybar}"
    local -a runtime_paths=(
        "$HOME/.config/niri/scripts/swayidle.sh"
        "$HOME/.local/bin/toggle-wlsunset"
        "$HOME/.local/bin/desktop-shell"
    )
    for cmd in brightnessctl swayidle clipse mako fuzzel grim slurp wl-copy kanshi wlsunset ddcutil; do
        if command -v "$cmd" >/dev/null 2>&1; then
            doctor_ok "Runtime dep" "$cmd"
        else
            doctor_warn "Runtime dep" "$cmd missing (referenced by niri/desktop)"
        fi
    done

    if [[ "$desktop_shell_profile" == waybar || "$desktop_shell_profile" == dual ]]; then
        runtime_paths+=(
            "$HOME/.config/waybar/scripts/matugen-select-type.sh"
            "$HOME/.local/bin/wcr-post-apply-waybar.sh"
        )
    fi

    for path in "${runtime_paths[@]}"
    do
        if [[ -x "$path" ]]; then
            doctor_ok "Runtime script" "${path/#$HOME/~}"
        elif [[ -e "$path" ]]; then
            doctor_warn "Runtime script" "${path/#$HOME/~} exists but is not executable"
        else
            doctor_warn "Runtime script" "${path/#$HOME/~} missing"
        fi
    done
}

doctor_check_backups() {
    local backup_base="${DOTFILES_BACKUP_BASE:-$HOME/.dotfiles-backups}"
    local -a rollbacks=()

    if [[ ! -d "$backup_base" ]]; then
        doctor_warn "Backups" "no backup directory at $backup_base"
        return 0
    fi

    mapfile -t rollbacks < <(find "$backup_base" -mindepth 2 -maxdepth 2 -type f -name rollback.sh 2>/dev/null | sort -r || true)
    if ((${#rollbacks[@]} == 0)); then
        doctor_warn "Backups" "directory exists but no rollback.sh found"
    else
        doctor_ok "Backups" "${#rollbacks[@]} rollback script(s); latest: ${rollbacks[0]}"
    fi
}

doctor_check_managed_paths() {
    local repo_root="$1"
    local path_item display_path required_count=0 present_count=0 symlink_count=0

    # shellcheck source=scripts/sync-configs.sh
    source "$repo_root/scripts/sync-configs.sh"

    while IFS= read -r path_item; do
        [[ -n "$path_item" ]] || continue
        ((++required_count)) || true
        display_path="$path_item"
        if [[ "$display_path" == "$HOME"* ]]; then
            display_path="~${display_path#"$HOME"}"
        fi
        if [[ -L "$path_item" ]]; then
            ((++symlink_count)) || true
            doctor_err "Managed path" "$display_path is a symlink"
        elif [[ -e "$path_item" ]]; then
            ((++present_count)) || true
        else
            doctor_warn "Managed path" "$display_path missing"
        fi
    done < <(list_managed_dest_paths "$repo_root")

    doctor_ok "Managed paths" "$present_count/$required_count present ($symlink_count symlink issues)"
}

run_doctor() {
    local repo_root="$1"
    DOCTOR_ERRORS=0
    DOCTOR_WARNS=0

    ui_section "Doctor: environment"
    doctor_check_os
    doctor_check_tools
    doctor_check_aur_helper
    doctor_check_shell
    doctor_check_memory

    ui_section "Doctor: desktop tools"
    doctor_check_desktop_tools
    doctor_check_runtime_deps

    ui_section "Doctor: managed configs"
    doctor_check_managed_paths "$repo_root"

    ui_section "Doctor: backups"
    doctor_check_backups

    ui_section "Doctor: config validation"
    # shellcheck source=scripts/verify.sh
    source "$repo_root/scripts/verify.sh"
    if ! verify_installation false shell desktop terminal apps editors local-bin media; then
        ((++DOCTOR_ERRORS)) || true
        doctor_warn "Verification" "one or more checks failed (see above)"
    else
        doctor_ok "Verification" "selected-group checks passed or skipped"
    fi

    echo
    if ((DOCTOR_ERRORS > 0)); then
        ui_result_box "Doctor" \
            "fail:${DOCTOR_ERRORS} error(s)" \
            "warn:${DOCTOR_WARNS} warning(s)"
        return 1
    fi

    if ((DOCTOR_WARNS > 0)); then
        ui_result_box "Doctor" \
            "ok:No hard errors" \
            "warn:${DOCTOR_WARNS} warning(s)"
        return 0
    fi

    ui_result_box "Doctor" "ok:All checks passed"
    return 0
}

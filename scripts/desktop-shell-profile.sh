#!/usr/bin/env bash
# Install and persist the selected Waybar/QuickShell desktop profile.
# shellcheck disable=SC2034

set -euo pipefail

desktop_shell_profile_has_quickshell() {
    [[ "$1" == quickshell || "$1" == dual ]]
}

desktop_shell_profile_state_file() {
    printf '%s/dotfiles/desktop-shell-profile\n' \
        "${XDG_STATE_HOME:-$HOME/.local/state}"
}

load_saved_desktop_shell_profile() {
    local state_file profile
    state_file="$(desktop_shell_profile_state_file)"
    [[ -f "$state_file" ]] || return 1

    IFS= read -r profile <"$state_file" || true
    case "$profile" in
        waybar | quickshell | dual)
            printf '%s\n' "$profile"
            ;;
        *)
            return 1
            ;;
    esac
}

save_desktop_shell_profile() {
    local profile="$1"
    local state_file state_dir temporary
    state_file="$(desktop_shell_profile_state_file)"
    state_dir="$(dirname -- "$state_file")"

    mkdir -p "$state_dir"
    temporary="$(mktemp "$state_dir/.desktop-shell-profile.XXXXXX")"
    printf '%s\n' "$profile" >"$temporary"
    mv -f "$temporary" "$state_file"
}

prompt_desktop_shell_profile() {
    local saved_profile default_choice choice
    saved_profile="$(load_saved_desktop_shell_profile || true)"
    case "$saved_profile" in
        quickshell) default_choice=2 ;;
        dual) default_choice=3 ;;
        *) default_choice=1 ;;
    esac

    ui_section "Desktop shell"
    echo "  1) Waybar"
    echo "  2) QuickShell"
    echo "  3) Waybar + QuickShell (switch with desktop-shell)"
    read -r -p "$(ui_prompt "Choice" "$default_choice")" choice
    case "${choice:-$default_choice}" in
        1) DESKTOP_SHELL_PROFILE=waybar ;;
        2) DESKTOP_SHELL_PROFILE=quickshell ;;
        3) DESKTOP_SHELL_PROFILE=dual ;;
        *)
            ui_error "Invalid desktop shell choice: $choice"
            return 1
            ;;
    esac
}

load_quickshell_source_lock() {
    local repo_root="$1"
    local lock_file="$repo_root/packages/quickshell-source.conf"

    if [[ ! -f "$lock_file" ]]; then
        ui_error "QuickShell source lock is missing: $lock_file"
        return 1
    fi

    QUICKSHELL_REPOSITORY=""
    QUICKSHELL_REF=""
    # shellcheck source=/dev/null
    source "$lock_file"

    if [[ "$QUICKSHELL_REPOSITORY" != https://github.com/*/*.git ]]; then
        ui_error "QuickShell repository URL is invalid"
        return 1
    fi
    if [[ ! "$QUICKSHELL_REF" =~ ^[0-9a-f]{40}$ ]]; then
        ui_error "QuickShell ref must be a full commit SHA"
        return 1
    fi
}

install_desktop_shell_profile() {
    local repo_root="$1"
    local profile="$2"
    local dry_run="${3:-false}"
    local destination="${QUICKSHELL_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/clavis}"
    local prefix="${QUICKSHELL_PREFIX:-$HOME/.local}"
    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
    local receipt_file="$state_dir/quickshell-install-ref"
    local managed_root_file="$state_dir/quickshell-managed-root"
    local origin_url dirty_state checked_out_ref installed_ref="" managed_root=""

    if ! desktop_shell_profile_has_quickshell "$profile"; then
        ui_warn "QuickShell" "skipped (Waybar profile)"
        return 0
    fi

    load_quickshell_source_lock "$repo_root"
    echo "QuickShell source: $QUICKSHELL_REPOSITORY"
    echo "QuickShell ref: $QUICKSHELL_REF"
    echo "QuickShell destination: $destination"

    if [[ "$dry_run" == true ]]; then
        return 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        ui_error "git is required to install QuickShell"
        return 1
    fi

    if [[ -L "$destination" || (-e "$destination" && ! -d "$destination/.git") ]]; then
        ui_error "QuickShell destination is not a managed Git checkout: $destination"
        return 1
    fi

    if [[ ! -d "$destination/.git" ]]; then
        mkdir -p "$(dirname -- "$destination")"
        mkdir -p "$state_dir"
        printf '%s\n' "$destination" >"$managed_root_file.tmp"
        mv -f "$managed_root_file.tmp" "$managed_root_file"
        : >"$receipt_file"
        git init "$destination"
        git -C "$destination" remote add origin "$QUICKSHELL_REPOSITORY"
    else
        if [[ -f "$managed_root_file" ]]; then
            IFS= read -r managed_root <"$managed_root_file" || true
        fi
        if [[ "$managed_root" != "$destination" ]]; then
            ui_error "QuickShell checkout is not managed by dotfiles: $destination"
            return 1
        fi

        origin_url="$(git -C "$destination" config --get remote.origin.url || true)"
        if [[ "$origin_url" != "$QUICKSHELL_REPOSITORY" ]]; then
            ui_error "QuickShell checkout has an unexpected origin: ${origin_url:-missing}"
            return 1
        fi

        dirty_state="$(git -C "$destination" status --porcelain)"
        if [[ -n "$dirty_state" ]]; then
            ui_error "QuickShell checkout has local changes: $destination"
            return 1
        fi
    fi

    checked_out_ref="$(git -C "$destination" rev-parse HEAD 2>/dev/null || true)"
    if [[ -f "$receipt_file" ]]; then
        IFS= read -r installed_ref <"$receipt_file" || true
    fi
    if [[ -n "$installed_ref" && "$checked_out_ref" != "$installed_ref" ]]; then
        ui_error "QuickShell checkout differs from the last installed commit"
        return 1
    fi
    if [[ "$checked_out_ref" == "$QUICKSHELL_REF" \
        && "$installed_ref" == "$QUICKSHELL_REF" \
        && -f "$destination/shell.qml" \
        && -x "$prefix/bin/key" \
        && -d "$prefix/lib/qt6/qml/Clavis" \
        && -d "$prefix/lib/qt6/qml/M3Shapes" ]]; then
        ui_success "QuickShell" "already current"
        return 0
    fi

    git -C "$destination" fetch --depth=1 origin "$QUICKSHELL_REF"
    git -C "$destination" checkout --detach "$QUICKSHELL_REF"
    checked_out_ref="$(git -C "$destination" rev-parse HEAD)"
    if [[ "$checked_out_ref" != "$QUICKSHELL_REF" ]]; then
        ui_error "QuickShell checkout did not resolve to the pinned commit"
        return 1
    fi

    if [[ ! -x "$destination/install.sh" ]]; then
        ui_error "Pinned QuickShell source does not provide an executable install.sh"
        return 1
    fi

    "$destination/install.sh" --prefix "$prefix"
    mkdir -p "$state_dir"
    printf '%s\n' "$QUICKSHELL_REF" >"$receipt_file.tmp"
    mv -f "$receipt_file.tmp" "$receipt_file"
    ui_success "QuickShell" "installed from pinned source"
}

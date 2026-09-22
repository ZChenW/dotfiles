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
    local step="${1:-}"
    local total="${2:-}"
    local saved_profile default_choice choice
    saved_profile="$(load_saved_desktop_shell_profile || true)"
    case "${DESKTOP_SHELL_PROFILE:-$saved_profile}" in
        quickshell) default_choice=2 ;;
        dual) default_choice=3 ;;
        *) default_choice=1 ;;
    esac

    if [[ -n "$step" && -n "$total" ]]; then
        ui_stage "$step" "$total" "Desktop shell"
    else
        ui_section "Desktop shell"
    fi
    ui_menu "Select" "$default_choice" \
        "Waybar|Use the current Waybar desktop shell" \
        "QuickShell|Use the pinned Clavis QuickShell" \
        "Waybar + QuickShell|Switch at any time with desktop-shell"
    choice="$UI_MENU_CHOICE"
    case "$choice" in
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

validate_quickshell_local_source() {
    local source="${1:-${QUICKSHELL_LOCAL_SOURCE:-}}"

    if [[ -z "$source" ]]; then
        ui_error "QUICKSHELL_LOCAL_SOURCE is empty"
        return 1
    fi
    if [[ "$source" != /* ]]; then
        ui_error "QUICKSHELL_LOCAL_SOURCE must be an absolute directory"
        return 1
    fi
    if [[ ! -d "$source" ]]; then
        ui_error "QUICKSHELL_LOCAL_SOURCE is not a directory: $source"
        return 1
    fi
    if [[ ! -f "$source/shell.qml" ]]; then
        ui_error "QUICKSHELL_LOCAL_SOURCE is missing shell.qml: $source"
        return 1
    fi
    if [[ ! -f "$source/CMakeLists.txt" ]]; then
        ui_error "QUICKSHELL_LOCAL_SOURCE is missing CMakeLists.txt: $source"
        return 1
    fi
}

quickshell_m3shapes_available() {
    local root
    for root in \
        "${QUICKSHELL_EXTRA_QML_PATH:-}" \
        /usr/lib/qt6/qml \
        /usr/lib/qml \
        "${QUICKSHELL_PREFIX:-$HOME/.local}/lib/qt6/qml"; do
        [[ -d "$root/M3Shapes" ]] && return 0
    done
    return 1
}

report_quickshell_runtime_dependencies() {
    if command -v wallpaper-console-rust >/dev/null 2>&1 \
        && [[ "$(wallpaper-console-rust config-get restore_on_login off 2>/dev/null)" == on ]]; then
        ui_warn "Wallpaper restore" "WC login restore is enabled; when Clavis/desktop-shell manages restoration, disable WC restore_on_login to avoid duplicate startup restores"
    fi
    local -a missing=()
    local key_bin="${CLAVIS_KEY:-}"

    if [[ -n "$key_bin" ]]; then
        [[ "$key_bin" == /* && "$key_bin" != *$'\n'* && -x "$key_bin" ]] \
            || missing+=("key-cli (absolute executable required: $key_bin)")
    elif ! command -v key >/dev/null 2>&1; then
        missing+=("key-cli (key)")
    fi
    if ! command -v keytop >/dev/null 2>&1; then
        missing+=("keytop")
    fi
    if ! quickshell_m3shapes_available; then
        missing+=("M3Shapes (qt6-m3shapes-git)")
    fi
    if [[ -n "${QUICKSHELL_EXTRA_QML_PATH:-}" ]]; then
        [[ "$QUICKSHELL_EXTRA_QML_PATH" == /* && "$QUICKSHELL_EXTRA_QML_PATH" != *$'\n'* \
            && -d "$QUICKSHELL_EXTRA_QML_PATH" ]] || missing+=("valid extra QML directory")
    fi

    if ((${#missing[@]} > 0)); then
        ui_error "Missing QuickShell runtime dependencies: ${missing[*]}"
        ui_error "Install key-cli, keytop, and M3Shapes separately; this installer does not run sudo"
        return 1
    fi
}

quickshell_local_source_path_excluded() {
    case "$1" in
        build | build/* | Common/generated | Common/generated/* | .qmlls.ini)
            return 0
            ;;
    esac
    return 1
}

quickshell_local_source_manifest() {
    local source="$1"
    local digest

    digest="$(
        cd -- "$source" || exit 1
        {
            if [[ -e .git ]] && command -v git >/dev/null 2>&1; then
                git ls-files -z --cached --others --exclude-standard
            else
                find . -type f ! -path './.git/*' -print0 \
                    | sed -z 's|^\./||'
            fi
        } | while IFS= read -r -d '' path; do
            quickshell_local_source_path_excluded "$path" && continue
            [[ -f "$path" ]] || continue
            printf '%s\0' "$path"
        done | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}'
    )"
    printf '%s\n' "$digest"
}

quickshell_local_source_receipt() {
    local source="$1"
    local git_ref=none
    local dirty_state=clean
    local manifest

    if [[ -e "$source/.git" ]] && command -v git >/dev/null 2>&1; then
        git_ref="$(git -C "$source" rev-parse HEAD 2>/dev/null || printf 'none')"
        if [[ -n "$(git -C "$source" status --porcelain 2>/dev/null || true)" ]]; then
            dirty_state=dirty
        fi
    fi
    manifest="$(quickshell_local_source_manifest "$source")"
    printf 'local-source ref=%s state=%s manifest=%s\n' \
        "$git_ref" "$dirty_state" "$manifest"
}

write_quickshell_config_path_marker() {
    local state_dir="$1"
    local source="$2"
    local marker="$state_dir/quickshell-config-path"

    mkdir -p "$state_dir"
    printf '%s\n' "$source" >"$marker.tmp"
    mv -f "$marker.tmp" "$marker"
}

write_quickshell_runtime_markers() {
    local state_dir="$1" marker value
    mkdir -p "$state_dir"
    for marker in quickshell-key-path quickshell-extra-qml-path; do
        case "$marker" in
            quickshell-key-path) value="${CLAVIS_KEY:-}" ;;
            quickshell-extra-qml-path) value="${QUICKSHELL_EXTRA_QML_PATH:-}" ;;
        esac
        [[ -n "$value" ]] || continue
        [[ "$value" == /* && "$value" != *$'\n'* ]] || return 1
        printf '%s\n' "$value" >"$state_dir/$marker.tmp"
        mv -f "$state_dir/$marker.tmp" "$state_dir/$marker"
    done
}

install_quickshell_local_source() {
    local dry_run="${1:-false}"
    local source state_dir receipt_file config_marker build_dir native_qml config_link
    local expected_receipt installed_ref="" active_path=""
    local cmd

    validate_quickshell_local_source "$QUICKSHELL_LOCAL_SOURCE" || return 1
    source="$(readlink -f -- "$QUICKSHELL_LOCAL_SOURCE")"
    validate_quickshell_local_source "$source" || return 1

    state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
    receipt_file="$state_dir/quickshell-install-ref"
    config_marker="$state_dir/quickshell-config-path"
    build_dir="$source/build"
    native_qml="$build_dir/qml"
    config_link="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/clavis"
    if [[ -e "$config_link" || -L "$config_link" ]]; then
        if [[ ! -L "$config_link" || "$(readlink -f -- "$config_link")" != "$source" ]]; then
            ui_error "Named Clavis config already exists and is not this source: $config_link"
            return 1
        fi
    fi

    echo "QuickShell local source: $source"
    echo "QuickShell native QML path: $native_qml"

    if [[ "$dry_run" == true ]]; then
        return 0
    fi

    for cmd in cmake ninja ctest sha256sum; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            ui_error "$cmd is required to install a local QuickShell CMake source"
            return 1
        fi
    done

    report_quickshell_runtime_dependencies || return 1

    expected_receipt="$(quickshell_local_source_receipt "$source")"
    if [[ -f "$receipt_file" ]]; then
        IFS= read -r installed_ref <"$receipt_file" || true
    fi
    if [[ -f "$config_marker" ]]; then
        IFS= read -r active_path <"$config_marker" || true
    fi
    if [[ "$installed_ref" == "$expected_receipt" \
        && "$active_path" == "$config_link" \
        && -d "$native_qml" ]]; then
        write_quickshell_runtime_markers "$state_dir" || return 1
        ui_success "QuickShell" "already current (local source)"
        return 0
    fi

    # Upstream install.sh is a network package bootstrap. Never invoke it for
    # an existing local CMake source tree.
    # Explicit status checks: callers may invoke this from an `if` test where
    # `set -e` is suppressed for the whole function body.
    cmake -S "$source" -B "$build_dir" -G Ninja -DCMAKE_BUILD_TYPE=Debug \
        || return 1
    cmake --build "$build_dir" || return 1
    ctest --test-dir "$build_dir" --output-on-failure --no-tests=error \
        || return 1

    if [[ ! -d "$native_qml" ]]; then
        ui_error "Local QuickShell build did not produce native QML tree: $native_qml"
        return 1
    fi

    # Keep the user-level build-tree QML path. Do not overwrite the legacy
    # ~/.local/lib/qt6/qml install used by the personal checkout.
    expected_receipt="$(quickshell_local_source_receipt "$source")"
    mkdir -p "$state_dir"
    printf '%s\n' "$expected_receipt" >"$receipt_file.tmp"
    mv -f "$receipt_file.tmp" "$receipt_file"
    write_quickshell_runtime_markers "$state_dir" || return 1
    # key-cli uses `qs -c clavis`. Quickshell identifies symlink paths separately,
    # so the coordinator must launch the same named path, not the physical tree.
    mkdir -p "$(dirname -- "$config_link")"
    if [[ ! -L "$config_link" ]]; then
        ln -s -- "$source" "$config_link" || return 1
    fi
    write_quickshell_config_path_marker "$state_dir" "$config_link"
    ui_success "QuickShell" "installed from local CMake source"
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

    if [[ -n "${QUICKSHELL_LOCAL_SOURCE:-}" ]]; then
        install_quickshell_local_source "$dry_run" || return 1
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

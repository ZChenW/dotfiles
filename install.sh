#!/usr/bin/env bash
# Dotfiles installer entrypoint (Arch Linux).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# shellcheck source=scripts/ui.sh
source "$REPO_ROOT/scripts/ui.sh"

DRY_RUN=false
ASSUME_YES=false
SKIP_PACKAGES=false
RESTORE_ONLY=false
PACKAGES_ONLY=false
FULL_PACKAGES=false
EXPORT_PACKAGES=false
NO_AUR=false
INCLUDE_AUR=true
SNAPSHOT=false
SNAPSHOT_NO_COMMIT=false
SNAPSHOT_COMMIT=false
SNAPSHOT_PUSH=false
UPDATE=false
UPDATE_WITH_PACKAGES=false
UPDATE_NO_SNAPSHOT_PROMPT=false

ALL_CONFIG_GROUPS=(shell desktop terminal apps editors local-bin)
SELECTED_GROUPS=()

usage() {
    cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Arch Linux dotfiles installer. By default, runs interactively in a TTY.
Use --yes for non-interactive mode (scripts, CI, one-shot restore).

Options:
  --dry-run          Print planned actions without modifying $HOME
  --yes              Non-interactive mode with recommended defaults
  --skip-packages    Restore configs only, skip package installation
  --packages-only    Install packages only, skip config restore
  --full-packages    Include machine-local packages from packages/arch-machine-local.txt
  --no-aur           Skip AUR packages (default in interactive mode)
  --export-packages  Export current machine packages into packages/*.txt
  --restore-only     Skip packages and optional service actions
  --snapshot         Refresh package manifests and managed configs from this machine
  --no-commit        With --snapshot: update files only, do not ask to commit
  --commit           With --snapshot: commit after checks, do not push
  --push             With --snapshot: ask, then commit and push
  --update           Pull repo updates, then apply configs
  --with-packages    With --update: install package manifests after pulling
  --no-snapshot-prompt  With --update: do not ask to snapshot before pulling
  --help             Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            ;;
        --yes)
            ASSUME_YES=true
            ;;
        --skip-packages)
            SKIP_PACKAGES=true
            ;;
        --packages-only)
            PACKAGES_ONLY=true
            ;;
        --full-packages)
            FULL_PACKAGES=true
            ;;
        --no-aur)
            NO_AUR=true
            ;;
        --export-packages)
            EXPORT_PACKAGES=true
            ;;
        --restore-only)
            SKIP_PACKAGES=true
            RESTORE_ONLY=true
            ;;
        --snapshot)
            SNAPSHOT=true
            ;;
        --no-commit)
            SNAPSHOT_NO_COMMIT=true
            ;;
        --commit)
            SNAPSHOT_COMMIT=true
            ;;
        --push)
            SNAPSHOT_PUSH=true
            ;;
        --update)
            UPDATE=true
            ;;
        --with-packages)
            UPDATE_WITH_PACKAGES=true
            ;;
        --no-snapshot-prompt)
            UPDATE_NO_SNAPSHOT_PROMPT=true
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            ui_error "Unknown option: $1"
            usage >&2
            exit 1
            ;;
    esac
    shift
done

require_arch_linux() {
    if [[ ! -f /etc/os-release ]]; then
        ui_error "/etc/os-release not found. This installer supports Arch Linux only."
        exit 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "${ID:-}" != "arch" ]]; then
        ui_error "unsupported OS '${ID:-unknown}'. This installer supports Arch Linux only."
        exit 1
    fi
}

is_tty() {
    [[ -t 0 && -t 1 ]]
}

validate_snapshot_flags() {
    if [[ "$SNAPSHOT" != true ]]; then
        if [[ "$SNAPSHOT_NO_COMMIT" == true || "$SNAPSHOT_COMMIT" == true || "$SNAPSHOT_PUSH" == true ]]; then
            echo "Error: --no-commit, --commit, and --push require --snapshot." >&2
            exit 1
        fi
        return 0
    fi

    if [[ "$SNAPSHOT_NO_COMMIT" == true && "$SNAPSHOT_COMMIT" == true ]]; then
        echo "Error: --no-commit cannot be combined with --commit." >&2
        exit 1
    fi
    if [[ "$SNAPSHOT_NO_COMMIT" == true && "$SNAPSHOT_PUSH" == true ]]; then
        echo "Error: --no-commit cannot be combined with --push." >&2
        exit 1
    fi
    if [[ "$PACKAGES_ONLY" == true || "$SKIP_PACKAGES" == true || "$RESTORE_ONLY" == true || "$EXPORT_PACKAGES" == true ]]; then
        echo "Error: --snapshot cannot be combined with install/export mode flags." >&2
        exit 1
    fi
}

validate_update_flags() {
    if [[ "$UPDATE" != true ]]; then
        if [[ "$UPDATE_WITH_PACKAGES" == true || "$UPDATE_NO_SNAPSHOT_PROMPT" == true ]]; then
            echo "Error: --with-packages and --no-snapshot-prompt require --update." >&2
            exit 1
        fi
        return 0
    fi

    if [[ "$SNAPSHOT" == true || "$PACKAGES_ONLY" == true || "$SKIP_PACKAGES" == true || "$RESTORE_ONLY" == true || "$EXPORT_PACKAGES" == true || "$SNAPSHOT_NO_COMMIT" == true || "$SNAPSHOT_COMMIT" == true || "$SNAPSHOT_PUSH" == true ]]; then
        echo "Error: --update cannot be combined with snapshot/install/export mode flags." >&2
        exit 1
    fi
}

prompt_yes_no() {
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

resolve_config_groups() {
    local input="${1:-all}"
    local -a resolved=()
    local token normalized

    input="${input// /}"
    if [[ -z "$input" || "${input,,}" == all || "${input,,}" == "*" ]]; then
        SELECTED_GROUPS=("${ALL_CONFIG_GROUPS[@]}")
        return 0
    fi

    IFS=',' read -ra tokens <<<"$input"
    for token in "${tokens[@]}"; do
        [[ -n "$token" ]] || continue
        normalized="${token,,}"
        case "$normalized" in
            1 | shell)
                resolved+=(shell)
                ;;
            2 | desktop)
                resolved+=(desktop)
                ;;
            3 | terminal)
                resolved+=(terminal)
                ;;
            4 | apps)
                resolved+=(apps)
                ;;
            5 | editors)
                resolved+=(editors)
                ;;
            6 | local-bin | localbin)
                resolved+=(local-bin)
                ;;
            *)
                ui_error "Unknown config group: $token"
                return 1
                ;;
        esac
    done

    if ((${#resolved[@]} == 0)); then
        ui_error "No config groups selected."
        return 1
    fi

    SELECTED_GROUPS=("${resolved[@]}")
}

print_plan_summary() {
    ui_section "Installation plan"
    echo "Repository: $REPO_ROOT"
    echo "Dry run: $DRY_RUN"

    if [[ "$SKIP_PACKAGES" == true ]]; then
        echo "Packages: skip"
    else
        echo "Packages: install"
        if [[ "$INCLUDE_AUR" == true ]]; then
            echo "AUR: include"
        else
            echo "AUR: skip"
        fi
        if [[ "$FULL_PACKAGES" == true ]]; then
            echo "Machine-local packages: include"
        else
            echo "Machine-local packages: skip"
        fi
    fi

    if [[ "$PACKAGES_ONLY" == true ]]; then
        echo "Config groups: skip (packages-only)"
    else
        echo "Config groups: ${SELECTED_GROUPS[*]}"
        if printf '%s\n' "${SELECTED_GROUPS[@]}" | grep -qx shell; then
            echo "Private config: ~/.zshrc.local preserved when present; created from template when missing"
        fi
        echo "Config strategy: backup existing targets, then copy real files (no symlinks)"
    fi

    if [[ "$RESTORE_ONLY" == true ]]; then
        echo "Restore-only: skip optional service actions"
    fi
}

run_interactive_setup() {
    local mode_choice group_input

    if [[ "$PACKAGES_ONLY" != true && "$SKIP_PACKAGES" != true ]]; then
        ui_section "Step 1: Install mode"
        echo "  1) Full install (packages + configs)"
        echo "  2) Packages only"
        echo "  3) Configs only"
        echo "  4) Dry-run preview (full install)"
        read -r -p "$(ui_prompt "Choice" "1")" mode_choice
        case "${mode_choice:-1}" in
            1) ;;
            2)
                PACKAGES_ONLY=true
                ;;
            3)
                SKIP_PACKAGES=true
                ;;
            4)
                DRY_RUN=true
                ;;
            *)
                ui_error "Invalid choice: $mode_choice"
                exit 1
                ;;
        esac
    fi

    if [[ "$SKIP_PACKAGES" != true ]]; then
        ui_section "Step 2: Software scope"
        if ! prompt_yes_no "Install packages?" y; then
            SKIP_PACKAGES=true
        else
            if [[ "$NO_AUR" == true ]]; then
                INCLUDE_AUR=false
            elif prompt_yes_no "Install AUR packages?" n; then
                INCLUDE_AUR=true
            else
                INCLUDE_AUR=false
            fi

            if [[ "$FULL_PACKAGES" == true ]]; then
                :
            elif prompt_yes_no "Include machine-local packages (arch-machine-local.txt)?" n; then
                FULL_PACKAGES=true
            else
                FULL_PACKAGES=false
            fi
        fi
    fi

    if [[ "$PACKAGES_ONLY" != true ]]; then
        ui_section "Step 3: Config groups"
        echo "Available groups:"
        echo "  1) shell      - .zshrc, .zshrc.local"
        echo "  2) desktop    - niri, waybar, fcitx5, mako, environment.d, qt5ct, qt6ct"
        echo "  3) terminal   - kitty, fastfetch, cava"
        echo "  4) apps       - waypaper, Thunar, mimeapps.list, user-dirs.dirs, git/ignore"
        echo "  5) editors    - Code/Cursor settings, keybindings, optional snippets"
        echo "  6) local-bin  - inir, toggle-niri-shell"
        read -r -p "$(ui_prompt "Select groups (comma-separated names or numbers, default all)" "all")" group_input
        resolve_config_groups "${group_input:-all}"
    fi

    ui_section "Step 4: Local private config"
    echo "\$HOME/.zshrc.local is only handled when the shell group is selected."
    echo "Existing regular files are kept. Missing files are created from the template."
    echo "Existing symlinks are backed up and replaced with a real file."

    print_plan_summary
    ui_section "Step 5: Confirm"
    if ! prompt_yes_no "Proceed?" n; then
        ui_warn "Aborted."
        exit 0
    fi
}

apply_non_interactive_defaults() {
    if [[ "$NO_AUR" == true ]]; then
        INCLUDE_AUR=false
    else
        INCLUDE_AUR=true
    fi

    if [[ "$PACKAGES_ONLY" != true ]]; then
        SELECTED_GROUPS=("${ALL_CONFIG_GROUPS[@]}")
    fi
}

main() {
    ui_banner
    echo "Repository: $REPO_ROOT"

    require_arch_linux

    # shellcheck source=scripts/packages-arch.sh
    source "$REPO_ROOT/scripts/packages-arch.sh"

    validate_snapshot_flags
    validate_update_flags

    if [[ "$UPDATE" == true ]]; then
        # shellcheck source=scripts/update.sh
        source "$REPO_ROOT/scripts/update.sh"
        run_update "$REPO_ROOT" "$DRY_RUN" "$ASSUME_YES" "$UPDATE_WITH_PACKAGES" "$UPDATE_NO_SNAPSHOT_PROMPT"
        exit 0
    fi

    if [[ "$SNAPSHOT" == true ]]; then
        # shellcheck source=scripts/snapshot.sh
        source "$REPO_ROOT/scripts/snapshot.sh"
        run_snapshot "$REPO_ROOT" "$DRY_RUN" "$ASSUME_YES" "$SNAPSHOT_NO_COMMIT" "$SNAPSHOT_COMMIT" "$SNAPSHOT_PUSH"
        exit 0
    fi

    if [[ "$EXPORT_PACKAGES" == true ]]; then
        ui_step "Exporting package snapshot"
        export_package_snapshot "$REPO_ROOT"
        exit 0
    fi

    if [[ "$ASSUME_YES" == true ]]; then
        apply_non_interactive_defaults
    elif is_tty; then
        run_interactive_setup
    else
        ui_error "non-interactive stdin/stdout requires --yes."
        echo "Run in a terminal for interactive mode, or pass --yes for scripted installs." >&2
        exit 1
    fi

    if [[ "$SKIP_PACKAGES" != true ]]; then
        ui_step "Installing packages"
        install_package_files "$DRY_RUN" "$ASSUME_YES" "$FULL_PACKAGES" "$INCLUDE_AUR" "$REPO_ROOT"
    else
        ui_step "Skipping package installation"
    fi

    if [[ "$PACKAGES_ONLY" == true ]]; then
        echo
        if [[ "$DRY_RUN" == true ]]; then
            ui_success "Packages-only dry run complete. No config changes were made."
        else
            ui_success "Packages-only install complete."
        fi
        exit 0
    fi

    # shellcheck source=scripts/backup.sh
    source "$REPO_ROOT/scripts/backup.sh"
    # shellcheck source=scripts/sync-configs.sh
    source "$REPO_ROOT/scripts/sync-configs.sh"
    # shellcheck source=scripts/verify.sh
    source "$REPO_ROOT/scripts/verify.sh"

    local backup_root
    if [[ "$DRY_RUN" == true ]]; then
        backup_root="$(create_backup_dir)"
        ui_step "Dry run: would create backup directory $backup_root"
    else
        backup_root="$(create_backup_dir)"
        mkdir -p "$backup_root"
        ui_step "Created backup directory: $backup_root"
    fi

    ui_step "Syncing configs"
    sync_configs "$REPO_ROOT" "$backup_root" "$DRY_RUN" "${SELECTED_GROUPS[@]}"

    if [[ "$RESTORE_ONLY" == true ]]; then
        ui_step "Restore-only mode: skipping optional service actions"
    fi

    ui_step "Verifying installation"
    verify_installation "$DRY_RUN" "${SELECTED_GROUPS[@]}"

    echo
    if [[ "$DRY_RUN" == true ]]; then
        ui_success "Dry run complete. No changes were made."
    else
        ui_success "Install complete."
        echo "Backup directory: $backup_root"
        echo "To roll back: $backup_root/rollback.sh"
    fi
}

main "$@"

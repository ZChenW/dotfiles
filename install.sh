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
DOCTOR=false
UNINSTALL=false
UNINSTALL_MODE="safe"
VERBOSE=0
DEBUG=0
NO_COLOR_FLAG=false
ASCII_FLAG=false
MODE_LABEL=""
BACKUP_ROOT=""
LOG_FILE=""
LOG_INITIALIZED=false
INTRO_PRINTED=false

ALL_CONFIG_GROUPS=(shell desktop terminal apps editors local-bin media)
SELECTED_GROUPS=()

cleanup_on_exit() {
    local exit_code=$?
    if ((exit_code == 0 || exit_code == 130)); then
        return 0
    fi
    echo >&2
    echo "Installer exited unexpectedly (code $exit_code)." >&2
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "Log: $LOG_FILE" >&2
    fi
    if [[ -n "${BACKUP_ROOT:-}" && -d "${BACKUP_ROOT:-}" ]]; then
        echo "Backup (may be partial): $BACKUP_ROOT" >&2
        if [[ -x "$BACKUP_ROOT/rollback.sh" ]]; then
            echo "Rollback: $BACKUP_ROOT/rollback.sh" >&2
        fi
    fi
}
trap cleanup_on_exit EXIT

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
  --doctor           Run diagnostics without changing configs
  --uninstall [MODE] Remove managed configs (safe|restore|purge); default: safe
  --purge            Shortcut for --uninstall purge
  --verbose          Show readable per-operation details
  --debug            Show raw commands and internal details; implies --verbose
  --no-color         Disable color output
  --ascii            Disable Unicode symbols and box drawing
  --help             Show this help message

Uninstall modes:
  safe               Archive managed configs, then remove them (keeps packages/backups)
  restore            Run the latest ~/.dotfiles-backups/*/rollback.sh
  purge              Remove managed configs and all install backups (keeps packages)

Never removes OS packages. Never removes ~/.zshrc.local.
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
        --doctor)
            DOCTOR=true
            ;;
        --uninstall)
            UNINSTALL=true
            if [[ $# -ge 2 && "$2" != -* ]]; then
                UNINSTALL_MODE="$2"
                shift
            else
                UNINSTALL_MODE="safe"
            fi
            ;;
        --purge)
            UNINSTALL=true
            UNINSTALL_MODE="purge"
            ;;
        --verbose)
            VERBOSE=1
            ;;
        --debug)
            DEBUG=1
            VERBOSE=1
            ;;
        --no-color)
            NO_COLOR_FLAG=true
            NO_COLOR=1
            ;;
        --ascii)
            ASCII_FLAG=true
            DOTFILES_ASCII=1
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

UI_VERBOSE="$VERBOSE"
UI_DEBUG="$DEBUG"
export UI_VERBOSE UI_DEBUG
if [[ "$NO_COLOR_FLAG" == true ]]; then
    export NO_COLOR
fi
if [[ "$ASCII_FLAG" == true ]]; then
    export DOTFILES_ASCII
fi
ui_init

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
    if [[ "$PACKAGES_ONLY" == true || "$SKIP_PACKAGES" == true || "$RESTORE_ONLY" == true || "$EXPORT_PACKAGES" == true || "$DOCTOR" == true || "$UNINSTALL" == true ]]; then
        echo "Error: --snapshot cannot be combined with install/export/doctor/uninstall mode flags." >&2
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

    if [[ "$SNAPSHOT" == true || "$PACKAGES_ONLY" == true || "$SKIP_PACKAGES" == true || "$RESTORE_ONLY" == true || "$EXPORT_PACKAGES" == true || "$SNAPSHOT_NO_COMMIT" == true || "$SNAPSHOT_COMMIT" == true || "$SNAPSHOT_PUSH" == true || "$DOCTOR" == true || "$UNINSTALL" == true ]]; then
        echo "Error: --update cannot be combined with snapshot/install/export/doctor/uninstall mode flags." >&2
        exit 1
    fi
}

validate_lifecycle_flags() {
    local mode_count=0
    [[ "$SNAPSHOT" == true ]] && ((++mode_count))
    [[ "$UPDATE" == true ]] && ((++mode_count))
    [[ "$EXPORT_PACKAGES" == true ]] && ((++mode_count))
    [[ "$DOCTOR" == true ]] && ((++mode_count))
    [[ "$UNINSTALL" == true ]] && ((++mode_count))

    if ((mode_count > 1)); then
        echo "Error: --snapshot, --update, --export-packages, --doctor, and --uninstall are mutually exclusive." >&2
        exit 1
    fi

    if [[ "$DOCTOR" == true ]]; then
        if [[ "$PACKAGES_ONLY" == true || "$SKIP_PACKAGES" == true || "$RESTORE_ONLY" == true || "$SNAPSHOT_NO_COMMIT" == true || "$SNAPSHOT_COMMIT" == true || "$SNAPSHOT_PUSH" == true ]]; then
            echo "Error: --doctor cannot be combined with install/snapshot mode flags." >&2
            exit 1
        fi
    fi

    if [[ "$UNINSTALL" == true ]]; then
        case "$UNINSTALL_MODE" in
            safe | restore | purge | uninstall) ;;
            *)
                echo "Error: unknown uninstall mode '$UNINSTALL_MODE' (use safe, restore, or purge)." >&2
                exit 1
                ;;
        esac
        if [[ "$PACKAGES_ONLY" == true || "$SKIP_PACKAGES" == true || "$RESTORE_ONLY" == true || "$SNAPSHOT_NO_COMMIT" == true || "$SNAPSHOT_COMMIT" == true || "$SNAPSHOT_PUSH" == true || "$FULL_PACKAGES" == true ]]; then
            echo "Error: --uninstall cannot be combined with install/snapshot package flags." >&2
            exit 1
        fi
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
            7 | media)
                resolved+=(media)
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

mode_label() {
    if [[ -n "$MODE_LABEL" ]]; then
        printf '%s\n' "$MODE_LABEL"
        return 0
    fi

    if [[ "$DOCTOR" == true ]]; then
        printf 'doctor\n'
    elif [[ "$UNINSTALL" == true ]]; then
        printf 'uninstall (%s)\n' "$UNINSTALL_MODE"
    elif [[ "$SNAPSHOT" == true && "$DRY_RUN" == true ]]; then
        printf 'snapshot + dry-run\n'
    elif [[ "$SNAPSHOT" == true ]]; then
        printf 'snapshot\n'
    elif [[ "$UPDATE" == true && "$DRY_RUN" == true ]]; then
        printf 'update + dry-run\n'
    elif [[ "$UPDATE" == true ]]; then
        printf 'update\n'
    elif [[ "$EXPORT_PACKAGES" == true ]]; then
        printf 'export packages\n'
    elif [[ "$DRY_RUN" == true ]]; then
        printf 'dry-run\n'
    elif [[ "$PACKAGES_ONLY" == true ]]; then
        printf 'packages-only install\n'
    elif [[ "$RESTORE_ONLY" == true ]]; then
        printf 'restore-only install\n'
    else
        printf 'install\n'
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
        echo "  7) media      - Pictures/wallpapers"
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

init_log_once() {
    [[ "$LOG_INITIALIZED" == true ]] && return 0

    if [[ "$DRY_RUN" == true || "$SNAPSHOT" == true || "$UPDATE" == true || "$EXPORT_PACKAGES" == true || "$DOCTOR" == true || "$UNINSTALL" == true ]]; then
        LOG_FILE="/tmp/dotfiles-install-$(date +%Y%m%d-%H%M%S).log"
    else
        # shellcheck source=scripts/backup.sh
        source "$REPO_ROOT/scripts/backup.sh"
        BACKUP_ROOT="$(create_backup_dir)"
        LOG_FILE="$BACKUP_ROOT/install.log"
        mkdir -p "$BACKUP_ROOT"
    fi
    : >"$LOG_FILE"
    DOTFILES_LOG_FILE="$LOG_FILE"
    export DOTFILES_LOG_FILE
    LOG_INITIALIZED=true
}

print_intro_once() {
    [[ "$INTRO_PRINTED" == true ]] && return 0

    ui_banner "Dotfiles Installer" "Make this machine feel like home."
    echo
    ui_kv "Repository" "$REPO_ROOT"
    ui_kv "Mode" "$(mode_label)"
    if [[ -n "$BACKUP_ROOT" ]]; then
        ui_kv "Backup" "$BACKUP_ROOT"
    fi
    ui_kv "Log" "$LOG_FILE"
    INTRO_PRINTED=true
}

snapshot_managed_configs() {
    snapshot_capture_configs "$REPO_ROOT" false
}

export_package_manifests() {
    export_package_snapshot "$REPO_ROOT"
}

normalize_captured_text_files() {
    snapshot_normalize_captured_files "$REPO_ROOT"
}

run_safety_check() {
    snapshot_safety_check "$REPO_ROOT"
}

plan_packages() {
    install_package_files true "$ASSUME_YES" "$FULL_PACKAGES" "$INCLUDE_AUR" "$REPO_ROOT"
}

print_package_plan_summary() {
    :
}

plan_config_sync() {
    # shellcheck source=scripts/backup.sh
    source "$REPO_ROOT/scripts/backup.sh"
    # shellcheck source=scripts/sync-configs.sh
    source "$REPO_ROOT/scripts/sync-configs.sh"

    BACKUP_ROOT="$(create_backup_dir)"
    debug_log "[dry-run] would create backup directory $BACKUP_ROOT"
    sync_configs "$REPO_ROOT" "$BACKUP_ROOT" true "${SELECTED_GROUPS[@]}"
}

print_config_plan_summary() {
    :
}

run_verification() {
    # shellcheck source=scripts/verify.sh
    source "$REPO_ROOT/scripts/verify.sh"
    verify_installation true "${SELECTED_GROUPS[@]}"
}

snapshot_result_detail() {
    if [[ -z "$(git -C "$REPO_ROOT" status --short -- packages configs)" ]]; then
        printf 'No changes detected\n'
    else
        printf 'Changes left uncommitted\n'
    fi
}

run_snapshot_workflow() {
    # Capture mutates the repo; home stays untouched. Plan steps still run dry.
    MODE_LABEL="snapshot"
    SELECTED_GROUPS=("${ALL_CONFIG_GROUPS[@]}")

    init_log_once
    print_intro_once

    # shellcheck source=scripts/preflight.sh
    source "$REPO_ROOT/scripts/preflight.sh"
    run_preflight snapshot

    # shellcheck source=scripts/packages-arch.sh
    source "$REPO_ROOT/scripts/packages-arch.sh"
    # shellcheck source=scripts/snapshot.sh
    source "$REPO_ROOT/scripts/snapshot.sh"

    ui_section "1/5 Snapshot"
    snapshot_managed_configs
    normalize_captured_text_files
    ui_ok "Text files normalized"
    run_safety_check
    ui_ok "Safety check passed"

    ui_section "2/5 Package manifests"
    export_package_manifests

    ui_section "3/5 Package plan"
    plan_packages
    print_package_plan_summary

    ui_section "4/5 Config plan"
    plan_config_sync
    print_config_plan_summary

    ui_section "5/5 Verification"
    run_verification

    ui_result_box "Result" \
        "ok:Snapshot capture complete" \
        "ok:Home directory unchanged" \
        "ok:Repo files may have been updated" \
        "ok:$(snapshot_result_detail)"

    if [[ "$SNAPSHOT_NO_COMMIT" == true ]]; then
        return 0
    fi

    if [[ "$SNAPSHOT_COMMIT" == true || "$SNAPSHOT_PUSH" == true ]]; then
        if [[ "$SNAPSHOT_PUSH" == true ]] && is_tty && [[ "$ASSUME_YES" != true ]]; then
            if ! prompt_yes_no "Commit and push these snapshot changes?" n; then
                ui_success "Snapshot complete. Changes left uncommitted."
                return 0
            fi
        fi
        snapshot_commit "$REPO_ROOT"
        if [[ "$SNAPSHOT_PUSH" == true ]]; then
            snapshot_push "$REPO_ROOT"
        fi
        return 0
    fi

    # Plain --snapshot: ask to commit+push when interactive (matches docs).
    if is_tty && [[ "$ASSUME_YES" != true ]]; then
        if prompt_yes_no "Commit and push these snapshot changes?" n; then
            snapshot_commit "$REPO_ROOT"
            snapshot_push "$REPO_ROOT"
        else
            ui_success "Snapshot complete. Changes left uncommitted."
        fi
    fi
}

run_doctor_workflow() {
    MODE_LABEL="doctor"
    init_log_once
    print_intro_once

    # shellcheck source=scripts/preflight.sh
    source "$REPO_ROOT/scripts/preflight.sh"
    run_preflight doctor

    # shellcheck source=scripts/doctor.sh
    source "$REPO_ROOT/scripts/doctor.sh"
    run_doctor "$REPO_ROOT"
}

run_uninstall_workflow() {
    MODE_LABEL="uninstall ($UNINSTALL_MODE)"
    init_log_once
    print_intro_once

    # shellcheck source=scripts/preflight.sh
    source "$REPO_ROOT/scripts/preflight.sh"
    run_preflight uninstall

    # shellcheck source=scripts/uninstall.sh
    source "$REPO_ROOT/scripts/uninstall.sh"
    run_uninstall "$REPO_ROOT" "$UNINSTALL_MODE" "$DRY_RUN" "$ASSUME_YES"
}

run_install_workflow() {
    init_log_once
    print_intro_once

    # shellcheck source=scripts/preflight.sh
    source "$REPO_ROOT/scripts/preflight.sh"
    if [[ "$UPDATE" == true ]]; then
        run_preflight update
    elif [[ "$EXPORT_PACKAGES" == true ]]; then
        run_preflight export
    elif [[ "$DRY_RUN" == true ]]; then
        run_preflight dry-run
    else
        run_preflight install
    fi

    # shellcheck source=scripts/packages-arch.sh
    source "$REPO_ROOT/scripts/packages-arch.sh"

    if [[ "$UPDATE" == true ]]; then
        # shellcheck source=scripts/update.sh
        source "$REPO_ROOT/scripts/update.sh"
        run_update "$REPO_ROOT" "$DRY_RUN" "$ASSUME_YES" "$UPDATE_WITH_PACKAGES" "$UPDATE_NO_SNAPSHOT_PROMPT"
        return 0
    fi

    if [[ "$EXPORT_PACKAGES" == true ]]; then
        ui_section "Package manifests"
        export_package_snapshot "$REPO_ROOT"
        ui_result_box "Result" "ok:Package export complete"
        return 0
    fi

    if [[ "$ASSUME_YES" == true ]]; then
        apply_non_interactive_defaults
    elif is_tty; then
        run_interactive_setup
    else
        ui_error "non-interactive stdin/stdout requires --yes."
        echo "Run in a terminal for interactive mode, or pass --yes for scripted installs." >&2
        return 1
    fi

    if [[ "$SKIP_PACKAGES" != true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            ui_section "3/5 Package plan"
        else
            ui_section "3/5 Installing packages"
        fi
        if ! install_package_files "$DRY_RUN" "$ASSUME_YES" "$FULL_PACKAGES" "$INCLUDE_AUR" "$REPO_ROOT"; then
            ui_result_box "Result" "fail:Install failed"
            ui_note "See log: $LOG_FILE"
            return 1
        fi
    else
        ui_section "3/5 Package plan"
        ui_warn "Package installation skipped"
    fi

    if [[ "$PACKAGES_ONLY" == true ]]; then
        echo
        if [[ "$DRY_RUN" == true ]]; then
            ui_result_box "Result" "ok:Dry run complete" "ok:No config changes were made"
        else
            ui_result_box "Result" "ok:Packages-only install complete"
        fi
        return 0
    fi

    # shellcheck source=scripts/backup.sh
    source "$REPO_ROOT/scripts/backup.sh"
    # shellcheck source=scripts/sync-configs.sh
    source "$REPO_ROOT/scripts/sync-configs.sh"
    # shellcheck source=scripts/verify.sh
    source "$REPO_ROOT/scripts/verify.sh"

    if [[ "$DRY_RUN" == true ]]; then
        BACKUP_ROOT="$(create_backup_dir)"
        debug_log "[dry-run] would create backup directory $BACKUP_ROOT"
    else
        mkdir -p "$BACKUP_ROOT"
        debug_log "created backup directory: $BACKUP_ROOT"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        ui_section "4/5 Config plan"
    else
        ui_section "4/5 Syncing configs"
    fi
    if ! sync_configs "$REPO_ROOT" "$BACKUP_ROOT" "$DRY_RUN" "${SELECTED_GROUPS[@]}"; then
        ui_result_box "Result" "fail:Config sync failed"
        ui_note "See log: $LOG_FILE"
        return 1
    fi

    if [[ "$RESTORE_ONLY" == true ]]; then
        verbose_log "restore-only mode: skipping optional service actions"
    fi

    ui_section "5/5 Verification"
    if ! verify_installation "$DRY_RUN" "${SELECTED_GROUPS[@]}"; then
        ui_result_box "Result" "fail:Verification failed" "ok:Backup preserved"
        ui_note "See log: $LOG_FILE"
        return 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        ui_result_box "Result" "ok:Dry run complete" "ok:No changes were made" "ok:Rollback script planned"
    else
        ui_result_box "Result" "ok:Install complete" "ok:Backup created" "ok:Rollback script ready" "ok:Verification passed"
        ui_note "Rollback: $BACKUP_ROOT/rollback.sh"
    fi
}

run_dry_run_workflow() {
    DRY_RUN=true
    run_install_workflow
}

main() {
    validate_snapshot_flags
    validate_update_flags
    validate_lifecycle_flags
    require_arch_linux

    if [[ "$DOCTOR" == true ]]; then
        run_doctor_workflow
    elif [[ "$UNINSTALL" == true ]]; then
        run_uninstall_workflow
    elif [[ "$SNAPSHOT" == true ]]; then
        run_snapshot_workflow
    elif [[ "$DRY_RUN" == true ]]; then
        run_dry_run_workflow
    else
        run_install_workflow
    fi
}

main "$@"

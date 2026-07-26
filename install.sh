#!/usr/bin/env bash
# Dotfiles installer entrypoint (Arch Linux).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
CLI_ARGS_PROVIDED=false
if (($# > 0)); then
    CLI_ARGS_PROVIDED=true
fi

# shellcheck source=scripts/ui.sh
source "$REPO_ROOT/scripts/ui.sh"
# shellcheck source=scripts/desktop-shell-profile.sh
source "$REPO_ROOT/scripts/desktop-shell-profile.sh"

DRY_RUN=false
DRY_RUN_CLI=false
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
SHOW_MENU=false
DESKTOP_SHELL_PROFILE=""
MODE_LABEL=""
BACKUP_ROOT=""
LOG_FILE=""
LOG_INITIALIZED=false
INTRO_PRINTED=false
BANNER_PRINTED=false
FAILURE_REPORTED=false

ALL_CONFIG_GROUPS=(shell desktop terminal apps editors local-bin media)
SELECTED_GROUPS=()

cleanup_on_exit() {
    local exit_code=$?
    ui_cursor_show || true
    if ((exit_code == 0 || exit_code == 130)); then
        return 0
    fi
    if [[ "${FAILURE_REPORTED:-false}" == true ]]; then
        return 0
    fi
    echo >&2
    ui_result_box "Installation stopped" \
        "fail:Unexpected exit (code $exit_code)" >&2
    if [[ -n "${LOG_FILE:-}" ]]; then
        ui_note "Log: $LOG_FILE" >&2
    fi
    if [[ -n "${BACKUP_ROOT:-}" && -d "${BACKUP_ROOT:-}" ]]; then
        ui_note "Backup (may be partial): $BACKUP_ROOT" >&2
        if [[ -x "$BACKUP_ROOT/rollback.sh" ]]; then
            ui_note "Rollback: $BACKUP_ROOT/rollback.sh" >&2
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
  --menu             Show the interactive operation menu
  --dry-run          Print planned actions without modifying $HOME
  --yes              Non-interactive mode with recommended defaults
  --skip-packages    Restore configs only, skip package installation
  --packages-only    Install packages only, skip config restore
  --full-packages    Include machine-local packages from packages/arch-machine-local.txt
  --no-aur           Skip AUR packages (default in interactive mode)
  --export-packages  Export current machine packages into packages/*.txt
  --restore-only     Skip packages and optional service actions
  --desktop-shell PROFILE
                     Desktop shell profile: waybar, quickshell, or dual
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
        --menu)
            SHOW_MENU=true
            ;;
        --dry-run)
            DRY_RUN=true
            DRY_RUN_CLI=true
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
        --desktop-shell)
            if (($# < 2)); then
                ui_error "--desktop-shell requires waybar, quickshell, or dual"
                exit 2
            fi
            DESKTOP_SHELL_PROFILE="${2,,}"
            shift
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

case "$DESKTOP_SHELL_PROFILE" in
    "" | waybar | quickshell | dual) ;;
    *)
        ui_error "--desktop-shell must be waybar, quickshell, or dual"
        exit 2
        ;;
esac

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
    local packages_label aur_label machine_label groups_label private_label

    if [[ "$DRY_RUN" == true ]]; then
        private_label="Preview only; no changes"
    else
        private_label="Back up, then copy real files"
    fi

    if [[ "$SKIP_PACKAGES" == true ]]; then
        packages_label="Skipped"
        aur_label="Skipped"
        machine_label="Skipped"
    else
        if [[ "$INCLUDE_AUR" == true ]]; then
            packages_label="Official + AUR"
            aur_label="Included"
        else
            packages_label="Official repositories"
            aur_label="Skipped"
        fi
        if [[ "$FULL_PACKAGES" == true ]]; then
            machine_label="Included"
        else
            machine_label="Skipped"
        fi
    fi

    if [[ "$PACKAGES_ONLY" == true ]]; then
        groups_label="Skipped (packages only)"
        private_label="Not touched"
    else
        groups_label="${SELECTED_GROUPS[*]}"
    fi

    if [[ "$RESTORE_ONLY" == true ]]; then
        private_label="Configs only; optional services skipped"
    fi

    ui_plan_box "Installation plan" \
        "Mode|$(mode_label)" \
        "Desktop shell|$DESKTOP_SHELL_PROFILE" \
        "Packages|$packages_label" \
        "AUR|$aur_label" \
        "Machine packages|$machine_label" \
        "Config groups|$groups_label" \
        "Existing files|$private_label" \
        "Private config|~/.zshrc.local preserved"
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
    local group_input mode_default action

    while true; do
        mode_default=1
        [[ "$PACKAGES_ONLY" == true ]] && mode_default=2
        [[ "$SKIP_PACKAGES" == true ]] && mode_default=3
        [[ "$DRY_RUN" == true ]] && mode_default=4

        ui_stage 1 6 "Installation mode"
        ui_menu "Select" "$mode_default" \
            "Full install|Packages and configurations" \
            "Packages only|Do not modify configurations" \
            "Configurations only|Skip package installation" \
            "Preview|Show actions without modifying \$HOME"
        case "$UI_MENU_CHOICE" in
            1)
                PACKAGES_ONLY=false
                SKIP_PACKAGES=false
                [[ "$DRY_RUN_CLI" == true ]] || DRY_RUN=false
                ;;
            2)
                PACKAGES_ONLY=true
                SKIP_PACKAGES=false
                [[ "$DRY_RUN_CLI" == true ]] || DRY_RUN=false
                ;;
            3)
                PACKAGES_ONLY=false
                SKIP_PACKAGES=true
                [[ "$DRY_RUN_CLI" == true ]] || DRY_RUN=false
                ;;
            4)
                PACKAGES_ONLY=false
                SKIP_PACKAGES=false
                DRY_RUN=true
                ;;
        esac

        ui_stage 2 6 "Software scope"
        if [[ "$SKIP_PACKAGES" != true ]]; then
            if [[ "$PACKAGES_ONLY" != true ]] && ! prompt_yes_no "Install packages?" y; then
                SKIP_PACKAGES=true
            else
                if [[ "$NO_AUR" == true ]]; then
                    INCLUDE_AUR=false
                    ui_warn "AUR packages" "disabled by --no-aur"
                elif prompt_yes_no "Install AUR packages?" "$([[ "$INCLUDE_AUR" == true ]] && printf y || printf n)"; then
                    INCLUDE_AUR=true
                else
                    INCLUDE_AUR=false
                fi

                if prompt_yes_no "Include machine-local packages?" "$([[ "$FULL_PACKAGES" == true ]] && printf y || printf n)"; then
                    FULL_PACKAGES=true
                else
                    FULL_PACKAGES=false
                fi
            fi
        else
            ui_warn "Package installation" "skipped"
        fi

        prompt_desktop_shell_profile 3 6

        ui_stage 4 6 "Configuration groups"
        if [[ "$PACKAGES_ONLY" != true ]]; then
            echo "  1) shell      .zshrc and private local config"
            echo "  2) desktop    niri, desktop shell, input and notifications"
            echo "  3) terminal   kitty, fastfetch and cava"
            echo "  4) apps       waypaper, matugen, Thunar and desktop defaults"
            echo "  5) editors    Code and Cursor preferences"
            echo "  6) local-bin  desktop-shell and local helpers"
            echo "  7) media      Pictures/wallpapers"
            read -r -p "$(ui_prompt "Groups (names/numbers, comma separated)" "all")" group_input
            resolve_config_groups "${group_input:-all}"
        else
            ui_warn "Configuration groups" "skipped (packages only)"
        fi

        ui_stage 5 6 "Private configuration"
        if [[ "$PACKAGES_ONLY" == true ]]; then
            ui_warn "Private config" "$HOME/.zshrc.local not touched (packages only)"
        else
            ui_ok "Private config" "$HOME/.zshrc.local is preserved"
            ui_note "Missing files are created from the safe template."
            ui_note "Existing symlinks are archived before replacement."
        fi

        ui_stage 6 6 "Review"
        print_plan_summary
        ui_menu "Action" 1 \
            "Install now|Apply the plan shown above" \
            "Review choices|Return to the first step" \
            "Cancel|Exit without changing this machine"
        action="$UI_MENU_CHOICE"
        case "$action" in
            1) return 0 ;;
            2) continue ;;
            3)
                ui_warn "Cancelled" "no changes were made"
                exit 0
                ;;
        esac
    done
}

run_operation_menu() {
    local operation uninstall_choice

    ui_banner "Dotfiles Installer" "Choose an operation, then review its plan."
    BANNER_PRINTED=true
    ui_section "Choose an operation"
    ui_menu "Select" 1 \
        "Install or restore|Set up packages and configurations" \
        "Update dotfiles|Pull changes and apply them" \
        "Snapshot this machine|Capture packages and managed configurations" \
        "Export packages|Refresh package manifests only" \
        "Doctor diagnostics|Inspect this installation without changing it" \
        "Uninstall|Archive, restore or purge managed configurations" \
        "Exit|Leave without making changes"
    operation="$UI_MENU_CHOICE"

    case "$operation" in
        1)
            ;;
        2)
            UPDATE=true
            if prompt_yes_no "Install changed package manifests too?" n; then
                UPDATE_WITH_PACKAGES=true
            fi
            ;;
        3)
            SNAPSHOT=true
            ;;
        4)
            EXPORT_PACKAGES=true
            ;;
        5)
            DOCTOR=true
            ;;
        6)
            UNINSTALL=true
            ui_section "Uninstall mode"
            ui_menu "Select" 1 \
                "Safe uninstall|Archive and remove managed configurations" \
                "Restore latest backup|Run the newest rollback script" \
                "Purge|Remove managed configurations and install backups"
            uninstall_choice="$UI_MENU_CHOICE"
            case "$uninstall_choice" in
                1) UNINSTALL_MODE=safe ;;
                2) UNINSTALL_MODE=restore ;;
                3) UNINSTALL_MODE=purge ;;
                *)
                    ui_error "Invalid uninstall mode: $uninstall_choice"
                    exit 1
                    ;;
            esac
            ;;
        7)
            ui_warn "Exited without changes."
            exit 0
            ;;
        *)
            ui_error "Invalid operation: $operation"
            exit 1
            ;;
    esac
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

    if [[ -z "$DESKTOP_SHELL_PROFILE" ]]; then
        DESKTOP_SHELL_PROFILE="$(load_saved_desktop_shell_profile || printf 'waybar\n')"
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

    if [[ "$BANNER_PRINTED" != true ]]; then
        ui_banner "Dotfiles Installer" "Make this machine feel like home."
        BANNER_PRINTED=true
    fi
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
    install_package_files \
        true "$ASSUME_YES" "$FULL_PACKAGES" "$INCLUDE_AUR" \
        "$REPO_ROOT" "$DESKTOP_SHELL_PROFILE"
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
    if [[ -z "$DESKTOP_SHELL_PROFILE" ]]; then
        DESKTOP_SHELL_PROFILE="$(load_saved_desktop_shell_profile || printf 'waybar\n')"
    fi

    init_log_once
    print_intro_once

    # shellcheck source=scripts/preflight.sh
    source "$REPO_ROOT/scripts/preflight.sh"
    run_preflight snapshot

    # shellcheck source=scripts/packages-arch.sh
    source "$REPO_ROOT/scripts/packages-arch.sh"
    # shellcheck source=scripts/snapshot.sh
    source "$REPO_ROOT/scripts/snapshot.sh"

    ui_stage 1 5 "Snapshot"
    snapshot_managed_configs
    normalize_captured_text_files
    ui_ok "Text files normalized"
    run_safety_check
    ui_ok "Safety check passed"

    ui_stage 2 5 "Package manifests"
    export_package_manifests

    ui_stage 3 5 "Package plan"
    plan_packages
    print_package_plan_summary

    ui_stage 4 5 "Config plan"
    plan_config_sync
    print_config_plan_summary

    ui_stage 5 5 "Verification"
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
    if [[ -z "$DESKTOP_SHELL_PROFILE" ]]; then
        DESKTOP_SHELL_PROFILE="$(load_saved_desktop_shell_profile || printf 'waybar\n')"
    fi
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
    if [[ -z "$DESKTOP_SHELL_PROFILE" ]]; then
        DESKTOP_SHELL_PROFILE="$(load_saved_desktop_shell_profile || printf 'waybar\n')"
    fi
    init_log_once
    print_intro_once

    # shellcheck source=scripts/preflight.sh
    source "$REPO_ROOT/scripts/preflight.sh"
    run_preflight uninstall

    # shellcheck source=scripts/uninstall.sh
    source "$REPO_ROOT/scripts/uninstall.sh"
    run_uninstall "$REPO_ROOT" "$UNINSTALL_MODE" "$DRY_RUN" "$ASSUME_YES"
}

report_install_failure() {
    local message="$1"
    FAILURE_REPORTED=true
    ui_result_box "Installation stopped" \
        "fail:$message" \
        "warn:Review the log before retrying"
    ui_note "Log: $LOG_FILE"
    if [[ -n "$BACKUP_ROOT" && -x "$BACKUP_ROOT/rollback.sh" ]]; then
        ui_note "Rollback: $BACKUP_ROOT/rollback.sh"
    fi
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
        run_update \
            "$REPO_ROOT" "$DRY_RUN" "$ASSUME_YES" "$UPDATE_WITH_PACKAGES" \
            "$UPDATE_NO_SNAPSHOT_PROMPT" "$DESKTOP_SHELL_PROFILE"
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
        print_plan_summary
    elif is_tty; then
        run_interactive_setup
    else
        ui_error "non-interactive stdin/stdout requires --yes."
        echo "Run in a terminal for interactive mode, or pass --yes for scripted installs." >&2
        return 1
    fi

    if [[ "$SKIP_PACKAGES" != true ]]; then
        if [[ "$PACKAGES_ONLY" == true ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                ui_stage 1 1 "Package plan"
            else
                ui_stage 1 1 "Installing packages"
            fi
        elif [[ "$DRY_RUN" == true ]]; then
            ui_stage 1 4 "Package plan"
        else
            ui_stage 1 4 "Installing packages"
        fi
        if ! install_package_files \
            "$DRY_RUN" "$ASSUME_YES" "$FULL_PACKAGES" "$INCLUDE_AUR" \
            "$REPO_ROOT" "$DESKTOP_SHELL_PROFILE"; then
            report_install_failure "Package installation failed"
            return 1
        fi
    else
        ui_stage 1 4 "Packages"
        ui_warn "Package installation skipped"
    fi

    if [[ "$PACKAGES_ONLY" == true ]]; then
        echo
        if [[ "$DRY_RUN" == true ]]; then
            ui_result_box "Preview complete" \
                "ok:Package plan reviewed" \
                "ok:No configuration changes were made"
        else
            ui_result_box "Installation complete" \
                "ok:Package installation finished" \
                "ok:Configurations were not changed"
        fi
        ui_note "Log: $LOG_FILE"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        ui_stage 2 4 "Desktop shell plan"
    else
        ui_stage 2 4 "Desktop shell"
    fi
    if ! install_desktop_shell_profile \
        "$REPO_ROOT" "$DESKTOP_SHELL_PROFILE" "$DRY_RUN"; then
        report_install_failure "Desktop shell installation failed"
        return 1
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
        ui_stage 3 4 "Configuration plan"
    else
        ui_stage 3 4 "Synchronizing configurations"
    fi
    if ! sync_configs "$REPO_ROOT" "$BACKUP_ROOT" "$DRY_RUN" "${SELECTED_GROUPS[@]}"; then
        report_install_failure "Configuration synchronization failed"
        return 1
    fi

    if group_selected apps "${SELECTED_GROUPS[@]}" \
            || group_selected local-bin "${SELECTED_GROUPS[@]}" \
            || group_selected desktop "${SELECTED_GROUPS[@]}"; then
        if [[ "$DESKTOP_SHELL_PROFILE" == quickshell ]]; then
            disable_wallpaper_console_theme_hook "$DRY_RUN"
        else
            configure_wallpaper_console_theme_hook "$DRY_RUN"
        fi
    fi

    if [[ "$RESTORE_ONLY" == true ]]; then
        verbose_log "restore-only mode: skipping optional service actions"
    fi

    ui_stage 4 4 "Verification"
    if ! verify_installation "$DRY_RUN" "${SELECTED_GROUPS[@]}"; then
        report_install_failure "Verification failed; backup preserved"
        return 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        ui_result_box "Preview complete" \
            "ok:Installation plan verified" \
            "ok:No changes were made" \
            "ok:Rollback path planned"
    else
        save_desktop_shell_profile "$DESKTOP_SHELL_PROFILE"
        ui_result_box "Installation complete" \
            "ok:Desktop profile: $DESKTOP_SHELL_PROFILE" \
            "ok:Configurations verified" \
            "ok:Backup and rollback ready"
        if [[ "$DESKTOP_SHELL_PROFILE" == dual ]]; then
            ui_note "Next: desktop-shell toggle"
            ui_note "Status: desktop-shell status"
        fi
        ui_note "Rollback: $BACKUP_ROOT/rollback.sh"
    fi
    ui_note "Log: $LOG_FILE"
}

run_dry_run_workflow() {
    DRY_RUN=true
    run_install_workflow
}

main() {
    if [[ "$SHOW_MENU" == true || ("$CLI_ARGS_PROVIDED" == false && -t 0 && -t 1) ]]; then
        run_operation_menu
    fi

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

#!/usr/bin/env bash
# Dotfiles installer entrypoint (Arch Linux).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

DRY_RUN=false
ASSUME_YES=false
SKIP_PACKAGES=false
RESTORE_ONLY=false
PACKAGES_ONLY=false
FULL_PACKAGES=false
EXPORT_PACKAGES=false

usage() {
    cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Arch Linux dotfiles installer. Installs package manifests, backs up existing files,
copies configs, and verifies the result.

Options:
  --dry-run          Print planned actions without modifying $HOME
  --yes              Non-interactive mode (assume yes for prompts)
  --skip-packages    Restore configs only, skip package installation
  --packages-only    Install packages only, skip config restore
  --full-packages    Include machine-local packages from packages/arch-machine-local.txt
  --export-packages  Export current machine packages into packages/*.txt
  --restore-only     Skip packages and optional service actions
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
        --export-packages)
            EXPORT_PACKAGES=true
            ;;
        --restore-only)
            SKIP_PACKAGES=true
            RESTORE_ONLY=true
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

require_arch_linux() {
    if [[ ! -f /etc/os-release ]]; then
        echo "Error: /etc/os-release not found. This installer supports Arch Linux only." >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "${ID:-}" != "arch" ]]; then
        echo "Error: unsupported OS '${ID:-unknown}'. This installer supports Arch Linux only." >&2
        exit 1
    fi
}

main() {
    echo "Dotfiles installer"
    echo "Repository: $REPO_ROOT"

    require_arch_linux

    # shellcheck source=scripts/packages-arch.sh
    source "$REPO_ROOT/scripts/packages-arch.sh"

    if [[ "$EXPORT_PACKAGES" == true ]]; then
        echo "==> Exporting package snapshot"
        export_package_snapshot "$REPO_ROOT"
        exit 0
    fi

    if [[ "$SKIP_PACKAGES" != true ]]; then
        echo "==> Installing packages"
        install_package_files "$DRY_RUN" "$ASSUME_YES" "$FULL_PACKAGES" "$REPO_ROOT"
    else
        echo "==> Skipping package installation"
    fi

    if [[ "$PACKAGES_ONLY" == true ]]; then
        echo
        if [[ "$DRY_RUN" == true ]]; then
            echo "Packages-only dry run complete. No config changes were made."
        else
            echo "Packages-only install complete."
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
        echo "==> Dry run: would create backup directory $backup_root"
    else
        backup_root="$(create_backup_dir)"
        mkdir -p "$backup_root"
        echo "==> Created backup directory: $backup_root"
    fi

    echo "==> Syncing configs"
    sync_configs "$REPO_ROOT" "$backup_root" "$DRY_RUN"

    if [[ "$RESTORE_ONLY" == true ]]; then
        echo "==> Restore-only mode: skipping optional service actions"
    fi

    echo "==> Verifying installation"
    verify_installation "$DRY_RUN"

    echo
    if [[ "$DRY_RUN" == true ]]; then
        echo "Dry run complete. No changes were made."
    else
        echo "Install complete."
        echo "Backup directory: $backup_root"
        echo "To roll back: $backup_root/rollback.sh"
    fi
}

main "$@"

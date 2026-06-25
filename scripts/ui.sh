#!/usr/bin/env bash
# Shared terminal output helpers for the dotfiles installer.

if [[ "${DOTFILES_UI_LOADED:-}" == 1 ]]; then
    return 0
fi
DOTFILES_UI_LOADED=1

ui_supports_color() {
    if [[ -n "${NO_COLOR:-}" ]]; then
        return 1
    fi

    case "${DOTFILES_COLOR:-auto}" in
        always)
            return 0
            ;;
        never)
            return 1
            ;;
        auto)
            if [[ "${TERM:-}" == dumb ]]; then
                return 1
            fi
            [[ -t 1 ]]
            ;;
        *)
            if [[ "${TERM:-}" == dumb ]]; then
                return 1
            fi
            [[ -t 1 ]]
            ;;
    esac
}

if ui_supports_color; then
    UI_RESET=$'\033[0m'
    UI_BOLD=$'\033[1m'
    UI_DIM=$'\033[2m'
    UI_RED=$'\033[31m'
    UI_GREEN=$'\033[32m'
    UI_YELLOW=$'\033[33m'
    UI_BLUE=$'\033[34m'
    UI_MAGENTA=$'\033[35m'
    UI_CYAN=$'\033[36m'
else
    UI_RESET=
    UI_BOLD=
    UI_DIM=
    UI_RED=
    UI_GREEN=
    UI_YELLOW=
    UI_BLUE=
    UI_MAGENTA=
    UI_CYAN=
fi

ui_color() {
    local color="$1"
    shift
    printf '%s%s%s' "$color" "$*" "$UI_RESET"
}

ui_banner() {
    printf '%s\n' "$(ui_color "$UI_BOLD$UI_MAGENTA" "Dotfiles installer")"
    printf '%s\n' "$(ui_color "$UI_DIM" "Ready to make this machine feel like home.")"
}

ui_step() {
    printf '%s %s\n' "$(ui_color "$UI_BLUE" "=>")" "$(ui_color "$UI_BOLD" "$*")"
}

ui_substep() {
    printf '%s %s\n' "$(ui_color "$UI_CYAN" "->")" "$*"
}

ui_success() {
    printf '%s %s\n' "$(ui_color "$UI_GREEN" "OK")" "$*"
}

ui_warn() {
    printf '%s %s\n' "$(ui_color "$UI_YELLOW" "WARN")" "$*"
}

ui_error() {
    printf '%s %s\n' "$(ui_color "$UI_RED" "Error:")" "$*" >&2
}

ui_dry_run() {
    printf '%s %s\n' "$(ui_color "$UI_DIM" "[dry-run]")" "$*"
}

ui_section() {
    printf '\n%s\n' "$(ui_color "$UI_BOLD$UI_MAGENTA" "== $* ==")"
}

ui_prompt() {
    local prompt="$1"
    local hint="$2"
    printf '%s %s ' "$(ui_color "$UI_CYAN" "?")" "$prompt [$hint]"
}

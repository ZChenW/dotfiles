#!/usr/bin/env bash
# Shared terminal output helpers for the dotfiles installer.

if [[ "${DOTFILES_UI_LOADED:-}" == 1 ]]; then
    return 0
fi
DOTFILES_UI_LOADED=1

UI_RESET=
UI_BOLD=
UI_DIM=
UI_RED=
UI_GREEN=
UI_YELLOW=
UI_BLUE=

ICON_OK="✓"
ICON_WARN="⚠"
ICON_FAIL="✕"
ICON_STEP="▸"
ICON_DOT="•"

BOX_TOP_LEFT="╭"
BOX_TOP_RIGHT="╮"
BOX_BOTTOM_LEFT="╰"
BOX_BOTTOM_RIGHT="╯"
BOX_HORIZONTAL="─"
BOX_VERTICAL="│"

UI_VERBOSE="${UI_VERBOSE:-0}"
UI_DEBUG="${UI_DEBUG:-0}"
DOTFILES_LOG_FILE="${DOTFILES_LOG_FILE:-}"

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
        auto | *)
            if [[ "${TERM:-}" == dumb ]]; then
                return 1
            fi
            [[ -t 1 ]]
            ;;
    esac
}

ui_init() {
    if [[ -n "${DOTFILES_ASCII:-}" ]]; then
        ICON_OK="[OK]"
        ICON_WARN="[WARN]"
        ICON_FAIL="[FAIL]"
        ICON_STEP=">"
        ICON_DOT="-"
        BOX_TOP_LEFT="+"
        BOX_TOP_RIGHT="+"
        BOX_BOTTOM_LEFT="+"
        BOX_BOTTOM_RIGHT="+"
        BOX_HORIZONTAL="-"
        BOX_VERTICAL="|"
    fi

    if ui_supports_color; then
        UI_RESET=$'\033[0m'
        UI_BOLD=$'\033[1m'
        UI_DIM=$'\033[2m'
        UI_RED=$'\033[31m'
        UI_GREEN=$'\033[32m'
        UI_YELLOW=$'\033[33m'
        UI_BLUE=$'\033[34m'
    else
        UI_RESET=
        UI_BOLD=
        UI_DIM=
        UI_RED=
        UI_GREEN=
        UI_YELLOW=
        UI_BLUE=
    fi
}

ui_repeat() {
    local char="$1"
    local count="$2"
    local out=""
    local i
    for ((i = 0; i < count; i++)); do
        out+="$char"
    done
    printf '%s' "$out"
}

ui_color() {
    local color="$1"
    shift
    printf '%s%s%s' "$color" "$*" "$UI_RESET"
}

ui_pad_right() {
    local text="$1"
    local width="$2"
    printf '%-*s' "$width" "$text"
}

ui_banner() {
    local title="${1:-Dotfiles Installer}"
    local subtitle="${2:-Make this machine feel like home.}"
    local width=44
    local inner=$((width - 2))

    printf '%s%s%s\n' "$(ui_color "$UI_BLUE" "$BOX_TOP_LEFT")" "$(ui_color "$UI_BLUE" "$(ui_repeat "$BOX_HORIZONTAL" "$inner")")" "$(ui_color "$UI_BLUE" "$BOX_TOP_RIGHT")"
    printf '%s %s %s\n' "$(ui_color "$UI_BLUE" "$BOX_VERTICAL")" "$(ui_color "$UI_BOLD" "$(ui_pad_right "$title" $((inner - 2)))")" "$(ui_color "$UI_BLUE" "$BOX_VERTICAL")"
    printf '%s %s %s\n' "$(ui_color "$UI_BLUE" "$BOX_VERTICAL")" "$(ui_color "$UI_DIM" "$(ui_pad_right "$subtitle" $((inner - 2)))")" "$(ui_color "$UI_BLUE" "$BOX_VERTICAL")"
    printf '%s%s%s\n' "$(ui_color "$UI_BLUE" "$BOX_BOTTOM_LEFT")" "$(ui_color "$UI_BLUE" "$(ui_repeat "$BOX_HORIZONTAL" "$inner")")" "$(ui_color "$UI_BLUE" "$BOX_BOTTOM_RIGHT")"
}

ui_context() {
    local label value
    while (($# >= 2)); do
        label="$1"
        value="$2"
        shift 2
        ui_kv "$label" "$value"
    done
}

ui_kv() {
    local label="$1"
    local value="$2"
    printf '  %-10s %s\n' "$label" "$(ui_color "$UI_DIM" "$value")"
}

ui_section() {
    printf '\n%s %s\n' "$(ui_color "$UI_BLUE" "$ICON_STEP")" "$(ui_color "$UI_BOLD" "$*")"
}

ui_status_line() {
    local icon="$1"
    local color="$2"
    local label="$3"
    local meta="${4:-}"
    if [[ -n "$meta" ]]; then
        printf '  %s %-26s %s\n' "$(ui_color "$color" "$icon")" "$label" "$(ui_color "$UI_DIM" "$meta")"
    else
        printf '  %s %s\n' "$(ui_color "$color" "$icon")" "$label"
    fi
}

ui_ok() {
    ui_status_line "$ICON_OK" "$UI_GREEN" "$1" "${2:-}"
}

ui_warn() {
    ui_status_line "$ICON_WARN" "$UI_YELLOW" "$1" "${2:-}"
}

ui_fail() {
    ui_status_line "$ICON_FAIL" "$UI_RED" "$1" "${2:-}"
}

ui_detail() {
    [[ "${UI_VERBOSE:-0}" == 1 || "${UI_DEBUG:-0}" == 1 ]] || return 0
    printf '    %s %s\n' "$(ui_color "$UI_DIM" "$ICON_DOT")" "$*"
}

ui_note() {
    printf '    %s\n' "$(ui_color "$UI_DIM" "$*")"
}

ui_table_header() {
    local col1="$1"
    local col2="$2"
    printf '\n  %-27s %s\n' "$col1" "$col2"
    printf '  %s\n' "$(ui_repeat "$BOX_HORIZONTAL" 33)"
}

ui_table_row() {
    local col1="$1"
    local col2="$2"
    printf '  %-27s %5s\n' "$col1" "$col2"
}

ui_result_box() {
    local title="$1"
    shift
    local content_width=42
    local inner=$((content_width + 1))
    local title_text=" $title "
    local top_fill=$((inner - ${#title_text}))
    local item kind text icon color raw_content content pad_width

    printf '\n%s%s%s%s\n' "$(ui_color "$UI_BLUE" "$BOX_TOP_LEFT")" "$(ui_color "$UI_BLUE" "$BOX_HORIZONTAL")" "$(ui_color "$UI_BOLD" "$title_text")" "$(ui_color "$UI_BLUE" "$(ui_repeat "$BOX_HORIZONTAL" "$top_fill")$BOX_TOP_RIGHT")"
    for item in "$@"; do
        kind="ok"
        text="$item"
        if [[ "$item" == *:* ]]; then
            kind="${item%%:*}"
            text="${item#*:}"
        fi
        case "$kind" in
            warn)
                icon="$ICON_WARN"
                color="$UI_YELLOW"
                ;;
            fail)
                icon="$ICON_FAIL"
                color="$UI_RED"
                ;;
            ok | *)
                icon="$ICON_OK"
                color="$UI_GREEN"
                ;;
        esac
        raw_content="$icon $text"
        content="$(printf '%s %s' "$(ui_color "$color" "$icon")" "$text")"
        pad_width=$((content_width - ${#raw_content}))
        ((pad_width < 0)) && pad_width=0
        printf '%s %s%s%s\n' "$(ui_color "$UI_BLUE" "$BOX_VERTICAL")" "$content" "$(ui_repeat " " "$pad_width")" "$(ui_color "$UI_BLUE" "$BOX_VERTICAL")"
    done
    printf '%s%s%s\n' "$(ui_color "$UI_BLUE" "$BOX_BOTTOM_LEFT")" "$(ui_color "$UI_BLUE" "$(ui_repeat "$BOX_HORIZONTAL" "$inner")")" "$(ui_color "$UI_BLUE" "$BOX_BOTTOM_RIGHT")"
}

log_raw() {
    local msg="$1"
    if [[ -n "${DOTFILES_LOG_FILE:-}" ]]; then
        printf '%s\n' "$msg" >>"$DOTFILES_LOG_FILE"
    fi
    return 0
}

verbose_log() {
    local msg="$1"
    ui_detail "$msg"
    log_raw "$msg"
}

debug_log() {
    local msg="$1"
    if [[ "${UI_DEBUG:-0}" == 1 ]]; then
        printf '%s\n' "$msg"
    fi
    log_raw "$msg"
    return 0
}

ui_cmd_debug() {
    debug_log "$*"
}

ui_review_candidates() {
    local -a candidates=("$@")
    local total="${#candidates[@]}"
    local i

    ((total > 0)) || return 0

    if [[ "${UI_VERBOSE:-0}" == 1 || "${UI_DEBUG:-0}" == 1 ]]; then
        for candidate in "${candidates[@]}"; do
            ui_detail "$candidate"
        done
        return 0
    fi

    local limit=6
    local inline=""
    local shown=$total
    if ((shown > limit)); then
        shown=$limit
    fi
    for ((i = 0; i < shown; i++)); do
        if [[ -n "$inline" ]]; then
            inline+=", "
        fi
        inline+="${candidates[$i]}"
    done
    if ((total > limit)); then
        inline+=" …"
    fi
    ui_note "$inline"
}

ui_step() {
    ui_section "$*"
}

ui_substep() {
    verbose_log "$*"
}

ui_success() {
    ui_ok "$*"
}

ui_error() {
    printf '%s %s\n' "$(ui_color "$UI_RED" "Error:")" "$*" >&2
}

ui_dry_run() {
    debug_log "[dry-run] $*"
}

ui_prompt() {
    local prompt="$1"
    local hint="$2"
    printf '%s %s ' "$(ui_color "$UI_BLUE" "?")" "$prompt [$hint]"
}

ui_init

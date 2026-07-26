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
UI_CYAN=

ICON_OK="✓"
ICON_WARN="⚠"
ICON_FAIL="✕"
ICON_STEP="▸"
ICON_DOT="•"
ICON_ACTIVE="●"
ICON_INACTIVE="○"

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
        ICON_ACTIVE="(*)"
        ICON_INACTIVE="( )"
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
        UI_CYAN=$'\033[36m'
    else
        UI_RESET=
        UI_BOLD=
        UI_DIM=
        UI_RED=
        UI_GREEN=
        UI_YELLOW=
        UI_BLUE=
        UI_CYAN=
    fi
}

ui_terminal_width() {
    local width="${COLUMNS:-}"

    if [[ ! "$width" =~ ^[0-9]+$ ]] && [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
        width="$(tput cols 2>/dev/null || true)"
    fi
    if [[ ! "$width" =~ ^[0-9]+$ ]]; then
        width=80
    fi
    ((width < 24)) && width=24
    printf '%s\n' "$width"
}

ui_compact_width() {
    local terminal_width
    terminal_width="$(ui_terminal_width)"
    if ((terminal_width > 78)); then
        printf '78\n'
    else
        printf '%s\n' "$terminal_width"
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

ui_truncate() {
    local text="$1"
    local width="$2"
    local suffix="…"

    if ((width <= 0)); then
        return 0
    fi
    if ((${#text} <= width)); then
        printf '%s' "$text"
        return 0
    fi
    if [[ -n "${DOTFILES_ASCII:-}" ]]; then
        suffix="..."
    fi
    if ((width <= ${#suffix})); then
        printf '%.*s' "$width" "$text"
    else
        printf '%.*s%s' "$((width - ${#suffix}))" "$text" "$suffix"
    fi
}

ui_logo() {
    # Giant wordmark shown above the installer banner.
    if [[ -n "${DOTFILES_ASCII:-}" ]]; then
        printf '%s\n' "$(ui_color "$UI_BOLD$UI_BLUE" '
 ____   ___ _____ _____ ___ _     _____ ____
|  _ \ / _ \_   _|  ___|_ _| |   | ____/ ___|
| | | | | | || | | |_   | || |   |  _| \___ \
| |_| | |_| || | |  _|  | || |___| |___ ___) |
|____/ \___/ |_| |_|   |___|_____|_____|____/
')"
    else
        printf '%s\n' "$(ui_color "$UI_BOLD$UI_BLUE" '
██████╗  ██████╗ ████████╗███████╗██╗██╗     ███████╗███████╗
██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝██║██║     ██╔════╝██╔════╝
██║  ██║██║   ██║   ██║   █████╗  ██║██║     █████╗  ███████╗
██║  ██║██║   ██║   ██║   ██╔══╝  ██║██║     ██╔══╝  ╚════██║
██████╔╝╚██████╔╝   ██║   ██║     ██║███████╗███████╗███████║
╚═════╝  ╚═════╝    ╚═╝   ╚═╝     ╚═╝╚══════╝╚══════╝╚══════╝
')"
    fi
}

ui_banner() {
    local title="${1:-Dotfiles Installer}"
    local subtitle="${2:-Make this machine feel like home.}"
    local width=44
    local terminal_width inner title_width subtitle_width

    title_width=$((${#title} + 4))
    subtitle_width=$((${#subtitle} + 4))
    ((title_width > width)) && width="$title_width"
    ((subtitle_width > width)) && width="$subtitle_width"
    terminal_width="$(ui_compact_width)"
    ((width > terminal_width)) && width="$terminal_width"
    ((width < 24)) && width=24
    inner=$((width - 2))
    title="$(ui_truncate "$title" "$((inner - 2))")"
    subtitle="$(ui_truncate "$subtitle" "$((inner - 2))")"

    ui_logo
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

ui_stage() {
    local current="$1"
    local total="$2"
    local title="$3"
    local bar_width=24
    local filled empty

    printf '\n%s %s  %s\n' \
        "$(ui_color "$UI_BLUE$UI_BOLD" "$current/$total")" \
        "$(ui_color "$UI_BOLD" "$title")" \
        "$(ui_color "$UI_DIM" "step $current of $total")"

    if [[ -t 1 ]]; then
        filled=$((current * bar_width / total))
        ((filled < 1)) && filled=1
        empty=$((bar_width - filled))
        if [[ -n "${DOTFILES_ASCII:-}" ]]; then
            printf '  %s%s\n' \
                "$(ui_color "$UI_CYAN" "$(ui_repeat "=" "$filled")")" \
                "$(ui_color "$UI_DIM" "$(ui_repeat "-" "$empty")")"
        else
            printf '  %s%s\n' \
                "$(ui_color "$UI_CYAN" "$(ui_repeat "━" "$filled")")" \
                "$(ui_color "$UI_DIM" "$(ui_repeat "─" "$empty")")"
        fi
    fi
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

ui_plan_box() {
    local title="$1"
    shift
    local width inner label_width=20 value_width item label value
    local title_text top_fill label_text value_text

    width="$(ui_compact_width)"
    if ((width < 46)); then
        ui_section "$title"
        label_width=18
        value_width=$((width - label_width - 3))
        for item in "$@"; do
            label="${item%%|*}"
            value="${item#*|}"
            label_text="$(ui_truncate "$label" "$label_width")"
            value_text="$(ui_truncate "$value" "$value_width")"
            printf '  %-*s %s\n' "$label_width" "$label_text" "$value_text"
        done
        return 0
    fi

    inner=$((width - 2))
    value_width=$((inner - label_width - 2))
    title_text=" $title "
    top_fill=$((inner - 1 - ${#title_text}))
    ((top_fill < 1)) && top_fill=1

    printf '\n%s%s%s%s\n' \
        "$(ui_color "$UI_BLUE" "$BOX_TOP_LEFT$BOX_HORIZONTAL")" \
        "$(ui_color "$UI_BOLD" "$title_text")" \
        "$(ui_color "$UI_BLUE" "$(ui_repeat "$BOX_HORIZONTAL" "$top_fill")")" \
        "$(ui_color "$UI_BLUE" "$BOX_TOP_RIGHT")"
    for item in "$@"; do
        label="${item%%|*}"
        value="${item#*|}"
        label_text="$(ui_truncate "$label" "$label_width")"
        value_text="$(ui_truncate "$value" "$value_width")"
        printf '%s %-*s %s%s%s\n' \
            "$(ui_color "$UI_BLUE" "$BOX_VERTICAL")" \
            "$label_width" "$(ui_color "$UI_DIM" "$label_text")" \
            "$(ui_color "$UI_BOLD" "$value_text")" \
            "$(ui_repeat " " "$((value_width - ${#value_text}))")" \
            "$(ui_color "$UI_BLUE" "$BOX_VERTICAL")"
    done
    printf '%s%s%s\n' \
        "$(ui_color "$UI_BLUE" "$BOX_BOTTOM_LEFT")" \
        "$(ui_color "$UI_BLUE" "$(ui_repeat "$BOX_HORIZONTAL" "$inner")")" \
        "$(ui_color "$UI_BLUE" "$BOX_BOTTOM_RIGHT")"
}

ui_result_box() {
    local title="$1"
    shift
    local width content_width inner terminal_width desired_width=44
    local title_text=" $title "
    local top_fill
    local item kind text icon color raw_content content pad_width

    terminal_width="$(ui_compact_width)"
    for item in "$@"; do
        text="$item"
        [[ "$item" == *:* ]] && text="${item#*:}"
        ((${#text} + 8 > desired_width)) && desired_width=$((${#text} + 8))
    done
    ((desired_width > terminal_width)) && desired_width="$terminal_width"
    if ((desired_width < 32 && terminal_width >= 32)); then
        desired_width=32
    fi
    width="$desired_width"
    inner=$((width - 2))
    content_width=$((width - 3))
    title_text="$(ui_truncate "$title_text" "$((width - 3))")"
    top_fill=$((width - 3 - ${#title_text}))

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
        text="$(ui_truncate "$text" "$((content_width - ${#icon} - 1))")"
        raw_content="$icon $text"
        content="$(printf '%s %s' "$(ui_color "$color" "$icon")" "$text")"
        pad_width=$((content_width - ${#raw_content}))
        ((pad_width < 0)) && pad_width=0
        printf '%s %s%s%s\n' "$(ui_color "$UI_BLUE" "$BOX_VERTICAL")" "$content" "$(ui_repeat " " "$pad_width")" "$(ui_color "$UI_BLUE" "$BOX_VERTICAL")"
    done
    printf '%s%s%s\n' "$(ui_color "$UI_BLUE" "$BOX_BOTTOM_LEFT")" "$(ui_color "$UI_BLUE" "$(ui_repeat "$BOX_HORIZONTAL" "$inner")")" "$(ui_color "$UI_BLUE" "$BOX_BOTTOM_RIGHT")"
}

ui_menu_render() {
    local selected="$1"
    shift
    local width option_width index=1 item label description marker color

    width="$(ui_compact_width)"
    option_width=$((width - 8))
    for item in "$@"; do
        label="${item%%|*}"
        description="${item#*|}"
        if ((index == selected)); then
            marker="$ICON_ACTIVE"
            color="$UI_CYAN$UI_BOLD"
        else
            marker="$ICON_INACTIVE"
            color="$UI_DIM"
        fi

        if ((width < 58)) || [[ "$description" == "$label" || -z "$description" ]]; then
            printf '  %s %s\n' \
                "$(ui_color "$color" "$marker")" \
                "$(ui_color "$color" "$(ui_truncate "$label" "$option_width")")"
        else
            printf '  %s %-22s %s\n' \
                "$(ui_color "$color" "$marker")" \
                "$(ui_color "$color" "$(ui_truncate "$label" 22)")" \
                "$(ui_color "$UI_DIM" "$(ui_truncate "$description" "$((option_width - 23))")")"
        fi
        ((++index))
    done
}

# Sets UI_MENU_CHOICE to a one-based option index.
# TTY users get arrow-key navigation; piped/scripted input keeps a plain,
# deterministic numbered prompt.
ui_menu() {
    local prompt="$1"
    local default="$2"
    shift 2
    local -a options=("$@")
    local count="${#options[@]}"
    local selected="$default"
    local key sequence lines item index label description

    UI_MENU_CHOICE=""
    ((count > 0)) || return 1
    if ((selected < 1 || selected > count)); then
        selected=1
    fi

    if [[ ! -t 0 || ! -t 1 ]]; then
        index=1
        for item in "${options[@]}"; do
            label="${item%%|*}"
            description="${item#*|}"
            printf '  %d) %s\n' "$index" "$label"
            if [[ -n "$description" && "$description" != "$label" ]]; then
                printf '     %s\n' "$(ui_color "$UI_DIM" "$description")"
            fi
            ((++index))
        done
        read -r -p "$(ui_prompt "$prompt" "$default")" key
        key="${key:-$default}"
        if [[ "$key" =~ ^[0-9]+$ ]] && ((key >= 1 && key <= count)); then
            UI_MENU_CHOICE="$key"
            return 0
        fi
        ui_error "Invalid choice: $key"
        return 1
    fi

    while true; do
        ui_menu_render "$selected" "${options[@]}"
        if [[ -n "${DOTFILES_ASCII:-}" ]]; then
            printf '  %s\n' "$(ui_color "$UI_DIM" "Up/Down move  Enter select  1-$count quick select")"
        else
            printf '  %s\n' "$(ui_color "$UI_DIM" "↑/↓ move  Enter select  1–$count quick select")"
        fi
        lines=$((count + 1))

        if ! IFS= read -r -s -n 1 key; then
            printf '\n'
            return 1
        fi
        case "$key" in
            "")
                UI_MENU_CHOICE="$selected"
                printf '\n'
                return 0
                ;;
            [1-9])
                if ((key <= count)); then
                    selected="$key"
                    # Number shortcuts select immediately. Consume an optional
                    # trailing Enter so it cannot answer the next prompt.
                    sequence=""
                    IFS= read -r -s -n 1 -t 0.05 sequence || true
                    printf '\033[%dA\r\033[J' "$lines"
                    ui_menu_render "$selected" "${options[@]}"
                    item="${options[$((selected - 1))]}"
                    label="${item%%|*}"
                    printf '  %s %s\n\n' \
                        "$(ui_color "$UI_DIM" "Selected:")" \
                        "$(ui_color "$UI_BOLD" "$label")"
                    # Consumed by the caller after this function returns.
                    # shellcheck disable=SC2034
                    UI_MENU_CHOICE="$selected"
                    return 0
                fi
                ;;
            $'\e')
                sequence=""
                IFS= read -r -s -n 2 -t 0.1 sequence || true
                case "$sequence" in
                    "[A")
                        selected=$((selected - 1))
                        ((selected < 1)) && selected="$count"
                        ;;
                    "[B")
                        selected=$((selected + 1))
                        ((selected > count)) && selected=1
                        ;;
                esac
                ;;
        esac
        printf '\033[%dA\r\033[J' "$lines"
    done
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

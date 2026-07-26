#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

run_ui_helper() {
    local color_mode="$1"
    local no_color="$2"
    local ascii="${3:-}"

    TERM=dumb DOTFILES_COLOR="$color_mode" NO_COLOR="$no_color" DOTFILES_ASCII="$ascii" bash -c '
        source "$1"
        ui_init
        ui_section "1/2 Installing packages"
        ui_ok "Pacman packages" "3 packages"
        ui_warn "Machine-local skipped" "use --full-packages"
        UI_VERBOSE=1 ui_detail "backup   ~/.zshrc"
    ' _ "$REPO_ROOT/scripts/ui.sh"
}

echo "==> test 1: non-tty output is plain by default"
plain_output="$(run_ui_helper auto "")"
if [[ "$plain_output" == *$'\033'* ]]; then
    echo "Expected default non-tty UI output to omit color escapes" >&2
    printf '%s\n' "$plain_output" >&2
    exit 1
fi
if [[ "$plain_output" != *"1/2 Installing packages"* || "$plain_output" != *"Pacman packages"* || "$plain_output" != *"backup   ~/.zshrc"* ]]; then
    echo "Expected readable plain UI output" >&2
    printf '%s\n' "$plain_output" >&2
    exit 1
fi

echo "==> test 2: DOTFILES_COLOR=always enables color"
color_output="$(run_ui_helper always "")"
if [[ "$color_output" != *$'\033['* ]]; then
    echo "Expected forced UI color output to include ANSI escapes" >&2
    printf '%s\n' "$color_output" >&2
    exit 1
fi

echo "==> test 3: NO_COLOR disables forced color"
no_color_output="$(run_ui_helper always 1)"
if [[ "$no_color_output" == *$'\033'* ]]; then
    echo "Expected NO_COLOR to suppress ANSI escapes" >&2
    printf '%s\n' "$no_color_output" >&2
    exit 1
fi

echo "==> test 4: ASCII mode avoids Unicode symbols and box drawing"
ascii_output="$(run_ui_helper auto "" 1)"
if [[ "$ascii_output" == *"✓"* || "$ascii_output" == *"⚠"* || "$ascii_output" == *"▸"* || "$ascii_output" == *"•"* ]]; then
    echo "Expected ASCII UI output to avoid Unicode icons" >&2
    printf '%s\n' "$ascii_output" >&2
    exit 1
fi
if [[ "$ascii_output" != *"[OK]"* || "$ascii_output" != *"[WARN]"* || "$ascii_output" != *"> 1/2 Installing packages"* ]]; then
    echo "Expected ASCII fallback icons" >&2
    printf '%s\n' "$ascii_output" >&2
    exit 1
fi

echo "==> test 5: banner, table, and result box render"
box_output="$(
    TERM=dumb DOTFILES_COLOR=auto bash -c '
        source "$1"
        ui_init
        ui_banner "Dotfiles Installer" "Make this machine feel like home."
        ui_kv "Repository" "/tmp/repo"
        ui_table_header "manifest" "lines"
        ui_table_row "arch-essential.txt" "24"
        ui_result_box "Result" "ok:Dry run complete" "warn:Manual review suggested"
    ' _ "$REPO_ROOT/scripts/ui.sh"
)"
if [[ "$(grep -c "Dotfiles Installer" <<<"$box_output")" -ne 1 ]]; then
    echo "Expected one banner title" >&2
    printf '%s\n' "$box_output" >&2
    exit 1
fi
if [[ "$box_output" != *"██████"* ]]; then
    echo "Expected giant Unicode DOTFILES logo in default banner" >&2
    printf '%s\n' "$box_output" >&2
    exit 1
fi
if [[ "$box_output" != *"manifest"* || "$box_output" != *"arch-essential.txt"* || "$box_output" != *"Dry run complete"* || "$box_output" != *"Manual review suggested"* ]]; then
    echo "Expected table and result box content" >&2
    printf '%s\n' "$box_output" >&2
    exit 1
fi

echo "==> test 6: ASCII mode uses plain logo"
ascii_logo_output="$(
    TERM=dumb DOTFILES_COLOR=auto DOTFILES_ASCII=1 bash -c '
        source "$1"
        ui_init
        ui_logo
    ' _ "$REPO_ROOT/scripts/ui.sh"
)"
if [[ "$ascii_logo_output" != *"____"* || "$ascii_logo_output" != *"|  _ \\"* ]]; then
    echo "Expected ASCII DOTFILES logo fallback" >&2
    printf '%s\n' "$ascii_logo_output" >&2
    exit 1
fi
if [[ "$ascii_logo_output" == *"█"* ]]; then
    echo "Expected ASCII logo to avoid block characters" >&2
    printf '%s\n' "$ascii_logo_output" >&2
    exit 1
fi

echo "==> test 7: stages and plan cards render"
plan_output="$(
    TERM=dumb DOTFILES_COLOR=auto COLUMNS=72 bash -c '
        source "$1"
        ui_init
        ui_stage 2 6 "Software scope"
        ui_plan_box "Installation plan" \
            "Desktop shell|dual" \
            "Packages|Official + AUR" \
            "Private config|~/.zshrc.local preserved"
    ' _ "$REPO_ROOT/scripts/ui.sh"
)"
if [[ "$plan_output" != *"2/6"*"Software scope"* \
    || "$plan_output" != *"Installation plan"* \
    || "$plan_output" != *"Desktop shell"*"dual"* ]]; then
    echo "Expected stage and installation plan output" >&2
    printf '%s\n' "$plan_output" >&2
    exit 1
fi

echo "==> test 8: scripted menu input remains deterministic"
menu_output="$(
    printf '2\n' |
        TERM=dumb DOTFILES_COLOR=auto bash -c '
            source "$1"
            ui_init
            ui_menu "Select" 1 \
                "Waybar|Current shell" \
                "QuickShell|Pinned shell"
            printf "choice=%s\n" "$UI_MENU_CHOICE"
        ' _ "$REPO_ROOT/scripts/ui.sh"
)"
if [[ "$menu_output" != *"1) Waybar"* \
    || "$menu_output" != *"2) QuickShell"* \
    || "$menu_output" != *"choice=2"* ]]; then
    echo "Expected numbered menu fallback and selected value" >&2
    printf '%s\n' "$menu_output" >&2
    exit 1
fi

echo "==> test 9: narrow output stays readable"
narrow_output="$(
    TERM=dumb DOTFILES_COLOR=auto DOTFILES_ASCII=1 COLUMNS=40 bash -c '
        source "$1"
        ui_init
        ui_plan_box "Narrow plan" \
            "Desktop shell|Waybar and QuickShell" \
            "Very long setting name|A deliberately long value that must fit"
        ui_result_box "Installation complete" \
            "ok:A deliberately long result that must fit the terminal"
    ' _ "$REPO_ROOT/scripts/ui.sh"
)"
if [[ "$narrow_output" != *"Narrow plan"* \
    || "$narrow_output" != *"Installation complete"* ]]; then
    echo "Expected narrow fallback output" >&2
    printf '%s\n' "$narrow_output" >&2
    exit 1
fi
if awk 'length($0) > 40 { exit 1 }' <<<"$narrow_output"; then
    :
else
    echo "Expected narrow UI lines to fit within 40 columns" >&2
    printf '%s\n' "$narrow_output" >&2
    exit 1
fi

very_narrow_output="$(
    TERM=dumb DOTFILES_COLOR=auto DOTFILES_ASCII=1 COLUMNS=24 bash -c '
        source "$1"
        ui_init
        ui_result_box "Installation complete" \
            "ok:A deliberately long result"
    ' _ "$REPO_ROOT/scripts/ui.sh"
)"
if ! awk 'length($0) > 24 { exit 1 }' <<<"$very_narrow_output"; then
    echo "Expected result box to respect a 24-column terminal" >&2
    printf '%s\n' "$very_narrow_output" >&2
    exit 1
fi

echo "==> test 10: colored menu descriptions share one column"
colored_menu="$(
    NO_COLOR='' TERM=dumb DOTFILES_COLOR=always COLUMNS=78 bash -c '
        source "$1"
        ui_init
        ui_menu_render 1 \
            "A|Description" \
            "Much longer label|Description"
    ' _ "$REPO_ROOT/scripts/ui.sh"
)"
# shellcheck disable=SC2001
plain_menu="$(sed $'s/\033\\[[0-9;]*m//g' <<<"$colored_menu")"
mapfile -t description_columns < <(
    awk '/Description/ { print index($0, "Description") }' <<<"$plain_menu"
)
if ((${#description_columns[@]} != 2)) \
    || [[ "${description_columns[0]}" != "${description_columns[1]}" ]]; then
    echo "Expected colored menu descriptions to share one starting column" >&2
    printf '%s\n' "$plain_menu" >&2
    exit 1
fi

echo "==> test 11: arrow navigation avoids full-region clears"
if command -v script >/dev/null 2>&1; then
    pty_command="NO_COLOR= TERM=xterm DOTFILES_COLOR=never bash -e -c 'source \"$REPO_ROOT/scripts/ui.sh\"; ui_init; ui_menu \"Select\" 1 \"First|one\" \"Second|two\"; printf \"choice=%s\\\\n\" \"\$UI_MENU_CHOICE\"'"
    navigation_output="$(
        printf '\033[B\033[B\033[A\n' |
            script -qec "$pty_command" /dev/null
    )"
    if [[ "$navigation_output" == *$'\033[J'* ]]; then
        echo "Expected arrow navigation not to clear and redraw the full menu region" >&2
        exit 1
    fi
    if [[ "$navigation_output" != *$'\033[?25l'* ]]; then
        echo "Expected interactive menus to hide the blinking terminal cursor" >&2
        exit 1
    fi
    if [[ "$navigation_output" != *$'\033[?25h'* ]]; then
        echo "Expected interactive menus to restore the terminal cursor" >&2
        exit 1
    fi
    if [[ "$navigation_output" != *"choice=2"* ]]; then
        echo "Expected arrow navigation to select the second item" >&2
        printf '%q\n' "$navigation_output" >&2
        exit 1
    fi
    navigation_help_count="$(
        grep -F -c "quick select" <<<"$navigation_output" || true
    )"
    if [[ "$navigation_help_count" != 1 ]]; then
        echo "Expected arrow navigation to render the menu frame only once" >&2
        printf 'Observed help rows: %s\n' "$navigation_help_count" >&2
        exit 1
    fi

    interrupt_command="NO_COLOR= TERM=xterm DOTFILES_COLOR=never \"$REPO_ROOT/install.sh\" --menu --ascii --no-color"
    interrupt_output="$(
        { sleep 0.2; printf '\003'; } |
            script -qec "$interrupt_command" /dev/null || true
    )"
    if [[ "$interrupt_output" != *$'\033[?25l'* \
        || "$interrupt_output" != *$'\033[?25h'* ]]; then
        echo "Expected Ctrl+C to restore a cursor hidden by the menu" >&2
        exit 1
    fi
else
    echo "script(1) unavailable; PTY navigation check skipped"
fi

echo "All UI tests passed."

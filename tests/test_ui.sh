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

echo "All UI tests passed."

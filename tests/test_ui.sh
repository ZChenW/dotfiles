#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

run_ui_helper() {
    local color_mode="$1"
    local no_color="$2"

    TERM=dumb DOTFILES_COLOR="$color_mode" NO_COLOR="$no_color" bash -c '
        source "$1"
        ui_step "Installing packages"
        ui_dry_run "preview action"
    ' _ "$REPO_ROOT/scripts/ui.sh"
}

echo "==> test 1: non-tty output is plain by default"
plain_output="$(run_ui_helper auto "")"
if [[ "$plain_output" == *$'\033'* ]]; then
    echo "Expected default non-tty UI output to omit color escapes" >&2
    printf '%s\n' "$plain_output" >&2
    exit 1
fi
if [[ "$plain_output" != *"=> Installing packages"* || "$plain_output" != *"[dry-run] preview action"* ]]; then
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

echo "All UI tests passed."

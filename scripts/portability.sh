#!/usr/bin/env bash
# Shared portable/live boundary. Staging always obeys the caller's TMPDIR.
# shellcheck disable=SC2034 # consumed by the sync and snapshot callers
DOTFILES_PORTABILITY_PY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/portability.py"

dotfiles_hostname() {
    local name="${DOTFILES_HOSTNAME:-$(uname -n)}"
    if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ || "$name" == . || "$name" == .. ]]; then
        printf 'Invalid dotfiles hostname: %s\n' "$name" >&2
        return 1
    fi
    printf '%s\n' "$name"
}

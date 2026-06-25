#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/packages-arch.sh
source "$REPO_ROOT/scripts/packages-arch.sh"

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

packages_dir="$tmp_dir/repo/packages"
fakebin="$tmp_dir/bin"
mkdir -p "$packages_dir" "$fakebin"

cat >"$packages_dir/arch-essential.txt" <<'EOF'
git
EOF
cat >"$packages_dir/arch-desktop.txt" <<'EOF'
EOF
cat >"$packages_dir/arch-apps.txt" <<'EOF'
EOF
cat >"$packages_dir/arch-aur.txt" <<'EOF'
aur-only
EOF
cat >"$packages_dir/arch-machine-local.txt" <<'EOF'
EOF
cat >"$packages_dir/arch-exclude.txt" <<'EOF'
EOF

cat >"$fakebin/pacman" <<'EOF'
#!/usr/bin/bash
if [[ "${1:-}" == -Si && "${2:-}" == git ]]; then
    exit 0
fi
exit 1
EOF
chmod +x "$fakebin/pacman"
ln -s /usr/bin/awk "$fakebin/awk"
ln -s /usr/bin/sort "$fakebin/sort"

output="$(
    PATH="$fakebin" install_package_files true true false true "$tmp_dir/repo"
)"

if [[ "$output" == *"[dry-run] bootstrap AUR helper: paru"* || "$output" == *"[dry-run] paru -S --needed aur-only"* ]]; then
    echo "Expected default package dry-run output to hide raw commands" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

if [[ "$output" != *"Pacman packages"* || "$output" != *"AUR packages"* || "$output" != *"AUR helper bootstrap"* ]]; then
    echo "Expected default package dry-run summary" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

debug_output="$(
    PATH="$fakebin" UI_DEBUG=1 UI_VERBOSE=1 install_package_files true true false true "$tmp_dir/repo"
)"

if [[ "$debug_output" != *"[dry-run] bootstrap AUR helper: paru"* ]]; then
    echo "Expected debug output to include dry-run paru bootstrap plan" >&2
    printf '%s\n' "$debug_output" >&2
    exit 1
fi

if [[ "$debug_output" != *"[dry-run] paru -S --needed aur-only"* ]]; then
    echo "Expected debug output to include AUR package raw command" >&2
    printf '%s\n' "$debug_output" >&2
    exit 1
fi

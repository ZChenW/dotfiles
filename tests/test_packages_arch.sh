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
case "${1:-}" in
    -Si)
        if [[ "${2:-}" == git ]]; then
            exit 0
        fi
        exit 1
        ;;
    -Qi|-Qq|-Q)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "$fakebin/pacman"
ln -s /usr/bin/awk "$fakebin/awk"
ln -s /usr/bin/sort "$fakebin/sort"
ln -s /usr/bin/wc "$fakebin/wc"
ln -s /usr/bin/tr "$fakebin/tr"

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

echo "==> test 2: snapshot removes uninstalled AUR packages"
cat >"$packages_dir/arch-aur.txt" <<'EOF'
installed-aur
removed-aur
EOF
cat >"$fakebin/pacman" <<'EOF'
#!/usr/bin/bash
case "${1:-}" in
    -Qqen)
        printf '%s\n' git
        ;;
    -Qqem)
        printf '%s\n' installed-aur
        ;;
    -Slq)
        printf '%s\n' git
        ;;
    -Si)
        [[ "${2:-}" == git ]]
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$fakebin/pacman"

PATH="$fakebin:/usr/bin" export_package_snapshot "$tmp_dir/repo" >/dev/null
if grep -Fxq removed-aur "$packages_dir/arch-aur.txt"; then
    echo "Snapshot retained an AUR package that is no longer installed" >&2
    exit 1
fi
if ! grep -Fxq installed-aur "$packages_dir/arch-aur.txt"; then
    echo "Snapshot lost a currently installed AUR package" >&2
    exit 1
fi

echo "==> test 3: official package index is loaded once"
pacman_log="$tmp_dir/pacman.log"
cat >"$fakebin/pacman" <<EOF
#!/usr/bin/bash
printf '%s\n' "\$*" >>"$pacman_log"
case "\${1:-}" in
    -Slq)
        printf '%s\n' git niri waybar
        ;;
    -Si)
        exit 1
        ;;
esac
EOF
chmod +x "$fakebin/pacman"
unset OFFICIAL_PACKAGE_LIST OFFICIAL_PACKAGE_INDEX_READY OFFICIAL_PACKAGE_INDEX_INITIALIZED
PATH="$fakebin:/usr/bin" package_available_in_pacman git
PATH="$fakebin:/usr/bin" package_available_in_pacman niri
PATH="$fakebin:/usr/bin" package_available_in_pacman waybar
if [[ "$(grep -c '^-Slq$' "$pacman_log" || true)" != 1 ]]; then
    echo "Expected one pacman repo-index query for all package classifications" >&2
    cat "$pacman_log" >&2
    exit 1
fi
if grep -q '^-Si ' "$pacman_log"; then
    echo "Expected cached package classification, not one pacman process per package" >&2
    cat "$pacman_log" >&2
    exit 1
fi

echo "==> test 4: desktop shell profiles filter package manifests"
cat >"$packages_dir/arch-essential.txt" <<'EOF'
git
waybar
EOF
cat >"$packages_dir/arch-apps.txt" <<'EOF'
quickshell
EOF
cat >"$packages_dir/quickshell-build.txt" <<'EOF'
cmake
EOF
cat >"$packages_dir/arch-aur.txt" <<'EOF'
waybar-cava-git
EOF
cat >"$fakebin/pacman" <<'EOF'
#!/usr/bin/bash
case "${1:-}" in
    -Slq)
        printf '%s\n' git waybar quickshell cmake
        ;;
    -Si)
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$fakebin/pacman"

build_installed_package_index() {
    declare -gA INSTALLED_NAMES=()
    declare -gA PROVIDES_INDEX=()
    declare -g INSTALLED_PACKAGE_INDEX_INITIALIZED=true
}

unset OFFICIAL_PACKAGE_LIST OFFICIAL_PACKAGE_INDEX_READY OFFICIAL_PACKAGE_INDEX_INITIALIZED
quickshell_output="$(
    PATH="$fakebin:/usr/bin" UI_DEBUG=1 UI_VERBOSE=1 \
        install_package_files true true false true "$tmp_dir/repo" quickshell
)"
if [[ "$quickshell_output" != *"pacman -S --needed"*"quickshell"* \
    || "$quickshell_output" != *"pacman -S --needed"*"cmake"* \
    || "$quickshell_output" == *"pacman -S --needed"*"waybar"* \
    || "$quickshell_output" == *"waybar-cava-git"* ]]; then
    echo "QuickShell profile package filter is incorrect" >&2
    printf '%s\n' "$quickshell_output" >&2
    exit 1
fi

unset OFFICIAL_PACKAGE_LIST OFFICIAL_PACKAGE_INDEX_READY OFFICIAL_PACKAGE_INDEX_INITIALIZED
waybar_output="$(
    PATH="$fakebin:/usr/bin" UI_DEBUG=1 UI_VERBOSE=1 \
        install_package_files true true false true "$tmp_dir/repo" waybar
)"
if [[ "$waybar_output" != *"pacman -S --needed"*"waybar"* \
    || "$waybar_output" == *"quickshell"* \
    || "$waybar_output" == *"cmake"* ]]; then
    echo "Waybar profile package filter is incorrect" >&2
    printf '%s\n' "$waybar_output" >&2
    exit 1
fi

echo "==> test 5: AUR fuzzy search never substitutes another package"
_aur_rpc_search() {
    printf '%s\n' '{"results":[{"Name":"requested-bin"},{"Name":"different"}]}'
}
resolved="$(resolve_aur_package_name requested)"
if [[ "$resolved" != requested ]]; then
    echo "Fuzzy AUR search replaced requested with $resolved" >&2
    exit 1
fi

_aur_rpc_search() {
    printf '%s\n' '{"results":[]}'
}
resolved="$(resolve_aur_package_name requested)"
if [[ "$resolved" != requested ]]; then
    echo "Empty AUR search did not preserve the requested package" >&2
    exit 1
fi

echo "All package helper tests passed."

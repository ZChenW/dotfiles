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

echo "==> test 6: Lightweight snapshot updates only its owned manifest"
profile_repo="$tmp_dir/profile-repo"
mkdir -p "$profile_repo/packages"
for manifest in arch-essential arch-desktop arch-apps arch-aur arch-machine-local arch-exclude; do
    printf '# %s\nkeep-%s\n' "$manifest" "$manifest" \
        >"$profile_repo/packages/$manifest.txt"
done
printf '# Lightweight\nold-lightweight\n' \
    >"$profile_repo/packages/arch-lightweight.txt"
standard_before="$(
    find "$profile_repo/packages" -type f ! -name arch-lightweight.txt \
        -exec sha256sum {} + | sort
)"

cat >"$fakebin/pacman" <<'EOF'
#!/usr/bin/bash
case "${1:-}" in
    -Qqen)
        printf '%s\n' base firefox git linux steam
        ;;
    -Qqem)
        printf '%s\n' cursor-bin visual-studio-code-bin
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$fakebin/pacman"

PATH="$fakebin:/usr/bin" export_package_snapshot "$profile_repo" lightweight >/dev/null

standard_after="$(
    find "$profile_repo/packages" -type f ! -name arch-lightweight.txt \
        -exec sha256sum {} + | sort
)"
if [[ "$standard_before" != "$standard_after" ]]; then
    echo "Lightweight snapshot changed a Standard-owned manifest" >&2
    exit 1
fi
for expected in firefox git steam visual-studio-code-bin cursor-bin; do
    if ! grep -Fxq "$expected" "$profile_repo/packages/arch-lightweight.txt"; then
        echo "Expected Lightweight snapshot to include explicit package: $expected" >&2
        exit 1
    fi
done
for excluded in base linux; do
    if grep -Fxq "$excluded" "$profile_repo/packages/arch-lightweight.txt"; then
        echo "Expected Lightweight snapshot to filter: $excluded" >&2
        exit 1
    fi
done

echo "==> test 7: package manifests use current Maple Mono AUR names"
obsolete_maplemono_references="$(
    rg -n \
        '^(ttf-maplemono|ttf-maplemono-nf-cn-unhinted|ttf-maplemono-nf-unhinted)$' \
        "$REPO_ROOT/packages" \
        || true
)"
if [[ -n "$obsolete_maplemono_references" ]]; then
    echo "Package manifests still reference retired Maple Mono AUR names" >&2
    printf '%s\n' "$obsolete_maplemono_references" >&2
    exit 1
fi
for expected in maplemono-ttf maplemono-nf-cn-unhinted; do
    if ! grep -Fxq "$expected" "$REPO_ROOT/packages/arch-lightweight.txt"; then
        echo "Lightweight manifest is missing current package: $expected" >&2
        exit 1
    fi
done
for expected in maplemono-ttf maplemono-nf-cn-unhinted maplemono-nf-unhinted; do
    if ! grep -Fxq "$expected" "$REPO_ROOT/packages/arch-aur.txt"; then
        echo "Standard AUR manifest is missing current package: $expected" >&2
        exit 1
    fi
done

echo "==> test 8: AUR helper output is copied to the install log"
package_log="$tmp_dir/package-install.log"
: >"$package_log"
DOTFILES_LOG_FILE="$package_log"
export DOTFILES_LOG_FILE

build_installed_package_index() {
    declare -gA INSTALLED_NAMES=()
    declare -gA PROVIDES_INDEX=()
    declare -g INSTALLED_PACKAGE_INDEX_INITIALIZED=true
}
_aur_rpc_search() {
    printf '%s\n' '{"results":[{"Name":"broken-aur-package"}]}'
}
_aur_get_provides() {
    return 1
}
failing_aur_helper() {
    printf 'AUR-HELPER-STDOUT: resolving target\n'
    printf 'AUR-HELPER-STDERR: target not found\n' >&2
    return 23
}

unset INSTALLED_NAMES PROVIDES_INDEX INSTALLED_PACKAGE_INDEX_INITIALIZED
if package_output="$(
    install_packages_batch false true failing_aur_helper broken-aur-package 2>&1
)"; then
    echo "Expected the fixture AUR helper to fail" >&2
    exit 1
fi
for marker in AUR-HELPER-STDOUT AUR-HELPER-STDERR; do
    if [[ "$package_output" != *"$marker"* ]]; then
        echo "AUR helper output disappeared from the terminal stream: $marker" >&2
        exit 1
    fi
    if ! grep -Fq "$marker" "$package_log"; then
        echo "AUR helper output is missing from the install log: $marker" >&2
        printf '%s\n' "$package_output" >&2
        printf '%s\n' "--- install log ---" >&2
        sed -n '1,80p' "$package_log" >&2
        exit 1
    fi
done

echo "==> test 9: missing AUR packages fail before package writes"
preflight_repo="$tmp_dir/preflight-repo"
mkdir -p "$preflight_repo/packages"
cat >"$preflight_repo/packages/arch-essential.txt" <<'EOF'
git
EOF
for manifest in arch-desktop arch-apps arch-machine-local arch-exclude; do
    : >"$preflight_repo/packages/$manifest.txt"
done
cat >"$preflight_repo/packages/arch-aur.txt" <<'EOF'
retired-aur-package
EOF

package_command_log="$tmp_dir/package-commands.log"
: >"$package_command_log"
cat >"$fakebin/pacman" <<EOF
#!/usr/bin/bash
printf 'pacman %s\n' "\$*" >>"$package_command_log"
case "\${1:-}" in
    -Slq) printf '%s\n' git ;;
    -Qqen|-Qqem) exit 0 ;;
    *) exit 0 ;;
esac
EOF
cat >"$fakebin/sudo" <<EOF
#!/usr/bin/bash
printf 'sudo %s\n' "\$*" >>"$package_command_log"
exit 0
EOF
cat >"$fakebin/paru" <<EOF
#!/usr/bin/bash
printf 'paru %s\n' "\$*" >>"$package_command_log"
exit 1
EOF
chmod +x "$fakebin/pacman" "$fakebin/sudo" "$fakebin/paru"

_aur_rpc_info_many() {
    printf '%s\n' '{"resultcount":0,"results":[],"type":"multiinfo","version":5}'
}
unset INSTALLED_NAMES PROVIDES_INDEX INSTALLED_PACKAGE_INDEX_INITIALIZED
if preflight_output="$(
    PATH="$fakebin:/usr/bin" \
        install_package_files false true false true "$preflight_repo" 2>&1
)"; then
    echo "Expected an unavailable AUR package to fail pre-install validation" >&2
    exit 1
fi
if [[ "$preflight_output" != *"retired-aur-package"* ]]; then
    echo "Expected pre-install validation to name the unavailable AUR package" >&2
    printf '%s\n' "$preflight_output" >&2
    exit 1
fi
if grep -Eq '^(sudo|paru) ' "$package_command_log"; then
    echo "Package writes started before AUR manifests were validated" >&2
    cat "$package_command_log" >&2
    exit 1
fi

echo "==> test 10: Snapshot exports retired package names canonically"
migration_repo="$tmp_dir/migration-repo"
mkdir -p "$migration_repo/packages"
for manifest in \
    arch-essential \
    arch-desktop \
    arch-apps \
    arch-aur \
    arch-machine-local \
    arch-exclude \
    arch-lightweight; do
    printf '# %s\n' "$manifest" >"$migration_repo/packages/$manifest.txt"
done
cat >"$fakebin/pacman" <<'EOF'
#!/usr/bin/bash
case "${1:-}" in
    -Qqen)
        printf '%s\n' \
            git \
            ttf-maplemono \
            ttf-maplemono-nf-cn-unhinted \
            ttf-maplemono-nf-unhinted
        ;;
    -Qqem)
        printf '%s\n' maplemono-ttf
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$fakebin/pacman"

for profile in standard lightweight; do
    unset INSTALLED_NAMES PROVIDES_INDEX INSTALLED_PACKAGE_INDEX_INITIALIZED
    PATH="$fakebin:/usr/bin" \
        export_package_snapshot "$migration_repo" "$profile" >/dev/null

    if rg -n \
        '^(ttf-maplemono|ttf-maplemono-nf-cn-unhinted|ttf-maplemono-nf-unhinted)$' \
        "$migration_repo/packages"; then
        echo "$profile Snapshot reintroduced a retired Maple Mono name" >&2
        exit 1
    fi

    if [[ "$profile" == lightweight ]]; then
        exported_manifest="$migration_repo/packages/arch-lightweight.txt"
    else
        exported_manifest="$migration_repo/packages/arch-aur.txt"
    fi
    for expected in \
        maplemono-ttf \
        maplemono-nf-cn-unhinted \
        maplemono-nf-unhinted; do
        if ! grep -Fxq "$expected" "$exported_manifest"; then
            echo "$profile Snapshot did not canonicalize package: $expected" >&2
            exit 1
        fi
    done
done

echo "All package helper tests passed."

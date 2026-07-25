#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_home="$tmp_dir/home"
fake_bin="$tmp_dir/bin"
source_fixture="$tmp_dir/source"
command_log="$tmp_dir/commands.log"
mkdir -p "$fake_home" "$fake_bin" "$source_fixture"

cat >"$source_fixture/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'quickshell-install %s\n' "$*" >>"$DOTFILES_TEST_COMMAND_LOG"
[[ "${1:-}" == --prefix ]]
prefix="$2"
mkdir -p "$prefix/bin" "$prefix/lib/qt6/qml/Clavis" "$prefix/lib/qt6/qml/M3Shapes"
printf '#!/usr/bin/env bash\n' >"$prefix/bin/key"
chmod +x "$prefix/bin/key"
EOF
printf 'qml\n' >"$source_fixture/shell.qml"
chmod +x "$source_fixture/install.sh"

cat >"$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$*" >>"$DOTFILES_TEST_COMMAND_LOG"

if [[ "${1:-}" == init ]]; then
    mkdir -p "$2/.git"
    exit 0
fi

[[ "${1:-}" == -C ]]
destination="$2"
shift 2

case "${1:-} ${2:-}" in
    "remote add")
        printf '%s\n' "$4" >"$destination/.git/origin-url"
        ;;
    "config --get")
        cat "$destination/.git/origin-url"
        ;;
    "fetch --depth=1")
        mkdir -p "$destination/.git"
        printf '%s\n' "$4" >"$destination/.git/fetched-ref"
        ;;
    "checkout --detach")
        cp "$DOTFILES_TEST_SOURCE_FIXTURE/install.sh" "$destination/install.sh"
        cp "$DOTFILES_TEST_SOURCE_FIXTURE/shell.qml" "$destination/shell.qml"
        chmod +x "$destination/install.sh"
        ;;
    "status --porcelain")
        if [[ -f "$destination/.git/dirty" ]]; then
            printf ' M local.qml\n'
        fi
        ;;
    "rev-parse HEAD")
        cat "$destination/.git/fetched-ref"
        ;;
    *)
        echo "unexpected git invocation: $*" >&2
        exit 2
        ;;
esac
EOF
chmod +x "$fake_bin/git"

export HOME="$fake_home"
export PATH="$fake_bin:/usr/bin"
export DOTFILES_TEST_COMMAND_LOG="$command_log"
export DOTFILES_TEST_SOURCE_FIXTURE="$source_fixture"
export QUICKSHELL_INSTALL_ROOT="$fake_home/.local/share/quickshell/clavis"

# shellcheck source=scripts/ui.sh
source "$repo_root/scripts/ui.sh"
ui_init
# shellcheck source=scripts/desktop-shell-profile.sh
source "$repo_root/scripts/desktop-shell-profile.sh"

install_desktop_shell_profile "$repo_root" dual false

[[ -x "$QUICKSHELL_INSTALL_ROOT/install.sh" ]]
grep -Fq "git init $QUICKSHELL_INSTALL_ROOT" "$command_log"
grep -Fq "git -C $QUICKSHELL_INSTALL_ROOT remote add origin https://github.com/ZChenW/quickshell.git" "$command_log"
grep -Fq "git -C $QUICKSHELL_INSTALL_ROOT fetch --depth=1 origin" "$command_log"
grep -Fq "quickshell-install --prefix $fake_home/.local" "$command_log"

install_count_before="$(grep -Fc 'quickshell-install ' "$command_log")"
fetch_count_before="$(grep -Fc "git -C $QUICKSHELL_INSTALL_ROOT fetch " "$command_log")"
current_output="$(install_desktop_shell_profile "$repo_root" dual false)"
[[ "$current_output" == *"already current"* ]]
install_count_after="$(grep -Fc 'quickshell-install ' "$command_log")"
fetch_count_after="$(grep -Fc "git -C $QUICKSHELL_INSTALL_ROOT fetch " "$command_log")"
((install_count_after == install_count_before))
((fetch_count_after == fetch_count_before))

unsafe_destination="$tmp_dir/unsafe"
mkdir -p "$unsafe_destination"
printf 'keep\n' >"$unsafe_destination/personal.txt"
QUICKSHELL_INSTALL_ROOT="$unsafe_destination"
if install_desktop_shell_profile "$repo_root" quickshell false >"$tmp_dir/unsafe.out" 2>&1; then
    echo "Non-Git QuickShell destination was overwritten" >&2
    exit 1
fi
grep -Fq "not a managed Git checkout" "$tmp_dir/unsafe.out"
[[ "$(cat "$unsafe_destination/personal.txt")" == keep ]]

unowned_destination="$tmp_dir/unowned"
mkdir -p "$unowned_destination/.git"
printf 'https://github.com/ZChenW/quickshell.git\n' \
    >"$unowned_destination/.git/origin-url"
printf '%s\n' 689f57d984dbad1aee45ed9ce5f495981ee3fba4 \
    >"$unowned_destination/.git/fetched-ref"
QUICKSHELL_INSTALL_ROOT="$unowned_destination"
if install_desktop_shell_profile "$repo_root" dual false >"$tmp_dir/unowned.out" 2>&1; then
    echo "Unowned same-origin QuickShell checkout was overwritten" >&2
    exit 1
fi
grep -Fq "not managed by dotfiles" "$tmp_dir/unowned.out"

dirty_destination="$tmp_dir/dirty"
mkdir -p "$dirty_destination/.git"
printf 'https://github.com/ZChenW/quickshell.git\n' >"$dirty_destination/.git/origin-url"
: >"$dirty_destination/.git/dirty"
printf '%s\n' "$dirty_destination" \
    >"$fake_home/.local/state/dotfiles/quickshell-managed-root"
QUICKSHELL_INSTALL_ROOT="$dirty_destination"
if install_desktop_shell_profile "$repo_root" dual false >"$tmp_dir/dirty.out" 2>&1; then
    echo "Dirty QuickShell checkout was overwritten" >&2
    exit 1
fi
grep -Fq "has local changes" "$tmp_dir/dirty.out"

echo "Desktop shell source installation tests passed"

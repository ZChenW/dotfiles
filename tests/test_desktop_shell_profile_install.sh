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

cmake_fixture="$tmp_dir/cmake-source"
mkdir -p "$cmake_fixture"
printf 'qml\n' >"$cmake_fixture/shell.qml"
printf 'cmake_minimum_required(VERSION 3.21)\nproject(TestClavis)\n' \
    >"$cmake_fixture/CMakeLists.txt"
cat >"$cmake_fixture/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'forbidden-install-sh %s\n' "$*" >>"$DOTFILES_TEST_COMMAND_LOG"
echo "upstream install.sh must not run for local CMake source" >&2
exit 99
EOF
chmod +x "$cmake_fixture/install.sh"

cat >"$fake_bin/cmake" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'cmake %s\n' "$*" >>"$DOTFILES_TEST_COMMAND_LOG"

if [[ "${1:-}" == -S && "${3:-}" == -B ]]; then
    mkdir -p "$4"
    exit 0
fi
if [[ "${1:-}" == --build ]]; then
    mkdir -p "$2/qml/Clavis"
    exit 0
fi
echo "unexpected cmake invocation: $*" >&2
exit 2
EOF
chmod +x "$fake_bin/cmake"

cat >"$fake_bin/ninja" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ninja %s\n' "$*" >>"$DOTFILES_TEST_COMMAND_LOG"
EOF
chmod +x "$fake_bin/ninja"

cat >"$fake_bin/ctest" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ctest %s\n' "$*" >>"$DOTFILES_TEST_COMMAND_LOG"
if [[ -n "${DOTFILES_TEST_CTEST_FAIL:-}" ]]; then
    echo "simulated ctest failure" >&2
    exit 1
fi
EOF
chmod +x "$fake_bin/ctest"

printf '#!/usr/bin/env bash\n' >"$fake_bin/key"
printf '#!/usr/bin/env bash\n' >"$fake_bin/keytop"
chmod +x "$fake_bin/key" "$fake_bin/keytop"
mkdir -p "$fake_home/.local/lib/qt6/qml/M3Shapes"

state_dir="$fake_home/.local/state/dotfiles"
mkdir -p "$state_dir"
printf '/prior/active/config\n' >"$state_dir/quickshell-config-path"
printf 'legacy-ref\n' >"$state_dir/quickshell-install-ref"

: >"$command_log"
export QUICKSHELL_LOCAL_SOURCE="$cmake_fixture"
export DOTFILES_TEST_CTEST_FAIL=1
if install_desktop_shell_profile "$repo_root" dual false >"$tmp_dir/local-fail.out" 2>&1; then
    echo "Local source install succeeded despite ctest failure" >&2
    exit 1
fi
unset DOTFILES_TEST_CTEST_FAIL
grep -Fq "simulated ctest failure" "$tmp_dir/local-fail.out"
grep -Fq "ctest " "$command_log"
[[ "$(cat "$state_dir/quickshell-config-path")" == /prior/active/config ]]
[[ "$(cat "$state_dir/quickshell-install-ref")" == legacy-ref ]]
if grep -Fq 'forbidden-install-sh ' "$command_log"; then
    echo "Local source install invoked upstream install.sh" >&2
    exit 1
fi
if grep -Eq 'git .*fetch|git .*checkout' "$command_log"; then
    echo "Local source install performed git fetch/checkout" >&2
    exit 1
fi

: >"$command_log"
printf 'legacy-clavis\n' >"$fake_home/.local/lib/qt6/qml/Clavis/sentinel"
install_desktop_shell_profile "$repo_root" dual false >"$tmp_dir/local-ok.out"
grep -Fq "cmake -S $cmake_fixture -B $cmake_fixture/build -G Ninja" "$command_log"
grep -Fq "cmake --build $cmake_fixture/build" "$command_log"
grep -Fq "ctest --test-dir $cmake_fixture/build" "$command_log"
if grep -Fq 'forbidden-install-sh ' "$command_log"; then
    echo "Successful local source install invoked upstream install.sh" >&2
    exit 1
fi
if grep -Eq 'git .*fetch|git .*checkout|git init' "$command_log"; then
    echo "Successful local source install touched git checkout flow" >&2
    exit 1
fi
[[ "$(cat "$fake_home/.local/lib/qt6/qml/Clavis/sentinel")" == legacy-clavis ]]
[[ -d "$cmake_fixture/build/qml/Clavis" ]]
[[ "$(cat "$state_dir/quickshell-config-path")" == "$fake_home/.config/quickshell/clavis" ]]
[[ "$(readlink -f "$fake_home/.config/quickshell/clavis")" == "$cmake_fixture" ]]
grep -Eq '^local-source ref=none state=clean manifest=[0-9a-f]{64}$' \
    "$state_dir/quickshell-install-ref"

QUICKSHELL_LOCAL_SOURCE=relative/path
if install_desktop_shell_profile "$repo_root" dual false >"$tmp_dir/relative.out" 2>&1; then
    echo "Relative QUICKSHELL_LOCAL_SOURCE was accepted" >&2
    exit 1
fi
grep -Fq "must be an absolute directory" "$tmp_dir/relative.out"
[[ "$(cat "$state_dir/quickshell-config-path")" == "$fake_home/.config/quickshell/clavis" ]]

echo "Desktop shell source installation tests passed"

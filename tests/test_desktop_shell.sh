#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

tmp_dir="$(mktemp -d)"
cleanup() {
    local status=$?
    if ((status != 0)) && [[ -f "$fake_state/dotfiles/desktop-shell.log" ]]; then
        cat "$fake_state/dotfiles/desktop-shell.log" >&2
    fi
    if [[ -f "${runtime_state:-}/wcr-child.pid" ]]; then
        kill "$(cat "$runtime_state/wcr-child.pid")" >/dev/null 2>&1 || true
    fi
    rm -rf "$tmp_dir"
    return "$status"
}
trap cleanup EXIT

fake_home="$tmp_dir/home"
fake_bin="$fake_home/.local/bin"
fake_state="$tmp_dir/state"
runtime_state="$tmp_dir/runtime"
mkdir -p \
    "$fake_home/.local/share/quickshell/clavis" \
    "$fake_home/.config/niri/scripts" \
    "$fake_bin" \
    "$fake_state/dotfiles" \
    "$runtime_state"
touch "$fake_home/.local/share/quickshell/clavis/shell.qml"
printf 'dual\n' >"$fake_state/dotfiles/desktop-shell-profile"

cat >"$fake_bin/setsid" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == -f ]] && shift
"$@" </dev/null >/dev/null 2>&1 &
EOF

cat >"$fake_bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == -x ]] || exit 2
[[ -e "$DESKTOP_SHELL_TEST_RUNTIME/${2:?}" ]]
EOF

cat >"$fake_bin/pkill" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -x)
        [[ "${DESKTOP_SHELL_TEST_PROCESS_STOP_FAIL:-}" == "${2:-}" ]] && exit 1
        rm -f "$DESKTOP_SHELL_TEST_RUNTIME/${2:?}"
        ;;
    -f)
        ;;
esac
EOF

for process_name in waybar mako; do
    cat >"$fake_bin/$process_name" <<EOF
#!/usr/bin/env bash
touch "\$DESKTOP_SHELL_TEST_RUNTIME/$process_name"
[[ "$process_name" == waybar ]] \
    && printf '%s\n' waybar-start >>"\$DESKTOP_SHELL_TEST_RUNTIME/lifecycle.log"
EOF
done

cat >"$fake_home/.config/niri/scripts/swayidle.sh" <<'EOF'
#!/usr/bin/env bash
touch "$DESKTOP_SHELL_TEST_RUNTIME/swayidle"
EOF

cat >"$fake_bin/qs" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *" ipc "*" show "*)
        if [[ -n "${DESKTOP_SHELL_TEST_IPC_DELAY:-}" ]] \
            && [[ ! -e "$DESKTOP_SHELL_TEST_RUNTIME/ipc-delay-consumed" ]]; then
            touch "$DESKTOP_SHELL_TEST_RUNTIME/ipc-delay-consumed"
            sleep "$DESKTOP_SHELL_TEST_IPC_DELAY"
        fi
        [[ -e "$DESKTOP_SHELL_TEST_RUNTIME/quickshell" ]]
        ;;
    *" kill "*)
        printf '%s\n' qs-kill >>"$DESKTOP_SHELL_TEST_RUNTIME/lifecycle.log"
        [[ "${DESKTOP_SHELL_TEST_QS_KILL_FAIL:-0}" == 1 ]] && exit 1
        rm -f "$DESKTOP_SHELL_TEST_RUNTIME/quickshell"
        ;;
    *" ipc "*" call "*)
        [[ -e "$DESKTOP_SHELL_TEST_RUNTIME/quickshell" ]]
        ;;
    *)
        printf '%s\n' qs-start >>"$DESKTOP_SHELL_TEST_RUNTIME/lifecycle.log"
        printf '%s\n' "$QML_IMPORT_PATH" >"$DESKTOP_SHELL_TEST_RUNTIME/qml-import-path"
        touch "$DESKTOP_SHELL_TEST_RUNTIME/quickshell"
        ;;
esac
EOF

cat >"$fake_bin/wallpaper-console-rust" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DESKTOP_SHELL_TEST_RUNTIME/wcr.log"
printf 'wcr-%s\n' "$*" >>"$DESKTOP_SHELL_TEST_RUNTIME/lifecycle.log"
[[ "${DESKTOP_SHELL_TEST_WCR_FAIL:-}" == "${1:-}" ]] && exit 1
if [[ "${DESKTOP_SHELL_TEST_WCR_FORK:-}" == "${1:-}" ]]; then
    sleep 30 &
    printf '%s\n' "$!" >"$DESKTOP_SHELL_TEST_RUNTIME/wcr-child.pid"
fi
exit 0
EOF

cat >"$fake_bin/notify-send" <<'EOF'
#!/usr/bin/env bash
:
EOF

chmod +x "$fake_bin"/* "$fake_home/.config/niri/scripts/swayidle.sh"
touch "$runtime_state/waybar" "$runtime_state/mako" "$runtime_state/swayidle"

run_shell() {
    HOME="$fake_home" \
        XDG_STATE_HOME="$fake_state" \
        PATH="$fake_bin:/usr/bin" \
        DESKTOP_SHELL_NOTIFY=0 \
        DESKTOP_SHELL_TEST_RUNTIME="$runtime_state" \
        DESKTOP_SHELL_TEST_WCR_FAIL="${DESKTOP_SHELL_TEST_WCR_FAIL:-}" \
        DESKTOP_SHELL_TEST_WCR_FORK="${DESKTOP_SHELL_TEST_WCR_FORK:-}" \
        DESKTOP_SHELL_TEST_QS_KILL_FAIL="${DESKTOP_SHELL_TEST_QS_KILL_FAIL:-0}" \
        DESKTOP_SHELL_TEST_PROCESS_STOP_FAIL="${DESKTOP_SHELL_TEST_PROCESS_STOP_FAIL:-}" \
        "$REPO_ROOT/configs/local-bin/desktop-shell" "$@"
}

status_output="$(run_shell)"
[[ "$status_output" == *"profile=dual"* ]]
[[ "$status_output" == *"configured=waybar"* ]]
[[ "$status_output" == *"active=waybar"* ]]
[[ "$status_output" == *"quickshell_config=$fake_home/.local/share/quickshell/clavis"* ]]

pretty_status_output="$(DESKTOP_SHELL_STATUS_STYLE=pretty run_shell)"
[[ "$pretty_status_output" == *"Desktop Shell"* ]]
[[ "$pretty_status_output" == *"Active"*"Waybar"* ]]
[[ "$pretty_status_output" == *"Saved"*"Waybar"* ]]
[[ "$pretty_status_output" == *"Mod+Shift+7 · desktop-shell toggle"* ]]

plain_status_output="$(DESKTOP_SHELL_STATUS_STYLE=pretty run_shell status --plain)"
[[ "$plain_status_output" == "$status_output" ]]

if run_shell wayvar >"$tmp_dir/invalid.out" 2>&1; then
    echo "Invalid desktop-shell action unexpectedly succeeded" >&2
    exit 1
fi
grep -Fq "Usage: desktop-shell" "$tmp_dir/invalid.out"

if run_shell status --unknown >"$tmp_dir/invalid-status.out" 2>&1; then
    echo "Invalid desktop-shell status option unexpectedly succeeded" >&2
    exit 1
fi
grep -Fq "desktop-shell status --plain" "$tmp_dir/invalid-status.out"

DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell
[[ -e "$runtime_state/quickshell" ]]
[[ ! -e "$runtime_state/waybar" ]]
[[ ! -e "$runtime_state/mako" ]]
[[ ! -e "$runtime_state/swayidle" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == quickshell ]]
grep -Fxq "stop" "$runtime_state/wcr.log"
[[ "$(cat "$runtime_state/qml-import-path")" == "$fake_home/.local/lib/qt6/qml"* ]]
mapfile -t lifecycle_events <"$runtime_state/lifecycle.log"
[[ "${lifecycle_events[*]}" == "qs-start wcr-stop" ]]

: >"$runtime_state/wcr.log"
DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell
grep -Fxq "stop" "$runtime_state/wcr.log"

: >"$runtime_state/lifecycle.log"
DESKTOP_SHELL_TEST_WCR_FORK=restore DESKTOP_SHELL_FOREGROUND=1 run_shell toggle
[[ ! -e "$runtime_state/quickshell" ]]
[[ -e "$runtime_state/waybar" ]]
[[ -e "$runtime_state/mako" ]]
[[ -e "$runtime_state/swayidle" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == waybar ]]
grep -Fxq "restore" "$runtime_state/wcr.log"
mapfile -t lifecycle_events <"$runtime_state/lifecycle.log"
[[ "${lifecycle_events[*]}" == "waybar-start wcr-restore qs-kill" ]]
flock -n "$fake_state/dotfiles/desktop-shell.lock" true

status_output="$(run_shell status)"
[[ "$status_output" == *"configured=waybar"* ]]
[[ "$status_output" == *"active=waybar"* ]]

: >"$runtime_state/lifecycle.log"
if DESKTOP_SHELL_TEST_WCR_FAIL=stop DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell; then
    echo "QuickShell switch unexpectedly succeeded when Wallpaper Console stop failed" >&2
    exit 1
fi
[[ ! -e "$runtime_state/quickshell" ]]
[[ -e "$runtime_state/waybar" ]]
[[ -e "$runtime_state/mako" ]]
[[ -e "$runtime_state/swayidle" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == waybar ]]
mapfile -t lifecycle_events <"$runtime_state/lifecycle.log"
[[ "${lifecycle_events[*]}" == "qs-start wcr-stop qs-kill" ]]

DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell
: >"$runtime_state/lifecycle.log"
if DESKTOP_SHELL_TEST_WCR_FAIL=restore DESKTOP_SHELL_FOREGROUND=1 run_shell waybar; then
    echo "Waybar switch unexpectedly succeeded when Wallpaper Console restore failed" >&2
    exit 1
fi
[[ -e "$runtime_state/quickshell" ]]
[[ ! -e "$runtime_state/waybar" ]]
[[ ! -e "$runtime_state/mako" ]]
[[ ! -e "$runtime_state/swayidle" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == quickshell ]]
mapfile -t lifecycle_events <"$runtime_state/lifecycle.log"
[[ "${lifecycle_events[*]}" == "waybar-start wcr-restore" ]]

: >"$runtime_state/lifecycle.log"
if DESKTOP_SHELL_TEST_QS_KILL_FAIL=1 DESKTOP_SHELL_FOREGROUND=1 run_shell waybar; then
    echo "Waybar switch unexpectedly succeeded when QuickShell did not stop" >&2
    exit 1
fi
[[ -e "$runtime_state/quickshell" ]]
[[ ! -e "$runtime_state/waybar" ]]
[[ ! -e "$runtime_state/mako" ]]
[[ ! -e "$runtime_state/swayidle" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == quickshell ]]
mapfile -t lifecycle_events <"$runtime_state/lifecycle.log"
[[ "${lifecycle_events[*]}" == "waybar-start wcr-restore qs-kill wcr-stop" ]]

rm -f "$runtime_state/quickshell"
: >"$runtime_state/lifecycle.log"
if DESKTOP_SHELL_TEST_WCR_FAIL=restore DESKTOP_SHELL_FOREGROUND=1 run_shell waybar; then
    echo "Waybar switch unexpectedly succeeded without a restorable wallpaper" >&2
    exit 1
fi
[[ ! -e "$runtime_state/quickshell" ]]
[[ ! -e "$runtime_state/waybar" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == quickshell ]]
mapfile -t lifecycle_events <"$runtime_state/lifecycle.log"
[[ "${lifecycle_events[*]}" == "waybar-start wcr-restore" ]]

DESKTOP_SHELL_FOREGROUND=1 run_shell waybar
: >"$runtime_state/lifecycle.log"
if DESKTOP_SHELL_TEST_PROCESS_STOP_FAIL=waybar \
    DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell; then
    echo "QuickShell switch unexpectedly succeeded when Waybar did not stop" >&2
    exit 1
fi
[[ ! -e "$runtime_state/quickshell" ]]
[[ -e "$runtime_state/waybar" ]]
[[ -e "$runtime_state/mako" ]]
[[ -e "$runtime_state/swayidle" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == waybar ]]
mapfile -t lifecycle_events <"$runtime_state/lifecycle.log"
[[ "${lifecycle_events[*]}" == "qs-start wcr-stop qs-kill wcr-restore" ]]

rm -f "$runtime_state/ipc-delay-consumed"
if ! DESKTOP_SHELL_TEST_IPC_DELAY=2 timeout 0.5s \
    env \
        HOME="$fake_home" \
        XDG_STATE_HOME="$fake_state" \
        PATH="$fake_bin:/usr/bin" \
        DESKTOP_SHELL_NOTIFY=0 \
        DESKTOP_SHELL_TEST_RUNTIME="$runtime_state" \
        DESKTOP_SHELL_TEST_IPC_DELAY=2 \
        "$REPO_ROOT/configs/local-bin/desktop-shell" quickshell \
        >"$tmp_dir/dispatch.out" 2>&1; then
    echo "Foreground dispatcher blocked on the switch worker" >&2
    cat "$tmp_dir/dispatch.out" >&2
    exit 1
fi
grep -Fq "switch requested: quickshell" "$tmp_dir/dispatch.out"

for _ in {1..100}; do
    if [[ -e "$runtime_state/quickshell" && ! -e "$runtime_state/waybar" ]] \
        && [[ "$(cat "$fake_state/dotfiles/desktop-shell")" == quickshell ]]; then
        break
    fi
    sleep 0.1
done
[[ -e "$runtime_state/quickshell" ]]
[[ ! -e "$runtime_state/waybar" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == quickshell ]]

for _ in {1..30}; do
    flock -n "$fake_state/dotfiles/desktop-shell.lock" true >/dev/null 2>&1 && break
    sleep 0.1
done
flock -n "$fake_state/dotfiles/desktop-shell.lock" true

printf 'waybar\n' >"$fake_state/dotfiles/desktop-shell-profile"
if DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell >"$tmp_dir/waybar-profile.out" 2>&1; then
    echo "Waybar-only profile unexpectedly allowed QuickShell" >&2
    exit 1
fi
grep -Fq "profile is waybar" "$tmp_dir/waybar-profile.out"

printf 'quickshell\n' >"$fake_state/dotfiles/desktop-shell-profile"
if DESKTOP_SHELL_FOREGROUND=1 run_shell waybar >"$tmp_dir/quickshell-profile.out" 2>&1; then
    echo "QuickShell-only profile unexpectedly allowed Waybar" >&2
    exit 1
fi
grep -Fq "profile is quickshell" "$tmp_dir/quickshell-profile.out"

completion_file="$REPO_ROOT/configs/zsh/site-functions/_desktop-shell"
grep -Fxq '#compdef desktop-shell' "$completion_file"
for completion in toggle waybar quickshell status start launcher lock hub tools control-center; do
    grep -Fq "'$completion:" "$completion_file"
done
grep -Fq -- "'--plain[" "$completion_file"

completion_dump="$tmp_dir/zcompdump"
F_PATH="$REPO_ROOT/configs/zsh/site-functions" ZCOMPDUMP="$completion_dump" \
    zsh -fc '
        fpath=("$F_PATH" $fpath)
        autoload -Uz compinit
        compinit -d "$ZCOMPDUMP"
        (( $+functions[_desktop-shell] ))
    '

echo "desktop shell switching tests passed"

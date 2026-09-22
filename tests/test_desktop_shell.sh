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
touch "$fake_home/.local/share/quickshell/clavis/switcher.qml"
touch "$fake_home/.local/share/quickshell/clavis/controlcenter.qml"
printf 'dual\n' >"$fake_state/dotfiles/desktop-shell-profile"

cat >"$fake_bin/setsid" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == -f ]] && shift
"$@" </dev/null >/dev/null 2>&1 &
EOF

cat >"$fake_bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == -x ]] || exit 2
if [[ -e "$DESKTOP_SHELL_TEST_RUNTIME/${2:?}" ]]; then
    printf '4242\n'
    exit 0
fi
exit 1
EOF

cat >"$fake_bin/ps" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == -C ]] || exec /usr/bin/ps "$@"
process_name=${2:?}
[[ -e "$DESKTOP_SHELL_TEST_RUNTIME/$process_name" ]] || exit 1
if [[ -e "$DESKTOP_SHELL_TEST_RUNTIME/$process_name.zombie" ]]; then
    printf 'Z\n'
else
    printf 'S\n'
fi
EOF

cat >"$fake_bin/pkill" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DESKTOP_SHELL_TEST_RUNTIME/pkill.log"
case "${1:-}" in
    -x)
        process_name=${2:?}
        if [[ "${DESKTOP_SHELL_TEST_PROCESS_STOP_FAIL:-}" == "$process_name" ]] \
            || { [[ "${DESKTOP_SHELL_TEST_PROCESS_STOP_FAIL:-}" == quickshell ]] \
                && [[ "$process_name" == qs ]]; }; then
            exit 1
        fi
        rm -f "$DESKTOP_SHELL_TEST_RUNTIME/$process_name"
        if [[ "$process_name" == qs || "$process_name" == quickshell ]]; then
            rm -f "$DESKTOP_SHELL_TEST_RUNTIME/quickshell"
            touch "$DESKTOP_SHELL_TEST_RUNTIME/quickshell-supervisor-stopped"
        fi
        ;;
    -f)
        shift
        [[ "${1:-}" == -- ]] && shift
        pattern="${1:-}"
        # desktop-shell stops the exact qs --path supervisor with a regex atom
        # containing "qs"; match on that intent rather than a spaced " qs " token.
        if [[ "$pattern" == *qs* && "$pattern" == *--path* ]]; then
            touch "$DESKTOP_SHELL_TEST_RUNTIME/quickshell-supervisor-stopped"
            if [[ "${DESKTOP_SHELL_TEST_PROCESS_STOP_FAIL:-}" == quickshell ]]; then
                exit 0
            fi
            rm -f "$DESKTOP_SHELL_TEST_RUNTIME/quickshell"
        elif [[ "$pattern" == *cava* && "$pattern" == *sh* ]]; then
            rm -f "$DESKTOP_SHELL_TEST_RUNTIME/cava-sh"
        elif [[ "$pattern" == *waybar_cava_config* ]]; then
            rm -f "$DESKTOP_SHELL_TEST_RUNTIME/cava"
        fi
        ;;
esac
EOF

for process_name in waybar mako; do
    cat >"$fake_bin/$process_name" <<EOF
#!/usr/bin/env bash
touch "\$DESKTOP_SHELL_TEST_RUNTIME/$process_name"
rm -f "\$DESKTOP_SHELL_TEST_RUNTIME/$process_name.zombie"
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
if [[ "$*" == *"switcher.qml"* ]]; then
    if [[ "$*" == *"call shell-switcher show"* ]]; then
        [[ -e "$DESKTOP_SHELL_TEST_RUNTIME/switcher" ]]
    else
        printf '%s\n' switcher-start >>"$DESKTOP_SHELL_TEST_RUNTIME/lifecycle.log"
        touch "$DESKTOP_SHELL_TEST_RUNTIME/switcher"
    fi
    exit $?
fi
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
        if [[ "${DESKTOP_SHELL_TEST_QS_RESTART_AFTER_KILL:-0}" == 1 ]]; then
            (
                sleep 0.2
                [[ -e "$DESKTOP_SHELL_TEST_RUNTIME/quickshell-supervisor-stopped" ]] \
                    || touch "$DESKTOP_SHELL_TEST_RUNTIME/quickshell"
            ) &
        fi
        ;;
    *" ipc "*" call "*)
        printf '%s\n' "$*" >>"$DESKTOP_SHELL_TEST_RUNTIME/ipc.log"
        [[ -e "$DESKTOP_SHELL_TEST_RUNTIME/quickshell" ]] || exit 1

        if [[ " $* " == *" desktop-integration version "* ]]; then
            [[ "${DESKTOP_SHELL_TEST_DI:-0}" == 1 ]] || exit 1
            printf '%s\n' "${DESKTOP_SHELL_TEST_DI_VERSION:-1}"
            exit 0
        fi
        if [[ " $* " == *" desktop-integration ping "* ]]; then
            [[ "${DESKTOP_SHELL_TEST_DI:-0}" == 1 ]] || exit 1
            if [[ "${DESKTOP_SHELL_TEST_PING:-READY}" == READY ]]; then
                printf 'READY\n'
                exit 0
            fi
            printf '%s\n' "${DESKTOP_SHELL_TEST_PING}"
            exit 0
        fi
        if [[ " $* " == *" desktop-integration settleWallpaper "* ]]; then
            printf '%s\n' "${DESKTOP_SHELL_TEST_WALLPAPER:-WC}"
            exit 0
        fi
        if [[ " $* " == *" desktop-integration prepareWaybar "* ]]; then
            [[ "${DESKTOP_SHELL_TEST_DI:-0}" == 1 ]] || exit 1
            printf '%s\n' "prepareWaybar" >>"$DESKTOP_SHELL_TEST_RUNTIME/lifecycle.log"
            case "${DESKTOP_SHELL_TEST_PREPARE:-READY}" in
                READY | READY_WC)
                    printf '%s\n' "${DESKTOP_SHELL_TEST_PREPARE:-READY}"
                    exit 0
                    ;;
                PENDING)
                    printf 'PENDING\n'
                    exit 0
                    ;;
                *)
                    printf '%s\n' "${DESKTOP_SHELL_TEST_PREPARE}"
                    exit 1
                    ;;
            esac
        fi
        if [[ " $* " == *" desktop-integration resume "* ]]; then
            [[ "${DESKTOP_SHELL_TEST_DI:-0}" == 1 ]] || exit 1
            printf '%s\n' resume >>"$DESKTOP_SHELL_TEST_RUNTIME/lifecycle.log"
            printf 'READY\n'
            exit 0
        fi
        if [[ " $* " == *" idle setExternalOwner "* ]]; then
            [[ "${DESKTOP_SHELL_TEST_IDLE_FAIL:-0}" == 1 ]] && exit 1
            printf 'OK\n'
            exit 0
        fi
        if [[ " $* " == *" idle owner "* ]]; then
            [[ "${DESKTOP_SHELL_TEST_IDLE_FAIL:-0}" == 1 ]] && exit 1
            printf 'quickshell\n'
            exit 0
        fi
        ;;
    *)
        printf '%s\n' qs-start >>"$DESKTOP_SHELL_TEST_RUNTIME/lifecycle.log"
        printf '%s\n' "$QML_IMPORT_PATH" >"$DESKTOP_SHELL_TEST_RUNTIME/qml-import-path"
        printf '%s\n' "${CLAVIS_KEY:-}" >"$DESKTOP_SHELL_TEST_RUNTIME/key-path"
        printf '%s\n' "${CLAVIS_EXTERNAL_IDLE_OWNER:-}" >"$DESKTOP_SHELL_TEST_RUNTIME/external-idle"
        rm -f "$DESKTOP_SHELL_TEST_RUNTIME/quickshell-supervisor-stopped"
        touch "$DESKTOP_SHELL_TEST_RUNTIME/quickshell"
        [[ "${DESKTOP_SHELL_TEST_MAKO_RACE:-0}" == 1 ]] \
            && touch "$DESKTOP_SHELL_TEST_RUNTIME/mako"
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

cat >"$fake_bin/busctl" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" StartServiceByName "* ]]; then
    printf '%s\n' secret-service-start \
        >>"$DESKTOP_SHELL_TEST_RUNTIME/lifecycle.log"
    printf '%s\n' "$*" >>"$DESKTOP_SHELL_TEST_RUNTIME/secret-service.log"
    touch "$DESKTOP_SHELL_TEST_RUNTIME/secret-service"
elif [[ " $* " == *" org.freedesktop.secrets "* ]]; then
    [[ -e "$DESKTOP_SHELL_TEST_RUNTIME/secret-service" ]] || exit 1
    printf '%s\n' Comm=ksecretd
elif [[ -e "$DESKTOP_SHELL_TEST_RUNTIME/mako" ]]; then
    printf '%s\n' Comm=mako
elif [[ -e "$DESKTOP_SHELL_TEST_RUNTIME/quickshell" ]]; then
    printf '%s\n' Comm=qs
else
    exit 1
fi
EOF

chmod +x "$fake_bin"/* "$fake_home/.config/niri/scripts/swayidle.sh"
touch "$runtime_state/waybar" "$runtime_state/mako" "$runtime_state/swayidle"

run_shell() {
    HOME="$fake_home" \
        XDG_STATE_HOME="$fake_state" \
        PATH="$fake_bin:/usr/bin" \
        QML_IMPORT_PATH="$fake_home/.local/lib/qt6/qml" \
        DESKTOP_SHELL_NOTIFY=0 \
        DESKTOP_SHELL_TEST_RUNTIME="$runtime_state" \
        DESKTOP_SHELL_TEST_WCR_FAIL="${DESKTOP_SHELL_TEST_WCR_FAIL:-}" \
        DESKTOP_SHELL_TEST_WCR_FORK="${DESKTOP_SHELL_TEST_WCR_FORK:-}" \
        DESKTOP_SHELL_TEST_MAKO_RACE="${DESKTOP_SHELL_TEST_MAKO_RACE:-0}" \
        DESKTOP_SHELL_TEST_QS_KILL_FAIL="${DESKTOP_SHELL_TEST_QS_KILL_FAIL:-0}" \
        DESKTOP_SHELL_TEST_QS_RESTART_AFTER_KILL="${DESKTOP_SHELL_TEST_QS_RESTART_AFTER_KILL:-0}" \
        DESKTOP_SHELL_TEST_PROCESS_STOP_FAIL="${DESKTOP_SHELL_TEST_PROCESS_STOP_FAIL:-}" \
        DESKTOP_SHELL_TEST_DI="${DESKTOP_SHELL_TEST_DI:-0}" \
        DESKTOP_SHELL_TEST_PING="${DESKTOP_SHELL_TEST_PING:-READY}" \
        DESKTOP_SHELL_TEST_PREPARE="${DESKTOP_SHELL_TEST_PREPARE:-READY}" \
        DESKTOP_SHELL_TEST_IDLE_FAIL="${DESKTOP_SHELL_TEST_IDLE_FAIL:-0}" \
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

# A zombie does not own a usable bar and must not suppress a replacement.
: >"$runtime_state/lifecycle.log"
touch "$runtime_state/waybar.zombie"
DESKTOP_SHELL_FOREGROUND=1 run_shell waybar
grep -Fxq "waybar-start" "$runtime_state/lifecycle.log"
[[ ! -e "$runtime_state/waybar.zombie" ]]
: >"$runtime_state/lifecycle.log"

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

DESKTOP_SHELL_TEST_MAKO_RACE=1 DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell
[[ -e "$runtime_state/quickshell" ]]
[[ ! -e "$runtime_state/waybar" ]]
if [[ -e "$runtime_state/mako" ]]; then
    echo "Mako retained notification ownership after QuickShell became ready" >&2
    exit 1
fi
[[ ! -e "$runtime_state/swayidle" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == quickshell ]]
grep -Fxq "stop" "$runtime_state/wcr.log"
[[ "$(cat "$runtime_state/qml-import-path")" == "$fake_home/.local/lib/qt6/qml" ]]
mapfile -t lifecycle_events <"$runtime_state/lifecycle.log"
[[ "${lifecycle_events[*]}" == "secret-service-start qs-start wcr-stop" ]]
grep -Fq "StartServiceByName su org.freedesktop.secrets 0" \
    "$runtime_state/secret-service.log"

: >"$runtime_state/wcr.log"
touch "$runtime_state/mako"
touch "$runtime_state/cava-sh" "$runtime_state/cava"
DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell
[[ ! -e "$runtime_state/mako" ]]
[[ ! -e "$runtime_state/cava-sh" ]]
[[ ! -e "$runtime_state/cava" ]]
grep -Fxq "stop" "$runtime_state/wcr.log"

: >"$runtime_state/lifecycle.log"
: >"$runtime_state/pkill.log"
DESKTOP_SHELL_TEST_WCR_FORK=restore \
    DESKTOP_SHELL_TEST_QS_RESTART_AFTER_KILL=1 \
    DESKTOP_SHELL_FOREGROUND=1 run_shell toggle
sleep 0.4
[[ ! -e "$runtime_state/quickshell" ]]
[[ -e "$runtime_state/waybar" ]]
[[ -e "$runtime_state/mako" ]]
[[ -e "$runtime_state/swayidle" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == waybar ]]
grep -Fxq "restore" "$runtime_state/wcr.log"
mapfile -t lifecycle_events <"$runtime_state/lifecycle.log"
[[ "${lifecycle_events[*]}" == "waybar-start wcr-restore qs-kill" ]]
# Legacy stop may still use a global quickshell pkill.
grep -Eq '(^| )-x quickshell($| )' "$runtime_state/pkill.log"
flock -n "$fake_state/dotfiles/desktop-shell.lock" true

mkdir -p "$fake_state/idle-control"
touch "$fake_state/idle-control/active"
rm -f "$runtime_state/swayidle"
DESKTOP_SHELL_FOREGROUND=1 run_shell waybar
[[ ! -e "$runtime_state/swayidle" ]]
DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell
grep -Fq "call idle setExternalOwner true" "$runtime_state/ipc.log"
rm -f "$fake_state/idle-control/active"
DESKTOP_SHELL_FOREGROUND=1 run_shell waybar

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
if DESKTOP_SHELL_TEST_QS_KILL_FAIL=1 \
    DESKTOP_SHELL_TEST_PROCESS_STOP_FAIL=quickshell \
    DESKTOP_SHELL_FOREGROUND=1 run_shell waybar; then
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

# A failed native-module build must preserve the active shell and avoid launch.
mkdir -p "$fake_home/.config/waybar/cffi"
printf '#!/usr/bin/env bash\nexit 1\n' >"$fake_home/.config/waybar/cffi/build.sh"
chmod +x "$fake_home/.config/waybar/cffi/build.sh"
: >"$runtime_state/lifecycle.log"
if DESKTOP_SHELL_FOREGROUND=1 run_shell waybar; then
    echo "Waybar switch ignored brightness module preparation failure" >&2
    exit 1
fi
[[ -e "$runtime_state/quickshell" && ! -e "$runtime_state/waybar" ]]
[[ ! -s "$runtime_state/lifecycle.log" ]]
rm "$fake_home/.config/waybar/cffi/build.sh"

DESKTOP_SHELL_FOREGROUND=1 run_shell switcher
[[ -e "$runtime_state/switcher" ]]
grep -Fxq "switcher-start" "$runtime_state/lifecycle.log"

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

printf 'dual\n' >"$fake_state/dotfiles/desktop-shell-profile"

# --- Upstream migration adapter cases ---

upstream_config="$tmp_dir/upstream-clavis"
mkdir -p "$upstream_config/build/qml/Clavis" "$upstream_config/Modules/ControlCenter"
touch "$upstream_config/shell.qml" "$upstream_config/AppShell.qml" "$upstream_config/switcher.qml"
# No controlcenter.qml — marks an upstream tree.
printf '%s\n' "$upstream_config" >"$fake_state/dotfiles/quickshell-config-path"

status_output="$(run_shell status)"
[[ "$status_output" == *"quickshell_config=$upstream_config"* ]]

# Invalid marker must fall back to the legacy default.
printf 'relative/not/absolute\n' >"$fake_state/dotfiles/quickshell-config-path"
status_output="$(run_shell status)"
[[ "$status_output" == *"quickshell_config=$fake_home/.local/share/quickshell/clavis"* ]]
printf '%s\n' "$upstream_config" >"$fake_state/dotfiles/quickshell-config-path"

# Env override still wins over the marker.
status_output="$(
    QUICKSHELL_CONFIG_PATH="$fake_home/.local/share/quickshell/clavis" run_shell status
)"
[[ "$status_output" == *"quickshell_config=$fake_home/.local/share/quickshell/clavis"* ]]

rm -f "$runtime_state/quickshell" "$runtime_state/waybar" "$runtime_state/mako" \
    "$runtime_state/swayidle" "$runtime_state/switcher"
touch "$runtime_state/waybar" "$runtime_state/mako" "$runtime_state/swayidle"
: >"$runtime_state/lifecycle.log"
: >"$runtime_state/ipc.log"
: >"$runtime_state/wcr.log"
: >"$runtime_state/pkill.log"

mkdir -p "$tmp_dir/dependency-qml/M3Shapes" "$fake_state/idle-control"
printf '%s\n' "$tmp_dir/dependency-qml" >"$fake_state/dotfiles/quickshell-extra-qml-path"
printf '%s\n' "$fake_bin/qs" >"$fake_state/dotfiles/quickshell-key-path"
touch "$fake_state/idle-control/active"
DESKTOP_SHELL_TEST_DI=1 DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell
[[ -e "$runtime_state/quickshell" ]]
[[ ! -e "$runtime_state/waybar" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == quickshell ]]
qml_path="$(cat "$runtime_state/qml-import-path")"
[[ "$qml_path" == "$upstream_config/build/qml:"* ]] \
    || [[ "$qml_path" == "$upstream_config/build/qml" ]]
[[ "$qml_path" == *"$fake_home/.local/lib/qt6/qml"* ]]
[[ "$qml_path" == "$upstream_config/build/qml:$tmp_dir/dependency-qml:"* ]]
[[ "$(cat "$runtime_state/key-path")" == "$fake_bin/qs" ]]
[[ "$(cat "$runtime_state/external-idle")" == 1 ]]
rm -f "$fake_state/idle-control/active"
grep -Fq "call desktop-integration version" "$runtime_state/ipc.log"
grep -Fq "call desktop-integration ping" "$runtime_state/ipc.log"

# Upstream launcher / control-center IPC targets.
: >"$runtime_state/ipc.log"
run_shell launcher
grep -Fq "call spotlight toggle" "$runtime_state/ipc.log"
: >"$runtime_state/ipc.log"
run_shell control-center
grep -Fq 'call control-center toggle' "$runtime_state/ipc.log"

# Exact stop: auxiliary switcher survives; no global quickshell pkill.
DESKTOP_SHELL_FOREGROUND=1 run_shell switcher
[[ -e "$runtime_state/switcher" ]]
: >"$runtime_state/lifecycle.log"
: >"$runtime_state/pkill.log"
DESKTOP_SHELL_TEST_DI=1 \
    DESKTOP_SHELL_FOREGROUND=1 run_shell waybar
[[ ! -e "$runtime_state/quickshell" ]]
[[ -e "$runtime_state/waybar" ]]
[[ -e "$runtime_state/switcher" ]]
grep -Fq "prepareWaybar" "$runtime_state/lifecycle.log"
if grep -Eq '(^| )-x quickshell($| )' "$runtime_state/pkill.log"; then
    echo "Upstream stop used global pkill -x quickshell" >&2
    cat "$runtime_state/pkill.log" >&2
    exit 1
fi

# Non-ready desktop-integration ping keeps Waybar.
rm -f "$runtime_state/quickshell"
touch "$runtime_state/waybar" "$runtime_state/mako" "$runtime_state/swayidle"
: >"$runtime_state/lifecycle.log"
if DESKTOP_SHELL_TEST_DI=1 DESKTOP_SHELL_TEST_PING=NOT_READY \
    DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell; then
    echo "QuickShell switch ignored non-ready desktop-integration ping" >&2
    exit 1
fi
[[ ! -e "$runtime_state/quickshell" ]]
[[ -e "$runtime_state/waybar" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == waybar ]]
mapfile -t lifecycle_events <"$runtime_state/lifecycle.log"
[[ "${lifecycle_events[*]}" == "qs-start qs-kill" ]]

# prepareWaybar failure rolls back before Wallpaper Console restore.
DESKTOP_SHELL_TEST_DI=1 DESKTOP_SHELL_TEST_PING=READY \
    DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell
: >"$runtime_state/lifecycle.log"
: >"$runtime_state/wcr.log"
if DESKTOP_SHELL_TEST_DI=1 DESKTOP_SHELL_TEST_PREPARE=FAIL \
    DESKTOP_SHELL_FOREGROUND=1 run_shell waybar; then
    echo "Waybar switch ignored prepareWaybar failure" >&2
    exit 1
fi
[[ -e "$runtime_state/quickshell" ]]
[[ ! -e "$runtime_state/waybar" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == quickshell ]]
[[ ! -s "$runtime_state/wcr.log" ]]
grep -Fq "prepareWaybar" "$runtime_state/lifecycle.log"

# prepareWaybar succeeded then WC restore failed → resume.
grep -Fq "resume" "$runtime_state/lifecycle.log"
: >"$runtime_state/lifecycle.log"
: >"$runtime_state/wcr.log"
if DESKTOP_SHELL_TEST_DI=1 DESKTOP_SHELL_TEST_PREPARE=READY \
    DESKTOP_SHELL_TEST_WCR_FAIL=restore \
    DESKTOP_SHELL_FOREGROUND=1 run_shell waybar; then
    echo "Waybar switch ignored Wallpaper Console restore failure after prepare" >&2
    exit 1
fi
[[ -e "$runtime_state/quickshell" ]]
[[ ! -e "$runtime_state/waybar" ]]
grep -Fq "resume" "$runtime_state/lifecycle.log"
mapfile -t lifecycle_events <"$runtime_state/lifecycle.log"
[[ "${lifecycle_events[*]}" == "waybar-start prepareWaybar wcr-restore resume" ]]

# Idle sync failure with external-owner marker is fatal before removing Waybar.
rm -f "$runtime_state/quickshell"
touch "$runtime_state/waybar" "$runtime_state/mako" "$runtime_state/swayidle"
printf 'waybar\n' >"$fake_state/dotfiles/desktop-shell"
mkdir -p "$fake_state/idle-control"
touch "$fake_state/idle-control/active"
: >"$runtime_state/lifecycle.log"
if DESKTOP_SHELL_TEST_DI=1 DESKTOP_SHELL_TEST_IDLE_FAIL=1 \
    DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell; then
    echo "Upstream QuickShell switch ignored fatal idle sync failure" >&2
    exit 1
fi
[[ ! -e "$runtime_state/quickshell" ]]
[[ -e "$runtime_state/waybar" ]]
[[ "$(cat "$fake_state/dotfiles/desktop-shell")" == waybar ]]
mapfile -t lifecycle_events <"$runtime_state/lifecycle.log"
[[ "${lifecycle_events[*]}" == "qs-start qs-kill" ]]
rm -f "$fake_state/idle-control/active"

# New trees without the integration contract cannot displace a healthy Waybar.
if DESKTOP_SHELL_TEST_DI=0 DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell; then
    echo "Upstream shell without desktop integration was accepted" >&2
    exit 1
fi
[[ -e "$runtime_state/waybar" && ! -e "$runtime_state/quickshell" ]]

# Version 2 delegates wallpaper decisions to Clavis, including degraded WC.
for wallpaper in WC WC_FALLBACK LOCAL; do
    rm -f "$runtime_state/quickshell"
    touch "$runtime_state/waybar"
    : >"$runtime_state/wcr.log"
    DESKTOP_SHELL_TEST_DI=1 DESKTOP_SHELL_TEST_DI_VERSION=2 \
        DESKTOP_SHELL_TEST_WALLPAPER="$wallpaper" DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell
    [[ -e "$runtime_state/quickshell" && ! -e "$runtime_state/waybar" ]]
    [[ ! -s "$runtime_state/wcr.log" ]]
    DESKTOP_SHELL_TEST_DI=1 DESKTOP_SHELL_TEST_DI_VERSION=2 \
        DESKTOP_SHELL_TEST_WALLPAPER="$wallpaper" DESKTOP_SHELL_FOREGROUND=1 run_shell start
    [[ ! -s "$runtime_state/wcr.log" ]]
done

# WC remains owned while handing the shell to Waybar: no restore/restart.
: >"$runtime_state/wcr.log"
DESKTOP_SHELL_TEST_DI=1 DESKTOP_SHELL_TEST_DI_VERSION=2 \
    DESKTOP_SHELL_TEST_PREPARE=READY_WC DESKTOP_SHELL_FOREGROUND=1 run_shell waybar
[[ -e "$runtime_state/waybar" && ! -e "$runtime_state/quickshell" ]]
[[ ! -s "$runtime_state/wcr.log" ]]

# A failed new protocol must never invoke the legacy unconditional stop.
for wallpaper in ERROR unexpected; do
    : >"$runtime_state/wcr.log"
    if DESKTOP_SHELL_TEST_DI=1 DESKTOP_SHELL_TEST_DI_VERSION=2 \
        DESKTOP_SHELL_TEST_WALLPAPER="$wallpaper" DESKTOP_SHELL_FOREGROUND=1 run_shell quickshell; then
        echo "Version 2 ignored wallpaper handoff failure" >&2
        exit 1
    fi
    [[ -e "$runtime_state/waybar" && ! -e "$runtime_state/quickshell" ]]
    [[ ! -s "$runtime_state/wcr.log" ]]
done

completion_file="$REPO_ROOT/configs/zsh/site-functions/_desktop-shell"
grep -Fxq '#compdef desktop-shell' "$completion_file"
for completion in toggle waybar quickshell status switcher start launcher lock hub tools control-center; do
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

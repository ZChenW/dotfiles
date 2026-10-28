#!/usr/bin/env bash
# macOS layer: OmniWM + kitty on top of stock macOS, fully reversible.
#
#   scripts/macos.sh apply [--system] [--dry-run]
#   scripts/macos.sh rollback [--system-only] [--dry-run]
#   scripts/macos.sh status
#
# `apply` installs the casks in packages/macos-casks.txt and the configs in
# configs/macos. `--system` also sets the preferences in
# configs/macos/system-defaults.tsv. Before changing anything it records what
# was there in $STATE_DIR, and `rollback` uses that record to put the machine
# back: it uninstalls only the casks it installed, restores every file and
# preference, and moves anything it would delete into ~/.dotfiles-backups.
#
# Runs under macOS's /bin/bash 3.2: no associative arrays, mapfile or ${x,,}.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
MACOS_CONFIG="$REPO_ROOT/configs/macos"
SHARED_CONFIG="$REPO_ROOT/configs/config"
HELPERS="$SCRIPT_DIR/macos"
CASKS_FILE="$REPO_ROOT/packages/macos-casks.txt"
FORMULAE_FILE="$REPO_ROOT/packages/macos-formulae.txt"

STATE_DIR="${DOTFILES_MACOS_STATE:-$HOME/.local/state/dotfiles-macos}"
BACKUP_BASE="${DOTFILES_BACKUP_BASE:-$HOME/.dotfiles-backups}"
OMNIWM_CONFIG="$HOME/.config/omniwm"
OMNIWM_BUNDLE_ID=com.barut.OmniWM
OMNIWM_WAIT="${OMNIWM_WAIT:-30}"
RIME_DIR="$HOME/Library/Rime"
RIME_ICE_REPO="${RIME_ICE_REPO:-https://github.com/iDvel/rime-ice}"
RIME_ICE_TAG=2026.06.30
SQUIRREL="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
NVIM_DIR="$HOME/.config/nvim"
NVIMDOTS_REPO="${NVIMDOTS_REPO:-https://github.com/ayamir/nvimdots}"
# nvimdots `main` for Neovim 0.12, as of 2026-10-15.
NVIMDOTS_REF="${NVIMDOTS_REF:-5e2eb61fe95788a82fece844a18097f7be91bdb2}"

DRY_RUN=false
WITH_SYSTEM=false
SYSTEM_ONLY=false
BACKUP_DIR=""

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    c_bold=$'\033[1m' c_dim=$'\033[2m' c_green=$'\033[32m' c_yellow=$'\033[33m' c_red=$'\033[31m' c_off=$'\033[0m'
else
    c_bold="" c_dim="" c_green="" c_yellow="" c_red="" c_off=""
fi

step() { printf '\n%s==> %s%s\n' "$c_bold" "$*" "$c_off"; }
info() { printf '  %s\n' "$*"; }
ok() { printf '  %s✓%s %s\n' "$c_green" "$c_off" "$*"; }
warn() { printf '  %s!%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
# Show a path with $HOME as ~ (the ~ in a ${x/#...} replacement expands in bash 5).
tilde() {
    local home='~'
    printf '%s' "${1/#"$HOME"/$home}"
}

die() {
    printf '%serror:%s %s\n' "$c_red" "$c_off" "$*" >&2
    exit 1
}

# Run a command, or only show it under --dry-run.
run() {
    if $DRY_RUN; then
        printf '  %s[dry-run]%s %s\n' "$c_dim" "$c_off" "$*"
    else
        "$@"
    fi
}

usage() {
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- state ----------------------------------------------------------------
# $STATE_DIR/casks      casks this script installed
# $STATE_DIR/taps       third-party taps it added (and trusted formulae from)
# $STATE_DIR/formulae   formulae it installed
# $STATE_DIR/services   launchd services it started (skhd)
# $STATE_DIR/login      login items it added (OmniWM)
# $STATE_DIR/files      <dest>\t<backup path, or - if dest did not exist>
# $STATE_DIR/created    paths that apps created after we installed them
# $STATE_DIR/prefs      <domain>\t<keypath>\t<saved-value file>
# $STATE_DIR/omniwm-default-settings.toml   OmniWM's own generated defaults

state_init() {
    $DRY_RUN && return 0
    mkdir -p "$STATE_DIR/prefs.d"
    touch "$STATE_DIR/casks" "$STATE_DIR/taps" "$STATE_DIR/formulae" "$STATE_DIR/services" \
        "$STATE_DIR/login" "$STATE_DIR/files" "$STATE_DIR/created" "$STATE_DIR/prefs"
}

# state_has FILE FIELD1 [FIELD2]: is there a record starting with these fields?
state_has() {
    local file="$STATE_DIR/$1" key="$2"
    [[ $# -ge 3 ]] && key="$2"$'\t'"$3"
    [[ -f "$file" ]] || return 1
    awk -F'\t' -v key="$key" -v n="$#" '
        { k = (n >= 3) ? $1 "\t" $2 : $1 }
        k == key { found = 1 }
        END { exit !found }' "$file"
}

state_add() {
    $DRY_RUN && return 0
    printf '%s\n' "$2" >>"$STATE_DIR/$1"
}

# Print a state file's lines last-first, so rollback undoes in reverse order.
state_reversed() {
    [[ -f "$STATE_DIR/$1" ]] || return 0
    awk '{ line[NR] = $0 } END { for (i = NR; i > 0; i--) if (line[i] != "") print line[i] }' "$STATE_DIR/$1"
}

# BACKUP_DIR is chosen once in main(); it is only created when first used.
backup_dir() {
    $DRY_RUN || mkdir -p "$BACKUP_DIR"
    printf '%s\n' "$BACKUP_DIR"
}

# Move PATH under the backup dir, keeping its path relative to $HOME.
stash() {
    local path="$1" rel dest
    rel="${path#"$HOME"/}"
    dest="$(backup_dir)/$rel"
    run mkdir -p "$(dirname -- "$dest")"
    run mv "$path" "$dest"
}

# --- apply ----------------------------------------------------------------

read_list() {
    grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$' || true
}

# Paths an app creates on first run; recorded only when absent beforehand, so
# rollback can stash them without touching anything the user already had.
created_paths_for() {
    case "$1" in
        omniwm)
            printf '%s\n' "$OMNIWM_CONFIG" "$HOME/.local/state/omniwm" \
                "$HOME/Library/Logs/OmniWM" "$HOME/Library/Preferences/$OMNIWM_BUNDLE_ID.plist"
            ;;
        kitty)
            printf '%s\n' "$HOME/Library/Caches/kitty" \
                "$HOME/Library/Preferences/net.kovidgoyal.kitty.plist"
            ;;
        neovim)
            printf '%s\n' "$NVIM_DIR" "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"
            ;;
        go)
            printf '%s\n' "$HOME/go" "$HOME/Library/Caches/go-build"
            ;;
        squirrel-app)
            printf '%s\n' "$RIME_DIR" "$HOME/Library/Caches/im.rime.inputmethod.Squirrel" \
                "$HOME/Library/Preferences/im.rime.inputmethod.Squirrel.plist"
            ;;
    esac
}

apply_casks() {
    step "Homebrew casks"
    command -v brew >/dev/null 2>&1 || die "Homebrew is required: https://brew.sh"
    local cask path
    while IFS= read -r cask; do
        if state_has casks "$cask"; then
            ok "$cask (installed earlier by this script)"
            continue
        fi
        if brew list --cask "$cask" </dev/null >/dev/null 2>&1; then
            ok "$cask already installed; rollback will keep it"
            continue
        fi
        while IFS= read -r path; do
            [[ -e "$path" ]] || state_has created "$path" || state_add created "$path"
        done < <(created_paths_for "$cask")
        # </dev/null: brew must not read the cask list this loop is reading.
        run brew install --cask "$cask" </dev/null
        state_add casks "$cask"
    done < <(read_list "$CASKS_FILE")
}

# Formulae are tap-qualified (owner/tap/name). Homebrew only loads formulae
# from third-party taps it has been told to trust, so trust exactly those.
apply_formulae() {
    step "Homebrew formulae"
    local formula tap taps_before path
    while IFS= read -r formula; do
        if state_has formulae "$formula"; then
            ok "$formula (installed earlier by this script)"
            continue
        fi
        if brew list --formula "${formula##*/}" </dev/null >/dev/null 2>&1; then
            ok "$formula already installed; rollback will keep it"
            continue
        fi
        while IFS= read -r path; do
            [[ -e "$path" ]] || state_has created "$path" || state_add created "$path"
        done < <(created_paths_for "${formula##*/}")
        # Compare taps before and after: a renamed tap pulls in its new name too.
        taps_before="$(brew tap </dev/null)"
        if [[ "$formula" == */*/* ]]; then
            tap="${formula%/*}"
            printf '%s\n' "$taps_before" | grep -qx "$tap" || run brew tap "$tap" </dev/null
            run brew trust --formula "$formula" </dev/null
        fi
        run brew install "$formula" </dev/null
        state_add formulae "$formula"
        if ! $DRY_RUN; then
            while IFS= read -r tap; do
                printf '%s\n' "$taps_before" | grep -qx "$tap" || state_has taps "$tap" || state_add taps "$tap"
            done < <(brew tap </dev/null)
        fi
    done < <(read_list "$FORMULAE_FILE")
}

# Rime with rime-ice, the same engine and dictionary as fcitx5-rime on Linux.
# Left Shift switches Chinese/English (rime-ice's default.yaml).
apply_rime() {
    step "Rime (rime-ice $RIME_ICE_TAG)"
    if [[ -f "$RIME_DIR/rime_ice.schema.yaml" ]]; then
        ok "$(tilde "$RIME_DIR") has rime-ice"
        return 0
    fi
    if [[ -d "$RIME_DIR" ]] && ! state_has created "$RIME_DIR" && [[ -n "$(ls -A "$RIME_DIR")" ]]; then
        warn "$(tilde "$RIME_DIR") already has your own Rime setup; leaving it alone"
        return 0
    fi
    [[ -e "$RIME_DIR" ]] || state_has created "$RIME_DIR" || state_add created "$RIME_DIR"
    if $DRY_RUN; then
        info "would copy rime-ice $RIME_ICE_TAG into $(tilde "$RIME_DIR")"
        return 0
    fi
    local tmp
    tmp="$(mktemp -d)"
    git clone --quiet --depth 1 --branch "$RIME_ICE_TAG" -c advice.detachedHead=false \
        "$RIME_ICE_REPO" "$tmp/rime-ice" </dev/null
    rm -rf "$tmp/rime-ice/.git" "$tmp/rime-ice/.github" "$tmp/rime-ice/others"
    mkdir -p "$RIME_DIR"
    cp -R "$tmp/rime-ice/." "$RIME_DIR/"
    rm -rf "$tmp"
    ok "rime-ice copied to $(tilde "$RIME_DIR")"
    if [[ -x "$SQUIRREL" ]]; then
        "$SQUIRREL" --reload >/dev/null 2>&1 || true
        ok "Squirrel redeployed"
    fi
}

# The shared .zshrc decides per OS what it loads (see its linux* blocks).
apply_shell() {
    step "zsh"
    deploy "$REPO_ROOT/configs/home/.zshrc" "$HOME/.zshrc"
    if [[ -e "$HOME/.zshrc.local" ]]; then
        ok "~/.zshrc.local kept (private, never managed)"
    else
        deploy "$REPO_ROOT/templates/zshrc.local.example" "$HOME/.zshrc.local" 600
    fi
    deploy "$SHARED_CONFIG/git/ignore" "$HOME/.config/git/ignore"
}

# Copy a config tree, rendering the @HOME@/@CONFIG_HOME@ placeholders the
# Linux installer also renders.
deploy_tree() {
    local src_root="$1" dest_root="$2" src rel rendered
    rendered="$(mktemp -d)"
    while IFS= read -r src; do
        rel="${src#"$src_root"/}"
        if grep -Iq . "$src" 2>/dev/null && grep -q '@\(CONFIG_\)\{0,1\}HOME@' "$src"; then
            mkdir -p "$(dirname -- "$rendered/$rel")"
            sed -e "s|@CONFIG_HOME@|$HOME/.config|g" -e "s|@HOME@|$HOME|g" "$src" >"$rendered/$rel"
            deploy "$rendered/$rel" "$dest_root/$rel"
        else
            deploy "$src" "$dest_root/$rel"
        fi
    done < <(find "$src_root" -type f ! -name .DS_Store | sort)
    rm -rf "$rendered"
}

apply_fastfetch() {
    step "fastfetch"
    deploy_tree "$SHARED_CONFIG/fastfetch" "$HOME/.config/fastfetch"
}

# nvimdots, pinned; installed the way its own scripts/install.sh does it.
apply_nvim() {
    step "Neovim (nvimdots ${NVIMDOTS_REF:0:7})"
    if [[ -f "$NVIM_DIR/lua/user/settings.lua" ]] && state_has created "$NVIM_DIR"; then
        ok "$(tilde "$NVIM_DIR") has nvimdots"
        return 0
    fi
    if [[ -e "$NVIM_DIR" ]] && ! state_has created "$NVIM_DIR"; then
        warn "$(tilde "$NVIM_DIR") already exists and is yours; leaving it alone"
        return 0
    fi
    [[ -e "$NVIM_DIR" ]] || state_has created "$NVIM_DIR" || state_add created "$NVIM_DIR"
    if $DRY_RUN; then
        info "would clone nvimdots into $(tilde "$NVIM_DIR") and fetch its plugins"
        return 0
    fi
    git clone --quiet -c advice.detachedHead=false "$NVIMDOTS_REPO" "$NVIM_DIR" </dev/null
    git -C "$NVIM_DIR" checkout --quiet "$NVIMDOTS_REF"
    mkdir -p "$NVIM_DIR/lua/user"
    cp -R "$NVIM_DIR/lua/user_template/." "$NVIM_DIR/lua/user/"
    sed -i '' 's/settings\["use_ssh"\] = true/settings["use_ssh"] = false/' "$NVIM_DIR/lua/user/settings.lua"
    ok "nvimdots in $(tilde "$NVIM_DIR") (plugins over HTTPS)"
    if command -v nvim >/dev/null 2>&1; then
        info "fetching plugins (lazy.nvim); this takes a few minutes"
        perl -e 'alarm 900; exec @ARGV' nvim --headless "+Lazy! restore" +qa </dev/null >/dev/null 2>&1 ||
            warn "plugin fetch did not finish; open nvim and run :Lazy restore"
    fi
}

# skhd binds the hotkeys that launch programs, which OmniWM cannot do.
apply_skhd() {
    step "skhd"
    deploy "$MACOS_CONFIG/skhd/skhdrc" "$HOME/.config/skhd/skhdrc"
    if state_has services skhd; then
        $DRY_RUN || skhd --restart-service >/dev/null 2>&1 || true
        return 0
    fi
    local plist="$HOME/Library/LaunchAgents/com.koekeishiya.skhd.plist"
    if [[ -e "$plist" ]]; then
        ok "skhd service already set up; rollback will keep it"
        return 0
    fi
    state_has created "$plist" || state_add created "$plist"
    run skhd --start-service
    state_add services skhd
}

login_items() {
    osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null |
        tr ',' '\n' | sed 's/^ *//'
}

# Start OmniWM at login, as niri starts with the session.
apply_login_items() {
    step "Login items"
    if state_has login OmniWM || login_items | grep -qx OmniWM; then
        ok "OmniWM starts at login"
        return 0
    fi
    run osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/OmniWM.app", hidden:false}' >/dev/null
    state_add login OmniWM
    $DRY_RUN || ok "OmniWM starts at login"
}

# Install SRC at DEST, backing up whatever DEST was the first time.
deploy() {
    local src="$1" dest="$2" mode="${3:-644}" saved="-"
    if ! state_has files "$dest"; then
        if [[ -e "$dest" ]]; then
            saved="$(backup_dir)/${dest#"$HOME"/}"
            run mkdir -p "$(dirname -- "$saved")"
            run cp -p "$dest" "$saved"
        fi
        state_add files "$dest"$'\t'"$saved"
    fi
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        ok "$(tilde "$dest") up to date"
        return 0
    fi
    # Remember the outermost directory this creates, so rollback removes it too.
    local top
    top="$(dirname -- "$dest")"
    if [[ ! -d "$top" ]]; then
        while [[ ! -d "$(dirname -- "$top")" ]]; do top="$(dirname -- "$top")"; done
        state_has created "$top" || state_add created "$top"
    fi
    run mkdir -p "$(dirname -- "$dest")"
    run install -m "$mode" "$src" "$dest"
    $DRY_RUN || ok "$(tilde "$dest")"
}

apply_kitty() {
    step "kitty"
    local name
    for name in hyde.conf theme.conf matugen.conf focus_opacity.py; do
        deploy "$SHARED_CONFIG/kitty/$name" "$HOME/.config/kitty/$name"
    done
    deploy "$MACOS_CONFIG/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
    deploy "$MACOS_CONFIG/local-bin/kitty-new-window" "$HOME/.local/bin/kitty-new-window" 755
}

omniwm_patch() {
    python3 -I "$HELPERS/omniwm_patch.py" "$@" \
        --defaults "$STATE_DIR/omniwm-default-settings.toml" \
        --hotkeys "$MACOS_CONFIG/omniwm/hotkeys.tsv" \
        --settings "$MACOS_CONFIG/omniwm/settings.tsv" \
        --app-rules "$MACOS_CONFIG/omniwm/app-rules.toml"
}

apply_omniwm() {
    step "OmniWM"
    local settings="$OMNIWM_CONFIG/settings.toml" waited=0
    if [[ ! -f "$settings" ]]; then
        if $DRY_RUN; then
            info "would start OmniWM so it writes its default settings.toml, then"
            info "bind $(read_list "$MACOS_CONFIG/omniwm/hotkeys.tsv" | wc -l | tr -d ' ') hotkeys and set $(read_list "$MACOS_CONFIG/omniwm/settings.tsv" | wc -l | tr -d ' ') settings in it"
            return 0
        fi
        info "starting OmniWM to generate its default settings"
        open -a OmniWM || die "could not start OmniWM"
        while [[ ! -f "$settings" && $waited -lt $OMNIWM_WAIT ]]; do
            sleep 1
            waited=$((waited + 1))
        done
        if [[ ! -f "$settings" ]]; then
            warn "OmniWM has not written $settings yet."
            warn "Finish its first-run setup (permissions below), then run: scripts/macos.sh apply"
            return 0
        fi
    fi
    if [[ ! -f "$STATE_DIR/omniwm-default-settings.toml" ]]; then
        if $DRY_RUN; then
            info "would keep a copy of the current settings.toml as the id reference"
            python3 -I "$HELPERS/omniwm_patch.py" "$settings" --dry-run \
                --defaults "$settings" \
                --hotkeys "$MACOS_CONFIG/omniwm/hotkeys.tsv" \
                --settings "$MACOS_CONFIG/omniwm/settings.tsv" \
                --app-rules "$MACOS_CONFIG/omniwm/app-rules.toml" | sed 's/^/  /'
            return 0
        fi
        cp -p "$settings" "$STATE_DIR/omniwm-default-settings.toml"
    fi
    if ! state_has files "$settings"; then
        local saved
        saved="$(backup_dir)/${settings#"$HOME"/}"
        run mkdir -p "$(dirname -- "$saved")"
        run cp -p "$settings" "$saved"
        state_add files "$settings"$'\t'"$saved"
    fi
    if $DRY_RUN; then
        omniwm_patch "$settings" --dry-run | sed 's/^/  /'
    else
        omniwm_patch "$settings" | sed 's/^/  /'
    fi
}

apply_system() {
    step "macOS preferences"
    local domain keypath value file n=0
    while IFS=$'\t' read -r domain keypath value; do
        n=$((n + 1))
        if ! state_has prefs "$domain" "$keypath"; then
            file="$STATE_DIR/prefs.d/$n-$(printf '%s' "$domain-$keypath" | tr -c 'A-Za-z0-9._-' '_').plist"
            run python3 -I "$HELPERS/prefs.py" save "$domain" "$keypath" "$file"
            state_add prefs "$domain"$'\t'"$keypath"$'\t'"$file"
        fi
        run python3 -I "$HELPERS/prefs.py" set "$domain" "$keypath" "$value"
        $DRY_RUN || ok "$domain $keypath = $value"
    done < <(read_list "$MACOS_CONFIG/system-defaults.tsv")
    refresh_system
    info "Trackpad and key repeat changes may need a log out and back in to take effect."
}

refresh_system() {
    run killall Dock || true
    run killall Finder || true
    local activate=/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings
    if [[ -x "$activate" ]]; then
        run "$activate" -u || true
    fi
}

manual_steps() {
    step "Manual steps (macOS does not let scripts do these)"
    cat <<'EOF'
  1. System Settings > Privacy & Security > Accessibility: turn on OmniWM and
     skhd. Input Monitoring: turn on OmniWM. Screen & System Audio Recording:
     turn on OmniWM (window previews in the workspace bar and the overview).
  2. Squirrel (after a first install, log out and back in first): System
     Settings > Keyboard > Input Sources > Edit > + > Chinese, Simplified >
     Squirrel. Remove "Pinyin - Simplified" there, and in "All Input Sources"
     turn off "Use the Caps Lock key to switch to and from U.S.".
  Undo: rollback resets the OmniWM permissions; remove skhd from the
  Accessibility list by hand (macOS only lets scripts reset app bundles).
  After a rollback, add "Pinyin - Simplified" back and turn the Caps Lock
  switch on again in the same Input Sources sheet.
EOF
    if [[ "$(defaults read com.apple.spaces spans-displays 2>/dev/null || echo 0)" == 1 ]]; then
        warn "OmniWM needs \"Displays have separate Spaces\" (System Settings > Desktop & Dock) turned on."
    fi
}

cmd_apply() {
    $DRY_RUN && info "dry run: nothing will be changed"
    state_init
    apply_casks
    apply_formulae
    apply_rime
    apply_shell
    apply_fastfetch
    apply_nvim
    apply_kitty
    apply_omniwm
    apply_login_items
    apply_skhd
    $WITH_SYSTEM && apply_system
    manual_steps
    step "Done"
    info "Undo everything with: scripts/macos.sh rollback"
    $WITH_SYSTEM || info "When the trial feels right: scripts/macos.sh apply --system"
}

# --- rollback -------------------------------------------------------------

rollback_system() {
    step "Restore macOS preferences"
    local domain keypath file
    if [[ ! -s "$STATE_DIR/prefs" ]]; then
        info "no preferences were changed"
        return 0
    fi
    while IFS=$'\t' read -r domain keypath file; do
        run python3 -I "$HELPERS/prefs.py" restore "$domain" "$keypath" "$file"
        $DRY_RUN || ok "$domain $keypath"
    done < <(state_reversed prefs)
    refresh_system
    if ! $DRY_RUN; then
        rm -rf "$STATE_DIR/prefs.d"
        : >"$STATE_DIR/prefs"
    fi
    info "Trackpad gesture changes may need a log out and back in to take effect."
}

rollback_files() {
    step "Restore files"
    local dest saved
    while IFS=$'\t' read -r dest saved; do
        if [[ "$saved" == "-" ]]; then
            if [[ -e "$dest" ]]; then
                stash "$dest"
                $DRY_RUN || ok "removed $(tilde "$dest") (it did not exist before)"
            fi
        else
            run mkdir -p "$(dirname -- "$dest")"
            run cp -p "$saved" "$dest"
            $DRY_RUN || ok "restored $(tilde "$dest")"
        fi
    done < <(state_reversed files)
}

rollback_casks() {
    step "Uninstall what this script installed"
    local cask path
    if [[ ! -s "$STATE_DIR/casks" && ! -s "$STATE_DIR/formulae" ]]; then
        info "none"
    fi
    while IFS= read -r cask; do
        run brew uninstall --cask "$cask" </dev/null || warn "could not uninstall $cask"
    done < <(state_reversed casks)
    local service formula tap item
    while IFS= read -r item; do
        run osascript -e "tell application \"System Events\" to delete login item \"$item\"" >/dev/null 2>&1 ||
            warn "could not remove login item $item"
    done < <(state_reversed login)
    while IFS= read -r service; do
        run "$service" --uninstall-service </dev/null || warn "could not remove the $service service"
    done < <(state_reversed services)
    while IFS= read -r formula; do
        run brew uninstall "$formula" </dev/null || warn "could not uninstall $formula"
        [[ "$formula" == */*/* ]] && { run brew untrust --formula "$formula" </dev/null || true; }
    done < <(state_reversed formulae)
    # Dependencies Homebrew pulled in for those formulae and nothing else needs.
    if [[ -s "$STATE_DIR/formulae" ]]; then
        run brew autoremove </dev/null || warn "brew autoremove failed"
    fi
    while IFS= read -r tap; do
        run brew untap "$tap" </dev/null || warn "could not untap $tap"
    done < <(state_reversed taps)
    while IFS= read -r path; do
        [[ -e "$path" ]] && stash "$path"
    done < <(state_reversed created)
    if state_has casks omniwm; then
        run tccutil reset Accessibility "$OMNIWM_BUNDLE_ID" >/dev/null 2>&1 || true
        run tccutil reset ListenEvent "$OMNIWM_BUNDLE_ID" >/dev/null 2>&1 || true
        run tccutil reset ScreenCapture "$OMNIWM_BUNDLE_ID" >/dev/null 2>&1 || true
        $DRY_RUN || ok "OmniWM permissions reset"
    fi
}

cmd_rollback() {
    if [[ ! -d "$STATE_DIR" ]]; then
        info "Nothing to roll back ($STATE_DIR does not exist)."
        return 0
    fi
    $DRY_RUN && info "dry run: nothing will be changed"
    rollback_system
    $SYSTEM_ONLY && return 0
    # Quit OmniWM first so it cannot rewrite its settings while they are restored.
    if pgrep -xq OmniWM; then
        run osascript -e 'quit app "OmniWM"' >/dev/null 2>&1 || true
    fi
    if [[ "${TERM_PROGRAM:-}" == kitty || -n "${KITTY_PID:-}" ]] && state_has casks kitty; then
        warn "Running inside kitty, which is about to be uninstalled; the window stays open until you close it."
    fi
    rollback_files
    rollback_casks
    run mv "$STATE_DIR" "$(backup_dir)/dotfiles-macos-state"
    step "Back to stock macOS"
    info "The record of this setup and anything removed is in $(tilde "$BACKUP_DIR")"
    info "Delete the \"New kitty Window\" shortcut in Shortcuts.app if you made one."
}

# --- status ---------------------------------------------------------------

cmd_status() {
    if [[ ! -d "$STATE_DIR" ]]; then
        info "Not applied (no $STATE_DIR)."
        return 0
    fi
    step "Installed by this script"
    if [[ -s "$STATE_DIR/casks" || -s "$STATE_DIR/formulae" ]]; then
        cat "$STATE_DIR/casks" "$STATE_DIR/formulae" | sed 's/^/  /'
    else
        info "none"
    fi
    step "Managed files (backup, or - when the file was new)"
    if [[ -s "$STATE_DIR/files" ]]; then
        sed "s|$HOME|~|g; s/^/  /" "$STATE_DIR/files"
    else
        info "none"
    fi
    step "Changed preferences (now)"
    local domain keypath file
    if [[ -s "$STATE_DIR/prefs" ]]; then
        while IFS=$'\t' read -r domain keypath file; do
            info "$domain $keypath = $(python3 -I "$HELPERS/prefs.py" get "$domain" "$keypath")"
        done <"$STATE_DIR/prefs"
    else
        info "none (run apply --system to change them)"
    fi
    step "OmniWM"
    if pgrep -xq OmniWM; then ok "running"; else info "not running"; fi
}

# --- main -----------------------------------------------------------------

main() {
    local command=""
    while (($#)); do
        case "$1" in
            apply | rollback | status) command="$1" ;;
            --uninstall | --rollback) command=rollback ;;
            --status) command=status ;;
            --system) WITH_SYSTEM=true ;;
            --system-only) SYSTEM_ONLY=true ;;
            -n | --dry-run) DRY_RUN=true ;;
            -h | --help)
                usage
                return 0
                ;;
            *) die "unknown argument: $1 (see --help)" ;;
        esac
        shift
    done
    [[ "$(uname -s)" == Darwin || -n "${DOTFILES_MACOS_TEST:-}" ]] || die "this script is for macOS"
    BACKUP_DIR="$BACKUP_BASE/macos-${command:-apply}-$(date +%Y%m%d-%H%M%S)"
    case "${command:-apply}" in
        apply) cmd_apply ;;
        rollback) cmd_rollback ;;
        status) cmd_status ;;
    esac
}

main "$@"

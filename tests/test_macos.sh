#!/usr/bin/env bash
# scripts/macos.sh: apply, apply --system and rollback leave a fake HOME exactly
# as it was. brew, defaults, open and friends are stubs; nothing real changes.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

export HOME="$tmp_dir/home"
export DOTFILES_MACOS_TEST=1 NO_COLOR=1 OMNIWM_WAIT=2
unset XDG_CONFIG_HOME XDG_STATE_HOME TERM_PROGRAM KITTY_PID
stub_bin="$tmp_dir/bin"
prefs_dir="$tmp_dir/prefs"
mkdir -p "$HOME" "$stub_bin" "$prefs_dir"
export STUB_LOG="$tmp_dir/calls.log" PREFS_DIR="$prefs_dir"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# brew: font-maple-mono-nf counts as already installed, the rest are not.
cat >"$stub_bin/brew" <<'EOF'
#!/usr/bin/env bash
echo "brew $*" >>"$STUB_LOG"
cat >/dev/null # like real brew, swallow stdin if it is allowed to
case "$1 $2" in
    "list --cask") [[ "$3" == font-maple-mono-nf ]] ;;
    "list --formula") exit 1 ;;
    "tap ")
        # After tapping koekeishiya/formulae, its renamed twin appears as well.
        printf 'some/othertap\n'
        if [[ -f "$STUB_LOG.tapped" ]]; then printf 'asmvik/formulae\nkoekeishiya/formulae\n'; fi
        ;;
    "tap koekeishiya/formulae") touch "$STUB_LOG.tapped" ;;
    "untap koekeishiya/formulae") rm -f "$STUB_LOG.tapped" ;;
    *) exit 0 ;;
esac
EOF

# open -a OmniWM writes a settings.toml shaped like OmniWM's canonical file.
cat >"$stub_bin/open" <<EOF
#!/usr/bin/env bash
echo "open \$*" >>"\$STUB_LOG"
if [[ "\$2" == OmniWM ]]; then
    mkdir -p "\$HOME/.config/omniwm"
    cp "$tmp_dir/omniwm-default.toml" "\$HOME/.config/omniwm/settings.toml"
fi
EOF

# defaults: one XML plist per domain under $PREFS_DIR.
cat >"$stub_bin/defaults" <<'EOF'
#!/usr/bin/env bash
host=""
if [[ "$1" == -currentHost ]]; then host="byhost-"; shift; fi
file="$PREFS_DIR/$host$2.plist"
# Like the real one, import merges top-level keys into the domain.
case "$1" in
    export) [[ -f "$file" ]] && cat "$file" || printf '' ;;
    import) python3 -c 'import plistlib, sys, os
f = sys.argv[1]
old = plistlib.load(open(f, "rb")) if os.path.exists(f) else {}
old.update(plistlib.loads(sys.stdin.buffer.read()))
plistlib.dump(old, open(f, "wb"))' "$file" ;;
    delete) python3 -c 'import plistlib, sys
f = sys.argv[1]
data = plistlib.load(open(f, "rb"))
if sys.argv[2] not in data: sys.exit(1)
del data[sys.argv[2]]
plistlib.dump(data, open(f, "wb"))' "$file" "$3" ;;
    read) exit 1 ;;
esac
EOF

for name in osascript killall tccutil skhd nvim; do
    printf '#!/usr/bin/env bash\necho "%s $*" >>"$STUB_LOG"\n' "$name" >"$stub_bin/$name"
done
printf '#!/usr/bin/env bash\nexit 1\n' >"$stub_bin/pgrep"
chmod +x "$stub_bin"/*
export PATH="$stub_bin:$PATH"

# A cut-down canonical OmniWM settings.toml: every id hotkeys.tsv binds, plus
# a few defaults that must end up unassigned.
{
    printf 'schemaVersion = 5\n\n[borders]\nenabled = true\nwidth = 5.0\n\n'
    printf '[borders.color]\nalpha = 1.0\nblue = 0.9793\ngreen = 1.0\nred = 0.0846\n\n'
    printf '[gestures]\nfingerCount = 3\nscrollEnabled = true\nworkspaceSwipeAxis = "vertical"\n'
    printf 'workspaceSwipeEnabled = false\nworkspaceSwipeFingerCount = 3\n\n'
    printf '[niri]\ncenterFocusedColumn = "never"\nvisibleContainerCount = 2\n\n'
    printf '[workspaceBar]\nposition = "overlappingMenuBar"\nreserveLayoutSpace = false\nwindowLevel = "popup"\n\n'
    printf '[focus]\nfollowsMouse = false\n\n'
    printf '[[appRules]]\nbundleId = "com.apple.Safari"\nid = "81426D13-C1A5-475E-AFBC-00BBA05042D0"\nminWidth = 574.0\n\n'
    grep -v '^#' "$REPO_ROOT/configs/macos/omniwm/hotkeys.tsv" | grep . | cut -f1 |
        while read -r id; do printf '[[hotkeys]]\nbinding = "Unassigned"\nid = "%s"\n\n' "$id"; done
    printf '[[hotkeys]]\nbinding = "Option+Shift+O"\nid = "toggleWorkspaceLayout"\n\n'
    printf '[[hotkeys]]\nbinding = "Option+Grave"\nid = "toggleQuakeTerminal"\n\n'
    printf '[[workspaces]]\nid = "A"\nlayoutType = "niri"\nname = "1"\n'
} >"$tmp_dir/omniwm-default.toml"

# A local stand-in for the rime-ice repository, tagged like the real one.
rime_repo="$tmp_dir/rime-ice"
mkdir -p "$rime_repo"
(
    cd "$rime_repo"
    git init -q
    printf 'schema_list:\n  - schema: rime_ice\n' >default.yaml
    printf 'schema:\n  schema_id: rime_ice\n' >rime_ice.schema.yaml
    mkdir others && echo extra >others/README
    git add . && git -c user.name=t -c user.email=t@t commit -qm init && git tag 2026.06.30
)
export RIME_ICE_REPO="$rime_repo"

# A local stand-in for nvimdots.
nvimdots_repo="$tmp_dir/nvimdots"
mkdir -p "$nvimdots_repo/lua/user_template"
(
    cd "$nvimdots_repo"
    git init -q
    printf 'require("core")\n' >init.lua
    printf 'local settings = {}\nsettings["use_ssh"] = true\nreturn settings\n' >lua/user_template/settings.lua
    git add . && git -c user.name=t -c user.email=t@t commit -qm init
)
export NVIMDOTS_REPO="$nvimdots_repo"
NVIMDOTS_REF="$(git -C "$nvimdots_repo" rev-parse HEAD)"
export NVIMDOTS_REF

# Prior state that rollback must restore.
mkdir -p "$HOME/.config/kitty"
echo "# my own kitty.conf" >"$HOME/.config/kitty/kitty.conf"
echo "# my own zshrc" >"$HOME/.zshrc"
cat >"$prefs_dir/com.apple.dock.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>autohide</key><false/><key>tilesize</key><integer>48</integer></dict></plist>
EOF
cp "$prefs_dir/com.apple.dock.plist" "$tmp_dir/dock-before.plist"
(cd "$HOME" && find . | sort) >"$tmp_dir/home-before.txt"

macos() {
    "$REPO_ROOT/scripts/macos.sh" "$@" >>"$tmp_dir/out.log" 2>&1 || {
        cat "$tmp_dir/out.log" >&2
        fail "scripts/macos.sh $* exited non-zero"
    }
}

state="$HOME/.local/state/dotfiles-macos"
settings="$HOME/.config/omniwm/settings.toml"

# --- dry run changes nothing ----------------------------------------------
macos apply --system --dry-run
[[ ! -e "$state" ]] || fail "dry run created state"
grep -q 'brew install' "$STUB_LOG" && fail "dry run installed a cask"
[[ "$(cat "$HOME/.config/kitty/kitty.conf")" == "# my own kitty.conf" ]] || fail "dry run touched kitty.conf"

# --- trial apply -------------------------------------------------------------
macos apply
grep -qx 'brew install --cask omniwm' "$STUB_LOG" || fail "omniwm not installed"
grep -qx 'brew install --cask font-maple-mono-nf' "$STUB_LOG" && fail "installed an already present cask"
[[ "$(cat "$state/casks")" == $'omniwm\nkitty\nsquirrel-app' ]] || fail "casks state: $(cat "$state/casks")"
[[ -f "$HOME/Library/Rime/rime_ice.schema.yaml" ]] || fail "rime-ice not copied"
cmp -s "$REPO_ROOT/configs/home/.zshrc" "$HOME/.zshrc" || fail ".zshrc not deployed"
[[ -f "$HOME/.zshrc.local" ]] || fail ".zshrc.local not created from the template"
[[ -f "$HOME/.config/git/ignore" ]] || fail "global gitignore not deployed"
grep -q "\"source\": \"$HOME/.config/fastfetch/logo/" "$HOME/.config/fastfetch/config.jsonc" ||
    fail "fastfetch placeholders not rendered"
cmp -s "$REPO_ROOT/configs/config/fastfetch/anime.png" "$HOME/.config/fastfetch/anime.png" || fail "fastfetch image changed"
grep -qx 'settings\["use_ssh"\] = false' "$HOME/.config/nvim/lua/user/settings.lua" || fail "nvimdots not set to HTTPS"
grep -qx 'brew install neovim' "$STUB_LOG" || fail "neovim not installed"
[[ -e "$HOME/Library/Rime/others" || -e "$HOME/Library/Rime/.git" ]] && fail "rime-ice extras copied"
grep -qx 'brew tap koekeishiya/formulae' "$STUB_LOG" || fail "skhd tap not added"
grep -qx 'brew trust --formula koekeishiya/formulae/skhd' "$STUB_LOG" || fail "skhd formula not trusted"
grep -qx 'brew install koekeishiya/formulae/skhd' "$STUB_LOG" || fail "skhd not installed"
grep -qx 'skhd --start-service' "$STUB_LOG" || fail "skhd service not started"
grep -q 'make login item.*OmniWM.app' "$STUB_LOG" || fail "OmniWM not added to login items"
cmp -s "$REPO_ROOT/configs/macos/skhd/skhdrc" "$HOME/.config/skhd/skhdrc" || fail "skhdrc not deployed"
cmp -s "$REPO_ROOT/configs/macos/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf" || fail "kitty.conf not deployed"
cmp -s "$REPO_ROOT/configs/config/kitty/focus_opacity.py" "$HOME/.config/kitty/focus_opacity.py" || fail "focus_opacity.py not deployed"
[[ -x "$HOME/.local/bin/kitty-new-window" ]] || fail "kitty-new-window not executable"
[[ -x "$HOME/.local/bin/safari-new-window" ]] || fail "safari-new-window not executable"
grep -A1 -x 'binding = "Left Option+H"' "$settings" | grep -qx 'id = "focus.left"' || fail "focus.left not bound"
grep -q 'toggleWorkspaceLayout' "$settings" && fail "unlisted default hotkey kept"
grep -qx 'width = 4.0' "$settings" || fail "border width not set"
grep -qx 'red = 0.498' "$settings" || fail "border colour not set"
grep -qx 'workspaceSwipeEnabled = true' "$settings" || fail "workspace swipe not enabled"
grep -qx 'overviewGestureEnabled = true' "$settings" || fail "optional gesture key not added"
grep -qx 'resizeStepPercent = 10' "$settings" || fail "optional niri key not added"
grep -q '^\[\[workspaces\]\]' "$settings" || fail "workspaces lost"
grep -qx 'position = "belowMenuBar"' "$settings" || fail "workspace bar still covers the menu bar"
grep -qx 'followsMouse = true' "$settings" || fail "focus does not follow the mouse"
grep -q 'bundleId = "com.apple.Safari"' "$settings" || fail "OmniWM's own app rules lost"
[[ "$(grep -c 'bundleId = "com.apple.systempreferences"' "$settings")" == 1 ]] || fail "float rule missing or duplicated"
awk '/com.apple.Safari/ { s = NR } /com.apple.systempreferences/ { o = NR } END { exit !(s && o > s) }' "$settings" ||
    fail "our app rules are not after OmniWM's"
[[ -s "$state/prefs" ]] && fail "trial apply changed preferences"

# --- system apply, then re-apply: idempotent -----------------------------------
macos apply --system
macos apply --system
[[ "$(wc -l <"$state/casks" | tr -d ' ')" == 3 ]] || fail "casks recorded twice"
[[ "$(sort "$state/files" | uniq -d)" == "" ]] || fail "files recorded twice"
[[ "$(sort "$state/prefs" | uniq -d)" == "" ]] || fail "prefs recorded twice"
[[ "$(grep -c 'bundleId = "com.apple.systempreferences"' "$settings")" == 1 ]] || fail "re-apply duplicated app rules"
python3 -I "$REPO_ROOT/scripts/macos/prefs.py" get com.apple.dock autohide | grep -qx true || fail "dock autohide not set"
python3 -I "$REPO_ROOT/scripts/macos/prefs.py" get com.apple.symbolichotkeys AppleSymbolicHotKeys/64 |
    grep -q '524288' || fail "Spotlight hotkey not set"
python3 -I "$REPO_ROOT/scripts/macos/prefs.py" get currentHost:NSGlobalDomain com.apple.trackpad.threeFingerVertSwipeGesture |
    grep -qx 0 || fail "ByHost trackpad key not set"

# --- rollback --system-only keeps the trial setup -------------------------------
macos rollback --system-only
python3 - "$tmp_dir/dock-before.plist" "$prefs_dir/com.apple.dock.plist" <<'EOF' || fail "dock prefs not restored"
import plistlib, sys
a, b = (plistlib.load(open(p, "rb")) for p in sys.argv[1:])
sys.exit(a != b)
EOF
python3 -I "$REPO_ROOT/scripts/macos/prefs.py" get com.apple.symbolichotkeys AppleSymbolicHotKeys/64 |
    grep -qx '<unset>' || fail "Spotlight hotkey not removed"
python3 -I "$REPO_ROOT/scripts/macos/prefs.py" get currentHost:NSGlobalDomain com.apple.trackpad.threeFingerVertSwipeGesture |
    grep -qx '<unset>' || fail "unset top-level key left behind"
[[ -f "$settings" ]] || fail "system-only rollback removed OmniWM settings"

# --- full rollback ----------------------------------------------------------------
macos apply --system
macos rollback
[[ "$(cat "$HOME/.config/kitty/kitty.conf")" == "# my own kitty.conf" ]] || fail "kitty.conf not restored"
[[ "$(cat "$HOME/.zshrc")" == "# my own zshrc" ]] || fail ".zshrc not restored"
[[ ! -e "$HOME/.zshrc.local" && ! -e "$HOME/.config/nvim" && ! -e "$HOME/.config/fastfetch" ]] ||
    fail "new shell/nvim/fastfetch files left behind"
grep -qx 'brew uninstall neovim' "$STUB_LOG" || fail "neovim not uninstalled"
grep -qx 'brew autoremove' "$STUB_LOG" || fail "leftover dependencies not removed"
grep -qx 'brew uninstall --cask kitty' "$STUB_LOG" || fail "kitty not uninstalled"
grep -qx 'brew uninstall --cask omniwm' "$STUB_LOG" || fail "omniwm not uninstalled"
grep -qx 'brew uninstall --cask squirrel-app' "$STUB_LOG" || fail "squirrel not uninstalled"
[[ ! -e "$HOME/Library/Rime" ]] || fail "rime-ice left behind"
grep -q 'brew uninstall --cask font-maple-mono-nf' "$STUB_LOG" && fail "uninstalled a cask the user had"
grep -q 'tccutil reset Accessibility com.barut.OmniWM' "$STUB_LOG" || fail "permissions not reset"
grep -q 'tccutil reset ScreenCapture com.barut.OmniWM' "$STUB_LOG" || fail "screen recording not reset"
grep -qx 'skhd --uninstall-service' "$STUB_LOG" || fail "skhd service not removed"
grep -q 'delete login item "OmniWM"' "$STUB_LOG" || fail "OmniWM login item not removed"
grep -qx 'brew uninstall koekeishiya/formulae/skhd' "$STUB_LOG" || fail "skhd not uninstalled"
grep -qx 'brew untrust --formula koekeishiya/formulae/skhd' "$STUB_LOG" || fail "skhd still trusted"
grep -qx 'brew untap koekeishiya/formulae' "$STUB_LOG" || fail "tap not removed"
grep -qx 'brew untap asmvik/formulae' "$STUB_LOG" || fail "renamed twin tap not removed"
grep -q 'brew untap some/othertap' "$STUB_LOG" && fail "untapped a tap the user had"
[[ "$(grep -c "skhd --start-service" "$STUB_LOG")" == 1 ]] || fail "skhd service started again on re-apply"
[[ ! -e "$state" ]] || fail "state dir left behind"
[[ ! -e "$HOME/.config/omniwm" ]] || fail "OmniWM config left behind"
ls "$HOME"/.dotfiles-backups/macos-rollback-*/dotfiles-macos-state/casks >/dev/null || fail "state not archived"
# Only the backup dir, and empty dirs the files lived in, may be new.
# (Python's stdlib bytecode cache lands in the fake HOME; it is not ours.)
(cd "$HOME" && find . -not -path './.dotfiles-backups*' -not -path './Library/Caches/com.apple.python*' \
    -not -type d | sort) >"$tmp_dir/files-after.txt"
grep -v '/$' "$tmp_dir/home-before.txt" | while read -r p; do [[ -d "$HOME/$p" ]] || echo "$p"; done |
    sort >"$tmp_dir/files-expected.txt"
diff "$tmp_dir/files-expected.txt" "$tmp_dir/files-after.txt" || fail "files differ from before apply"
macos rollback # second rollback is a no-op

# --- the patcher refuses unknown ids ----------------------------------------------
printf 'focus.left\tLeft Option+H\nnoSuchAction\tLeft Option+Z\n' >"$tmp_dir/bad.tsv"
cp "$tmp_dir/omniwm-default.toml" "$tmp_dir/s.toml"
if python3 -I "$REPO_ROOT/scripts/macos/omniwm_patch.py" "$tmp_dir/s.toml" --defaults "$tmp_dir/omniwm-default.toml" \
    --hotkeys "$tmp_dir/bad.tsv" --settings /dev/null >/dev/null 2>&1; then
    fail "unknown hotkey id accepted"
fi
cmp -s "$tmp_dir/s.toml" "$tmp_dir/omniwm-default.toml" || fail "rejected patch modified the file"

# --- inline colour tables are patched too ------------------------------------------
printf '[borders]\ncolor = { alpha = 1.0, blue = 0.9, green = 1.0, red = 0.1 }\nwidth = 5.0\n[[hotkeys]]\nbinding = "Unassigned"\nid = "focus.left"\n' \
    >"$tmp_dir/inline.toml"
printf 'borders.color.red\t0.498\n' >"$tmp_dir/inline.tsv"
printf 'focus.left\tLeft Option+H\n' >"$tmp_dir/one.tsv"
python3 -I "$REPO_ROOT/scripts/macos/omniwm_patch.py" "$tmp_dir/inline.toml" --defaults "$tmp_dir/inline.toml" \
    --hotkeys "$tmp_dir/one.tsv" --settings "$tmp_dir/inline.tsv" >/dev/null
grep -qx 'color = { alpha = 1.0, blue = 0.9, green = 1.0, red = 0.498 }' "$tmp_dir/inline.toml" || fail "inline colour not patched"

echo "test_macos: ok"

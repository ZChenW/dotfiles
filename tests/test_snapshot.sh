#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

fake_home="$tmp_dir/home"
fake_repo="$tmp_dir/repo"
mkdir -p "$fake_home/.config/mako" "$fake_repo/configs/config/mako" "$fake_repo/packages"

cat >"$fake_home/.config/mako/config" <<'EOF'
test-mako-config
EOF

cat >"$fake_repo/packages/arch-essential.txt" <<'EOF'
git
EOF

export HOME="$fake_home"
mkdir -p "$tmp_dir/bin"
export PATH="$tmp_dir/bin:$PATH"

# shellcheck source=scripts/packages-arch.sh
source "$REPO_ROOT/scripts/packages-arch.sh"
# shellcheck source=scripts/snapshot.sh
source "$REPO_ROOT/scripts/snapshot.sh"

cat >"$tmp_dir/bin/pacman" <<'EOF'
#!/usr/bin/bash
if [[ "${1:-}" == -Qqen ]]; then
    printf '%s\n' git
    exit 0
fi
if [[ "${1:-}" == -Qqem ]]; then
    exit 0
fi
if [[ "${1:-}" == -Si && "${2:-}" == git ]]; then
    exit 0
fi
exit 1
EOF
chmod +x "$tmp_dir/bin/pacman"
ln -sf /usr/bin/awk "$tmp_dir/bin/awk"
ln -sf /usr/bin/sort "$tmp_dir/bin/sort"

SNAPSHOT_MAPPINGS=(
    "file|$HOME/.config/mako/config|configs/config/mako/config|required"
    "dir|$HOME/.config/mako|configs/config/mako|required"
    "file|$HOME/.config/missing-optional.json|configs/config/missing-optional.json|optional"
)

echo "==> test 1: dry-run capture"
before_hash="$(find "$fake_repo" -type f -exec md5sum {} + | sort)"
output="$(snapshot_capture_configs "$fake_repo" true)"
snapshot_run_package_export "$fake_repo" true >/dev/null
after_hash="$(find "$fake_repo" -type f -exec md5sum {} + | sort)"

if [[ "$before_hash" != "$after_hash" ]]; then
    echo "Dry-run modified repo files" >&2
    exit 1
fi

if [[ "$output" == *"[dry-run] install -Dm644"* || "$output" == *"[dry-run] rsync"* ]]; then
    echo "Expected default snapshot dry-run output to hide raw copy commands" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

if [[ "$output" != *"Managed configs captured"* ]]; then
    echo "Expected default snapshot dry-run summary" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

export_dry="$(snapshot_run_package_export "$fake_repo" true)"
if [[ "$export_dry" == *"[dry-run] export package snapshot into packages/*.txt"* || "$export_dry" != *"Export planned"* ]]; then
    echo "Expected default package export dry-run summary" >&2
    printf '%s\n' "$export_dry" >&2
    exit 1
fi

debug_output="$(UI_DEBUG=1 UI_VERBOSE=1 snapshot_capture_configs "$fake_repo" true)"
if [[ "$debug_output" != *"[dry-run] install -Dm644 $HOME/.config/mako/config -> $fake_repo/configs/config/mako/config"* ]]; then
    echo "Expected debug snapshot dry-run file copy command" >&2
    printf '%s\n' "$debug_output" >&2
    exit 1
fi

if [[ "$debug_output" != *"[dry-run] rsync -a --delete --delete-excluded $HOME/.config/mako/ -> $fake_repo/configs/config/mako/"* ]]; then
    echo "Expected debug snapshot dry-run directory copy command" >&2
    printf '%s\n' "$debug_output" >&2
    exit 1
fi

echo "==> test 2: real snapshot copies required paths"
SNAPSHOT_MAPPINGS=(
    "file|$HOME/.config/mako/config|configs/config/mako/config|required"
    "dir|$HOME/.config/mako|configs/config/mako|required"
)

snapshot_capture_configs "$fake_repo" false

if [[ "$(cat "$fake_repo/configs/config/mako/config")" != "test-mako-config" ]]; then
    echo "Expected required file to be copied" >&2
    exit 1
fi

if [[ ! -f "$fake_repo/configs/config/mako/config" ]]; then
    echo "Expected required directory contents to be copied" >&2
    exit 1
fi

echo "==> test 2b: snapshot preserves committed Waybar color seed"
mkdir -p "$fake_home/.config/waybar" "$fake_repo/configs/config/waybar"
printf 'live-generated\n' >"$fake_home/.config/waybar/colors.css"
printf 'stable-seed\n' >"$fake_repo/configs/config/waybar/colors.css"
printf 'style\n' >"$fake_home/.config/waybar/style.css"
SNAPSHOT_MAPPINGS=(
    "dir|$HOME/.config/waybar|configs/config/waybar|required"
)
snapshot_capture_configs "$fake_repo" false >/dev/null
if [[ "$(cat "$fake_repo/configs/config/waybar/colors.css")" != stable-seed ]]; then
    echo "Snapshot replaced the committed Waybar seed with runtime-generated colors" >&2
    exit 1
fi

echo "==> test 3: optional missing source is skipped"
SNAPSHOT_MAPPINGS=(
    "file|$HOME/.config/missing-optional.json|configs/config/missing-optional.json|optional"
)
optional_output="$(snapshot_capture_configs "$fake_repo" false)"
if [[ "$optional_output" != *"SKIP optional source: $HOME/.config/missing-optional.json"* ]]; then
    echo "Expected optional skip message" >&2
    printf '%s\n' "$optional_output" >&2
    exit 1
fi

echo "==> test 4: missing required source fails"
SNAPSHOT_MAPPINGS=(
    "file|$HOME/.config/missing-required.json|configs/config/missing-required.json|required"
)
if snapshot_capture_configs "$fake_repo" false 2>/dev/null; then
    echo "Expected missing required source to fail" >&2
    exit 1
fi

echo "==> test 5: safety check rejects forbidden path fragments"
mkdir -p "$fake_repo/configs/config/bad/workspaceStorage"
echo "secret" >"$fake_repo/configs/config/bad/workspaceStorage/state"
SNAPSHOT_MAPPINGS=(
    "dir|$fake_repo/configs/config/bad|configs/config/bad|required"
)
if snapshot_safety_check "$fake_repo" 2>/dev/null; then
    echo "Expected safety check to reject workspaceStorage" >&2
    exit 1
fi

echo "==> test 6: commit staging uses explicit paths"
git -C "$fake_repo" init -q
git -C "$fake_repo" config user.email "test@example.com"
git -C "$fake_repo" config user.name "Test User"
git -C "$fake_repo" add packages/arch-essential.txt
git -C "$fake_repo" commit -q -m "init"

echo "unrelated change" >"$fake_repo/README.md"
echo "package change" >>"$fake_repo/packages/arch-essential.txt"
echo "config change" >"$fake_repo/configs/config/mako/config"

SNAPSHOT_MAPPINGS=(
    "file|$fake_repo/configs/config/mako/config|configs/config/mako/config|required"
)

stage_log="$tmp_dir/stage.log"
cat >"$tmp_dir/bin/git" <<EOF
#!/usr/bin/bash
real_git="/usr/bin/git"
for arg in "\$@"; do
    if [[ "\$arg" == add ]]; then
        printf '%s\n' "\$@" >>"$stage_log"
        break
    fi
done
exec "\$real_git" "\$@"
EOF
chmod +x "$tmp_dir/bin/git"

export PATH="$tmp_dir/bin:$PATH"
: >"$stage_log"

snapshot_stage_managed_changes "$fake_repo"

stage_contents="$(cat "$stage_log")"

if [[ "$stage_contents" == *"add ."* ]]; then
    echo "snapshot staging must not use git add ." >&2
    exit 1
fi

if [[ "$stage_contents" != *"add"* ]] || [[ "$stage_contents" != *"packages/arch-essential.txt"* ]]; then
    echo "Expected explicit package staging" >&2
    cat "$stage_log" >&2
    exit 1
fi

if [[ "$stage_contents" != *"configs/config/mako/config"* ]]; then
    echo "Expected explicit config staging" >&2
    cat "$stage_log" >&2
    exit 1
fi

echo "==> test 6b: non-snapshot changes are listed"
non_snapshot_output="$(snapshot_non_snapshot_changes "$fake_repo")"
if [[ "$non_snapshot_output" != *"README.md"* ]]; then
    echo "Expected non-snapshot change list to include README.md" >&2
    printf '%s\n' "$non_snapshot_output" >&2
    exit 1
fi

echo "==> test 6c: managed non-ASCII paths are not misclassified"
mkdir -p "$fake_repo/configs/Pictures/wallpapers"
git -C "$fake_repo" config core.quotePath true
SNAPSHOT_MAPPINGS=(
    "file|$fake_repo/configs/config/mako/config|configs/config/mako/config|required"
    "dir|$fake_repo/configs/Pictures/wallpapers|configs/Pictures/wallpapers|required"
)
non_snapshot_before="$(snapshot_non_snapshot_changes "$fake_repo")"
printf 'wallpaper\n' >"$fake_repo/configs/Pictures/wallpapers/主题壁纸.png"
non_snapshot_output="$(snapshot_non_snapshot_changes "$fake_repo")"
if [[ "$non_snapshot_output" != "$non_snapshot_before" ]]; then
    echo "Managed non-ASCII path was misclassified as a non-snapshot change" >&2
    printf '%s\n' "Before:" "$non_snapshot_before" >&2
    printf '%s\n' "After:" "$non_snapshot_output" >&2
    exit 1
fi

echo "==> test 6d: jj repositories use jj commit and push semantics"
jj_repo="$tmp_dir/jj-repo"
mkdir -p "$jj_repo/configs/example" "$jj_repo/.jj"
printf '.jj/\n' >"$jj_repo/.gitignore"
printf 'before\n' >"$jj_repo/configs/example/config"
git -C "$jj_repo" init -q
git -C "$jj_repo" config user.email "test@example.com"
git -C "$jj_repo" config user.name "Test User"
git -C "$jj_repo" add .gitignore configs/example/config
git -C "$jj_repo" commit -q -m "init"
printf 'after\n' >"$jj_repo/configs/example/config"

jj_log="$tmp_dir/jj.log"
cat >"$tmp_dir/bin/jj" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$jj_log"
EOF
chmod +x "$tmp_dir/bin/jj"

SNAPSHOT_MAPPINGS=(
    "file|$jj_repo/configs/example/config|configs/example/config|required"
)
head_before="$(git -C "$jj_repo" rev-parse HEAD)"
snapshot_commit "$jj_repo"
head_after="$(git -C "$jj_repo" rev-parse HEAD)"

if [[ "${SNAPSHOT_COMMIT_CREATED:-false}" != true \
    || "${SNAPSHOT_COMMIT_VCS:-}" != jj ]]; then
    echo "Snapshot did not record a jj commit" >&2
    exit 1
fi
if [[ "$head_after" != "$head_before" ]]; then
    echo "Snapshot created a detached Git commit inside a jj repository" >&2
    exit 1
fi

snapshot_push "$jj_repo"
if ! grep -Fq -- "-R $jj_repo describe -m chore: update dotfiles snapshot" "$jj_log" \
    || ! grep -Fq -- "-R $jj_repo git push --change @" "$jj_log" \
    || ! grep -Fq -- "-R $jj_repo new @" "$jj_log"; then
    echo "Snapshot did not run the expected jj commit/push lifecycle" >&2
    cat "$jj_log" >&2
    exit 1
fi

echo "==> test 7: snapshot rejects symlinks in source config"
rm -rf "$fake_home/.config/mako-link"
mkdir -p "$fake_home/.config/mako-link"
echo "real-file" >"$fake_home/.config/mako-link/config"
ln -s "$fake_home/.config/mako-link/other" "$fake_home/.config/mako-link/link-target"
SNAPSHOT_MAPPINGS=(
    "dir|$HOME/.config/mako-link|configs/config/mako-link|required"
)
if snapshot_capture_configs "$fake_repo" false 2>/dev/null; then
    echo "Expected symlink in source directory to fail capture" >&2
    exit 1
fi

echo "==> test 8: .zshrc secret markers are scanned outside comments"
mkdir -p "$fake_repo/configs/home"
cat >"$fake_repo/configs/home/.zshrc" <<'EOF'
# Example: export OPENAI_API_KEY=sk-example
export OPENAI_API_KEY=sk-live-abcdefghijklmnopqrstuvwxyz
EOF
SNAPSHOT_MAPPINGS=(
    "file|$fake_repo/configs/home/.zshrc|configs/home/.zshrc|required"
)
if snapshot_safety_check "$fake_repo" 2>/dev/null; then
    echo "Expected .zshrc non-comment secret marker to fail safety check" >&2
    exit 1
fi

cat >"$fake_repo/configs/home/.zshrc" <<'EOF'
# Example: export OPENAI_API_KEY=sk-example
alias ll='ls -la'
EOF
if ! snapshot_safety_check "$fake_repo"; then
    echo "Expected comment-only secret marker in .zshrc to pass safety check" >&2
    exit 1
fi

echo "==> test 8b: CURSOR_API_KEY and ANTHROPIC_AUTH_TOKEN are rejected"
cat >"$fake_repo/configs/home/.zshrc" <<'EOF'
export CURSOR_API_KEY='crsr_ba850e8ecf85a3d920c79f8136c6b1793284225b'
EOF
if snapshot_safety_check "$fake_repo" 2>/dev/null; then
    echo "Expected CURSOR_API_KEY export to fail safety check" >&2
    exit 1
fi

cat >"$fake_repo/configs/home/.zshrc" <<'EOF'
export ANTHROPIC_AUTH_TOKEN=sk-7c7536e23fb641dbacd96ffae8d43e39
EOF
if snapshot_safety_check "$fake_repo" 2>/dev/null; then
    echo "Expected ANTHROPIC_AUTH_TOKEN export to fail safety check" >&2
    exit 1
fi

cat >"$fake_repo/configs/home/.zshrc" <<'EOF'
# export CURSOR_API_KEY='crsr_example_placeholder_not_real_000'
# export ANTHROPIC_AUTH_TOKEN=sk-example_placeholder_not_real
alias ll='ls -la'
EOF
if ! snapshot_safety_check "$fake_repo"; then
    echo "Expected commented cursor/deepseek examples to pass safety check" >&2
    exit 1
fi

echo "==> test 8c: fcitx5 ForPassword keys are not false positives"
mkdir -p "$fake_repo/configs/config/fcitx5"
cat >"$fake_repo/configs/config/fcitx5/config" <<'EOF'
# Allow input method in the password field
AllowInputMethodForPassword=False
# Show preedit text when typing password
ShowPreeditForPassword=False
EOF
SNAPSHOT_MAPPINGS=(
    "dir|$fake_repo/configs/config/fcitx5|configs/config/fcitx5|required"
)
if ! snapshot_safety_check "$fake_repo"; then
    echo "Expected fcitx5 ForPassword settings to pass safety check" >&2
    exit 1
fi

cat >"$fake_repo/configs/home/.zshrc" <<'EOF'
export DB_PASSWORD=super-secret-value
password=literal-secret
EOF
SNAPSHOT_MAPPINGS=(
    "file|$fake_repo/configs/home/.zshrc|configs/home/.zshrc|required"
)
if snapshot_safety_check "$fake_repo" 2>/dev/null; then
    echo "Expected standalone password= assignment to fail safety check" >&2
    exit 1
fi

echo "==> test 9: binary files do not trigger null-byte scan warnings"
mkdir -p "$fake_repo/configs/config/binary"
printf 'abc\0def' >"$fake_repo/configs/config/binary/blob.bin"
SNAPSHOT_MAPPINGS=(
    "dir|$fake_repo/configs/config/binary|configs/config/binary|required"
)
binary_err="$tmp_dir/binary-scan.err"
if ! snapshot_safety_check "$fake_repo" 2>"$binary_err"; then
    echo "Expected binary safety scan to pass" >&2
    cat "$binary_err" >&2
    exit 1
fi
if [[ -s "$binary_err" ]]; then
    echo "Expected binary safety scan to avoid warnings" >&2
    cat "$binary_err" >&2
    exit 1
fi

echo "==> test 10: text normalization removes diff-check whitespace"
mkdir -p "$fake_repo/configs/config/whitespace"
printf 'value   \n\n\n' >"$fake_repo/configs/config/whitespace/config.txt"
snapshot_normalize_text_file "$fake_repo/configs/config/whitespace/config.txt"
if grep -q '[[:blank:]]$' "$fake_repo/configs/config/whitespace/config.txt"; then
    echo "Expected trailing whitespace to be removed" >&2
    cat -vet "$fake_repo/configs/config/whitespace/config.txt" >&2
    exit 1
fi
if [[ "$(tail -c 2 "$fake_repo/configs/config/whitespace/config.txt")" == $'\n\n' ]]; then
    echo "Expected extra blank lines at EOF to be removed" >&2
    cat -vet "$fake_repo/configs/config/whitespace/config.txt" >&2
    exit 1
fi

echo "==> test 11: verification disables git pager"
verify_repo="$tmp_dir/verify-repo"
mkdir -p "$verify_repo/scripts" "$verify_repo/tests"
cat >"$verify_repo/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$verify_repo/scripts/verify-test.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$verify_repo/install.sh" "$verify_repo/scripts/verify-test.sh"

verify_log="$tmp_dir/verify-git.log"
(
    mkdir -p "$tmp_dir/verify-bin"
    cat >"$tmp_dir/verify-bin/git" <<EOF
#!/usr/bin/bash
printf '%s\n' "\$*" >>"$verify_log"
exit 0
EOF
    cat >"$tmp_dir/verify-bin/shellcheck" <<'EOF'
#!/usr/bin/bash
exit 0
EOF
    chmod +x "$tmp_dir/verify-bin/git" "$tmp_dir/verify-bin/shellcheck"
    PATH="$tmp_dir/verify-bin:$PATH" snapshot_run_verification "$verify_repo"
)
if ! grep -q -- '--no-pager -C .* diff --check' "$verify_log"; then
    echo "Expected snapshot verification to call git with --no-pager" >&2
    cat "$verify_log" >&2
    exit 1
fi

echo "==> test 12: snapshot mappings follow the desktop shell profile"
DESKTOP_SHELL_PROFILE=quickshell
build_snapshot_mappings
if printf '%s\n' "${SNAPSHOT_MAPPINGS[@]}" \
    | grep -F -e '/waybar|' -e 'wcr-post-apply-waybar' >/dev/null; then
    echo "QuickShell-only snapshot still requires Waybar files" >&2
    exit 1
fi
DESKTOP_SHELL_PROFILE=dual
build_snapshot_mappings
if ! printf '%s\n' "${SNAPSHOT_MAPPINGS[@]}" | grep -Fq '/waybar|'; then
    echo "Dual snapshot lost Waybar config capture" >&2
    exit 1
fi

echo "==> test 13: Snapshot manages only the active profile package manifests"
INSTALL_PROFILE=lightweight
lightweight_paths="$(snapshot_managed_paths "$fake_repo")"
if [[ "$lightweight_paths" != *"packages/arch-lightweight.txt"* \
    || "$lightweight_paths" == *"packages/arch-essential.txt"* ]]; then
    echo "Expected Lightweight Snapshot to own only arch-lightweight.txt" >&2
    printf '%s\n' "$lightweight_paths" >&2
    exit 1
fi

INSTALL_PROFILE=standard
standard_paths="$(snapshot_managed_paths "$fake_repo")"
if [[ "$standard_paths" != *"packages/arch-essential.txt"* \
    || "$standard_paths" == *"packages/arch-lightweight.txt"* ]]; then
    echo "Expected Standard Snapshot to own only Standard manifests" >&2
    printf '%s\n' "$standard_paths" >&2
    exit 1
fi

echo "==> test 14: Snapshot refuses dirty repositories before capture"
prepare_repo="$tmp_dir/prepare-repo"
mkdir -p "$prepare_repo"
/usr/bin/git -C "$prepare_repo" init -q
/usr/bin/git -C "$prepare_repo" config user.email test@example.com
/usr/bin/git -C "$prepare_repo" config user.name "Test User"
printf 'clean\n' >"$prepare_repo/tracked"
/usr/bin/git -C "$prepare_repo" add tracked
/usr/bin/git -C "$prepare_repo" commit -qm initial
snapshot_prepare_repo "$prepare_repo" true >/dev/null
printf 'dirty\n' >"$prepare_repo/tracked"
if snapshot_prepare_repo "$prepare_repo" true >/dev/null 2>&1; then
    echo "Expected dirty Snapshot preparation to fail" >&2
    exit 1
fi

echo "==> test 15: Snapshot diff includes untracked file contents"
untracked_repo="$tmp_dir/untracked-repo"
mkdir -p "$untracked_repo/configs/example"
/usr/bin/git -C "$untracked_repo" init -q
printf 'new snapshot content\n' >"$untracked_repo/configs/example/new.conf"
INSTALL_PROFILE=standard
untracked_diff="$(snapshot_show_diff "$untracked_repo")"
if [[ "$untracked_diff" != *"new snapshot content"* ]]; then
    echo "Expected untracked captured content in Snapshot review diff" >&2
    printf '%s\n' "$untracked_diff" >&2
    exit 1
fi

echo "All snapshot tests passed."

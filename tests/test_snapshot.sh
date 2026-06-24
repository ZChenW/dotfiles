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

if [[ "$output" != *"[dry-run] install -Dm644 $HOME/.config/mako/config -> $fake_repo/configs/config/mako/config"* ]]; then
    echo "Expected dry-run file copy plan" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

if [[ "$output" != *"[dry-run] rsync -a --delete $HOME/.config/mako/ -> $fake_repo/configs/config/mako/"* ]]; then
    echo "Expected dry-run directory copy plan" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

export_dry="$(snapshot_run_package_export "$fake_repo" true)"
if [[ "$export_dry" != *"[dry-run] export package snapshot into packages/*.txt"* ]]; then
    echo "Expected dry-run package export plan" >&2
    printf '%s\n' "$export_dry" >&2
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
export OPENAI_API_KEY=sk-live
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

echo "All snapshot tests passed."

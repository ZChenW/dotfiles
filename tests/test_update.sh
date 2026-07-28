#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

fake_repo="$tmp_dir/repo"
mkdir -p "$fake_repo"
git -C "$fake_repo" init -q
git -C "$fake_repo" config user.email "test@example.com"
git -C "$fake_repo" config user.name "Test User"

cat >"$fake_repo/install.sh" <<'EOS'
#!/usr/bin/env bash
printf 'fake install:'
printf ' %s' "$@"
printf '\n'
EOS
chmod +x "$fake_repo/install.sh"

echo "initial" >"$fake_repo/tracked.txt"
git -C "$fake_repo" add tracked.txt install.sh
git -C "$fake_repo" commit -q -m "init"

# shellcheck source=scripts/update.sh
source "$REPO_ROOT/scripts/update.sh"

echo "==> test 1: clean repo has no changes"
if update_repo_has_changes "$fake_repo"; then
    echo "Expected clean repo" >&2
    exit 1
fi

echo "==> test 2: dirty repo detected"
echo "changed" >"$fake_repo/tracked.txt"
if ! update_repo_has_changes "$fake_repo"; then
    echo "Expected dirty repo" >&2
    exit 1
fi

echo "==> test 3: require clean repo fails on dirty repo"
if update_require_clean_repo "$fake_repo" 2>/dev/null; then
    echo "Expected clean check to fail" >&2
    exit 1
fi
git -C "$fake_repo" checkout -q -- tracked.txt

echo "==> test 4: dry-run pull"
pull_output="$(update_pull "$fake_repo" true)"
if [[ "$pull_output" != *"[dry-run] git pull --ff-only"* ]]; then
    echo "Expected dry-run pull output" >&2
    printf '%s\n' "$pull_output" >&2
    exit 1
fi

echo "==> test 5: dry-run apply consumes the active profile"
apply_profile_output="$(update_apply "$fake_repo" true lightweight)"
if [[ "$apply_profile_output" != *"install.sh --yes --install-profile lightweight --dry-run"* ]]; then
    echo "Expected profile-aware package and config apply" >&2
    printf '%s\n' "$apply_profile_output" >&2
    exit 1
fi

echo "==> test 6: dry-run apply forwards a compatible desktop shell profile"
apply_shell_output="$(update_apply "$fake_repo" true standard quickshell)"
if [[ "$apply_shell_output" != *"--desktop-shell quickshell"* ]]; then
    echo "Expected update apply to forward the desktop shell profile" >&2
    printf '%s\n' "$apply_shell_output" >&2
    exit 1
fi

echo "==> test 7: full dry-run update"
before_hash="$(find "$fake_repo" -type f -exec md5sum {} + | sort)"
run_output="$(run_update "$fake_repo" true lightweight)"
after_hash="$(find "$fake_repo" -type f -exec md5sum {} + | sort)"
if [[ "$before_hash" != "$after_hash" ]]; then
    echo "Dry-run update mutated fake repo" >&2
    exit 1
fi
if [[ "$run_output" != *"[dry-run] git pull --ff-only"* || "$run_output" != *"Update dry run complete. No changes were made."* ]]; then
    echo "Expected dry-run update output" >&2
    printf '%s\n' "$run_output" >&2
    exit 1
fi
if [[ "$run_output" == *"Snapshot"* || "$run_output" == *"commit"* || "$run_output" == *"push"* ]]; then
    echo "Update must not offer or invoke publication behavior" >&2
    printf '%s\n' "$run_output" >&2
    exit 1
fi

echo "==> test 7b: dry-run update still refuses a dirty repository"
echo "dirty" >"$fake_repo/tracked.txt"
if run_update "$fake_repo" true lightweight >/dev/null 2>&1; then
    echo "Expected dirty dry-run update to fail before applying" >&2
    exit 1
fi
git -C "$fake_repo" checkout -q -- tracked.txt

echo "==> test 8: invalid flag combinations"
invalid_flags=(
    "--with-packages"
    "--no-snapshot-prompt"
    "--update --snapshot"
    "--update --packages-only"
    "--update --skip-packages"
    "--update --export-packages"
)
for flags in "${invalid_flags[@]}"; do
    # shellcheck disable=SC2086
    if "$REPO_ROOT/install.sh" $flags >/dev/null 2>&1; then
        echo "Expected failure for: install.sh $flags" >&2
        exit 1
    fi
done

echo "==> test 9: public Update reuses saved profile without publication commands"
public_repo="$tmp_dir/public-repo"
public_home="$tmp_dir/public-home"
public_bin="$tmp_dir/public-bin"
mkdir -p "$public_home/.local/state/dotfiles" "$public_bin"
cp -a "$REPO_ROOT" "$public_repo"
rm -rf "$public_repo/.git"
/usr/bin/git -C "$public_repo" init -q
/usr/bin/git -C "$public_repo" config user.email test@example.com
/usr/bin/git -C "$public_repo" config user.name "Test User"
/usr/bin/git -C "$public_repo" add -A
/usr/bin/git -C "$public_repo" commit -qm baseline
printf 'lightweight\n' >"$public_home/.local/state/dotfiles/install-profile"

git_log="$tmp_dir/public-git.log"
cat >"$public_bin/git" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$git_log"
if [[ " \$* " == *" pull --ff-only "* ]]; then
    exit 0
fi
exec /usr/bin/git "\$@"
EOF
cat >"$public_bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -Slq)
        sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' \
            "$DOTFILES_TEST_REPO/packages/arch-lightweight.txt"
        ;;
    -Qqen|-Qqem)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
cat >"$public_bin/sudo" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$public_bin/git" "$public_bin/pacman" "$public_bin/sudo"

public_output="$(
    HOME="$public_home" \
    DOTFILES_TEST_REPO="$public_repo" \
    PATH="$public_bin:$PATH" \
        "$public_repo/install.sh" --update --dry-run --yes \
        --ascii --no-color 2>&1
)"
if [[ "$public_output" != *"Lightweight"* \
    || "$public_output" != *"git pull --ff-only"* \
    || "$public_output" != *"--install-profile lightweight"* ]]; then
    echo "Expected public Update to consume the saved Lightweight profile" >&2
    printf '%s\n' "$public_output" >&2
    exit 1
fi
if grep -Eq '(^| )(commit|push)( |$)' "$git_log"; then
    echo "Public Update attempted a publication command" >&2
    cat "$git_log" >&2
    exit 1
fi

if command -v jj >/dev/null 2>&1; then
    echo "==> test 10: colocated Jujutsu repository fast-forwards cleanly"
    jj_remote="$tmp_dir/jj-remote.git"
    jj_seed="$tmp_dir/jj-seed"
    jj_work="$tmp_dir/jj-work"
    /usr/bin/git init -q --bare "$jj_remote"
    /usr/bin/git init -q -b main "$jj_seed"
    /usr/bin/git -C "$jj_seed" config user.email test@example.com
    /usr/bin/git -C "$jj_seed" config user.name "Test User"
    printf 'one\n' >"$jj_seed/version"
    /usr/bin/git -C "$jj_seed" add version
    /usr/bin/git -C "$jj_seed" commit -qm one
    /usr/bin/git -C "$jj_seed" remote add origin "$jj_remote"
    /usr/bin/git -C "$jj_seed" push -qu origin main
    /usr/bin/git clone -q "$jj_remote" "$jj_work"
    /usr/bin/git -C "$jj_work" config user.email test@example.com
    /usr/bin/git -C "$jj_work" config user.name "Test User"
    jj git init --colocate "$jj_work" >/dev/null
    jj -R "$jj_work" new main >/dev/null

    printf 'two\n' >"$jj_seed/version"
    /usr/bin/git -C "$jj_seed" add version
    /usr/bin/git -C "$jj_seed" commit -qm two
    /usr/bin/git -C "$jj_seed" push -q

    repo_pull_ff_only "$jj_work" false >/dev/null
    if [[ "$(<"$jj_work/version")" != two ]]; then
        echo "Expected colocated Jujutsu worktree to fast-forward" >&2
        exit 1
    fi
    if [[ "$(jj -R "$jj_work" diff --summary)" != "" ]]; then
        echo "Expected clean Jujutsu working copy after fast-forward" >&2
        jj -R "$jj_work" status >&2
        exit 1
    fi
else
    echo "jj unavailable; colocated fast-forward check skipped"
fi

echo "All update tests passed."

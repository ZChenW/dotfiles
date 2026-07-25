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

echo "==> test 5: dry-run apply configs only"
apply_configs_output="$(update_apply "$fake_repo" true false)"
if [[ "$apply_configs_output" != *"install.sh --skip-packages --yes --dry-run"* ]]; then
    echo "Expected configs-only dry-run apply" >&2
    printf '%s\n' "$apply_configs_output" >&2
    exit 1
fi

echo "==> test 6: dry-run apply with packages"
apply_packages_output="$(update_apply "$fake_repo" true true)"
if [[ "$apply_packages_output" != *"install.sh --yes --dry-run"* ]]; then
    echo "Expected package dry-run apply" >&2
    printf '%s\n' "$apply_packages_output" >&2
    exit 1
fi

echo "==> test 6b: dry-run apply forwards desktop shell profile"
apply_profile_output="$(update_apply "$fake_repo" true false quickshell)"
if [[ "$apply_profile_output" != *"--desktop-shell quickshell"* ]]; then
    echo "Expected update apply to forward the desktop shell profile" >&2
    printf '%s\n' "$apply_profile_output" >&2
    exit 1
fi

echo "==> test 7: full dry-run update"
before_hash="$(find "$fake_repo" -type f -exec md5sum {} + | sort)"
run_output="$(run_update "$fake_repo" true false false false)"
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

echo "All update tests passed."

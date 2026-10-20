#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

export HOME="$tmp_dir/home"
stub_bin="$tmp_dir/bin"
mkdir -p "$HOME" "$stub_bin"

# The stub curl prints an "installer" that records how it was run and then
# drops the binary into ~/.local/bin, like the vendor installers do.
cat >"$stub_bin/curl" <<'EOS'
#!/usr/bin/env bash
url="${*: -1}"
printf '%s\n' "$url" >>"$HOME/curl.log"
[[ -f "$HOME/curl-fails" ]] && exit 22
name=claude
[[ "$url" == *codex* ]] && name=codex
cat <<EOF
printf 'PATH=%s NONINTERACTIVE=%s\n' "\$PATH" "\$CODEX_NON_INTERACTIVE" >"\$HOME/$name.env"
printf '#!/bin/sh\n' >"\$HOME/.local/bin/$name"
chmod +x "\$HOME/.local/bin/$name"
EOF
EOS
chmod +x "$stub_bin/curl"
export PATH="$stub_bin:/usr/bin:/bin"

# shellcheck source=scripts/ui.sh
source "$REPO_ROOT/scripts/ui.sh"
# shellcheck source=scripts/agents.sh
source "$REPO_ROOT/scripts/agents.sh"

expect_contains() {
    if [[ "$1" != *"$2"* ]]; then
        echo "Expected output to contain: $2" >&2
        printf '%s\n' "$1" >&2
        exit 1
    fi
}

echo "==> test 1: dry run downloads nothing"
out="$(install_coding_agents true 2>&1)"
expect_contains "$out" "would be installed from https://claude.ai/install.sh"
expect_contains "$out" "would be installed from https://chatgpt.com/codex/install.sh"
if [[ -e "$HOME/curl.log" ]]; then
    echo "Expected no download in a dry run" >&2
    exit 1
fi

echo "==> test 2: missing agents come from the vendor installers"
out="$(install_coding_agents false 2>&1)"
expect_contains "$out" "installed"
expect_contains "$(cat "$HOME/curl.log")" "https://claude.ai/install.sh"
expect_contains "$(cat "$HOME/curl.log")" "https://chatgpt.com/codex/install.sh"
[[ -x "$HOME/.local/bin/claude" && -x "$HOME/.local/bin/codex" ]]

echo "==> test 3: the Codex installer sees ~/.local/bin first and never prompts"
codex_env="$(cat "$HOME/codex.env")"
expect_contains "$codex_env" "PATH=$HOME/.local/bin:"
expect_contains "$codex_env" "NONINTERACTIVE=1"

echo "==> test 4: installed agents are left alone"
rm "$HOME/curl.log"
out="$(install_coding_agents false 2>&1)"
expect_contains "$out" "already installed"
if [[ -e "$HOME/curl.log" ]]; then
    echo "Expected no download for installed agents" >&2
    exit 1
fi

echo "==> test 5: a failed download warns without failing the install"
rm "$HOME/.local/bin/codex"
touch "$HOME/curl-fails"
out="$(install_coding_agents false 2>&1)"
expect_contains "$out" "install failed; run: curl -fsSL https://chatgpt.com/codex/install.sh | sh"

echo "All agents tests passed."

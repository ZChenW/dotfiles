#!/usr/bin/env bash
# Coding agents: Claude Code and Codex from their vendors' own installers.
# Not from pacman/AUR: extra/openai-codex and AUR claude-code are third-party
# builds. Both official installers put the binary in ~/.local/bin.

CLAUDE_INSTALLER_URL="https://claude.ai/install.sh"
CODEX_INSTALLER_URL="https://chatgpt.com/codex/install.sh"

coding_agent_installed() {
    local name="$1"
    [[ -x "$HOME/.local/bin/$name" ]] || command -v "$name" >/dev/null 2>&1
}

# Pipes a vendor installer into its shell. ~/.local/bin goes first on PATH:
# the Codex installer appends a PATH block to ~/.zshrc when it is missing,
# which would put an untracked edit into a managed file.
run_coding_agent_installer() {
    local url="$1" shell="$2"
    mkdir -p "$HOME/.local/bin"
    curl -fsSL "$url" | PATH="$HOME/.local/bin:$PATH" CODEX_NON_INTERACTIVE=1 "$shell"
}

# install_coding_agents DRY_RUN: installs each agent that is missing. Agents
# already present, from any source, are left alone; they update themselves.
install_coding_agents() {
    local dry_run="${1:-false}"
    local entry name url shell
    local -a agents=(
        "claude $CLAUDE_INSTALLER_URL bash"
        "codex $CODEX_INSTALLER_URL sh"
    )

    for entry in "${agents[@]}"; do
        read -r name url shell <<<"$entry"
        if coding_agent_installed "$name"; then
            ui_ok "$name" "already installed"
            continue
        fi
        if [[ "$dry_run" == true ]]; then
            debug_log "[dry-run] curl -fsSL $url | $shell"
            ui_ok "$name" "would be installed from $url"
            continue
        fi
        if run_logged_command run_coding_agent_installer "$url" "$shell"; then
            ui_ok "$name" "installed"
        else
            ui_warn "$name" "install failed; run: curl -fsSL $url | $shell"
        fi
    done
}

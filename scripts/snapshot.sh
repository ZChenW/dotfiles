#!/usr/bin/env bash
# Snapshot managed dotfiles and package manifests from the live machine into the repo.

set -euo pipefail

SNAPSHOT_MAPPINGS=(
    "dir|$HOME/.config/niri|configs/config/niri|required"
    "dir|$HOME/.config/waybar|configs/config/waybar|required"
    "dir|$HOME/.config/kitty|configs/config/kitty|required"
    "dir|$HOME/.config/fastfetch|configs/config/fastfetch|required"
    "dir|$HOME/.config/waypaper|configs/config/waypaper|required"
    "dir|$HOME/.config/fcitx5|configs/config/fcitx5|required"
    "dir|$HOME/.config/mako|configs/config/mako|required"
    "dir|$HOME/.config/environment.d|configs/config/environment.d|required"
    "dir|$HOME/.config/qt5ct|configs/config/qt5ct|required"
    "dir|$HOME/.config/qt6ct|configs/config/qt6ct|required"
    "dir|$HOME/.config/cava|configs/config/cava|required"
    "dir|$HOME/.config/Thunar|configs/config/Thunar|required"
    "file|$HOME/.zshrc|configs/home/.zshrc|required"
    "file|$HOME/.config/git/ignore|configs/config/git/ignore|required"
    "file|$HOME/.config/mimeapps.list|configs/config/mimeapps.list|required"
    "file|$HOME/.config/user-dirs.dirs|configs/config/user-dirs.dirs|required"
    "file|$HOME/.config/Code/User/settings.json|configs/config/Code/User/settings.json|optional"
    "file|$HOME/.config/Code/User/keybindings.json|configs/config/Code/User/keybindings.json|optional"
    "dir|$HOME/.config/Code/User/snippets|configs/config/Code/User/snippets|optional"
    "file|$HOME/.config/Cursor/User/settings.json|configs/config/Cursor/User/settings.json|optional"
    "file|$HOME/.config/Cursor/User/keybindings.json|configs/config/Cursor/User/keybindings.json|optional"
    "dir|$HOME/.config/Cursor/User/snippets|configs/config/Cursor/User/snippets|optional"
    "file|$HOME/.local/bin/inir|configs/local-bin/inir|required"
    "file|$HOME/.local/bin/toggle-niri-shell|configs/local-bin/toggle-niri-shell|required"
)

SNAPSHOT_FORBIDDEN_PATH_FRAGMENTS=(
    Cookies
    History
    workspaceStorage
    globalStorage
    state.vscdb
    auth.db
    auth.db-shm
    auth.db-wal
    "Local Storage"
    "Session Storage"
    IndexedDB
    Cache
    GPUCache
    Crashpad
    logs
    .git/
    .cache/
)

SNAPSHOT_SECRET_MARKERS=(
    github_pat
    ghp_
    OPENAI_API_KEY
    ANTHROPIC_API_KEY
    api_key
    access_token
    refresh_token
    cookie
    password=
    passwd=
)

SNAPSHOT_SECRET_MARKER_ALLOWLIST=(
    docs/INSTALL.md
)

SNAPSHOT_SECRET_MARKER_COMMENT_SKIP_FILES=(
    templates/zshrc.local.example
    configs/home/.zshrc
)

snapshot_managed_paths() {
    local repo_root="$1"
    local mapping mode _src dest _required

    for mapping in "${SNAPSHOT_MAPPINGS[@]}"; do
        IFS='|' read -r mode _src dest _required <<<"$mapping"
        printf '%s\n' "$dest"
    done

    local pkg
    for pkg in "$repo_root"/packages/*.txt; do
        [[ -f "$pkg" ]] || continue
        printf '%s\n' "packages/$(basename "$pkg")"
    done
}

snapshot_path_is_managed() {
    local repo_root="$1"
    local path="$2"
    local managed

    while IFS= read -r managed; do
        [[ -z "$managed" ]] && continue
        if [[ "$path" == "$managed" || "$path" == "$managed"/* ]]; then
            return 0
        fi
    done < <(snapshot_managed_paths "$repo_root")

    return 1
}

snapshot_has_non_snapshot_changes() {
    local repo_root="$1"
    local line path

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        path="${line:3}"
        if [[ "$path" == */ ]]; then
            path="${path%/}"
        fi
        if ! snapshot_path_is_managed "$repo_root" "$path"; then
            return 0
        fi
    done < <(git -C "$repo_root" status --porcelain)

    return 1
}

snapshot_reject_source_symlinks() {
    local src="$1"
    local mode="$2"
    local link

    if [[ -L "$src" ]]; then
        echo "Error: snapshot source is a symlink: $src" >&2
        return 1
    fi

    if [[ "$mode" == dir && -d "$src" ]]; then
        while IFS= read -r link; do
            [[ -z "$link" ]] && continue
            echo "Error: snapshot source contains a symlink: $link" >&2
            return 1
        done < <(find "$src" -type l 2>/dev/null)
    fi

    return 0
}

snapshot_capture_configs() {
    local repo_root="$1"
    local dry_run="$2"
    local mapping mode src dest required

    for mapping in "${SNAPSHOT_MAPPINGS[@]}"; do
        IFS='|' read -r mode src dest required <<<"$mapping"

        if [[ ! -e "$src" ]]; then
            if [[ "$required" == optional ]]; then
                echo "SKIP optional source: $src"
                continue
            fi
            echo "Error: missing required snapshot source: $src" >&2
            return 1
        fi

        snapshot_reject_source_symlinks "$src" "$mode" || return 1

        if [[ "$dry_run" == true ]]; then
            if [[ "$mode" == dir ]]; then
                echo "[dry-run] rsync -a --delete $src/ -> $repo_root/$dest/"
            else
                echo "[dry-run] install -Dm644 $src -> $repo_root/$dest"
            fi
            continue
        fi

        if [[ "$mode" == dir ]]; then
            mkdir -p "$repo_root/$dest"
            rsync -a --delete -- "$src/" "$repo_root/$dest/"
        else
            install -Dm644 -- "$src" "$repo_root/$dest"
        fi

        case "$dest" in
            configs/local-bin/inir | configs/local-bin/toggle-niri-shell)
                chmod +x "$repo_root/$dest"
                ;;
        esac
    done
}

snapshot_run_package_export() {
    local repo_root="$1"
    local dry_run="$2"

    if [[ "$dry_run" == true ]]; then
        echo "[dry-run] export package snapshot into packages/*.txt"
        return 0
    fi

    export_package_snapshot "$repo_root"
}

snapshot_secret_marker_allowed() {
    local rel_path="$1"
    local allowed

    for allowed in "${SNAPSHOT_SECRET_MARKER_ALLOWLIST[@]}"; do
        if [[ "$rel_path" == "$allowed" ]]; then
            return 0
        fi
    done

    return 1
}

snapshot_secret_marker_comment_skip() {
    local rel_path="$1"
    local skip_file

    for skip_file in "${SNAPSHOT_SECRET_MARKER_COMMENT_SKIP_FILES[@]}"; do
        if [[ "$rel_path" == "$skip_file" ]]; then
            return 0
        fi
    done

    return 1
}

snapshot_file_has_secret_marker() {
    local file="$1"
    local rel_path="$2"
    local marker scan_input

    if snapshot_secret_marker_comment_skip "$rel_path"; then
        scan_input="$(grep -Ev '^[[:space:]]*#' "$file" || true)"
    else
        scan_input="$(cat "$file")"
    fi

    for marker in "${SNAPSHOT_SECRET_MARKERS[@]}"; do
        if grep -qF -- "$marker" <<<"$scan_input"; then
            echo "Error: secret marker '$marker' found in $rel_path" >&2
            return 1
        fi
    done

    return 0
}

snapshot_scan_file_for_secrets() {
    local repo_root="$1"
    local file="$2"
    local rel_path="${file#"$repo_root"/}"

    if snapshot_secret_marker_allowed "$rel_path"; then
        return 0
    fi

    snapshot_file_has_secret_marker "$file" "$rel_path"
}

snapshot_safety_check() {
    local repo_root="$1"
    local -a scan_paths=()
    local mapping mode _src dest _required rel_path fragment

    for mapping in "${SNAPSHOT_MAPPINGS[@]}"; do
        IFS='|' read -r mode _src dest _required <<<"$mapping"
        scan_paths+=("$repo_root/$dest")
    done

    local pkg
    for pkg in "$repo_root"/packages/*.txt; do
        [[ -f "$pkg" ]] || continue
        scan_paths+=("$pkg")
    done

    local path
    for path in "${scan_paths[@]}"; do
        if [[ ! -e "$path" ]]; then
            continue
        fi

        rel_path="${path#"$repo_root"/}"

        if [[ -d "$path" ]]; then
            local found
            while IFS= read -r found; do
                [[ -z "$found" ]] && continue
                for fragment in "${SNAPSHOT_FORBIDDEN_PATH_FRAGMENTS[@]}"; do
                    if [[ "$found" == *"$fragment"* ]]; then
                        echo "Error: forbidden path fragment '$fragment' in $found" >&2
                        return 1
                    fi
                done
                snapshot_scan_file_for_secrets "$repo_root" "$found" || return 1
            done < <(find "$path" -type f 2>/dev/null)
        else
            for fragment in "${SNAPSHOT_FORBIDDEN_PATH_FRAGMENTS[@]}"; do
                if [[ "$rel_path" == *"$fragment"* ]]; then
                    echo "Error: forbidden path fragment '$fragment' in $rel_path" >&2
                    return 1
                fi
            done
            snapshot_scan_file_for_secrets "$repo_root" "$path" || return 1
        fi
    done
}

snapshot_run_verification() {
    local repo_root="$1"
    local -a shell_scripts=("$repo_root/install.sh" "$repo_root"/scripts/*.sh)

    git -C "$repo_root" diff --check

    if compgen -G "$repo_root/tests/*.sh" >/dev/null; then
        shell_scripts+=("$repo_root"/tests/*.sh)
    fi

    bash -n "${shell_scripts[@]}"
    shellcheck "${shell_scripts[@]}"
    "$repo_root/install.sh" --yes --dry-run
}

snapshot_print_summary() {
    local repo_root="$1"
    local -a status_lines=()
    local line path
    local has_dotfiles=false has_packages=false has_other=false

    mapfile -t status_lines < <(git -C "$repo_root" status --short -- packages configs)

    if ((${#status_lines[@]} == 0)); then
        echo "Snapshot complete. No changes detected."
        return 1
    fi

    echo "Changed dotfiles:"
    for line in "${status_lines[@]}"; do
        path="${line:3}"
        if [[ "$path" == configs/* ]]; then
            echo "  $line"
            has_dotfiles=true
        fi
    done
    if [[ "$has_dotfiles" != true ]]; then
        echo "  (none)"
    fi

    echo
    echo "Changed packages:"
    for line in "${status_lines[@]}"; do
        path="${line:3}"
        if [[ "$path" == packages/* ]]; then
            echo "  $line"
            has_packages=true
        fi
    done
    if [[ "$has_packages" != true ]]; then
        echo "  (none)"
    fi

    echo
    echo "Other managed changes:"
    for line in "${status_lines[@]}"; do
        path="${line:3}"
        if [[ "$path" != configs/* && "$path" != packages/* ]]; then
            echo "  $line"
            has_other=true
        fi
    done
    if [[ "$has_other" != true ]]; then
        echo "  (none)"
    fi

    return 0
}

snapshot_stage_managed_changes() {
    local repo_root="$1"
    local managed

    while IFS= read -r managed; do
        [[ -z "$managed" ]] && continue
        if [[ -n "$(git -C "$repo_root" status --porcelain -- "$managed")" ]]; then
            git -C "$repo_root" add -- "$managed"
        fi
    done < <(snapshot_managed_paths "$repo_root")
}

snapshot_commit() {
    local repo_root="$1"

    if snapshot_has_non_snapshot_changes "$repo_root"; then
        echo "Error: non-snapshot changes are present. Commit or stash them before running --snapshot commit/push." >&2
        return 1
    fi

    snapshot_stage_managed_changes "$repo_root"

    if git -C "$repo_root" diff --cached --quiet; then
        echo "No staged snapshot changes to commit."
        return 0
    fi

    git -C "$repo_root" commit -m "$(cat <<'EOF'
chore: update dotfiles snapshot
EOF
)"
}

snapshot_push() {
    local repo_root="$1"

    if ! git -C "$repo_root" push; then
        echo "Error: git push failed. Commit was created locally." >&2
        return 1
    fi
}

snapshot_prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local hint reply

    if [[ "$default" == y ]]; then
        hint="Y/n"
    else
        hint="y/N"
    fi

    while true; do
        read -r -p "$prompt [$hint] " reply
        reply="${reply:-$default}"
        case "${reply,,}" in
            y | yes)
                return 0
                ;;
            n | no)
                return 1
                ;;
            *)
                echo "Please answer y or n."
                ;;
        esac
    done
}

run_snapshot() {
    local repo_root="$1"
    local dry_run="$2"
    local assume_yes="$3"
    local no_commit="$4"
    local commit="$5"
    local push="$6"

    echo "==> Snapshotting managed configs"
    snapshot_capture_configs "$repo_root" "$dry_run"

    echo "==> Exporting package manifests"
    snapshot_run_package_export "$repo_root" "$dry_run"

    if [[ "$dry_run" == true ]]; then
        echo "==> Dry run: skipping safety check, verification, and commit"
        return 0
    fi

    echo "==> Running safety check"
    snapshot_safety_check "$repo_root"

    echo "==> Running verification"
    snapshot_run_verification "$repo_root"

    echo
    if ! snapshot_print_summary "$repo_root"; then
        return 0
    fi

    if [[ "$no_commit" == true ]]; then
        echo
        echo "Snapshot complete. Changes left uncommitted (--no-commit)."
        return 0
    fi

    local do_commit=false
    local do_push=false

    if [[ "$push" == true ]]; then
        if snapshot_prompt_yes_no "Commit and push these snapshot changes?" n; then
            do_commit=true
            do_push=true
        else
            echo "Snapshot complete. Changes left uncommitted."
            return 0
        fi
    elif [[ "$commit" == true || "$assume_yes" == true ]]; then
        do_commit=true
    elif snapshot_prompt_yes_no "Commit and push these snapshot changes?" n; then
        do_commit=true
        do_push=true
    else
        echo "Snapshot complete. Changes left uncommitted."
        return 0
    fi

    if [[ "$do_commit" != true ]]; then
        return 0
    fi

    echo "==> Committing snapshot changes"
    snapshot_commit "$repo_root"

    if [[ "$do_push" == true ]]; then
        echo "==> Pushing snapshot commit"
        snapshot_push "$repo_root"
    fi

    echo "Snapshot complete."
}

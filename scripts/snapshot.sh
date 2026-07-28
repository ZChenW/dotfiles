#!/usr/bin/env bash
# Snapshot managed dotfiles and package manifests from the live machine into the repo.

set -euo pipefail

DOTFILES_UI_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ui.sh
source "$DOTFILES_UI_SCRIPT_DIR/ui.sh"
# shellcheck source=scripts/repo-sync.sh
source "$DOTFILES_UI_SCRIPT_DIR/repo-sync.sh"

build_snapshot_mappings() {
    local desktop_shell_profile="${DESKTOP_SHELL_PROFILE:-dual}"
    SNAPSHOT_MAPPINGS=(
    "dir|$HOME/.config/niri|configs/config/niri|required"
    "dir|$HOME/.config/kitty|configs/config/kitty|required"
    "dir|$HOME/.config/fastfetch|configs/config/fastfetch|required"
    "dir|$HOME/.config/waypaper|configs/config/waypaper|required"
    "dir|$HOME/.config/matugen|configs/config/matugen|required"
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
    "file|$HOME/.local/bin/toggle-wlsunset|configs/local-bin/toggle-wlsunset|required"
    "file|$HOME/.local/bin/desktop-shell|configs/local-bin/desktop-shell|required"
    "file|$HOME/.local/share/zsh/site-functions/_desktop-shell|configs/zsh/site-functions/_desktop-shell|required"
    "dir|$HOME/Pictures/wallpapers|configs/Pictures/wallpapers|optional"
    )

    if [[ "$desktop_shell_profile" == waybar || "$desktop_shell_profile" == dual ]]; then
        SNAPSHOT_MAPPINGS+=(
            "dir|$HOME/.config/waybar|configs/config/waybar|required"
            "file|$HOME/.local/bin/wcr-post-apply-waybar.sh|configs/local-bin/wcr-post-apply-waybar.sh|required"
        )
    fi
}

build_snapshot_mappings

snapshot_profile_package_paths() {
    local repo_root="$1"
    local install_profile="${INSTALL_PROFILE:-standard}"
    local manifest

    if [[ "$install_profile" == lightweight ]]; then
        printf 'packages/arch-lightweight.txt\n'
        return 0
    fi

    for manifest in \
        arch-essential.txt \
        arch-desktop.txt \
        arch-apps.txt \
        arch-aur.txt \
        arch-machine-local.txt \
        arch-exclude.txt; do
        printf 'packages/%s\n' "$manifest"
    done
}

snapshot_prepare_repo() {
    local repo_root="$1"
    local dry_run="$2"

    if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
        ui_error "Snapshot requires a clean repository before capture."
        ui_note "Commit or otherwise resolve local changes; Snapshot will not stash, reset, or merge."
        return 1
    fi

    repo_pull_ff_only "$repo_root" "$dry_run"
}

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

# Case-insensitive substring markers (matched with grep -iF).
SNAPSHOT_SECRET_MARKERS=(
    github_pat
    ghp_
    OPENAI_API_KEY
    ANTHROPIC_API_KEY
    ANTHROPIC_AUTH_TOKEN
    CURSOR_API_KEY
    API_KEY
    AUTH_TOKEN
    ACCESS_TOKEN
    REFRESH_TOKEN
    SECRET_KEY
)

# Assignment keys that must stand alone (avoid ForPassword= / ShowPreeditForPassword=).
SNAPSHOT_SECRET_KEY_REGEXES=(
    '(^|[[:space:]_])password[[:space:]]*='
    '(^|[[:space:]_])passwd[[:space:]]*='
)

# High-confidence token shapes (ERE). Keep thresholds high to limit false positives.
SNAPSHOT_SECRET_TOKEN_REGEXES=(
    'crsr_[A-Za-z0-9]{20,}'
    'sk-[A-Za-z0-9]{20,}'
    'ghp_[A-Za-z0-9]{20,}'
    'github_pat_[A-Za-z0-9_]{20,}'
)

SNAPSHOT_SECRET_MARKER_ALLOWLIST=(
    docs/INSTALL.md
)

SNAPSHOT_SECRET_MARKER_COMMENT_SKIP_FILES=(
    templates/zshrc.local.example
    configs/home/.zshrc
)

SNAPSHOT_RSYNC_EXCLUDES=(
    .codex
    "*.bak"
    "*.bak.*"
    "*.bak-*"
    "*.backup"
    "*backup*"
)

snapshot_managed_paths() {
    local repo_root="$1"
    local mapping mode _src dest _required

    for mapping in "${SNAPSHOT_MAPPINGS[@]}"; do
        IFS='|' read -r mode _src dest _required <<<"$mapping"
        printf '%s\n' "$dest"
    done

    snapshot_profile_package_paths "$repo_root"
}

snapshot_path_is_managed() {
    local repo_root="$1"
    local path="$2"
    local managed
    local -a managed_paths=()

    mapfile -t managed_paths < <(snapshot_managed_paths "$repo_root")
    for managed in "${managed_paths[@]}"; do
        [[ -z "$managed" ]] && continue
        if [[ "$path" == "$managed" || "$path" == "$managed"/* ]]; then
            return 0
        fi
    done

    return 1
}

snapshot_git_changed_paths() {
    local repo_root="$1"
    local record status path renamed_from

    while IFS= read -r -d '' record; do
        status="${record:0:2}"
        path="${record:3}"
        printf '%s\0' "$path"

        # In porcelain v1 -z output, rename/copy entries contain a second
        # NUL-delimited source path. Check both sides so moving a file across
        # the managed boundary cannot bypass the snapshot safety check.
        if [[ "$status" == *R* || "$status" == *C* ]]; then
            if IFS= read -r -d '' renamed_from; then
                printf '%s\0' "$renamed_from"
            fi
        fi
    done < <(
        git -C "$repo_root" status \
            --porcelain=v1 -z --untracked-files=all
    )
}

snapshot_has_non_snapshot_changes() {
    local repo_root="$1"
    local path

    while IFS= read -r -d '' path; do
        if [[ "$path" == */ ]]; then
            path="${path%/}"
        fi
        if ! snapshot_path_is_managed "$repo_root" "$path"; then
            return 0
        fi
    done < <(snapshot_git_changed_paths "$repo_root")

    return 1
}

snapshot_non_snapshot_changes() {
    local repo_root="$1"
    local path

    while IFS= read -r -d '' path; do
        if [[ "$path" == */ ]]; then
            path="${path%/}"
        fi
        if ! snapshot_path_is_managed "$repo_root" "$path"; then
            printf '%s\n' "$path"
        fi
    done < <(snapshot_git_changed_paths "$repo_root")
}

snapshot_reject_source_symlinks() {
    local src="$1"
    local mode="$2"
    local link

    if [[ -L "$src" ]]; then
        ui_error "snapshot source is a symlink: $src"
        return 1
    fi

    if [[ "$mode" == dir && -d "$src" ]]; then
        while IFS= read -r link; do
            [[ -z "$link" ]] && continue
            ui_error "snapshot source contains a symlink: $link"
            return 1
        done < <(find "$src" -type l 2>/dev/null)
    fi

    return 0
}

snapshot_capture_configs() {
    local repo_root="$1"
    local dry_run="$2"
    local mapping mode src dest required exclude
    local captured_count=0

    for mapping in "${SNAPSHOT_MAPPINGS[@]}"; do
        IFS='|' read -r mode src dest required <<<"$mapping"

        if [[ ! -e "$src" ]]; then
            if [[ "$required" == optional ]]; then
                ui_warn "SKIP optional source: $src"
                continue
            fi
            ui_error "missing required snapshot source: $src"
            return 1
        fi

        snapshot_reject_source_symlinks "$src" "$mode" || return 1

        if [[ "$dry_run" == true ]]; then
            if [[ "$mode" == dir ]]; then
                verbose_log "rsync    $dest/"
                debug_log "[dry-run] rsync -a --delete --delete-excluded $src/ -> $repo_root/$dest/"
            else
                verbose_log "install  $dest"
                debug_log "[dry-run] install -Dm644 $src -> $repo_root/$dest"
            fi
            ((++captured_count))
            continue
        fi

        if [[ "$mode" == dir ]]; then
            mkdir -p "$repo_root/$dest"
            local -a rsync_args=(-a --delete --delete-excluded)
            for exclude in "${SNAPSHOT_RSYNC_EXCLUDES[@]}"; do
                rsync_args+=(--exclude="$exclude")
            done
            if [[ "$dest" == configs/config/waybar ]]; then
                # colors.css is runtime output from the wallpaper hook. Keep
                # the committed seed file stable instead of snapshotting the
                # currently selected wallpaper palette.
                rsync_args+=(--filter="P /colors.css" --exclude=/colors.css)
            fi
            rsync "${rsync_args[@]}" -- "$src/" "$repo_root/$dest/"
        else
            install -Dm644 -- "$src" "$repo_root/$dest"
        fi

        case "$dest" in
            configs/local-bin/toggle-wlsunset | configs/local-bin/wcr-post-apply-waybar.sh | configs/local-bin/desktop-shell)
                chmod +x "$repo_root/$dest"
                ;;
        esac
        ((++captured_count))
    done

    ui_ok "Managed configs captured" "$captured_count paths"
}

snapshot_run_package_export() {
    local repo_root="$1"
    local dry_run="$2"
    local install_profile="${3:-${INSTALL_PROFILE:-standard}}"

    if [[ "$dry_run" == true ]]; then
        ui_ok "Export planned"
        debug_log "[dry-run] export package snapshot into packages/*.txt"
        return 0
    fi

    export_package_snapshot "$repo_root" "$install_profile"
}

snapshot_is_text_file() {
    local file="$1"

    [[ ! -s "$file" ]] || grep -Iq . "$file"
}

snapshot_normalize_text_file() {
    local file="$1"
    local tmp_file

    snapshot_is_text_file "$file" || return 0

    tmp_file="$(mktemp)"
    awk '
        {
            sub(/[ \t]+$/, "")
            lines[NR] = $0
        }
        END {
            end = NR
            while (end > 0 && lines[end] == "") {
                end--
            }
            for (i = 1; i <= end; i++) {
                print lines[i]
            }
        }
    ' "$file" >"$tmp_file"
    cat "$tmp_file" >"$file"
    rm -f "$tmp_file"
}

snapshot_normalize_captured_files() {
    local repo_root="$1"
    local -a normalize_paths=()
    local mapping _mode _src dest _required path found package_path

    for mapping in "${SNAPSHOT_MAPPINGS[@]}"; do
        IFS='|' read -r _mode _src dest _required <<<"$mapping"
        normalize_paths+=("$repo_root/$dest")
    done

    while IFS= read -r package_path; do
        [[ -n "$package_path" ]] || continue
        normalize_paths+=("$repo_root/$package_path")
    done < <(snapshot_profile_package_paths "$repo_root")

    for path in "${normalize_paths[@]}"; do
        [[ -e "$path" ]] || continue
        if [[ -d "$path" ]]; then
            while IFS= read -r found; do
                [[ -n "$found" ]] || continue
                snapshot_normalize_text_file "$found"
            done < <(find "$path" -type f 2>/dev/null)
        else
            snapshot_normalize_text_file "$path"
        fi
    done
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

snapshot_file_scan_payload() {
    local file="$1"
    local rel_path="$2"

    if snapshot_secret_marker_comment_skip "$rel_path"; then
        grep -Ev '^[[:space:]]*#' "$file" || true
    else
        cat -- "$file"
    fi
}

snapshot_file_has_secret_marker() {
    local file="$1"
    local rel_path="$2"
    local marker regex payload

    snapshot_is_text_file "$file" || return 0

    payload="$(snapshot_file_scan_payload "$file" "$rel_path")"

    for marker in "${SNAPSHOT_SECRET_MARKERS[@]}"; do
        if grep -qiF -- "$marker" <<<"$payload"; then
            ui_error "secret marker '$marker' found in $rel_path (move secrets to ~/.zshrc.local)"
            return 1
        fi
    done

    for regex in "${SNAPSHOT_SECRET_KEY_REGEXES[@]}"; do
        if grep -Eqi -- "$regex" <<<"$payload"; then
            ui_error "secret key pattern '$regex' found in $rel_path (move secrets to ~/.zshrc.local)"
            return 1
        fi
    done

    for regex in "${SNAPSHOT_SECRET_TOKEN_REGEXES[@]}"; do
        if grep -Eq -- "$regex" <<<"$payload"; then
            ui_error "secret token pattern '$regex' found in $rel_path (move secrets to ~/.zshrc.local)"
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

    local package_path
    while IFS= read -r package_path; do
        [[ -n "$package_path" ]] || continue
        scan_paths+=("$repo_root/$package_path")
    done < <(snapshot_profile_package_paths "$repo_root")

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
                        ui_error "forbidden path fragment '$fragment' in $found"
                        return 1
                    fi
                done
                snapshot_scan_file_for_secrets "$repo_root" "$found" || return 1
            done < <(find "$path" -type f 2>/dev/null)
        else
            for fragment in "${SNAPSHOT_FORBIDDEN_PATH_FRAGMENTS[@]}"; do
                if [[ "$rel_path" == *"$fragment"* ]]; then
                    ui_error "forbidden path fragment '$fragment' in $rel_path"
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

    git --no-pager -C "$repo_root" diff --check

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
        ui_success "Snapshot complete. No changes detected."
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

snapshot_show_diff() {
    local repo_root="$1"
    local -a paths=(configs)
    local package_path untracked_path diff_status

    while IFS= read -r package_path; do
        [[ -n "$package_path" ]] || continue
        paths+=("$package_path")
    done < <(snapshot_profile_package_paths "$repo_root")

    ui_section "Snapshot diff"
    git --no-pager -C "$repo_root" diff -- "${paths[@]}"
    while IFS= read -r untracked_path; do
        [[ -n "$untracked_path" ]] || continue
        [[ -f "$repo_root/$untracked_path" ]] || continue
        diff_status=0
        git --no-pager diff --no-index -- /dev/null \
            "$repo_root/$untracked_path" || diff_status=$?
        if ((diff_status > 1)); then
            return "$diff_status"
        fi
    done < <(
        git -C "$repo_root" ls-files \
            --others --exclude-standard -- "${paths[@]}"
    )
    git -C "$repo_root" status --short -- "${paths[@]}"
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

snapshot_has_managed_changes() {
    local repo_root="$1"
    local managed

    while IFS= read -r managed; do
        [[ -z "$managed" ]] && continue
        if [[ -n "$(git -C "$repo_root" status --porcelain -- "$managed")" ]]; then
            return 0
        fi
    done < <(snapshot_managed_paths "$repo_root")

    return 1
}

snapshot_repo_uses_jj() {
    local repo_root="$1"

    [[ -d "$repo_root/.jj" ]] && command -v jj >/dev/null 2>&1
}

snapshot_commit() {
    local repo_root="$1"
    local message="chore: update dotfiles snapshot"
    local -a blockers=()

    SNAPSHOT_COMMIT_CREATED=false
    SNAPSHOT_COMMIT_VCS=""

    mapfile -t blockers < <(snapshot_non_snapshot_changes "$repo_root")
    if ((${#blockers[@]} > 0)); then
        ui_error "non-snapshot changes are present. Commit or stash them before running --snapshot commit/push."
        printf '  %s\n' "${blockers[@]}" >&2
        return 1
    fi

    if ! snapshot_has_managed_changes "$repo_root"; then
        ui_warn "No snapshot changes to commit."
        return 0
    fi

    if snapshot_repo_uses_jj "$repo_root"; then
        if ! jj -R "$repo_root" describe -m "$message"; then
            ui_error "jj failed to describe the snapshot commit."
            return 1
        fi
        SNAPSHOT_COMMIT_CREATED=true
        SNAPSHOT_COMMIT_VCS=jj
        return 0
    fi

    snapshot_stage_managed_changes "$repo_root"

    if git -C "$repo_root" diff --cached --quiet; then
        ui_warn "No staged snapshot changes to commit."
        return 0
    fi

    git -C "$repo_root" commit -m "$message"
    SNAPSHOT_COMMIT_CREATED=true
    SNAPSHOT_COMMIT_VCS=git
}

snapshot_push() {
    local repo_root="$1"

    if [[ "${SNAPSHOT_COMMIT_CREATED:-false}" != true ]]; then
        ui_warn "No snapshot commit to push."
        return 0
    fi

    if [[ "${SNAPSHOT_COMMIT_VCS:-}" == jj ]]; then
        if ! jj -R "$repo_root" git push --change @; then
            ui_error "jj push failed. The snapshot commit remains local."
            return 1
        fi
        if ! jj -R "$repo_root" new @; then
            ui_error "Snapshot was pushed, but jj could not create a clean working-copy commit."
            return 1
        fi
        SNAPSHOT_COMMIT_CREATED=false
        return 0
    fi

    if ! git -C "$repo_root" push; then
        ui_error "git push failed. Commit was created locally."
        return 1
    fi
    SNAPSHOT_COMMIT_CREATED=false
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
        read -r -p "$(ui_prompt "$prompt" "$hint")" reply
        reply="${reply:-$default}"
        case "${reply,,}" in
            y | yes)
                return 0
                ;;
            n | no)
                return 1
                ;;
            *)
                ui_warn "Please answer y or n."
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

    ui_section "Snapshot"
    snapshot_capture_configs "$repo_root" "$dry_run"

    ui_section "Package manifests"
    snapshot_run_package_export "$repo_root" "$dry_run"

    if [[ "$dry_run" == true ]]; then
        ui_ok "Safety check planned"
        ui_ok "Verification planned"
        return 0
    fi

    ui_section "Normalize"
    snapshot_normalize_captured_files "$repo_root"
    ui_ok "Text files normalized"

    ui_section "Safety"
    snapshot_safety_check "$repo_root"
    ui_ok "Safety check passed"

    ui_section "Verification"
    snapshot_run_verification "$repo_root"
    ui_ok "Verification passed"

    echo
    if ! snapshot_print_summary "$repo_root"; then
        return 0
    fi

    if [[ "$no_commit" == true ]]; then
        echo
        ui_success "Snapshot complete. Changes left uncommitted (--no-commit)."
        return 0
    fi

    local do_commit=false
    local do_push=false

    if [[ "$push" == true ]]; then
        if snapshot_prompt_yes_no "Commit and push these snapshot changes?" n; then
            do_commit=true
            do_push=true
        else
            ui_success "Snapshot complete. Changes left uncommitted."
            return 0
        fi
    elif [[ "$commit" == true || "$assume_yes" == true ]]; then
        do_commit=true
    elif snapshot_prompt_yes_no "Commit and push these snapshot changes?" n; then
        do_commit=true
        do_push=true
    else
        ui_success "Snapshot complete. Changes left uncommitted."
        return 0
    fi

    if [[ "$do_commit" != true ]]; then
        return 0
    fi

    ui_step "Committing snapshot changes"
    snapshot_commit "$repo_root"

    if [[ "$do_push" == true ]]; then
        ui_step "Pushing snapshot commit"
        snapshot_push "$repo_root"
    fi

    ui_success "Snapshot complete."
}

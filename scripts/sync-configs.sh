#!/usr/bin/env bash
# Config sync helpers for dotfiles install.

set -euo pipefail

SYNC_MANIFEST_FILE=".restore-manifest"

sync_configs() {
    local repo_root="$1"
    local backup_root="$2"
    local dry_run="${3:-false}"

    # shellcheck source=scripts/backup.sh
    source "$repo_root/scripts/backup.sh"

    local -a mappings=(
        "$repo_root/configs/home/.zshrc|$HOME/.zshrc|644"
        "$repo_root/configs/config/niri|$HOME/.config/niri|dir"
        "$repo_root/configs/config/waybar|$HOME/.config/waybar|dir"
        "$repo_root/configs/config/kitty|$HOME/.config/kitty|dir"
        "$repo_root/configs/config/fastfetch|$HOME/.config/fastfetch|dir"
        "$repo_root/configs/config/waypaper|$HOME/.config/waypaper|dir"
        "$repo_root/configs/local-bin/inir|$HOME/.local/bin/inir|755"
        "$repo_root/configs/local-bin/toggle-niri-shell|$HOME/.local/bin/toggle-niri-shell|755"
    )

    local manifest="$backup_root/$SYNC_MANIFEST_FILE"
    if [[ "$dry_run" != true ]]; then
        : >"$manifest"
    fi

    local mapping src dest mode
    for mapping in "${mappings[@]}"; do
        IFS='|' read -r src dest mode <<<"$mapping"

        if [[ ! -e "$src" ]]; then
            echo "Warning: missing repo config source: $src" >&2
            continue
        fi

        local existed_before=false
        if path_existed "$dest"; then
            existed_before=true
        fi

        backup_path "$dest" "$backup_root" "$dry_run"
        remove_symlink_dest "$dest" "$dry_run"

        if [[ "$dry_run" == true ]]; then
            local action="created"
            [[ "$existed_before" == true ]] && action="backed_up"
            echo "[dry-run] manifest: $dest|$action"
            if [[ "$mode" == dir ]]; then
                echo "[dry-run] rsync -a $src/ -> $dest/"
            else
                echo "[dry-run] install -Dm$mode $src -> $dest"
            fi
        else
            record_manifest_entry "$manifest" "$dest" "$existed_before"
            if [[ "$mode" == dir ]]; then
                mkdir -p "$dest"
                rsync -a --delete -- "$src/" "$dest/"
                echo "Synced directory: $dest"
            else
                install -Dm"$mode" -- "$src" "$dest"
                echo "Synced file: $dest"
            fi
        fi
    done

    local zshrc_local="$HOME/.zshrc.local"
    local zshrc_local_template="$repo_root/templates/zshrc.local.example"
    if path_existed "$zshrc_local"; then
        local was_symlink=false
        [[ -L "$zshrc_local" ]] && was_symlink=true

        backup_path "$zshrc_local" "$backup_root" "$dry_run"

        if [[ "$was_symlink" == true ]]; then
            remove_symlink_dest "$zshrc_local" "$dry_run"
            if [[ "$dry_run" == true ]]; then
                echo "[dry-run] manifest: $zshrc_local|backed_up"
                echo "[dry-run] install -Dm644 $zshrc_local_template -> $zshrc_local (replace symlink)"
            else
                record_manifest_entry "$manifest" "$zshrc_local" true
                install -Dm644 -- "$zshrc_local_template" "$zshrc_local"
                echo "Replaced symlink with real file: $zshrc_local"
            fi
        elif [[ "$dry_run" == true ]]; then
            echo "[dry-run] manifest: $zshrc_local|backed_up"
            echo "[dry-run] keep existing: $zshrc_local"
        else
            record_manifest_entry "$manifest" "$zshrc_local" true
            echo "Keeping existing: $zshrc_local"
        fi
    elif [[ "$dry_run" == true ]]; then
        echo "[dry-run] manifest: $zshrc_local|created"
        echo "[dry-run] install -Dm644 $zshrc_local_template -> $zshrc_local (new file)"
    else
        install -Dm644 -- "$zshrc_local_template" "$zshrc_local"
        record_manifest_entry "$manifest" "$zshrc_local" false
        echo "Created: $zshrc_local"
    fi

    if [[ "$dry_run" == true ]]; then
        echo "[dry-run] chmod +x $HOME/.local/bin/inir $HOME/.local/bin/toggle-niri-shell"
    else
        chmod +x "$HOME/.local/bin/inir" "$HOME/.local/bin/toggle-niri-shell"
        echo "Ensured executable: ~/.local/bin/inir ~/.local/bin/toggle-niri-shell"
    fi

    write_rollback_script "$backup_root" "$dry_run"
}

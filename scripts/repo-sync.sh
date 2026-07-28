#!/usr/bin/env bash
# Fast-forward-only repository synchronization for Git and colocated Jujutsu.

set -euo pipefail

repo_nearest_tracking_branch() {
    local repo_root="$1"
    local branch upstream distance
    local best_branch="" best_upstream="" best_distance=""

    while IFS='|' read -r branch upstream; do
        [[ -n "$branch" && -n "$upstream" ]] || continue
        git -C "$repo_root" merge-base --is-ancestor "$branch" HEAD \
            || continue
        distance="$(
            git -C "$repo_root" rev-list --count "$branch"..HEAD
        )"
        if [[ -z "$best_distance" ]] || ((distance < best_distance)); then
            best_branch="$branch"
            best_upstream="$upstream"
            best_distance="$distance"
        fi
    done < <(
        git -C "$repo_root" for-each-ref \
            --format='%(refname:short)|%(upstream:short)' refs/heads
    )

    [[ -n "$best_branch" ]] || return 1
    printf '%s|%s\n' "$best_branch" "$best_upstream"
}

repo_pull_ff_only() {
    local repo_root="$1"
    local dry_run="$2"

    if [[ "$dry_run" == true ]]; then
        echo "[dry-run] git pull --ff-only"
        return 0
    fi

    if [[ ! -d "$repo_root/.jj" ]] || ! command -v jj >/dev/null 2>&1; then
        git -C "$repo_root" pull --ff-only
        return
    fi

    local tracking local_branch upstream remote remote_branch pulled_head
    if ! tracking="$(repo_nearest_tracking_branch "$repo_root")"; then
        ui_error "Jujutsu repository has no tracked Git branch in the current ancestry."
        return 1
    fi
    IFS='|' read -r local_branch upstream <<<"$tracking"
    remote="${upstream%%/*}"
    remote_branch="${upstream#*/}"

    ui_note "Jujutsu fast-forward base: $local_branch -> $upstream"
    git -C "$repo_root" pull --ff-only "$remote" "$remote_branch" \
        || return 1
    pulled_head="$(git -C "$repo_root" rev-parse HEAD)"
    jj -R "$repo_root" new "$pulled_head"
}

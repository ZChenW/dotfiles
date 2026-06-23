# Install Guide

This repository restores an Arch Linux desktop setup with zsh, niri, Waybar, kitty, fastfetch, waypaper, and local launcher scripts.

## Supported OS

Arch Linux only. The installer checks `/etc/os-release` and exits on other distributions.

## Quick Start

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh
```

Preview planned changes without modifying `$HOME`:

```bash
./install.sh --dry-run
```

Other flags:

- `--yes` — non-interactive mode for package prompts
- `--skip-packages` — restore configs only, skip `pacman`/AUR installs
- `--restore-only` — same as `--skip-packages`, and skip optional service actions

## What Gets Installed

Official Arch packages (via `sudo pacman -S --needed`):

| Group | Packages |
|-------|----------|
| base | git, rsync, zsh |
| terminal | kitty, lsd, yazi, fastfetch |
| desktop | niri, waybar, fuzzel, mako, fcitx5, kanshi, swayidle, brightnessctl, playerctl, wl-clipboard |
| screenshot/recording | grim, slurp, wf-recorder, ffmpeg |
| wallpaper/theme | waypaper, matugen |
| shell helpers | clipse |

Packages not found in the official repos are installed with `paru` or `yay` when available. The installer does not bootstrap an AUR helper.

## What Gets Restored

Real files and directories are copied into `$HOME` (no symlinks):

| Repository path | Destination |
|-----------------|-------------|
| `configs/home/.zshrc` | `~/.zshrc` |
| `configs/config/niri/` | `~/.config/niri/` |
| `configs/config/waybar/` | `~/.config/waybar/` |
| `configs/config/kitty/` | `~/.config/kitty/` |
| `configs/config/fastfetch/` | `~/.config/fastfetch/` |
| `configs/config/waypaper/` | `~/.config/waypaper/` |
| `configs/local-bin/inir` | `~/.local/bin/inir` |
| `configs/local-bin/toggle-niri-shell` | `~/.local/bin/toggle-niri-shell` |
| `templates/zshrc.local.example` | `~/.zshrc.local` (only if missing) |

Before overwriting, existing targets are backed up under:

```text
~/.dotfiles-backups/YYYYmmdd-HHMMSS/
```

If an existing target is a symlink, the symlink and a `.symlink-info` note are stored before replacement with a real file or directory.

## What Is Intentionally Excluded

- `~/.config/quickshell/inir` third-party source tree (large; handle separately)
- Secrets, proxy values, tokens, SSH keys, browser profiles, and account-specific auth
- Machine-local values — use `~/.zshrc.local` instead (see `templates/zshrc.local.example`)
- Generated noise: `.git/`, `.codex`, `*.bak`, `*.backup`, `__pycache__/`, `*.pyc`

## Rollback

Each install creates a timestamped backup directory with a `rollback.sh` script:

```bash
~/.dotfiles-backups/YYYYmmdd-HHMMSS/rollback.sh
```

Run that script to restore the pre-install state:

- Paths that existed before install are restored from the backup.
- Paths created by the installer (for example a new `~/.zshrc.local`) are removed.

The installer prints the exact backup path when it finishes.

## Verification

After syncing, the installer runs:

- `zsh -n ~/.zshrc`
- `niri validate -c ~/.config/niri/config.kdl`
- `fastfetch --version`, `waybar --version`, `kitty --version` (when installed)
- Checks that restored paths are real files/directories, not symlinks

Missing tools are reported as `SKIP` when packages were not installed.

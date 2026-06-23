# Install Guide

This repository restores an Arch Linux desktop setup with zsh, niri, Waybar, kitty, fastfetch, waypaper, and local launcher scripts.

## Supported OS

Arch Linux only. The installer checks `/etc/os-release` and exits on other distributions.

## Quick Start

Recommended flow on a new machine:

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh --dry-run
./install.sh --yes
```

Preview planned changes without modifying `$HOME`:

```bash
./install.sh --dry-run
```

## Installer Modes

| Command | Behavior |
|---------|----------|
| `./install.sh` | Install portable packages + restore configs |
| `./install.sh --packages-only` | Install packages only |
| `./install.sh --skip-packages` | Restore configs only |
| `./install.sh --full-packages` | Include `packages/arch-machine-local.txt` |
| `./install.sh --export-packages` | Regenerate `packages/*.txt` from this machine |

Other flags:

- `--yes` — non-interactive mode for package prompts
- `--restore-only` — same as `--skip-packages`, and skip optional service actions

## Package Manifests

Software is managed through files in `packages/`:

| File | Purpose | Default install |
|------|---------|-----------------|
| `arch-essential.txt` | Installer-required and core shell/desktop packages | yes |
| `arch-desktop.txt` | Fonts, portals, Bluetooth, desktop utilities | yes |
| `arch-apps.txt` | User applications from official repositories | yes |
| `arch-aur.txt` | AUR and foreign packages | yes |
| `arch-machine-local.txt` | Kernel, firmware, boot, GPU, audio stack | no |
| `arch-exclude.txt` | Packages excluded from automation | never |

By default, the installer restores a portable software set. Machine-local packages are listed separately and skipped unless you pass `--full-packages`.

Regenerate the manifests from the current machine:

```bash
./install.sh --export-packages
```

Install software without touching configs:

```bash
./install.sh --packages-only --yes
```

Official packages are installed with:

```bash
sudo pacman -S --needed ...
```

AUR packages use `paru` or `yay`. The installer does not bootstrap an AUR helper.

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
- Packages listed in `packages/arch-exclude.txt`
- Machine-local kernel/driver/audio packages unless `--full-packages` is used

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

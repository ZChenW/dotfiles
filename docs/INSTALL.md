# Install Guide

This repository restores an Arch Linux desktop setup with zsh, niri, Waybar, kitty, fastfetch, waypaper, and local launcher scripts.

## Supported OS

Arch Linux only. The installer checks `/etc/os-release` and exits on other distributions.

## Quick Start

Interactive flow (default in a terminal):

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh
```

Non-interactive flow for scripts or a new machine:

```bash
./install.sh --dry-run --yes
./install.sh --yes
```

Preview planned changes without modifying `$HOME`:

```bash
./install.sh --yes --dry-run
```

## Interactive Installer

When stdin and stdout are a TTY and `--yes` is not passed, `./install.sh` runs five steps:

1. **Install mode** — full install, packages only, configs only, or dry-run preview
2. **Software scope** — install packages, include AUR, include `arch-machine-local.txt`
3. **Config groups** — choose one or more groups (default: all)
4. **Local private config** — explains `~/.zshrc.local` handling
5. **Confirm** — prints a plan summary; proceeds only on `y` (default `N`)

`--dry-run` can be combined with interactive mode. Selections are applied, then actions are printed without modifying `$HOME`.

Non-TTY stdin/stdout without `--yes` fails with a message to use `--yes` or run in a terminal.

## Installer Modes

| Command | Behavior |
|---------|----------|
| `./install.sh` | Interactive: choose packages and config groups |
| `./install.sh --yes` | Non-interactive: portable packages + all config groups |
| `./install.sh --packages-only` | Install packages only |
| `./install.sh --skip-packages` | Restore configs only |
| `./install.sh --full-packages` | Include `packages/arch-machine-local.txt` |
| `./install.sh --no-aur` | Skip AUR packages |
| `./install.sh --export-packages` | Regenerate `packages/*.txt` from this machine |

Other flags:

- `--yes` — non-interactive mode with recommended defaults
- `--restore-only` — same as `--skip-packages`, and skip optional service actions
- `--dry-run` — preview actions without modifying `$HOME`

With `--yes`, AUR packages are installed by default. Pass `--no-aur` to install official packages only. In interactive mode, AUR is off by default unless you choose to include it.

## Config Groups

| Group | Restored paths |
|-------|----------------|
| `shell` | `~/.zshrc`, `~/.zshrc.local` |
| `desktop` | `~/.config/niri`, waybar, fcitx5, mako, environment.d, qt5ct, qt6ct |
| `terminal` | `~/.config/kitty`, fastfetch, cava |
| `apps` | waypaper, Thunar, mimeapps.list, user-dirs.dirs, git/ignore |
| `editors` | Code/Cursor `settings.json`, `keybindings.json`, optional `snippets/` |
| `local-bin` | `~/.local/bin/inir`, `toggle-niri-shell` |

`~/.zshrc.local` is handled only when the `shell` group is selected:

- Missing file: created from `templates/zshrc.local.example`
- Existing regular file: kept
- Existing symlink: backed up and replaced with a real file from the template

`chmod +x` on local-bin scripts runs only when the `local-bin` group is selected.

## Package Manifests

Software is managed through files in `packages/`:

| File | Purpose | Default install |
|------|---------|-----------------|
| `arch-essential.txt` | Installer-required and core shell/desktop packages | yes |
| `arch-desktop.txt` | Fonts, portals, Bluetooth, desktop utilities | yes |
| `arch-apps.txt` | User applications from official repositories | yes |
| `arch-aur.txt` | AUR and foreign packages | yes (`--yes`), no (interactive default) |
| `arch-machine-local.txt` | Kernel, firmware, boot, GPU, audio stack | no |
| `arch-exclude.txt` | Packages excluded from automation | never |

By default, the installer restores a portable software set. Machine-local packages are listed separately and skipped unless you pass `--full-packages` or choose them in interactive mode.

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

AUR packages use `paru` or `yay` when included. The installer does not bootstrap an AUR helper. When AUR is skipped, those packages are listed and not installed.

## What Gets Restored

Real files and directories are copied into `$HOME` (no symlinks). See the config group table above for the full mapping.

VS Code and Cursor restore only `settings.json`, `keybindings.json`, and optional `snippets/`. Editor history, workspace storage, global storage, and `state.vscdb` databases are not tracked.

`user-dirs.dirs` may contain home-directory paths. Review it after install if the target username or layout differs.

Before overwriting, existing targets are backed up under:

```text
~/.dotfiles-backups/YYYYmmdd-HHMMSS/
```

If an existing target is a symlink, the symlink and a `.symlink-info` note are stored before replacement with a real file or directory.

## What Is Intentionally Excluded

- `~/.config/quickshell/inir` third-party source tree (large; handle separately)
- Browser profiles and session data: Chromium, Edge, Firefox, and similar
- Editor runtime data: `History/`, `workspaceStorage/`, `globalStorage/`, `state.vscdb*`
- AI auth and provider state: `~/.config/github-copilot/`
- Proxy and account secrets: `~/.config/clash/config.yaml`, cookies, auth databases
- Desktop databases: `~/.config/dconf/user`, `~/.config/pulse/cookie`
- App-local databases and caches: `~/.config/obsidian/`, `~/.config/wallpaper-console/`
- Secrets, proxy values, tokens, SSH keys, and account-specific auth in tracked files
- Machine-local values — use `~/.zshrc.local` instead (see `templates/zshrc.local.example`)
- Generated noise: `.git/`, `.codex`, `*.bak`, `*.backup`, `__pycache__/`, `*.pyc`, editor caches
- Packages listed in `packages/arch-exclude.txt`
- Machine-local kernel/driver/audio packages unless `--full-packages` is used

The repository does not mirror all of `~/.config`. Only the whitelisted paths above are restored.

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

After syncing, the installer runs checks for the selected config groups:

- `zsh -n ~/.zshrc` (shell group)
- `niri validate -c ~/.config/niri/config.kdl` (desktop group)
- `fastfetch --version`, `waybar --version`, `kitty --version` (when installed)
- Checks that restored paths are real files/directories, not symlinks

Missing tools are reported as `SKIP` when packages were not installed.

# Install Guide

This repository restores an Arch Linux desktop setup with zsh, niri, a
Waybar/QuickShell desktop shell, kitty, fastfetch, waypaper, and local launcher
scripts.

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

With no arguments in a terminal, `./install.sh` first offers install, update,
snapshot, package export, doctor, uninstall, or exit. `--menu` opens the same
operation menu explicitly.

After choosing install, the installer runs six steps:

1. **Install mode** — full install, packages only, configs only, or dry-run preview
2. **Software scope** — install packages, include AUR, include `arch-machine-local.txt`
3. **Desktop shell** — Waybar, QuickShell, or both
4. **Config groups** — choose one or more groups (default: all)
5. **Local private config** — explains `~/.zshrc.local` handling
6. **Review** — prints a plan summary, then install, revise, or cancel

Interactive menus support Up/Down, Enter, and number shortcuts. The final
review can start the install, return to the first step, or cancel without
changes.

`--dry-run` can be combined with interactive mode. Selections are applied, then actions are printed without modifying `$HOME`.

Non-TTY stdin/stdout without `--yes` fails with a message to use `--yes` or run in a terminal.
TTY output includes step progress and compact result cards. Redirected and CI
output stays deterministic and plain; use `--verbose` for individual
operations or `--debug` for raw commands.

## Installer Modes

| Command | Behavior |
|---------|----------|
| `./install.sh` | Interactive: choose an operation, then its options |
| `./install.sh --menu` | Explicitly open the top-level operation menu |
| `./install.sh --yes` | Non-interactive: portable packages + all config groups |
| `./install.sh --packages-only` | Install packages only |
| `./install.sh --skip-packages` | Restore configs only |
| `./install.sh --full-packages` | Include `packages/arch-machine-local.txt` |
| `./install.sh --no-aur` | Skip AUR packages |
| `./install.sh --desktop-shell waybar` | Install Waybar only |
| `./install.sh --desktop-shell quickshell` | Install QuickShell only |
| `./install.sh --desktop-shell dual` | Install both and enable switching |
| `./install.sh --export-packages` | Regenerate `packages/*.txt` from this machine |
| `./install.sh --doctor` | Diagnostics only (tools, configs, backups, validation) |
| `./install.sh --uninstall` | Safe uninstall: archive then remove managed configs |
| `./install.sh --uninstall restore` | Run the latest install `rollback.sh` |
| `./install.sh --uninstall purge` / `--purge` | Remove managed configs and all install backups |

Other flags:

- `--yes` — non-interactive mode with recommended defaults
- `--restore-only` — same as `--skip-packages`, and skip optional service actions
- `--dry-run` — preview actions without modifying `$HOME` (also works with `--uninstall`)

Before install, snapshot, update, doctor, or uninstall, the installer runs a **preflight** check for required host tools (`bash`, `sudo`, `pacman`, `rsync`, `install`, `git`, and `tar` for uninstall). Missing tools fail early with an install hint.

With `--yes`, AUR packages are installed by default. Pass `--no-aur` to install official packages only. In interactive mode, AUR is off by default unless you choose to include it. If AUR is enabled and neither `paru` nor `yay` is available, the installer bootstraps `paru` in `--yes` mode or asks before doing so in interactive mode.

The selected desktop shell profile is stored under
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/desktop-shell-profile` and reused by
later non-interactive installs and updates. QuickShell is checked out from the
fork and exact commit in `packages/quickshell-source.conf`, built without root,
and kept at `${XDG_DATA_HOME:-~/.local/share}/quickshell/clavis`. A dirty or
unrelated directory at that path is never overwritten.

## Config Groups

| Group | Restored paths |
|-------|----------------|
| `shell` | `~/.zshrc`, `~/.zshrc.local` |
| `desktop` | `~/.config/niri`, profile-selected Waybar config, fcitx5, mako, environment.d, qt5ct, qt6ct |
| `terminal` | `~/.config/kitty`, fastfetch, cava |
| `apps` | waypaper, matugen, Thunar, mimeapps.list, user-dirs.dirs, git/ignore |
| `editors` | Code/Cursor `settings.json`, `keybindings.json`, optional `snippets/` |
| `local-bin` | `desktop-shell` and its zsh completion, `toggle-wlsunset`, profile-selected Waybar theme hook |
| `media` | `~/Pictures/wallpapers` |

`~/.zshrc.local` is handled only when the `shell` group is selected:

- Missing file: created from `templates/zshrc.local.example`
- Existing regular file: kept
- Existing symlink: backed up and replaced with a real file from the template

`chmod +x` on local-bin scripts runs only when the `local-bin` group is selected.

With the Waybar or dual profile, when Wallpaper Console Rust is installed,
syncing the desktop/apps/local-bin
groups enables its post-apply hook, stores the synchronized helper as an
absolute command path, and enables login restore. The helper passes the XDG
matugen config explicitly, verifies `waybar/colors.css` was generated, and
restarts Waybar only when it was already running. The generated
`waybar/colors.css` is preserved during update and snapshot; the committed copy
is used only as a first-install seed.

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
| `quickshell-build.txt` | QuickShell build/runtime dependencies | QuickShell or dual profile |
| `quickshell-source.conf` | Pinned QuickShell fork and commit | source lock, not a package list |

By default, the installer restores a portable software set. Machine-local packages are listed separately and skipped unless you pass `--full-packages` or choose them in interactive mode.

Regenerate the manifests from the current machine:

```bash
./install.sh --export-packages
```

The AUR/foreign manifest is rebuilt only from the current successful
`pacman -Qqem` result. Packages removed from the machine are removed from the
manifest; if pacman cannot provide a complete result, export stops before
overwriting any manifest.

## Snapshot Current Machine

Use this after changing configs or installing/removing packages:

```bash
./install.sh --snapshot
```

The snapshot command refreshes `packages/*.txt` and managed config files from this machine into the repo, runs safety checks (including secret markers / token shapes in managed files), prints a dry-run plan for what install would do on `$HOME` (home is not modified), then asks whether to commit and push when run in a TTY. It stages only snapshot-managed files and never uses `git add .`. Secrets belong in `~/.zshrc.local`, which is never snapshotted; if a secret is found in tracked configs, snapshot fails.

Use `--no-commit` to update files only, `--commit` to commit without pushing, and `--push` to request commit+push explicitly.

## Update From Git

Use this on another machine after pushing a snapshot:

```bash
./install.sh --update
```

By default, update pulls with `git pull --ff-only` and applies configs only. In a terminal it asks whether to snapshot and push the current machine before pulling. Use `--with-packages` to also install package manifests. Config mappings whose content and permissions already match are skipped before backup/copy, while changed paths keep the existing full backup and rollback behavior. Official/AUR classification loads the local pacman repository index once instead of running one query per package.

Install software without touching configs:

```bash
./install.sh --packages-only --yes
```

Official packages are installed with:

```bash
sudo pacman -S --needed ...
```

AUR packages use `paru` or `yay` when included, preferring `paru`. If neither helper exists, the installer can bootstrap `paru` from AUR after installing `git` and `base-devel`. When AUR is skipped, those packages are listed and not installed.

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

Unexpected install failures print the log path and, when available, the backup/rollback path. The installer does **not** auto-rollback on failure; run `rollback.sh` yourself if needed.

## Doctor

Run diagnostics without changing configs:

```bash
./install.sh --doctor
```

Doctor checks Arch OS, required tools, AUR helper presence, login shell, desktop tools, managed path presence/symlink safety, backup/rollback availability, and reuses the post-install verification checks.

## Uninstall

Remove managed configs without touching OS packages or `~/.zshrc.local`:

```bash
# Archive managed configs under ~/.dotfiles-backups, then remove them
./install.sh --uninstall

# Restore the latest install backup
./install.sh --uninstall restore

# Remove managed configs and all ~/.dotfiles-backups (final archive under ~/)
./install.sh --uninstall purge
# or
./install.sh --purge --yes
```

`--dry-run` works with uninstall modes and only prints planned removals.
Safe uninstall also removes the saved shell profile and a clean managed
QuickShell checkout. A checkout with local changes or a different origin is
kept and reported.

## Verification

After syncing, the installer runs checks for the selected config groups:

- `zsh -n ~/.zshrc` (shell group)
- `niri validate -c ~/.config/niri/config.kdl` (desktop group)
- `fastfetch --version`, `kitty --version`, and the selected shell binaries
- QuickShell source, `key`, and user-level QML modules for QuickShell/dual
- Checks that restored paths are real files/directories, not symlinks

Missing tools are reported as `SKIP` when packages were not installed.

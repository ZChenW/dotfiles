# dotfiles

Arch Linux desktop dotfiles for zsh, niri, Waybar, kitty, fastfetch, and related local scripts.

## Install

Interactive installer (default in a terminal):

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh
```

Non-interactive one-shot restore (scripts, CI, new machine):

```bash
./install.sh --dry-run --yes
./install.sh --yes
```

This installs the portable software set from `packages/` and restores configs. Existing files are backed up to `~/.dotfiles-backups/` before copying.

In a terminal, `./install.sh` walks through install mode, software scope, config groups, and a final confirmation. Pipe or redirect stdin without `--yes` and the installer exits with an error.

## Installer Modes

```bash
./install.sh                  # interactive: choose packages and config groups
./install.sh --yes            # non-interactive full install
./install.sh --packages-only  # software only, no config restore
./install.sh --skip-packages  # config restore only
./install.sh --full-packages  # also install machine-local packages
./install.sh --no-aur         # skip AUR packages
./install.sh --export-packages
```

By default, `packages/arch-machine-local.txt` is skipped. That file contains kernel, firmware, boot loader, GPU driver, and audio stack packages that should be chosen per machine.

In interactive mode, AUR packages are off by default. With `--yes`, AUR packages are installed unless you pass `--no-aur`.

## Config Groups

Config restore is grouped so you can sync only what you need:

| Group | Contents |
|-------|----------|
| `shell` | `.zshrc`, `.zshrc.local` |
| `desktop` | niri, waybar, fcitx5, mako, environment.d, qt5ct, qt6ct |
| `terminal` | kitty, fastfetch, cava |
| `apps` | waypaper, Thunar, mimeapps.list, user-dirs.dirs, git/ignore |
| `editors` | Code/Cursor settings, keybindings, optional snippets |
| `local-bin` | `inir`, `toggle-niri-shell` |

Interactive mode prompts for groups (default: all). Non-interactive `--yes` restores all groups unless `--packages-only` is used.

## Dry Run

```bash
./install.sh --dry-run        # interactive preview after prompts
./install.sh --yes --dry-run  # non-interactive preview
./install.sh --packages-only --yes --dry-run
```

## Regenerate Package Lists

On the current machine:

```bash
./install.sh --export-packages
```

Review `packages/arch-apps.txt`, `packages/arch-aur.txt`, and the manual-review summary before committing changes.

## Notes

- Restores real files and directories, not symlinks.
- Also restores selected editor, input method, notification, Qt/GTK, MIME, and Cava config. Browser/session/auth state is intentionally excluded.
- First version supports Arch Linux only.
- Private machine values go in `~/.zshrc.local`.

# dotfiles

Arch Linux desktop dotfiles for zsh, niri, Waybar, kitty, fastfetch, and related local scripts.

## Install

Recommended flow on a new machine:

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh --dry-run
./install.sh --yes
```

This installs the portable software set from `packages/` and restores configs. Existing files are backed up to `~/.dotfiles-backups/` before copying.

## Package Modes

```bash
./install.sh                  # recommended software + config restore
./install.sh --packages-only  # software only, no config restore
./install.sh --skip-packages  # config restore only
./install.sh --full-packages  # also install machine-local packages
./install.sh --export-packages
```

By default, `packages/arch-machine-local.txt` is skipped. That file contains kernel, firmware, boot loader, GPU driver, and audio stack packages that should be chosen per machine.

## Dry Run

```bash
./install.sh --dry-run
./install.sh --packages-only --dry-run
```

## Regenerate Package Lists

On the current machine:

```bash
./install.sh --export-packages
```

Review `packages/arch-apps.txt`, `packages/arch-aur.txt`, and the manual-review summary before committing changes.

## Notes

- Restores real files and directories, not symlinks.
- First version supports Arch Linux only.
- Private machine values go in `~/.zshrc.local`.

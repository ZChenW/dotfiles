# dotfiles

Arch Linux desktop dotfiles for zsh, niri, Waybar, kitty, fastfetch, and related local scripts.

## Install

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh
```

The installer backs up existing files to `~/.dotfiles-backups/` before copying anything.

## Dry Run

```bash
./install.sh --dry-run
```

## Notes

- Restores real files and directories, not symlinks.
- First version supports Arch Linux only.
- Private machine values go in `~/.zshrc.local`.

# dotfiles

My Arch Linux desktop dotfiles.

## Install

```bash
git clone git@github.com:ZChenW/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh
```

Preview first:

```bash
./install.sh --dry-run
```

## Commands

```bash
./install.sh --yes            # non-interactive install
./install.sh --skip-packages  # configs only
./install.sh --packages-only  # packages only
./install.sh --no-aur         # skip AUR
./install.sh --full-packages  # include machine-local packages
./install.sh --export-packages
```

## Notes

- Arch Linux only.
- Installs real files, not symlinks.
- Existing files are backed up to `~/.dotfiles-backups/`.
- Private local values belong in `~/.zshrc.local`.
- Full details: `docs/INSTALL.md`.

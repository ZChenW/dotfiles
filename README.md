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
./install.sh                         # interactive install
./install.sh --yes                   # non-interactive install
./install.sh --dry-run               # preview install
./install.sh --skip-packages         # restore configs only
./install.sh --packages-only         # install packages only
./install.sh --no-aur                # skip AUR packages
./install.sh --full-packages         # include machine-local packages

./install.sh --snapshot              # capture this machine, then ask commit+push
./install.sh --snapshot --no-commit  # capture only
./install.sh --snapshot --commit     # capture and commit
./install.sh --snapshot --push       # capture, ask, then commit+push

./install.sh --update                # pull latest dotfiles and apply configs
./install.sh --update --with-packages # pull and install packages too
./install.sh --update --yes          # non-interactive update

./install.sh --export-packages       # refresh package manifests only
```

## Notes

- Arch Linux only.
- Installs real files, not symlinks.
- Existing files are backed up to `~/.dotfiles-backups/`.
- Private local values belong in `~/.zshrc.local`.
- Full details: `docs/INSTALL.md`.

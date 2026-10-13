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
./install.sh                         # interactive operation menu
./install.sh --menu                  # force the operation menu
./install.sh --yes                   # non-interactive install
./install.sh --dry-run               # preview install
./install.sh --install-profile standard --yes
./install.sh --install-profile lightweight --yes
./install.sh --skip-packages         # restore configs only
./install.sh --packages-only         # install packages only
./install.sh --no-aur                # skip AUR packages
./install.sh --full-packages         # include machine-local packages

./install.sh --snapshot              # capture this machine, then ask commit+push
./install.sh --snapshot --no-commit  # capture only
./install.sh --snapshot --commit     # capture and commit
./install.sh --snapshot --push       # capture, ask, then commit+push

./install.sh --update                # pull and apply saved profile + configs
./install.sh --update --yes          # non-interactive update

./install.sh --export-packages       # refresh package manifests only
```

## Notes

The desktop is niri with Waybar. Each job has one owner:

| Job | Owner |
| --- | --- |
| Idle timeouts, locking, idle hibernate | [IdleFlow](https://github.com/ZChenW/IdleFlow) (`idled`, `idlectl`), installed separately; the lock screen is `swaylock-effects` |
| Power menu | `power-menu` (wlogout), opened from the rightmost Waybar button |
| Wallpaper | waywallen, installed separately |
| Colours | `waywallen-theme-sync`: matugen renders `~/.config/waywallen-theme/templates` from the wallpaper on the focused display |
| File managers | Nautilus and yazi |

Every lock goes through `idlectl lock`; sleep means hibernate, and suspend is
turned off (see `docs/INSTALL.md`).
Do not add a second idle daemon, locker or theme hook beside these.

- Arch Linux only.
- Installs real files, not symlinks.
- Existing files are backed up to `~/.dotfiles-backups/`.
- Private local values belong in `~/.zshrc.local`.
- Standard is the default complete portable scope; Lightweight is the
  X230-friendly Waybar daily-development scope.
- The selected installation profile is saved only after a successful real
  install and is reused by Update and Snapshot.
- Update only consumes repository state. Snapshot is the explicit publication
  flow and updates only the active profile's package manifests.
- Profile switching never removes installed packages.
- Full details: `docs/INSTALL.md`.

# Install Guide

This repository restores an Arch Linux desktop setup with zsh, niri, Waybar,
a wlogout power menu, wallpaper-driven colours, kitty, fastfetch, and local
launcher scripts.

## Supported OS

Arch Linux only. The installer checks `/etc/os-release` and exits on other distributions.

## Fresh Arch Install

`bootstrap/arch-install.sh` is the step before `install.sh`: it turns an
empty disk into a bootable Arch system and hands over to `install.sh`.

Before booting the ISO on a machine that also runs Windows:

- Save the BitLocker recovery key if Windows uses BitLocker or device
  encryption (Settings > Privacy & security > Device encryption, or
  https://aka.ms/myrecoverykey). Turning Secure Boot off, and starting Windows
  from the GRUB menu, can make Windows ask for it.
- Turn Secure Boot off in the firmware; the ISO and this GRUB are not signed.
  Starting Windows from the firmware's own boot menu instead of GRUB avoids
  the BitLocker prompt.

Run it from the Arch live ISO booted in UEFI mode. The ISO can be written to
a USB stick, or copied as a file onto a Ventoy stick; either way the script
recognizes the stick and never offers it as a target.

```bash
iwctl station wlan0 connect <SSID>     # Wi-Fi only; wired works by itself
curl -LO https://raw.githubusercontent.com/ZChenW/dotfiles/main/bootstrap/arch-install.sh
bash arch-install.sh --dry-run          # optional: print every step
bash arch-install.sh
```

The live console cannot show Chinese, so every prompt is in English.

To work from another computer (copy and paste, or a coding agent there), set
a temporary root password on the live ISO with `passwd` and find its address
with `ip -br a`. The live system runs from RAM and `sshd` is already running,
so this works before any disk is touched. Then, from the other computer:

```bash
scp bootstrap/arch-install.sh root@<ip>:   # no need to push first
ssh -t root@<ip> bash arch-install.sh      # -t: the prompts need a terminal
```

Type the passwords yourself. The live password and SSH host key are new on
every boot; `-o UserKnownHostsFile=/dev/null` keeps them out of known_hosts.

It asks for the disk, hostname, user name, password, whether to encrypt, the
time zone and the installation profile, prints a plan, and erases the disk
only after you type the disk name. It never touches other disks. With Windows
on another disk, os-prober adds it to the GRUB menu.

What it installs:

| Part | Choice |
|------|--------|
| Partitions | 1 GiB EFI partition at `/boot`, the rest btrfs |
| Encryption | LUKS2 on the btrfs partition unless you answer `no`; the password is asked at every boot |
| Subvolumes | `@` `/`, `@home`, `@snapshots` `/.snapshots`, `@log`, `@pkg` (pacman cache), `@swap` |
| Swap | A swap file as large as RAM in `@swap`, so hibernate fits |
| Boot | GRUB, plus the removable fallback path; `grub-btrfs` lists snapshots in the menu |
| Snapshots | snapper `root` config, timeline timers, `snap-pac`, and a "fresh install" snapshot |
| Packages | `paccache.timer` keeps the last three versions in `@pkg` |
| Hardware | `intel-ucode` or `amd-ucode`; `nvidia-open`, `vulkan-radeon` or `vulkan-intel` from `lspci`; `nvidia-prime` for hybrid graphics |
| System | NetworkManager, bluez, PipeWire, greetd with tuigreet, multilib enabled, `en_US` and `zh_CN` locales; the `iTCO_wdt` and `sp5100_tco` watchdog drivers are blacklisted, since `nowatchdog` alone does not stop them |
| User | In `wheel` with sudo, login shell zsh; root is locked |

It owns what `packages/arch-machine-local.txt` lists, so a new machine does
not need `--full-packages`. `nvidia-open` needs an RTX 20 / GTX 16 series
card or newer.

Snapshot entries in the GRUB menu boot the current kernel from `/boot`, which
is the EFI partition and is in no snapshot. A snapshot taken before a kernel
update has the older kernel's modules, so it may boot without some drivers,
including the `vfat` one that mounts `/boot`. Use such a boot to look around
and copy files. Rolling the system back to a snapshot is a manual step from
the live ISO and is not automated here.

The repository is cloned to `~/Projects/dotfiles` over HTTPS, with an SSH push
URL. On the first login on tty1, `~/.dotfiles-first-boot` waits for the
network (opening `nmtui` when there is none), runs
`./install.sh --install-profile <profile> --yes`, regenerates the GRUB menu
from the running system, enables greetd and reboots into the login screen. If `install.sh` fails it runs again at the next tty1
login; `rm ~/.dotfiles-first-boot` stops that.

Every question can be answered in advance with an environment variable:
`ARCH_INSTALL_DISK`, `ARCH_INSTALL_HOSTNAME`, `ARCH_INSTALL_USER`,
`ARCH_INSTALL_PASSWORD`, `ARCH_INSTALL_ENCRYPT` (`yes`/`no`),
`ARCH_INSTALL_LUKS_PASSWORD`, `ARCH_INSTALL_TIMEZONE`, `ARCH_INSTALL_PROFILE`,
`ARCH_INSTALL_SWAP_GIB` and `ARCH_INSTALL_REBOOT`. `ARCH_INSTALL_KERNEL_ARGS`
adds kernel parameters. Erasing still needs `ARCH_INSTALL_CONFIRM=<disk>`.

If anything fails, run the script again; it unmounts and starts over. Because
root is locked, repairs that need a root shell are done from the live ISO.

Test hibernate once on a new machine: `systemctl hibernate`, power on, and
check the session is still there. In a QEMU test VM without encryption the
image always loaded, but the machine reset about 0.3 s later whenever the
initrd resumed within the first few seconds of boot. With LUKS (the password
prompt delays the resume) or with a 10 second delay it resumed every time;
waiting for `udevadm settle` did not help. If a real machine shows the same,
delay only resume boots (systemd starts this service only when a hibernation
image is waiting):

```bash
sudo mkdir -p /etc/systemd/system/systemd-hibernate-resume.service.d
printf '[Service]\nExecStartPre=/usr/bin/sleep 10\n' |
    sudo tee /etc/systemd/system/systemd-hibernate-resume.service.d/delay.conf
printf 'FILES=(/etc/systemd/system/systemd-hibernate-resume.service.d/delay.conf)\nBINARIES=(sleep)\n' |
    sudo tee /etc/mkinitcpio.conf.d/20-resume-delay.conf
sudo mkinitcpio -P
```

## Quick Start

Interactive flow (default in a terminal):

```bash
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh
```

Non-interactive flow for scripts or a new machine:

```bash
./install.sh --install-profile standard --dry-run --yes
./install.sh --install-profile standard --yes
./install.sh --install-profile lightweight --dry-run --yes
./install.sh --install-profile lightweight --yes
```

Preview planned changes without modifying `$HOME`:

```bash
./install.sh --yes --dry-run
```

## Interactive Installer

With no arguments in a terminal, `./install.sh` first offers install, update,
snapshot, package export, doctor, uninstall, or exit. `--menu` opens the same
operation menu explicitly.

After choosing Install, choose an installation profile first:

- **Standard** is the default complete portable software scope.
- **Lightweight** is the X230-friendly daily development scope. It keeps
  Firefox, Nautilus, VS Code, Neovim, Vim, Codex, Kitty, Zsh, the Node/Python
  toolchain, Chinese input, fonts, Waybar, and every managed configuration
  group including wallpapers. It excludes games, Office, duplicate
  browsers, communication clients, KDE applications, heavyweight media tools,
  and specialist toolchains.

Then choose **Automatic** (recommended) or **Customize**. Automatic applies the
profile defaults and presents one final review. Customize exposes the existing
package and configuration-group controls. Lightweight never offers
machine-local packages.

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
| `./install.sh --install-profile standard --yes` | Explicit Standard install |
| `./install.sh --install-profile lightweight --yes` | Explicit Lightweight install |
| `./install.sh --packages-only` | Install packages only |
| `./install.sh --skip-packages` | Restore configs only |
| `./install.sh --full-packages` | Include `packages/arch-machine-local.txt` |
| `./install.sh --no-aur` | Skip AUR packages |
| `./install.sh --export-packages` | Regenerate `packages/*.txt` from this machine |
| `./install.sh --doctor` | Diagnostics only (tools, configs, backups, validation) |
| `./install.sh --uninstall` | Safe uninstall: archive then remove managed configs |
| `./install.sh --uninstall restore` | Run the latest install `rollback.sh` |
| `./install.sh --uninstall purge` / `--purge` | Remove managed configs and all install backups |

Other flags:

- `--yes` — non-interactive mode with recommended defaults
- `--restore-only` — same as `--skip-packages`, and skip optional service actions
- `--dry-run` — preview actions without modifying `$HOME` (also works with `--uninstall`)

Before install, snapshot, update, doctor, or uninstall, the installer runs a **preflight** check for required host tools (`bash`, `sudo`, `pacman`, `rsync`, `install`, `git`, `tee`, and `tar` for uninstall). Missing tools fail early with an install hint.

With `--yes` and Automatic, AUR packages required by the selected profile are
installed by default. Pass `--no-aur` to continue without them; the plan lists
the capabilities that will be unavailable. If AUR is enabled and neither
`paru` nor `yay` is available, the installer bootstraps `paru` in `--yes` mode
or asks before doing so in Customize.

Before a real package install starts, the installer asks the AUR RPC for every
selected AUR name in one exact-match batch. Confirmed missing names stop the
install before either package manager writes; if the RPC itself is unavailable,
the installed AUR helper performs the final check. Package-manager output stays
visible and is also copied to the install log for failure diagnosis.

Snapshot canonicalizes known retired package names to their current install
targets so an older machine cannot reintroduce stale aliases into either
profile. It reports legacy packages as out-of-profile but never removes them.

The selected installation profile is stored under
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/install-profile` only after a
successful real install. An explicit `--install-profile` wins over saved state;
saved state wins over the Standard default. Dry runs, cancellations, and
failures never update it.

There is one desktop: niri with Waybar. The earlier Waybar/QuickShell switcher
(`desktop-shell`) is retired; an install or update removes its launcher,
completion and the old Wallpaper Console theme hook from `~/.local`.

Two pieces are installed separately and only referenced here:

- **IdleFlow** owns idle timeouts, locking and the idle hibernate. niri, Waybar
  and the power menu lock through `idlectl lock`; nothing else may run its own
  idle timers or locker. The lock screen is `swaylock-effects`.
- **Suspend is not used.** This laptop only has suspend-to-idle, and it does
  not resume while the NVIDIA GPU drives the displays. The power menu has no
  suspend button, IdleFlow hibernates instead, and
  `/etc/systemd/sleep.conf.d/10-no-suspend.conf` (not managed here) turns the
  suspend verbs off system-wide.
- **waywallen** draws the wallpaper. `waywallen-theme-sync` follows it.

## Config Groups

| Group | Restored paths |
|-------|----------------|
| `shell` | `~/.zshrc`, `~/.zshrc.local` |
| `desktop` | `~/.config/niri`, Waybar, wlogout, `waywallen-theme`, the `waywallen-theme-sync` user service, the IdleFlow policy, fcitx5, mako, environment.d, qt5ct, qt6ct |
| `terminal` | `~/.config/kitty`, fastfetch, cava |
| `apps` | mimeapps.list, user-dirs.dirs, git/ignore |
| `editors` | Code/Cursor `settings.json`, `keybindings.json`, optional `snippets/` |
| `local-bin` | `toggle-wlsunset`, `power-menu`, `kitty-mode` (what `Mod+T` opens), `waywallen-theme-sync` |
| `media` | `~/Pictures/wallpapers` |

`~/.zshrc.local` is handled only when the `shell` group is selected:

- Missing file: created from `templates/zshrc.local.example`
- Existing regular file: kept
- Existing symlink: backed up and replaced with a real file from the template

`chmod +x` on local-bin scripts runs only when the `local-bin` group is selected.

Syncing the desktop group enables `waywallen-theme-sync.service` (skipped
with `--restore-only`). It renders every template in
`~/.config/waywallen-theme/templates` to the path listed for it in
`~/.config/waywallen-theme/config.toml`, which also holds the scheme and mode,
and rewrites `~/.config/matugen/config.toml` on each run.

Files it generates are preserved during update and never captured by a
snapshot: `waybar/colors.css`, `wlogout/colors.css` and
`niri/theme-colors.kdl`. The committed `colors.css` copies are used only as
first-install seeds. `~/.config/swaylock/config` is generated too and uses
`swaylock-effects` options, so plain `swaylock` cannot read it.

## Package Manifests

Software is managed through files in `packages/`:

| File | Purpose | Default install |
|------|---------|-----------------|
| `arch-essential.txt` | Installer-required and core shell/desktop packages | yes |
| `arch-desktop.txt` | Fonts, portals, Bluetooth, desktop utilities | yes |
| `arch-apps.txt` | User applications from official repositories | yes |
| `arch-aur.txt` | AUR and foreign packages | Standard unless `--no-aur` |
| `arch-lightweight.txt` | Lightweight official and AUR allowlist | Lightweight only |
| `arch-machine-local.txt` | Kernel, firmware, boot, GPU, audio stack | no |
| `arch-exclude.txt` | Packages excluded from automation | never |

Standard restores the existing portable software set. Lightweight reads only
`arch-lightweight.txt`. Machine-local packages are skipped unless Standard is
combined with `--full-packages`; that flag is rejected for Lightweight. The
installer never removes packages when switching profiles and reports
out-of-profile packages for manual review.

Regenerate the manifests from the current machine:

```bash
./install.sh --export-packages
```

The AUR/foreign manifest is rebuilt only from the current successful
`pacman -Qqem` result. Packages removed from the machine are removed from the
manifest; if pacman cannot provide a complete result, export stops before
overwriting any manifest.

## Coding Agents

Claude Code and Codex come from their vendors' own installers, not from
pacman or the AUR: `extra/openai-codex` and AUR `claude-code` are third-party
builds, and `openai-codex` is listed in `arch-exclude.txt`. After the packages,
Install and Update run whichever installer is missing:

```bash
curl -fsSL https://claude.ai/install.sh | bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

Both put the binary in `~/.local/bin` and keep it updated. An agent already on
`PATH` from another source, such as an npm-installed Codex, is left alone. A
failed download is a warning, not an install failure. `--skip-packages` skips
this step.

## Snapshot Current Machine

Use this after changing configs or installing/removing packages:

```bash
./install.sh --snapshot
```

Snapshot is the publication flow. It requires a clean repository, pulls with
`git pull --ff-only`, captures managed config files, runs safety checks
(including secret markers/token shapes), shows the diff, and asks once before
commit/push. It never stashes, resets, merges, or guesses through divergence.

Package ownership is profile-specific. Standard updates only
`arch-essential.txt`, `arch-desktop.txt`, `arch-apps.txt`, `arch-aur.txt`,
`arch-machine-local.txt`, and `arch-exclude.txt`. Lightweight updates only
`arch-lightweight.txt`, using explicitly installed packages while filtering
machine-local packages, base packages, AUR helpers, and global exclusions. A
no-op Snapshot skips commit and push. Snapshot stages only managed paths and
never uses `git add .`.

Use `--no-commit` to update files only, `--commit` to commit without pushing, and `--push` to request commit+push explicitly.

## Update From Git

Use this on another machine after pushing a snapshot:

```bash
./install.sh --update
```

Update is the consumption flow. It requires a clean repository, pulls with
`git pull --ff-only`, reuses the saved installation profile, applies every
managed configuration group including wallpapers, installs missing profile
packages, and verifies the result. It never invokes Snapshot, commits, pushes,
removes packages, runs `pacman -Syu`, or performs a full AUR upgrade. Dirty or
diverged repositories fail without stash/reset/merge. `--with-packages` and
`--no-snapshot-prompt` remain accepted only as compatibility no-ops.

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

Doctor checks Arch OS, required tools, AUR helper presence, login shell,
desktop tools, managed path presence/symlink safety, backup/rollback
availability, and reuses the post-install verification checks. On machines
with 8 GB RAM or less and no swap/zram, it emits an advisory warning that
Firefox, VS Code, and Codex may create memory pressure; this warning alone does
not make Doctor fail.

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
Safe uninstall also removes state files left by the retired desktop shell
switcher.

## Verification

After syncing, the installer runs checks for the selected config groups:

- `zsh -n ~/.zshrc` (shell group)
- `niri validate -c ~/.config/niri/config.kdl` (desktop group)
- `fastfetch --version`, `kitty --version`, `waybar --version`
- Checks that restored paths are real files/directories, not symlinks

Missing tools are reported as `SKIP` when packages were not installed.

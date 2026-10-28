# macOS

The Arch desktop cannot run on Apple Silicon M3 and newer, so on a Mac the
repository adds a thin layer on top of stock macOS that keeps the niri feel:
OmniWM for the scrolling layout, kitty, and the same keys. Everything else is
left to macOS. All of it can be undone with one command.

```bash
./install.sh --dry-run          # preview (install.sh hands over to scripts/macos.sh)
./install.sh                    # trial: packages + configs, no system settings
./install.sh apply --system     # also change the macOS settings below
./install.sh status
./install.sh rollback --system-only   # undo the macOS settings, keep OmniWM
./install.sh rollback                 # back to stock macOS
```

## What owns what

| Linux | macOS |
| --- | --- |
| niri | OmniWM (`configs/macos/omniwm`); focus follows the mouse as in niri, and `app-rules.toml` floats small utility windows (System Settings, Calculator, Installer, Archive Utility, System Information) |
| niri focus ring | OmniWM border |
| Waybar | macOS menu bar + OmniWM workspace bar |
| kitty | kitty (`configs/macos/kitty/kitty.conf` + the shared theme files and `focus_opacity.py`, which makes unfocused windows translucent) |
| niri `spawn` binds | skhd (`configs/macos/skhd/skhdrc`) |
| fuzzel | Spotlight on Option+D |
| clipse | Spotlight clipboard history |
| mako | Notification Center |
| IdleFlow, swaylock | macOS lock and sleep settings; Control+Command+Q locks |
| fcitx5 + Rime (rime-ice) | Squirrel + rime-ice, pinned to a tag; left Shift switches Chinese/English (macOS Pinyin has no Shift switch) |
| wlogout | Apple menu |
| screenshots | Command+Shift+4 / 5 |
| wlsunset | Night Shift |
| waywallen + matugen | macOS wallpaper and accent colour; kitty keeps the last matugen colours |
| kanshi, brightness, volume | macOS |
| zsh (`configs/home/.zshrc`) | the same file: its `linux*` blocks hold the pacman aliases, `open=xdg-open`, conda, npm/bun paths and Linux-only tools; macOS gets brew aliases and zoxide for `z` |
| neovim + nvimdots | nvimdots pinned to a commit of its `main` branch (Neovim 0.12), plugins restored from its `lazy-lock.json` |
| fastfetch, git ignore | the shared files |

Only `packages/macos-casks.txt` (OmniWM, kitty, Maple Mono NF, Squirrel) and
`packages/macos-formulae.txt` (skhd, the zsh plugins and CLI tools, Neovim and
what nvimdots calls out to) are installed. OmniWM cannot start
programs from a hotkey, so skhd binds the few that do; Shortcuts.app keyboard
shortcuts were tried first and never fired.

## Keys

Mod is the **left** Option key. Right Option stays Alt/Meta inside kitty
(`macos_option_as_alt right`), so shell and editor Alt bindings keep working.
The bindings live in `configs/macos/omniwm/hotkeys.tsv`; any OmniWM action not
listed there is unassigned. OmniWM allows one binding per action, so the
arrow-key variants of the niri binds are not bound.

| Keys | Action |
| --- | --- |
| Mod+H/J/K/L | focus column left / window down / up / column right |
| Mod+Ctrl+H/J/K/L | move column left / window down / up / column right |
| Mod+Home/End, Mod+Ctrl+Home/End | first / last column, move there |
| Mod+Shift+H/L | previous / next monitor |
| Mod+Shift+Ctrl+H/J/K/L | move window to monitor |
| Mod+U/I, Mod+Ctrl+U/I | next / previous workspace, move column there |
| Mod+1–9, Mod+Ctrl+1–9 | workspace N, move column there |
| Mod+O | overview |
| Mod+Q | close window |
| Mod+R, Mod+Shift+R, Mod+Ctrl+R | cycle column width, cycle window height, reset height |
| Mod+F, Mod+Shift+F, Mod+Ctrl+F | maximize column, fullscreen, expand to free width |
| Mod+C, Mod+Ctrl+C | center column, center visible columns |
| Mod+Minus/Equal, with Shift | column width, window height ±10% |
| Mod+[ / Mod+] | consume window into column / expel it |
| Mod+V, Mod+Shift+V | toggle floating, switch floating/tiling focus |
| Mod+W | tabbed column |
| Mod+Shift+/ | command palette (search every action) |
| Mod+Tab | previously focused window |
| Mod+T | new kitty window (skhd) |
| Option+D | Spotlight (`--system`) |


Trackpad: 3 fingers sideways scroll columns, 3 fingers up/down switch
workspaces, 4 fingers up opens the overview. `--system` turns off the macOS
gestures on those fingers.

## Manual steps

macOS keeps these out of reach of scripts:

1. System Settings > Privacy & Security > Accessibility: turn on OmniWM and
   skhd; Input Monitoring and Screen & System Audio Recording (window
   previews in the workspace bar and the overview): turn on OmniWM. Rollback
   resets OmniWM's; remove
   skhd from the list by hand, as macOS only lets scripts reset app bundles.
   skhd is built from source, so an upgrade needs the switch turned on again.
2. Squirrel: log out and in after its first install, then System Settings >
   Keyboard > Input Sources > Edit > + > Chinese, Simplified > Squirrel.
   Remove "Pinyin - Simplified", and under "All Input Sources" turn off "Use
   the Caps Lock key to switch to and from U.S.". After a rollback, undo
   these three by hand.

## Known gaps

- Switching workspaces from the keyboard has no animation: OmniWM 0.7.6
  switches instantly and has no setting for it. Swiping between workspaces
  does animate.
- macOS still moves windows on its own a little; OmniWM keeps a sliver of
  off-screen windows visible.

## How apply and rollback work

OmniWM rejects a `settings.toml` with any missing key or unknown hotkey id, so
the repository does not ship one. On first run OmniWM writes its own defaults;
`scripts/macos/omniwm_patch.py` replaces the hotkeys and sets the keys in
`configs/macos/omniwm/settings.tsv`, after checking every id against that
generated file.

`--system` sets the preferences in `configs/macos/system-defaults.tsv` through
`scripts/macos/prefs.py`, which saves each key's old value (or its absence)
first.

Everything apply touches is recorded in `~/.local/state/dotfiles-macos`:

| Record | Rollback |
| --- | --- |
| casks and formulae it installed | uninstalls those only; anything you already had stays |
| taps it added, formulae it trusted | untaps and untrusts them |
| services it started (skhd) | removes the launchd service |
| login items it added (OmniWM) | removes them |
| files, with a backup of what was there | restores the backup, or removes a file that was new |
| paths the apps created on first run | moves them to the backup directory |
| preferences, with their old values | restores each value, or deletes a key that was unset |

Rollback never deletes: removed files go to `~/.dotfiles-backups/macos-rollback-*`,
together with the record. `tests/test_macos.sh` runs apply and rollback against
stubs and checks the home directory ends up as it started.

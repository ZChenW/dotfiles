# Fixed icon size for niri-taskbar

The bundled `configs/config/waybar/libniri_taskbar.so` is built from
[LawnGnome/niri-taskbar](https://github.com/LawnGnome/niri-taskbar/tree/c530349fae638141ec58a9d4db0816d950a9295a),
revision `c530349fae638141ec58a9d4db0816d950a9295a`, plus `fixed-icon-size.patch`.
The patch also pins `niri-ipc` to **26.4.0** for this machine's Niri 26.04
and updates the lockfile. Upstream's 25.11 protocol dependency otherwise exits
the event stream on the new `CastsChanged` event, leaving a stale initial list.
Upstream source is MIT licensed; its license is included in this directory.

Upstream sizes each icon from its button's allocated height. When another
module temporarily makes the bar taller, the resized image retains that new
minimum height after the other module shrinks. The original library ignores
the `icon-size` setting already present in our configuration.

The patch supports `icon-size` (also `icon_size`) in logical pixels, bounded to
1–256. Without this option, upstream's automatic sizing is retained. The
existing setting of 18 now produces 18px icons independently of bar height;
monitor scaling still uses upstream's scale-factor handling.

Build explicitly; this does not install or restart anything:

```sh
bash tools/niri-taskbar/build.sh /tmp/niri-taskbar-build
bash tests/test_waybar_taskbar_size.sh \
  /tmp/niri-taskbar-build/source/target/release/libniri_taskbar.so
```

The test requires a running Niri desktop, GTK 3 development libraries, Waybar,
and at least one open application. It creates a bottom overlay for under five
seconds and a short-lived normal window to check window creation, focus, and
closure events. It then adds a taller sibling, removes it, and checks both
height recovery and 18px image requisitions. It does not click anything or
replace the real bar. The test window briefly receives focus.

Verified on 2026-09-29:

- Original binary: **29 → 54 → 54px**, regression fails.
- Patched binary: **29 → 54 → 29px**, regression passes; icons request 18px.
- Live IPC: **10 → 11 → 10** task buttons when the test window opens/closes;
  the new button receives the focused class, with no IPC stream errors.
- Full diagnostic layout: **29 → 54 → 29px** with the patched binary.
- Audio, brightness, and power drawers did not independently reproduce growth.
- Installed live bar: one Waybar process, DP-8 at **2560 × 29px**, patched
  library mapped, no Niri IPC stream error.
- Original live library/config/style backup:
  `~/.local/state/dotfiles/backups/waybar-taskbar-20260929/`.

Historical live logs show repeated 29 → 42px growth. The exact initial trigger
for those past events has not been identified; this patch fixes the confirmed
taskbar feedback that prevents subsequent recovery.

When installing, replace the shared library atomically: never truncate an inode
that a running Waybar has mapped. Restart Waybar afterward to load the new code;
a CSS reload cannot replace a loaded shared library.

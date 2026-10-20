#!/usr/bin/env python3
"""Keeps whichever displays are connected usable, without touching the saved layout.

outputs.kdl holds one layout for every combination of displays, so a choice that
is right while docked can be wrong on the road:

- the laptop panel saved as off leaves a laptop-only start with nothing lit;
- positions relative to an external monitor leave a lone panel away from 0,0,
  where Chromium draws window-modal dialogs ("Leave site?") out of view and only
  the darkened window remains.

Whenever niri starts, loads its config, or a display is plugged or unplugged, this
switches the laptop panel on if nothing is lit and slides the lit displays so the
origin falls inside one of them. Both are runtime (IPC) overrides: the saved
layout stays as the display settings wrote it, and wins again on the next change.
Started by niri (spawn-at-startup); exits with niri's event stream.
"""
import json
import selectors
import subprocess
import time

import display_preview

INTERNAL = ('eDP', 'LVDS', 'DSI')
SETTLE = 1.0  # niri finishes configuring a hotplugged connector before we look


def plan(outputs):
    """Returns the `niri msg output` argument lists that make these outputs usable."""
    if not outputs:
        return []
    lit = {name: data['logical'] for name, data in outputs.items()
           if data.get('current_mode') is not None and data.get('logical')}
    if not lit:
        # Nothing to see: prefer the panel that is physically there.
        name = min(outputs, key=lambda n: (not n.startswith(INTERNAL), n))
        return [[name, 'on']]
    if any(r['x'] <= 0 < r['x'] + r['width'] and r['y'] <= 0 < r['y'] + r['height'] for r in lit.values()):
        return []
    # The leftmost display's corner becomes the origin; the arrangement is kept.
    corner = min(lit.values(), key=lambda r: (r['x'], r['y']))
    return [[name, 'position', 'set', str(r['x'] - corner['x']), str(r['y'] - corner['y'])]
            for name, r in sorted(lit.items())]


def outputs():
    return json.loads(subprocess.run(['niri', 'msg', '-j', 'outputs'], check=True,
                                     capture_output=True, text=True, timeout=5).stdout)


def settle():
    """Applies plan() until it has nothing left to do. False while a preview owns the outputs."""
    # A preview verifies the exact state it asked for; it never leaves zero displays lit.
    if display_preview.active():
        return False
    for _ in range(3):
        actions = plan(outputs())
        if not actions:
            return True
        for action in actions:
            subprocess.run(['niri', 'msg', 'output', *action], capture_output=True, timeout=5)
        time.sleep(0.3)
    return True


def main():
    events = subprocess.Popen(['niri', 'msg', '-j', 'event-stream'], stdout=subprocess.PIPE, text=True)
    hotplug = subprocess.Popen(['udevadm', 'monitor', '--udev', '--subsystem-match=drm'],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    watch = selectors.DefaultSelector()
    watch.register(events.stdout, selectors.EVENT_READ, 'niri')
    watch.register(hotplug.stdout, selectors.EVENT_READ, 'udev')
    due = time.monotonic()
    try:
        while True:
            for key, _ in watch.select(max(0, due - time.monotonic()) if due else None):
                line = key.fileobj.readline()
                if not line:
                    if key.data == 'niri':
                        return 0  # niri is gone
                    watch.unregister(key.fileobj)
                elif key.data == 'udev' or '"ConfigLoaded"' in line:
                    due = time.monotonic() + SETTLE
            if due and time.monotonic() >= due:
                try:
                    due = None if settle() else time.monotonic() + 1
                except (OSError, ValueError, subprocess.SubprocessError):
                    due = time.monotonic() + 2
    finally:
        for process in (events, hotplug):
            process.kill()


if __name__ == '__main__':
    raise SystemExit(main())

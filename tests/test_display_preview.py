#!/usr/bin/env python3
"""Display backend: previews undo cleanly, saves stay tidy, and every display combination stays usable."""
import fcntl
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'configs/config/waybar/scripts/display-backend'))
import display_guard as guard
import display_preview as preview
import niri_config as config
import niri_outputs as outputs

loader = importlib.machinery.SourceFileLoader('theme_sync', str(ROOT / 'configs/local-bin/waywallen-theme-sync'))
sync = importlib.util.module_from_spec(importlib.util.spec_from_loader('theme_sync', loader))
loader.exec_module(sync)

MODE = '2560x1440@60.000'


def output(model, enabled):
    return dict(make='Test', model=model, serial=None, current_mode=0 if enabled else None,
                modes=[dict(width=2560, height=1440, refresh_rate=60000)],
                logical=dict(x=0, y=0, scale=1.0, transform='Normal') if enabled else None)


class PreviewTest(unittest.TestCase):
    def guardian(self, live, stuck=(), **state):
        """A guardian over simulated outputs; `stuck` names outputs that ignore On."""
        self.live, self.sent = live, []
        guardian = preview.Preview.__new__(preview.Preview)
        vars(guardian).update(original={name: dict(data) for name, data in live.items()},
                              combination=preview.connection_key(live), changed=True,
                              main=None, path=Path('outputs.kdl'), original_graph=None, **state)
        guardian.check = lambda: self.live
        guardian.wait = lambda *_: None

        def ipc(request):
            if request == 'Outputs':
                return self.live
            name, action = request['Output']['output'], request['Output']['action']
            self.sent.append((name, action if isinstance(action, str) else next(iter(action))))
            if action == 'Off' or (action == 'On' and name not in stuck):
                self.live[name]['current_mode'] = 0 if action == 'On' else None
        for target, replacement in ((preview, dict(ipc=ipc)), (preview.config, dict(Graph=lambda _: None)),
                                    (preview.outputs, dict(inspect=lambda *_: []))):
            mock = patch.multiple(target, **replacement)
            mock.start()
            self.addCleanup(mock.stop)
        return guardian

    def test_revert_switches_a_newly_enabled_output_off_again(self):
        # Only the laptop was patched; the untouched external monitor is the usable alternative.
        guardian = self.guardian({'DP-7': output('External', True), 'eDP-2': output('Laptop', True)},
                                 before={'eDP-2': dict(enabled=False)})
        self.assertEqual(guardian.restore(), [])
        self.assertEqual(self.sent, [('eDP-2', 'Off')])

    def test_revert_never_switches_off_the_last_usable_output(self):
        guardian = self.guardian({'DP-7': output('External', True), 'eDP-2': output('Laptop', False)},
                                 stuck=('eDP-2',),
                                 before={'DP-7': dict(enabled=False), 'eDP-2': dict(enabled=True, mode=MODE)})
        guardian.restore()
        self.assertNotIn(('DP-7', 'Off'), self.sent)
        self.assertIsNotNone(self.live['DP-7']['current_mode'])

    def test_positions_are_applied_after_outputs_are_switched_off(self):
        # The laptop takes over the origin from the monitor that is being switched off.
        laptop = dict(enabled=True, mode=MODE, scale=1, transform='normal', position=dict(x=0, y=0), vrr='off')
        guardian = self.guardian({'DP-7': output('External', True), 'eDP-2': output('Laptop', True)},
                                 desired={'DP-7': dict(enabled=False, mode=MODE), 'eDP-2': laptop})
        guardian.apply()
        self.assertEqual([entry for entry in self.sent if entry[1] in ('Off', 'Position')],
                         [('DP-7', 'Off'), ('eDP-2', 'Position')])


def lit(x, y, width=2560, height=1440):
    return dict(current_mode=0, logical=dict(x=x, y=y, width=width, height=height))


class GuardTest(unittest.TestCase):
    def test_a_saved_off_laptop_panel_is_lit_when_it_is_alone(self):
        # The black screen of 2026-10-14: docked layout saved eDP-2 off, then booted undocked.
        self.assertEqual(guard.plan({'eDP-2': dict(current_mode=None, logical=None)}), [['eDP-2', 'on']])
        self.assertEqual(guard.plan({'DP-7': dict(current_mode=None, logical=None),
                                     'eDP-1': dict(current_mode=None, logical=None)}), [['eDP-1', 'on']])
        self.assertEqual(guard.plan({}), [])

    def test_a_lone_display_away_from_the_origin_is_moved_onto_it(self):
        self.assertEqual(guard.plan({'eDP-2': lit(2560, 179, 1706, 1066)}), [['eDP-2', 'position', 'set', '0', '0']])
        self.assertEqual(guard.plan({'DP-7': lit(-8655, -181)}), [['DP-7', 'position', 'set', '0', '0']])

    def test_a_layout_covering_the_origin_is_left_alone(self):
        self.assertEqual(guard.plan({'DP-7': lit(0, 0), 'eDP-2': lit(2560, 179, 1706, 1066)}), [])
        self.assertEqual(guard.plan({'eDP-1': lit(-1828, 0, 1828, 1142), 'DP-7': lit(0, 0)}), [])

    def test_a_shifted_pair_keeps_its_arrangement(self):
        self.assertEqual(guard.plan({'DP-7': lit(-8655, -181), 'eDP-2': lit(-6095, -2, 1706, 1066)}),
                         [['DP-7', 'position', 'set', '0', '0'], ['eDP-2', 'position', 'set', '2560', '179']])

    def test_the_guard_stands_aside_during_a_preview(self):
        with patch.object(guard.display_preview, 'active', lambda: True), \
                patch.object(guard, 'outputs', lambda: self.fail('read outputs during a preview')):
            self.assertFalse(guard.settle())


class SaveTest(unittest.TestCase):
    def test_repeated_saves_do_not_pile_up_blank_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            main = Path(directory) / 'config.kdl'
            main.write_text('include "outputs.kdl"\n')
            (Path(directory) / 'outputs.kdl').write_text(
                'output "DP-7" {\n    // kept\n    mode "2560x1440@60.000";\n    position x=5 y=5;\n}\n')
            key = config.path_key(Path(directory) / 'outputs.kdl')
            request = dict(outputs=[dict(identifier='DP-7', settings=dict(mode=MODE, position=dict(x=0, y=0)))])
            graph, saved = config.Graph(main), []
            for _ in range(3):
                saved.append(outputs.edit(graph, key, request, config))
                graph = config.Graph(main, replacements={key: saved[-1]})
            self.assertEqual(saved[0], saved[2])
            self.assertEqual(saved[0], 'output "DP-7" {\n    // kept\n    mode "2560x1440@60.000";\n'
                                       '    position x=0 y=0;\n}\n')


class RecolourTest(unittest.TestCase):
    def test_recolouring_waits_only_while_a_preview_holds_its_lock(self):
        with tempfile.TemporaryDirectory() as runtime, patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
            self.assertFalse(sync.display_preview_active())
            lock = Path(runtime) / f'clavis-display-preview-{os.getuid()}.lock'
            lock.touch(0o600)
            (Path(runtime) / 'clavis-display-test').mkdir()
            (Path(runtime) / 'clavis-display-test/control').touch()
            # A socket left behind by a killed guardian does not block colours for ever.
            self.assertFalse(sync.display_preview_active())
            held = os.open(lock, os.O_RDWR)
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertTrue(sync.display_preview_active())
            os.close(held)
            self.assertFalse(sync.display_preview_active())


if __name__ == '__main__':
    unittest.main()

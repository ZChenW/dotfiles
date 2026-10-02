#!/usr/bin/env python3
"""Exercise real GTK controls/async jobs with a simulated preview guardian."""
import copy
import importlib.util
import json
from pathlib import Path
import time
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('displays_gtk', ROOT / 'configs/config/waybar/scripts/display-settings.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
FIXTURES = ROOT / 'tests/fixtures/waybar-displays'


class DisplaysGtkTest(unittest.TestCase):
    def setUp(self):
        import warnings
        warnings.filterwarnings('ignore', category=DeprecationWarning)
        self.live = json.loads((FIXTURES / 'outputs.json').read_text())
        self.saved = dict(main='/tmp/test-niri.kdl', revision='fixture',
                          fragments=dict(outputs=dict(state='ready')),
                          outputs=json.loads((FIXTURES / 'saved.json').read_text()))
        self.state = dict(phase='confirming', remaining=9)
        self.calls = []
        self.backend_delay = 0
        self.app = module.create_application()
        from gi.repository import Gio
        self.app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
        self.app.set_application_id(module.APP_ID + '.Test' + str(time.monotonic_ns()))
        self.app.register(None)
        for name, replacement in (
                ('backend_directory', lambda: Path('/tmp')),
                ('backend', self.backend),
                ('run_json', lambda _: copy.deepcopy(self.live))):
            mock = patch.object(module, name, replacement)
            mock.start()
            self.addCleanup(mock.stop)
        self.app.do_activate()
        self.wait(lambda: bool(self.app.rows) and not self.app.busy)

    def backend(self, path, script, request):
        self.calls.append(copy.deepcopy(request))
        if script == 'niri_config.py':
            return copy.deepcopy(self.saved)
        operation = request['operation']
        if operation == 'start':
            self.state = dict(phase='confirming', remaining=9)
            return dict(token='clavis-display-test')
        if operation == 'status':
            time.sleep(self.backend_delay)
            return copy.deepcopy(self.state)
        if operation == 'keep':
            self.state = dict(phase='kept')
        elif operation == 'revert':
            self.state = dict(phase='reverted', error='Changes reverted')
        return dict(schemaVersion=1)

    def wait(self, predicate):
        from gi.repository import GLib
        end = time.monotonic() + 5
        while time.monotonic() < end:
            while GLib.MainContext.default().pending():
                GLib.MainContext.default().iteration(False)
            if predicate():
                return
            time.sleep(0.01)
        self.fail('GTK state transition timed out')

    def tearDown(self):
        if self.app.window:
            self.app.close()
            self.wait(lambda: self.app.window is None)
        self.app.executor.shutdown(wait=True)

    def start_preview(self):
        self.app.rows[0]['settings']['scale'] = 1.25
        self.app.render_state()
        self.assertTrue(self.app.apply.get_sensitive())
        self.app.apply_clicked(None)
        self.wait(lambda: self.app.phase == 'confirming' and not self.app.busy)
        self.assertIn('9', self.app.apply.get_label())

    def test_keep_and_revert_reload(self):
        self.start_preview()
        self.app.apply_clicked(None)
        self.wait(lambda: self.app.phase == 'idle' and not self.app.busy)
        self.assertEqual(self.app.message.get_text(), '已保存')
        self.start_preview()
        self.app.reset_clicked(None)
        self.wait(lambda: self.app.phase == 'idle' and not self.app.busy)
        self.assertEqual(self.app.message.get_text(), '已还原')

    def test_timeout_and_restore_errors_are_visible(self):
        self.start_preview()
        self.state = dict(phase='reverted', error='Display preview timed out')
        self.wait(lambda: self.app.phase == 'idle' and not self.app.busy)
        self.assertIn('自动还原', self.app.message.get_text())
        self.state = dict(phase='confirming', remaining=9)
        self.start_preview()
        self.state = dict(phase='reverted', error='Restore failed', restoreErrors=['output missing'])
        self.wait(lambda: self.app.phase == 'idle' and not self.app.busy)
        self.assertIn('output missing', self.app.message.get_text())

    def test_escape_while_polling_is_not_lost(self):
        from gi.repository import Gdk
        self.start_preview()
        self.backend_delay = 0.2
        self.app.poll()
        self.assertTrue(self.app.busy)
        self.assertTrue(self.app.reset.get_sensitive())
        self.app.keypress(None, SimpleNamespace(keyval=Gdk.KEY_Escape))
        self.wait(lambda: self.app.phase == 'idle' and not self.app.busy)
        self.assertTrue(any(c['operation'] == 'revert' for c in self.calls))

    def test_background_watch_preserves_interaction_and_dirty_draft(self):
        self.app.rows[0]['settings']['scale'] = 1.25
        self.app.render_state()
        self.app.watch()
        self.assertTrue(self.app.cards.get_sensitive())
        self.assertTrue(self.app.apply.get_sensitive())
        self.wait(lambda: not self.app.busy)
        self.live.pop('eDP-1')
        self.app.watch()
        self.wait(lambda: not self.app.busy)
        self.assertTrue(self.app.stale)
        self.assertEqual(self.app.rows[0]['settings']['scale'], 1.25)
        self.assertFalse(self.app.apply.get_sensitive())
        self.app.reset_clicked(None)
        self.wait(lambda: not self.app.busy)
        self.assertFalse(self.app.stale)
        self.assertEqual(len(self.app.rows), 1)

    def test_dragging_an_output_to_the_other_side_makes_an_applicable_change(self):
        external, laptop = self.app.rows
        laptop['settings']['enabled'] = True
        self.app.render_state()
        self.wait(lambda: self.app.canvas.get_allocated_width() > 1)
        canvas = self.app.canvas
        scale, shift_x, shift_y = canvas.view()
        x, y, width, height = module.output_rect(laptop['settings'])
        grab = SimpleNamespace(button=1, x=(x + width / 2) * scale + shift_x, y=(y + height / 2) * scale + shift_y)
        self.assertTrue(canvas.press(canvas, grab))
        # Drop it roughly over the external monitor's left half: it must not stay overlapping.
        left = module.output_rect(external['settings'])[0]
        drop = SimpleNamespace(button=1, x=(left - width / 4) * scale + shift_x, y=grab.y)
        canvas.motion(canvas, drop)
        canvas.release(canvas, drop)
        self.assertEqual(laptop['settings']['position']['x'], left - width)
        self.assertEqual(external['settings']['position'], external['baseline']['position'])
        self.assertTrue(self.app.apply.get_sensitive())
        self.wait(lambda: True)

    def test_all_off_disabled_and_singleton_closes_with_revert(self):
        for row in self.app.rows:
            row['settings']['enabled'] = False
        self.app.render_state()
        self.assertFalse(self.app.apply.get_sensitive())
        self.assertIn('至少', self.app.message.get_text())
        self.app.rows[0]['settings']['enabled'] = True
        self.start_preview()
        self.app.do_activate()
        self.wait(lambda: self.app.window is None)
        self.assertTrue(any(c['operation'] == 'revert' for c in self.calls))


if __name__ == '__main__':
    if len(sys.argv) == 1:
        # GApplication's registration lifecycle is process-scoped, like the app.
        cases = unittest.defaultTestLoader.getTestCaseNames(DisplaysGtkTest)
        for case in cases:
            result = subprocess.run([sys.executable, __file__, '-q', f'DisplaysGtkTest.{case}'],
                                    capture_output=True, text=True)
            if result.returncode:
                print(result.stdout + result.stderr)
                sys.exit(result.returncode)
        print(f'PASS: {len(cases)} GTK display workflow tests')
    else:
        unittest.main()

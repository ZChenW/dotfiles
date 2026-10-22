#!/usr/bin/env python3
"""Portable text rendering and the snapshot/install boundary (no live state)."""
import importlib.util
import json
import os
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('portability', ROOT / 'scripts/portability.py')
portable = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portable)


class PortabilityTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.env = patch.dict(os.environ, HOME=str(self.root / 'residents/al ex.[1]'),
                              XDG_CONFIG_HOME=str(self.root / 'settings'))
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_home_round_trip_binary_and_prefix_boundary(self):
        file = self.root / 'config.conf'
        file.write_bytes(b'path=@HOME@/icons\r\nconfig=@CONFIG_HOME@/app\r\n')
        original = file.read_bytes()
        portable.transform(file, 'render')
        self.assertIn(os.environ['HOME'].encode(), file.read_bytes())
        portable.transform(file, 'capture')
        self.assertEqual(file.read_bytes(), original)
        file.write_text(os.environ['HOME'] + '-other/file')
        portable.transform(file, 'capture')
        self.assertNotIn('@HOME@', file.read_text())
        file.write_text('/backup' + os.environ['HOME'] + '/file')
        portable.transform(file, 'capture')
        self.assertNotIn('@HOME@', file.read_text())
        binary = self.root / 'asset.png'
        binary.write_bytes(b'\x89PNG\x00@HOME@\xff')
        portable.transform(binary, 'render')
        self.assertEqual(binary.read_bytes(), b'\x89PNG\x00@HOME@\xff')

    def test_json_home_with_quotes_is_valid_and_reversible(self):
        file = self.root / 'settings.json'
        file.write_text('{"path":"@HOME@/theme"}\n')
        with patch.dict(os.environ, HOME=str(self.root / 'a"b\\c')):
            portable.transform(file, 'render')
            self.assertEqual(json.loads(file.read_text())['path'], os.environ['HOME'] + '/theme')
            portable.transform(file, 'capture')
        self.assertEqual(file.read_text(), '{"path":"@HOME@/theme"}\n')

    def test_hostname_is_one_safe_exact_component(self):
        self.assertEqual(portable.host_name('Case-Sensitive'), 'Case-Sensitive')
        for value in ('../other', '.', '..', '', 'a/b'):
            with self.assertRaises(ValueError):
                portable.host_name(value)

    def test_overlay_rejects_whole_main_and_module_configs(self):
        for relative, filename in (('config/niri', 'config.kdl'),
                                   ('config/waybar', 'modules.jsonc'),
                                   ('config/waybar', 'libniri_taskbar.so')):
            with self.subTest(filename=filename):
                shared = self.root / 'configs' / relative
                shared.mkdir(parents=True, exist_ok=True)
                (shared / filename).write_text('shared edits\n')
                overlay = self.root / 'configs/hosts/test-host' / relative
                overlay.mkdir(parents=True, exist_ok=True)
                stale = overlay / filename
                stale.write_text('stale host copy\n')
                with self.assertRaisesRegex(ValueError, 'machine fragment'):
                    portable.prepare(shared, overlay, self.root / 'rendered', Path(relative))
                with self.assertRaisesRegex(ValueError, 'machine fragment'):
                    portable.capture(self.root, Path(relative), shared, 'test-host')
                stale.unlink()

    def test_snapshot_keeps_shared_edits_and_binary_outside_the_host(self):
        staged = self.root / 'staged'
        staged.mkdir()
        (staged / 'modules.jsonc').write_text(
            '{"label":"owner edit","module_path":"' +
            os.environ['XDG_CONFIG_HOME'] + '/waybar/libniri_taskbar.so"}\n')
        binary = b'\x7fELF\0unchanged@HOME@\xff'
        (staged / 'libniri_taskbar.so').write_bytes(binary)
        (staged / 'brightness-edp.jsonc').write_text('{"backlight":{"device":"intel_backlight"}}\n')
        shared = self.root / 'configs/config/waybar'
        shared.mkdir(parents=True)
        (shared / 'brightness-edp.jsonc').write_text('{"backlight":{}}\n')
        portable.capture(self.root, Path('config/waybar'), staged, 'test-host')
        self.assertEqual(json.loads((staged / 'modules.jsonc').read_text()), {
            'label': 'owner edit', 'module_path': '@CONFIG_HOME@/waybar/libniri_taskbar.so'})
        self.assertEqual((staged / 'libniri_taskbar.so').read_bytes(), binary)
        self.assertEqual((staged / 'brightness-edp.jsonc').read_text(), '{"backlight":{}}\n')
        host = self.root / 'configs/hosts/test-host/config/waybar'
        self.assertEqual([p.name for p in host.iterdir()], ['brightness-edp.jsonc'])

    def test_external_brightness_is_hidden_without_a_readable_monitor(self):
        helper = Path(os.environ['XDG_CONFIG_HOME']) / 'niri/scripts/brightness.sh'
        helper.parent.mkdir(parents=True)
        helper.write_text('#!/usr/bin/env bash\nexit 1\n')
        helper.chmod(0o755)
        wrapper = ROOT / 'configs/config/waybar/scripts/external-brightness.sh'
        result = subprocess.check_output([str(wrapper)], text=True)
        self.assertEqual(json.loads(result), {'text': ''})
        helper.write_text('#!/usr/bin/env bash\nprintf "HDMI-A-3,60,60,60,100\\n"\n')
        result = subprocess.check_output([str(wrapper)], text=True)
        self.assertIn('60%', json.loads(result)['text'])

    def test_snapshot_extracts_inline_hardware_and_keeps_unrelated_debug(self):
        file = self.root / 'config.kdl'
        file.write_text('input { mouse { accel-speed 0.2; }; }\n'
                        'output "HDMI-A-3" { scale 1.25; }\n'
                        'debug {\n    render-drm-device "/dev/dri/renderD135"\n'
                        '    enable-overlay-planes\n}\n')
        machine = portable.split_niri(file)
        self.assertNotIn('render-drm-device', file.read_text())
        self.assertNotIn('HDMI-A-3', file.read_text())
        self.assertIn('enable-overlay-planes', file.read_text())
        self.assertIn('mouse', file.read_text())
        self.assertIn('include optional=true "machine.kdl"', file.read_text())
        self.assertIn('HDMI-A-3', machine)
        self.assertIn('renderD135', machine)

    def test_legacy_hardware_comments_move_with_their_fragment(self):
        file = self.root / 'config.kdl'
        comment = '// GPU-specific reason for this selector\n'
        block = 'debug { render-drm-device "/dev/dri/renderD135"; }\n'
        file.write_text('input {}\n\n' + comment + block)
        machine = portable.split_niri(file)
        self.assertEqual(machine, comment + block)
        self.assertNotIn('GPU-specific', file.read_text())
        self.assertIn('input {}', file.read_text())

    def test_snapshot_of_original_machine_does_not_republish_disabled_hardware(self):
        fixture = ROOT / 'tests/fixtures/portability'
        owner = (fixture / 'owner-home').read_text().strip()
        staged = self.root / 'staged'
        staged.mkdir()
        legacy = (fixture / 'niri/config.kdl').read_text().replace(owner, os.environ['HOME'])
        (staged / 'config.kdl').write_text(legacy + '\n// shared edit before first Update\n')
        portable.capture(self.root, Path('config/niri'), staged, 'CHAKEW')
        shared = (staged / 'config.kdl').read_text()
        machine = (self.root / 'configs/hosts/CHAKEW/config/niri/machine.kdl').read_text()
        self.assertNotIn('/-output', shared)
        self.assertNotIn('render-drm-device', shared)
        self.assertNotIn('wired to the NVIDIA', shared)
        self.assertNotIn(os.environ['HOME'], shared)
        self.assertIn('@HOME@', shared)
        self.assertIn('shared edit before first Update', shared)
        self.assertIn('/-output', machine)
        self.assertIn('render-drm-device', machine)
        self.assertIn('wired to the NVIDIA', machine)

    def test_inline_selector_merges_with_existing_machine_debug_options(self):
        staged = self.root / 'staged'
        staged.mkdir()
        (staged / 'config.kdl').write_text(
            'debug { render-drm-device "/dev/dri/renderD135"; }\n'
            'include optional=true "machine.kdl"\n')
        (staged / 'machine.kdl').write_text(
            '// Existing machine explanation\n'
            'debug {\n    render-drm-device "/dev/dri/renderD136"\n'
            '    enable-overlay-planes\n}\n')
        portable.capture(self.root, Path('config/niri'), staged, 'test-host')
        machine = (self.root / 'configs/hosts/test-host/config/niri/machine.kdl').read_text()
        self.assertEqual(machine.count('debug {'), 1)
        self.assertIn('renderD135', machine)
        self.assertNotIn('renderD136', machine)
        self.assertIn('enable-overlay-planes', machine)
        self.assertIn('Existing machine explanation', machine)


if __name__ == '__main__':
    unittest.main()

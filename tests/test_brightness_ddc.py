#!/usr/bin/env python3
"""Exercise the installed keyboard/Waybar route with a dual-GPU DDC monitor."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(os.environ.get('BRIGHTNESS_SCRIPT', str(Path(__file__).resolve().parents[1] / 'configs/config/niri/scripts/brightness.sh')))

class BrightnessDdcTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        bindir = root / 'bin'
        bindir.mkdir()
        self.log = root / 'writes'
        self.log.touch()
        drm = root / 'drm'
        drm.mkdir()
        backlight = root / 'backlight'
        backlight.mkdir()
        gpu = root / 'gpu'
        connector = gpu / 'drm/card0/card0-DP-8'
        connector.mkdir(parents=True)
        (connector / 'status').write_text('connected\n')
        (connector / 'device').symlink_to(connector.parent)
        (connector.parent / 'device').symlink_to(gpu)
        (drm / connector.name).symlink_to(connector)
        panel = backlight / 'nvidia_0'
        panel.mkdir()
        (panel / 'device').symlink_to(gpu)
        self.env = dict(os.environ, PATH=f'{bindir}:/usr/bin',
                        BRIGHTNESS_SYSFS_ROOT=str(backlight),
                        BRIGHTNESS_DRM_SYSFS_ROOT=str(drm),
                        BRIGHTNESS_HELPER=str(bindir / 'helper'),
                        XDG_CACHE_HOME=str(root / 'cache'),
                        TEST_LOG=str(self.log), TEST_FOCUS='DP-8',
                        TEST_VCP='VCP 10 C 80 200', TEST_DETECT='''Invalid display
   I2C bus: /dev/i2c-2
   DRM connector: card1-eDP-1

Display 3
   I2C bus: /dev/i2c-24
   DRM connector: card0-DP-8
''')
        commands = {
            'niri': 'printf \'Output "Monitor" (%s)\\n\' "$TEST_FOCUS"',
            'helper': 'printf "BACKLIGHT %s\\n" "$*" >> "$TEST_LOG"',
            'brightnessctl': 'printf "BACKLIGHT %s\\n" "$*" >> "$TEST_LOG"',
            'ddcutil': '''case " $* " in
 *" detect "*) printf '%s\\n' "$TEST_DETECT"; exit "${TEST_DETECT_EXIT:-0}" ;;
 *" getvcp "*) printf '%s\\n' "$TEST_VCP"; exit "${TEST_READ_EXIT:-0}" ;;
 *" setvcp "*) printf 'DDC %s\\n' "$*" >> "$TEST_LOG"; exit "${TEST_WRITE_EXIT:-0}" ;;
 *) exit 2 ;;
esac''',
        }
        for name, body in commands.items():
            path = bindir / name
            path.write_text('#!/usr/bin/env bash\nset -eu\n' + body + '\n')
            path.chmod(0o755)

    def run_script(self, *args):
        return subprocess.run([str(SCRIPT), *args], env=self.env,
                              capture_output=True, text=True)

    def test_external_focus_uses_ddc_not_gpu_backlight(self):
        result = self.run_script('-5%')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'DDC -b 24 setvcp 10 70\n')

    def test_missing_ddc_never_falls_back_to_gpu(self):
        self.env['TEST_DETECT'] = ''
        self.assertNotEqual(self.run_script('+5%').returncode, 0)
        self.assertEqual(self.log.read_text(), '')

    def test_invalid_ddc_read_never_writes(self):
        self.env['TEST_VCP'] = 'VCP 10 ERR'
        self.assertNotEqual(self.run_script('+5%').returncode, 0)
        self.assertEqual(self.log.read_text(), '')

    def test_failed_ddc_read_never_writes(self):
        self.env['TEST_READ_EXIT'] = '1'
        self.assertNotEqual(self.run_script('+5%').returncode, 0)
        self.assertEqual(self.log.read_text(), '')

    def test_preset_from_internal_focus_selects_unique_external(self):
        self.env['TEST_FOCUS'] = 'eDP-1'
        result = self.run_script('--external', '--set-percent', '65')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'DDC -b 24 setvcp 10 130\n')

    def test_multiple_external_displays_require_focus(self):
        self.env['TEST_FOCUS'] = 'eDP-1'
        self.env['TEST_DETECT'] += '\nDisplay 1\n I2C bus: /dev/i2c-25\n DRM connector: card0-HDMI-A-1\n'
        self.assertNotEqual(self.run_script('--external', '+5%').returncode, 0)
        self.assertEqual(self.log.read_text(), '')

    def test_explicit_external_ignores_internal_focus(self):
        self.env['TEST_FOCUS'] = 'eDP-1'
        result = self.run_script('--output', 'DP-8', '-5%')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'DDC -b 24 setvcp 10 70\n')

    def test_explicit_external_read(self):
        self.env['TEST_FOCUS'] = 'eDP-1'
        result = self.run_script('--output', 'DP-8', '--get')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'DP-8,80,80,40,200\n')
        self.assertEqual(self.log.read_text(), '')

    def test_explicit_external_never_selects_different_external(self):
        self.env['TEST_FOCUS'] = 'DP-8'
        result = self.run_script('--output', 'HDMI-A-1', '--set-percent', '65')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.log.read_text(), '')

    def test_disconnected_internal_never_uses_other_backlight(self):
        result = self.run_script('--output', 'eDP-1', '+5%')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.log.read_text(), '')

    def test_explicit_internal_ignores_external_focus(self):
        root = Path(self.tmp.name)
        connector = root / 'integrated/drm/card1/card1-eDP-1'
        connector.mkdir(parents=True)
        (connector / 'status').write_text('connected\n')
        (connector / 'device').symlink_to(connector.parent)
        (connector.parent / 'device').symlink_to(root / 'integrated')
        (root / 'drm/card1-eDP-1').symlink_to(connector)
        panel = root / 'backlight/panel'
        panel.mkdir()
        (panel / 'device').symlink_to(connector)
        result = self.run_script('--output', 'eDP-1', '--set-percent', '65')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'BACKLIGHT --device panel --set-percent 65\n')

    def test_failed_detection_never_writes(self):
        self.env['TEST_DETECT_EXIT'] = '1'
        self.assertNotEqual(self.run_script('+5%').returncode, 0)
        self.assertEqual(self.log.read_text(), '')

    def test_external_control_without_any_backlight(self):
        panel = Path(self.env['BRIGHTNESS_SYSFS_ROOT']) / 'nvidia_0'
        (panel / 'device').unlink()
        panel.rmdir()
        result = self.run_script('-5%')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'DDC -b 24 setvcp 10 70\n')

    def test_clamps_to_monitor_maximum(self):
        result = self.run_script('+100%')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'DDC -b 24 setvcp 10 200\n')

    def test_failed_ddc_write_is_reported(self):
        self.env['TEST_WRITE_EXIT'] = '1'
        self.assertNotEqual(self.run_script('+5%').returncode, 0)

    def test_cached_bus_skips_detect_on_later_reads(self):
        first = self.run_script('--output', 'DP-8', '--get')
        self.assertEqual(first.returncode, 0, first.stderr)
        self.env['TEST_DETECT_EXIT'] = '1'
        second = self.run_script('--output', 'DP-8', '--get')
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(second.stdout, first.stdout)

    def test_cached_max_lets_set_percent_skip_getvcp(self):
        primed = self.run_script('--output', 'DP-8', '--get')
        self.assertEqual(primed.returncode, 0, primed.stderr)
        self.env['TEST_READ_EXIT'] = '1'
        result = self.run_script('--output', 'DP-8', '--set-percent', '65')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'DDC -b 24 setvcp 10 130\n')

if __name__ == '__main__':
    unittest.main()

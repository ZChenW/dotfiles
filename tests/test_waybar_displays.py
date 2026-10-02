#!/usr/bin/env python3
"""Display drafts must preserve saved policy and never patch untouched outputs."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('displays', ROOT / 'configs/config/waybar/scripts/display-settings.py')
displays = importlib.util.module_from_spec(spec)
spec.loader.exec_module(displays)
FIXTURES = ROOT / 'tests/fixtures/waybar-displays'


class DisplaysTest(unittest.TestCase):
    def setUp(self):
        self.live = json.loads((FIXTURES / 'outputs.json').read_text())
        self.saved = json.loads((FIXTURES / 'saved.json').read_text())
        self.rows = displays.build_rows(self.live, self.saved)

    def test_connector_and_identity_matching(self):
        self.saved[0]['identifier'] = displays.identity(self.live['DP-8']).upper()
        rows = displays.build_rows(self.live, self.saved)
        self.assertEqual(rows[0]['identifier'], self.saved[0]['identifier'])
        self.assertEqual(rows[1]['identifier'], 'eDP-1')
        self.assertTrue(all(r['editable'] for r in rows))

    def test_identifier_without_saved_configuration(self):
        rows = displays.build_rows(self.live, [])
        self.assertEqual(rows[0]['identifier'], displays.identity(self.live['DP-8']))
        self.assertEqual(rows[1]['identifier'], 'eDP-1')
        self.live['DP-9'] = copy.deepcopy(self.live['DP-8'])
        self.assertEqual(displays.build_rows(self.live, [])[0]['identifier'], 'DP-8')

    def test_duplicate_or_unmanaged_rows_are_read_only(self):
        self.saved.append(dict(self.saved[0], identifier=displays.identity(self.live['DP-8'])))
        self.assertFalse(displays.build_rows(self.live, self.saved)[0]['editable'])
        self.saved = self.saved[:2]
        self.saved[0]['managed'] = False
        self.assertFalse(displays.build_rows(self.live, self.saved)[0]['editable'])

    def test_disabled_defaults_and_transforms(self):
        row = displays.build_rows(self.live, [])[1]
        self.assertFalse(row['settings']['enabled'])
        self.assertEqual(row['settings']['mode'], '2560x1600@240.000')
        self.assertEqual(row['settings']['position'], dict(x=0, y=0))
        output = copy.deepcopy(self.live['DP-8'])
        output['logical']['transform'] = 'Flipped90'
        self.assertEqual(displays.defaults(output, {})['transform'], 'flipped-90')

    def test_preserve_unknown_policy_in_patch(self):
        policy = dict(hotCorners=False, focusAtStartup=True, gaps=12,
                      **{'preset-column-widths': [{'proportion': 0.5}],
                         'always-center-single-column': True})
        self.saved[0]['settings'].update(policy)
        rows = displays.build_rows(self.live, self.saved)
        rows[0]['settings']['scale'] = 1.25
        patch = displays.patches(rows)[0]
        for key, value in policy.items():
            self.assertEqual(patch['settings'][key], value)
        patch['settings']['preset-column-widths'].append({'proportion': 0.8})
        self.assertEqual(rows[0]['settings']['preset-column-widths'], [{'proportion': 0.5}])

    def test_only_changed_editable_rows_are_patched(self):
        self.assertEqual(displays.patches(self.rows), [])
        self.rows[0]['settings']['scale'] = 1.5
        self.assertEqual(len(displays.patches(self.rows)), 1)
        self.assertEqual(displays.patches(self.rows)[0]['identity']['name'], 'DP-8')
        self.rows[0]['editable'] = False
        self.assertEqual(displays.patches(self.rows), [])

    def test_mode_format_grouping_deduplication_and_sort(self):
        modes = self.live['DP-8']['modes']
        self.assertEqual(displays.mode_string(modes[1]), '2560x1440@99.946')
        groups = displays.mode_groups(modes)
        self.assertEqual(next(iter(groups)), (2560, 1440))
        self.assertEqual(groups[(2560, 1440)], [99946, 59951])
        self.assertEqual(groups[(1920, 1080)], [60000, 59939, 50000])

    def test_logical_size_and_arrangement(self):
        settings = dict(mode='2560x1600@240.000', scale=1.4, transform='90')
        self.assertEqual(displays.logical_size(settings), (1143, 1829))
        self.rows[1]['settings']['enabled'] = True
        self.rows[1]['settings']['transform'] = '90'
        displays.arrange(self.rows)
        self.assertEqual(self.rows[0]['settings']['position'], dict(x=0, y=0))
        self.assertEqual(self.rows[1]['settings']['position'], dict(x=2560, y=0))
        self.assertEqual(self.rows[0]['baseline']['position']['x'], -4388)

    def test_drag_snaps_to_nearby_edges_only(self):
        other = [(0, 0, 2560, 1440)]
        self.assertEqual(displays.snap_position((2575.4, 12.2, 1829, 1143), other, 20), (2560, 0))
        self.assertEqual(displays.snap_position((2700, 12, 1829, 1143), other, 20), (2700, 0))
        self.assertEqual(displays.snap_position((2700, 310, 1829, 1143), other, 20), (2700, 297))

    def test_drop_settles_on_nearest_free_edge(self):
        other = [(0, 0, 2560, 1440)]
        # Overlapping near the right edge lands flush on the right, keeping its height.
        self.assertEqual(displays.settle_position((2000, 100, 1829, 1143), other), (2560, 100))
        # Dropped above with a gap lands on top, keeping its horizontal offset.
        self.assertEqual(displays.settle_position((300, -2000, 1829, 1143), other), (300, -1143))
        # Already adjacent: untouched.
        self.assertEqual(displays.settle_position((-1829, 200, 1829, 1143), other), (-1829, 200))
        # A third output never lands on top of the second.
        pair = other + [(2560, 0, 1829, 1143)]
        placed = displays.settle_position((2600, 50, 1920, 1080), pair)
        self.assertFalse(any(displays.overlaps((*placed, 1920, 1080), o) for o in pair))
        self.assertTrue(any(displays.touches((*placed, 1920, 1080), o) for o in pair))

    def test_enabling_an_overlapping_output_moves_it_beside_the_other(self):
        self.rows[1]['settings']['position'] = dict(x=-4000, y=0)
        self.rows[1]['settings']['enabled'] = True
        displays.settle_row(self.rows[1], self.rows)
        first, second = (displays.output_rect(r['settings']) for r in self.rows)
        self.assertFalse(displays.overlaps(first, second))
        self.assertTrue(displays.touches(first, second))
        self.assertEqual(self.rows[0]['settings']['position'], dict(x=-4388, y=0))

    def test_frontend_validation(self):
        for row in self.rows:
            row['settings']['enabled'] = False
        self.assertIn('至少', displays.validation(self.rows))
        self.rows[0]['settings']['enabled'] = True
        self.rows[0]['settings']['mode'] = ''
        self.assertIn('显示模式', displays.validation(self.rows))

    def test_errors_even_with_nonzero_exit_and_terminal_status(self):
        with self.assertRaisesRegex(RuntimeError, 'Configuration changed'):
            displays.decode_response(1, '{"error":"Configuration changed"}', '')
        state = displays.decode_response(0, '{"phase":"reverted","error":"Changes reverted"}', '')
        self.assertEqual(displays.status_message(state), '已还原')
        self.assertIn('超时', displays.status_message(dict(error='Display preview timed out')))
        self.assertIn('restore failed', displays.status_message(dict(
            phase='reverted', error='Changes reverted', restoreErrors=['restore failed'])))

    def test_saved_settings_are_not_mutated(self):
        baseline = copy.deepcopy(self.saved)
        self.rows[0]['settings']['position']['x'] = 0
        self.assertEqual(self.saved, baseline)


if __name__ == '__main__':
    unittest.main()

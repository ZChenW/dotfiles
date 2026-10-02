#!/usr/bin/env python3
"""Exercise the commands owned by the visible speaker and microphone controls."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'configs/config/waybar'


def read_jsonc(path):
    tokens = r'("(?:\\.|[^"\\])*")|//[^\n]*|/\*[\s\S]*?\*/'
    text = re.sub(tokens, lambda m: m.group(1) or '', path.read_text())
    text = re.sub(r',\s*([}\]])', r'\1', text)
    return json.loads(text)


class AudioControlsTest(unittest.TestCase):
    def setUp(self):
        self.config = read_jsonc(ROOT / 'modules.jsonc')
        self.bar = read_jsonc(ROOT / 'bar-common.jsonc')
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        wpctl = Path(self.tmp.name) / 'wpctl'
        wpctl.write_text('#!/bin/sh\nprintf "%s\\n" "$*"\n')
        wpctl.chmod(0o755)
        self.env = dict(os.environ, PATH=self.tmp.name + ':' + os.environ['PATH'])

    def visible_modules(self):
        def visit(name):
            if name.startswith('group/') and name in self.config:
                group = self.config[name]
                children = group['modules']
                if 'drawer' in group:
                    children = children[:1]
                return [module for child in children for module in visit(child)]
            return [name]
        return [module for name in self.bar['modules-right'] for module in visit(name)]

    def microphone(self):
        for name in self.visible_modules():
            config = self.config.get(name, {})
            if '' in config.get('format-source', '') or '' in config.get('format', ''):
                return name, config
        self.fail('No microphone control visible with drawers closed')

    def run_action(self, config, action):
        return subprocess.check_output(config[action], shell=True,
                                       env=self.env, text=True).strip()

    def test_microphone_click_controls_source(self):
        _, microphone = self.microphone()
        self.assertEqual(self.run_action(microphone, 'on-click'),
                         'set-mute @DEFAULT_AUDIO_SOURCE@ toggle')

    def test_microphone_and_speaker_have_separate_hit_areas(self):
        name, microphone = self.microphone()
        self.assertNotEqual(name, 'pulseaudio')
        self.assertNotIn('{icon}', microphone['format'])
        self.assertNotIn('{format_source}', self.config['pulseaudio']['format'])
        for action, step in [('on-scroll-up', '5%+'), ('on-scroll-down', '5%-')]:
            self.assertEqual(self.run_action(microphone, action),
                             f'set-volume @DEFAULT_AUDIO_SOURCE@ {step}')

    def test_speaker_actions_and_drawer_control_sink(self):
        speaker = self.config['pulseaudio']
        self.assertEqual(self.run_action(speaker, 'on-click'),
                         'set-mute @DEFAULT_AUDIO_SINK@ toggle')
        for action, step in [('on-scroll-up', '5%+'), ('on-scroll-down', '5%-')]:
            self.assertEqual(self.run_action(speaker, action),
                             f'set-volume @DEFAULT_AUDIO_SINK@ {step}')
        slider = self.config['pulseaudio/slider']
        self.assertEqual(slider.get('target', 'sink'), 'sink')


if __name__ == '__main__':
    unittest.main()

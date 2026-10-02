#!/usr/bin/env python3
"""Waybar display controls using Clavis's guarded Niri preview transactions."""
import copy
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

APP_ID = 'io.github.zchenw.WaybarDisplays'
TRANSFORMS = [('normal', '正常'), ('90', '90°'), ('180', '180°'),
              ('270', '270°'), ('flipped', '翻转'), ('flipped-90', '翻转 90°'),
              ('flipped-180', '翻转 180°'), ('flipped-270', '翻转 270°')]


def identity(output):
    return ' '.join(str(output.get(k) or 'Unknown') for k in ('make', 'model', 'serial'))


def mode_string(mode):
    return f"{mode['width']}x{mode['height']}@{mode['refresh_rate'] / 1000:.3f}"


def mode_groups(modes):
    groups = {}
    for mode in modes:
        key = (mode['width'], mode['height'])
        groups.setdefault(key, set()).add(mode['refresh_rate'])
    return {key: sorted(groups[key], reverse=True)
            for key in sorted(groups, key=lambda k: (k[0] * k[1], k), reverse=True)}


def parse_mode(value):
    match = re.fullmatch(r'(\d+)x(\d+)(?:@([\d.]+))?', value or '')
    if not match:
        return 0, 0, 0
    return int(match[1]), int(match[2]), float(match[3] or 0)


def defaults(output, saved):
    settings = copy.deepcopy(saved)
    modes = output.get('modes', [])
    index = output.get('current_mode')
    mode = modes[index] if isinstance(index, int) and 0 <= index < len(modes) else next(
        (m for m in modes if m.get('is_preferred')), modes[0] if modes else None)
    logical = output.get('logical') or {}
    transform = logical.get('transform', 'Normal')
    transform = {'Normal': 'normal', 'Flipped': 'flipped', 'Flipped90': 'flipped-90',
                 'Flipped180': 'flipped-180', 'Flipped270': 'flipped-270'}.get(transform, transform)
    values = dict(enabled=index is not None, mode=mode_string(mode) if mode else '',
                  scale=logical.get('scale', 1), transform=transform,
                  position=dict(x=logical.get('x', 0), y=logical.get('y', 0)), vrr='off')
    for key, value in values.items():
        settings.setdefault(key, value)
    return settings


def build_rows(live, saved):
    rows = []
    for name, data in live.items():
        output = dict(data, name=name)
        ident = identity(output)
        matches = [r for r in saved if r['identifier'].casefold() in (name.casefold(), ident.casefold())]
        unique = sum(identity(o).casefold() == ident.casefold() for o in live.values()) == 1
        chosen = matches[0] if matches else {}
        settings = defaults(output, chosen.get('settings', {}))
        known_serial = bool(output.get('serial')) and str(output['serial']).casefold() != 'unknown'
        rows.append(dict(name=name, output=output,
                         identifier=chosen.get('identifier', ident if known_serial and unique else name),
                         editable=len(matches) <= 1 and (not matches or
                                  bool(chosen.get('managed') and chosen.get('editable'))),
                         source='\n'.join(r.get('source', '') for r in matches),
                         settings=settings, baseline=copy.deepcopy(settings)))
    return rows


def normalized(settings):
    return json.dumps(settings, sort_keys=True, ensure_ascii=False)


def patches(rows):
    return [dict(identifier=r['identifier'],
                 identity={k: r['output'].get(k) for k in ('name', 'make', 'model', 'serial')},
                 settings=copy.deepcopy(r['settings']), delete=False)
            for r in rows if r['editable'] and normalized(r['settings']) != normalized(r['baseline'])]


def logical_size(settings):
    width, height, _ = parse_mode(settings.get('mode'))
    scale = round(settings.get('scale', 1) * 120) / 120
    if settings.get('transform') in ('90', '270', 'flipped-90', 'flipped-270'):
        width, height = height, width
    return math.ceil(width / scale), math.ceil(height / scale)


def output_rect(settings):
    width, height = logical_size(settings)
    return settings['position']['x'], settings['position']['y'], width, height


def overlaps(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def touches(a, b):
    beside = a[0] + a[2] == b[0] or b[0] + b[2] == a[0]
    stacked = a[1] + a[3] == b[1] or b[1] + b[3] == a[1]
    return (beside and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]) or \
           (stacked and a[0] < b[0] + b[2] and b[0] < a[0] + a[2])


def snap_position(moving, others, threshold):
    """Pull a dragged rectangle's edges onto nearby edges of the other outputs."""
    x, y, width, height = moving
    best = dict(x=(threshold, 0), y=(threshold, 0))
    for ox, oy, ow, oh in others:
        for axis, deltas in (('x', (ox - x - width, ox + ow - x, ox - x, ox + ow - x - width)),
                             ('y', (oy - y - height, oy + oh - y, oy - y, oy + oh - y - height))):
            for delta in deltas:
                if abs(delta) < best[axis][0]:
                    best[axis] = (abs(delta), delta)
    return round(x + best['x'][1]), round(y + best['y'][1])


def settle_position(moving, others):
    """Nearest spot where the rectangle shares an edge with another output.

    Niri relocates overlapping outputs and the pointer cannot cross a gap, so a
    drop anywhere else would not behave the way the picture suggests.
    """
    x, y, width, height = moving
    if not others or (not any(overlaps(moving, o) for o in others) and any(touches(moving, o) for o in others)):
        return x, y
    candidates = []
    for ox, oy, ow, oh in others:
        along_y = min(max(y, oy - height + 1), oy + oh - 1)
        along_x = min(max(x, ox - width + 1), ox + ow - 1)
        candidates += [(ox - width, along_y), (ox + ow, along_y), (along_x, oy - height), (along_x, oy + oh)]
    free = [c for c in candidates if not any(overlaps((c[0], c[1], width, height), o) for o in others)]
    if not free:
        return max(o[0] + o[2] for o in others), y
    return min(free, key=lambda c: (c[0] - x) ** 2 + (c[1] - y) ** 2)


def settle_row(row, rows):
    if not row['editable'] or not row['settings'].get('enabled') or not row['settings'].get('mode'):
        return
    others = [output_rect(r['settings']) for r in rows
              if r is not row and r['settings'].get('enabled') and r['settings'].get('mode')]
    x, y = settle_position(output_rect(row['settings']), others)
    row['settings']['position'] = dict(x=x, y=y)


def arrange(rows):
    x = 0
    for row in sorted((r for r in rows if r['settings'].get('enabled')),
                      key=lambda r: r['settings']['position']['x']):
        # An unmanaged output's position is authoritative; never silently edit it.
        if row['editable']:
            row['settings']['position'] = dict(x=x, y=0)
        x = row['settings']['position']['x'] + logical_size(row['settings'])[0]


def validation(rows):
    if not any(r['settings'].get('enabled') for r in rows):
        return '至少保留一块启用的屏幕'
    if any(not r['settings'].get('mode') for r in rows if r['editable']):
        return '请选择可用的显示模式'
    return ''


def connection_key(live):
    return sorted((name, identity(output)) for name, output in live.items())


def status_message(state):
    error = state.get('error', '')
    restore = state.get('restoreErrors') or []
    if state.get('phase') == 'kept':
        message = '已保存'
    elif error == 'Changes reverted' and not restore:
        message = '已还原'
    elif error == 'Display preview timed out':
        message = '超时未确认，已自动还原'
    else:
        message = error or '已还原'
    return '\n'.join([message] + [str(e) for e in restore])


def decode_response(code, stdout, stderr):
    try:
        response = json.loads(stdout)
    except (ValueError, TypeError):
        raise RuntimeError(stderr.strip() or '后端返回了无效数据') from None
    if code:
        raise RuntimeError(response.get('error') or stderr.strip() or f'后端退出码 {code}')
    return response


def backend_directory():
    config_home = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')))
    candidates = []
    if os.environ.get('QUICKSHELL_CONFIG_PATH'):
        candidates.append(Path(os.environ['QUICKSHELL_CONFIG_PATH']) / 'scripts/system')
    candidates.append(config_home / 'quickshell/clavis/scripts/system')
    for path in candidates:
        if all((path / name).is_file() for name in ('niri_config.py', 'niri_outputs.py', 'display_preview.py')):
            return path
    raise RuntimeError('找不到 Clavis 显示预览后端。请检查 QuickShell 配置路径。')


def run_json(argv):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=8)
    return decode_response(result.returncode, result.stdout, result.stderr)


def backend(path, script, request):
    # Invoke directly so the preview guardian observes this GTK application's PID.
    return run_json([sys.executable, str(path / script), json.dumps(request)])


def create_application():
    import gi
    gi.require_version('Gtk', '3.0')
    gi.require_version('Gdk', '3.0')
    gi.require_version('PangoCairo', '1.0')
    from gi.repository import Gdk, Gio, GLib, Gtk, Pango, PangoCairo
    GLib.set_prgname(APP_ID)

    class Canvas(Gtk.DrawingArea):
        """Enabled outputs drawn to scale; drag one to place it next to another."""

        def __init__(self, app):
            super().__init__()
            self.app = app
            self.drag = None
            self.set_size_request(-1, 220)
            self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK |
                            Gdk.EventMask.BUTTON1_MOTION_MASK)
            self.get_accessible().set_name('屏幕排布')
            self.connect('draw', self.draw)
            self.connect('button-press-event', self.press)
            self.connect('motion-notify-event', self.motion)
            self.connect('button-release-event', self.release)

        def shown(self):
            return [r for r in self.app.rows if r['settings'].get('enabled') and r['settings'].get('mode')]

        def view(self):
            # Frozen while dragging so the picture does not rescale under the pointer.
            if self.drag:
                return self.drag['view']
            rects = [output_rect(r['settings']) for r in self.shown()]
            if not rects:
                return None
            left, top = min(r[0] for r in rects), min(r[1] for r in rects)
            span_x = max(r[0] + r[2] for r in rects) - left
            span_y = max(r[1] + r[3] for r in rects) - top
            width, height = self.get_allocated_width(), self.get_allocated_height()
            scale = min(width * 0.62 / max(span_x, 1), height * 0.72 / max(span_y, 1))
            return scale, (width - span_x * scale) / 2 - left * scale, (height - span_y * scale) / 2 - top * scale

        def draw(self, _, cr):
            view = self.view()
            if not view:
                return False
            scale, shift_x, shift_y = view
            context = self.get_style_context()
            text = context.get_color(context.get_state())
            found, accent = context.lookup_color('theme_selected_bg_color')
            if not found:
                accent = Gdk.RGBA(0.35, 0.55, 0.95, 1)
            for row in self.shown():
                x, y, width, height = output_rect(row['settings'])
                active = self.drag and self.drag['row'] is row
                color = accent if row['editable'] else text
                cr.rectangle(x * scale + shift_x + 1.5, y * scale + shift_y + 1.5,
                             width * scale - 3, height * scale - 3)
                cr.set_source_rgba(color.red, color.green, color.blue, 0.5 if active else 0.22)
                cr.fill_preserve()
                cr.set_source_rgba(color.red, color.green, color.blue, 1 if row['editable'] else 0.4)
                cr.set_line_width(2)
                cr.stroke()
                layout = self.create_pango_layout(f"{row['name']}\n{width} × {height}")
                layout.set_alignment(Pango.Alignment.CENTER)
                _, extents = layout.get_pixel_extents()
                cr.move_to((x + width / 2) * scale + shift_x - extents.width / 2,
                           (y + height / 2) * scale + shift_y - extents.height / 2)
                cr.set_source_rgba(text.red, text.green, text.blue, text.alpha)
                PangoCairo.show_layout(cr, layout)
            return False

        def press(self, _, event):
            view = self.view()
            if event.button != 1 or not view:
                return False
            scale, shift_x, shift_y = view
            px, py = (event.x - shift_x) / scale, (event.y - shift_y) / scale
            for row in reversed(self.shown()):
                x, y, width, height = output_rect(row['settings'])
                if row['editable'] and x <= px < x + width and y <= py < y + height:
                    self.drag = dict(row=row, view=view, dx=px - x, dy=py - y)
                    self.queue_draw()
                    return True
            return False

        def motion(self, _, event):
            if not self.drag:
                return False
            scale, shift_x, shift_y = self.drag['view']
            row = self.drag['row']
            _, _, width, height = output_rect(row['settings'])
            moving = ((event.x - shift_x) / scale - self.drag['dx'],
                      (event.y - shift_y) / scale - self.drag['dy'], width, height)
            others = [output_rect(r['settings']) for r in self.shown() if r is not row]
            x, y = snap_position(moving, others, 14 / scale)
            row['settings']['position'] = dict(x=x, y=y)
            self.queue_draw()
            return True

        def release(self, _, event):
            if event.button != 1 or not self.drag:
                return False
            row, self.drag = self.drag['row'], None
            settle_row(row, self.app.rows)
            self.app.notice = ''
            self.app.render_state()
            return True

    class Displays(Gtk.Application):
        def __init__(self):
            super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
            self.window = None
            self.rows = []
            self.saved = {}
            self.live = {}
            self.path = None
            self.token = None
            self.phase = 'idle'
            self.remaining = 0
            self.busy = False
            self.blocking = False
            self.deferred = None
            self.closing = False
            self.stale = False
            self.notice = ''
            self.poll_id = self.watch_id = 0
            self.executor = ThreadPoolExecutor(max_workers=1)

        def do_activate(self):
            if self.window:
                self.close()
                return
            self.window = Gtk.ApplicationWindow(application=self, title='显示器设置')
            self.window.set_resizable(False)
            self.window.set_default_size(680, -1)
            self.window.connect('delete-event', lambda *_: self.close() or True)
            self.window.connect('key-press-event', self.keypress)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
            box.set_border_width(18)
            self.window.add(box)
            heading = Gtk.Label(label='选择要启用的屏幕，再调整显示方式', xalign=0)
            box.pack_start(heading, False, False, 0)
            self.canvas = Canvas(self)
            box.pack_start(self.canvas, False, False, 0)
            hint = Gtk.Label(label='拖动屏幕调整相对位置，松开后自动贴边', xalign=0)
            hint.set_opacity(0.7)
            box.pack_start(hint, False, False, 0)
            scroll = Gtk.ScrolledWindow()
            scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            scroll.set_max_content_height(420)
            scroll.set_propagate_natural_height(True)
            self.cards = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
            scroll.add(self.cards)
            box.pack_start(scroll, True, True, 0)
            self.auto = Gtk.Button(label='自动并排')
            self.auto.set_halign(Gtk.Align.START)
            self.auto.connect('clicked', self.auto_arrange)
            box.pack_start(self.auto, False, False, 0)
            self.message = Gtk.Label(xalign=0)
            self.message.set_line_wrap(True)
            self.message.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
            self.message.set_max_width_chars(70)
            self.message.set_selectable(True)
            box.pack_start(self.message, False, False, 0)
            actions = Gtk.Box(spacing=10)
            actions.set_halign(Gtk.Align.END)
            self.reset = Gtk.Button(label='重置')
            self.apply = Gtk.Button(label='应用')
            self.apply.get_style_context().add_class('suggested-action')
            self.reset.connect('clicked', self.reset_clicked)
            self.apply.connect('clicked', self.apply_clicked)
            actions.add(self.reset)
            actions.add(self.apply)
            box.pack_start(actions, False, False, 0)
            self.window.show_all()
            self.load()
            self.watch_id = GLib.timeout_add_seconds(2, self.watch)

        def job(self, work, callback, background=False):
            if self.busy:
                if background:
                    return False
                self.deferred = (work, callback)
                self.blocking = True
                self.render_state()
                return True
            self.busy = True
            self.blocking = not background
            if not background:
                self.render_state()
            future = self.executor.submit(work)

            def complete():
                self.busy = False
                self.blocking = False
                try:
                    result, error = future.result(), None
                except Exception as exc:
                    result, error = None, str(exc)
                callback(result, error)
                if self.closing:
                    self.deferred = None
                    self.close()
                elif self.deferred and not self.busy:
                    queued_work, queued_callback = self.deferred
                    self.deferred = None
                    self.job(queued_work, queued_callback)
                else:
                    self.render_state()
                return False
            future.add_done_callback(lambda _: GLib.idle_add(complete))
            return True

        def load(self, notice=''):
            self.notice = '正在读取显示器…'

            def work():
                self.path = backend_directory()
                saved = backend(self.path, 'niri_config.py', dict(operation='status'))
                live = run_json(['niri', 'msg', '-j', 'outputs'])
                return saved, live

            def loaded(result, error):
                if error:
                    self.saved = {}
                    self.notice = error
                else:
                    self.saved, self.live = result
                    self.rows = build_rows(self.live, self.saved.get('outputs', []))
                    self.stale = False
                    self.notice = notice
                self.rebuild()
            self.job(work, loaded)

        def rebuild(self):
            for child in self.cards.get_children():
                child.destroy()
            for row in self.rows:
                self.card(row)
            self.cards.show_all()

        def card(self, row):
            settings, output = row['settings'], row['output']
            frame = Gtk.Frame()
            body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
            body.set_border_width(12)
            frame.add(body)
            header = Gtk.Box(spacing=12)
            title = f"{output['model']} · {row['name']}" if output.get('model') else row['name']
            label = Gtk.Label(xalign=0)
            label.set_markup(f'<b>{GLib.markup_escape_text(title)}</b>')
            header.pack_start(label, True, True, 0)
            header.add(Gtk.Label(label='启用'))
            switch = Gtk.Switch(active=bool(settings['enabled']))
            switch.get_accessible().set_name(f"启用 {row['name']}")
            header.add(switch)
            body.add(header)
            grid = Gtk.Grid(column_spacing=14, row_spacing=8)
            grid.set_opacity(1 if settings['enabled'] else 0.65)
            body.add(grid)

            def field(text, widget, column, line):
                box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
                box.add(Gtk.Label(label=text, xalign=0))
                widget.get_accessible().set_name(f"{row['name']} {text}")
                widget.set_hexpand(True)
                box.add(widget)
                grid.attach(box, column, line, 1, 1)
                return widget

            def change(key, value):
                settings[key] = value
                # A new size or a newly enabled output may no longer fit where it was.
                settle_row(row, self.rows)
                self.notice = ''
                self.render_state()

            def toggle(widget, _):
                grid.set_opacity(1 if widget.get_active() else 0.65)
                change('enabled', widget.get_active())
            switch.connect('notify::active', toggle)
            groups = mode_groups(output.get('modes', []))
            resolution, refresh = Gtk.ComboBoxText(), Gtk.ComboBoxText()
            for width, height in groups:
                resolution.append(f'{width}x{height}', f'{width} × {height}')
            width, height, hz = parse_mode(settings['mode'])
            current_resolution = f'{width}x{height}'
            if (width, height) not in groups and settings['mode']:
                resolution.append(current_resolution, f'{width} × {height}（已保存）')
            resolution.set_active_id(current_resolution)

            def refresh_options(wanted):
                refresh.remove_all()
                key = tuple(map(int, resolution.get_active_id().split('x'))) if resolution.get_active_id() else (0, 0)
                rates = groups.get(key, [])
                for rate in rates:
                    refresh.append(str(rate), f'{rate / 1000:.3f} Hz')
                if rates:
                    refresh.set_active_id(str(min(rates, key=lambda rate: abs(rate - wanted * 1000))))
                elif settings['mode']:
                    refresh.append(str(round(wanted * 1000)), f'{wanted:.3f} Hz（已保存）')
                    refresh.set_active(0)
            refresh_options(hz)

            def mode_changed(_):
                if resolution.get_active_id() and refresh.get_active_id():
                    change('mode', f'{resolution.get_active_id()}@{int(refresh.get_active_id()) / 1000:.3f}')

            def resolution_changed(_):
                wanted = parse_mode(settings['mode'])[2]
                refresh.handler_block(refresh_handler)
                refresh_options(wanted)
                refresh.handler_unblock(refresh_handler)
                mode_changed(None)
            refresh_handler = refresh.connect('changed', mode_changed)
            resolution.connect('changed', resolution_changed)
            field('分辨率', resolution, 0, 0)
            field('刷新率', refresh, 1, 0)

            def spin(value, lower, upper, step, digits=0):
                widget = Gtk.SpinButton.new_with_range(lower, upper, step)
                widget.set_digits(digits)
                widget.set_value(value)
                return widget
            scale = field('缩放', spin(settings['scale'], 0.5, 3, 0.05, 2), 2, 0)
            scale.connect('value-changed', lambda w: change('scale', w.get_value()))
            rotation = Gtk.ComboBoxText()
            for key, text in TRANSFORMS:
                rotation.append(key, text)
            rotation.set_active_id(settings['transform'])
            rotation.connect('changed', lambda w: change('transform', w.get_active_id()))
            field('旋转', rotation, 0, 1)
            if output.get('vrr_supported'):
                vrr = Gtk.ComboBoxText()
                for key, text in [('off', '关闭'), ('on', '开启'), ('on-demand', '按需')]:
                    vrr.append(key, text)
                vrr.set_active_id(settings['vrr'])
                vrr.connect('changed', lambda w: change('vrr', w.get_active_id()))
                field('可变刷新率 VRR', vrr, 1, 1)
            if not row['editable']:
                frame.set_sensitive(False)
                source = Gtk.Label(label=f"此配置不可编辑：{row['source']}", xalign=0)
                source.set_line_wrap(True)
                body.add(source)
            self.cards.add(frame)

        def render_state(self):
            if not self.window:
                return
            ready = self.saved.get('fragments', {}).get('outputs', {}).get('state') == 'ready'
            idle = self.phase == 'idle' and not self.token
            confirming = self.phase == 'confirming'
            error = validation(self.rows) if self.rows else ''
            self.cards.set_sensitive(idle and not self.blocking and ready)
            self.canvas.set_sensitive(idle and not self.blocking and ready)
            self.canvas.queue_draw()
            self.auto.set_sensitive(idle and not self.blocking and ready and bool(self.rows))
            self.reset.set_label('还原' if self.token else '重置')
            self.reset.set_sensitive(not self.blocking and (idle or confirming))
            self.apply.set_label(f'保留更改（{self.remaining}）' if confirming else '正在保存…' if self.phase == 'saving'
                                 else '正在应用…' if not idle else '应用')
            self.apply.set_sensitive(not self.blocking and (confirming or
                (idle and ready and not self.stale and not error and bool(patches(self.rows)))))
            message = self.notice or error
            if not ready and self.saved:
                message = '请先在 Clavis 设置里连接 outputs 片段'
            if self.stale:
                message = '显示器已变化，请重置后再应用'
            self.message.set_text(message or '应用后有 10 秒确认时间；未确认会自动还原')

        def auto_arrange(self, _):
            arrange(self.rows)
            self.notice = ''
            self.rebuild()
            self.render_state()

        def reset_clicked(self, _):
            if self.token:
                self.command('revert')
            else:
                self.load()

        def apply_clicked(self, _):
            if self.token:
                self.command('keep')
                return
            if validation(self.rows) or self.stale or not patches(self.rows):
                return
            request = dict(operation='start', revision=self.saved['revision'],
                           main=self.saved['main'], outputs=patches(self.rows))
            self.phase = 'start'
            self.notice = '正在应用…'

            def started(result, error):
                if error:
                    self.phase = 'idle'
                    self.notice = error
                else:
                    self.token = result['token']
                    self.phase = 'validating'
                    self.poll_id = GLib.timeout_add(400, self.poll)
            self.job(lambda: backend(self.path, 'display_preview.py', request), started)

        def command(self, operation):
            token = self.token
            def sent(_, error):
                self.notice = error or ('正在保存…' if operation == 'keep' else '正在还原…')
                if not error:
                    self.phase = 'saving' if operation == 'keep' else 'reverting'
            self.job(lambda: backend(self.path, 'display_preview.py',
                                     dict(operation=operation, token=token)), sent)

        def poll(self):
            if not self.token or self.closing:
                self.poll_id = 0
                return False
            if self.busy:
                return True

            def polled(state, error):
                if error:
                    self.notice = error + '\n预览状态读取失败；后端仍会自动还原'
                    return
                self.phase = state['phase']
                self.remaining = math.ceil(state.get('remaining', 0))
                if self.phase in ('kept', 'reverted'):
                    self.deferred = None
                    token, message = self.token, status_message(state)
                    if self.poll_id:
                        GLib.source_remove(self.poll_id)
                        self.poll_id = 0
                    def cleaned(_, cleanup_error):
                        self.token = None
                        self.phase = 'idle'
                        self.load(message + ('\n' + cleanup_error if cleanup_error else ''))
                    self.job(lambda: backend(self.path, 'display_preview.py',
                                             dict(operation='cleanup', token=token)), cleaned)
                else:
                    self.notice = {'validating': '正在校验…', 'applying': '正在应用…',
                                   'saving': '正在保存…'}.get(self.phase, '请确认显示正常')
                    self.render_state()
                    if self.phase == 'confirming':
                        self.apply.set_label(f"保留更改（{math.ceil(state.get('remaining', 0))}）")
            self.job(lambda: backend(self.path, 'display_preview.py',
                                     dict(operation='status', token=self.token)), polled, background=True)
            return True

        def watch(self):
            if self.busy or self.token or self.phase != 'idle' or self.closing or not self.path:
                return True

            def checked(live, error):
                if error:
                    self.stale = True
                    self.notice = error
                elif connection_key(live) != connection_key(self.live):
                    if patches(self.rows):
                        self.stale = True
                    else:
                        self.load()
            self.job(lambda: run_json(['niri', 'msg', '-j', 'outputs']), checked, background=True)
            return True

        def keypress(self, _, event):
            if event.keyval != Gdk.KEY_Escape:
                return False
            if self.token and self.phase == 'confirming':
                self.command('revert')
            else:
                self.close()
            return True

        def close(self):
            self.closing = True
            if self.busy:
                return True
            if self.token:
                token = self.token
                self.token = None
                self.job(lambda: backend(self.path, 'display_preview.py',
                                         dict(operation='revert', token=token)), lambda *_: None)
                return True
            for source in (self.poll_id, self.watch_id):
                if source:
                    GLib.source_remove(source)
            self.poll_id = self.watch_id = 0
            self.window.destroy()
            self.window = None
            self.quit()
            return True

    return Displays()


def main():
    # Waybar signals the process group of every on-click child when the bar that
    # spawned it goes away, which is exactly what disabling that bar's output
    # does. Dying there makes the preview guardian revert, so leave the group.
    if os.fork():
        os._exit(0)
    os.setsid()
    app = create_application()
    try:
        return app.run(sys.argv)
    finally:
        app.executor.shutdown(wait=False)


if __name__ == '__main__':
    sys.exit(main())

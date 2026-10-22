#!/usr/bin/env python3
"""The shared/host and portable/live boundaries used by both sync and snapshot.

Only UTF-8 text without NUL/control bytes is rendered. Native $HOME/~ syntax is
left alone; @HOME@ and @CONFIG_HOME@ are literal placeholders, never shell code.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sys

MACHINE_FILES = {
    'config/niri/outputs.kdl',
    'config/niri/machine.kdl',
    'config/waybar/config.jsonc',
    'config/waybar/brightness-edp.jsonc',
    'config/waybar/brightness-dp.jsonc',
}


def host_name(value):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', value) or value in ('.', '..'):
        raise ValueError('hostname must be a single nonempty directory component')
    return value


def text_content(path):
    with path.open('rb') as stream:
        head = stream.read(8192)
        if any(byte < 32 and byte not in (9, 10, 13) for byte in head):
            return None
        data = head + stream.read()
    if any(byte < 32 and byte not in (9, 10, 13) for byte in data):
        return None
    try:
        return data.decode('utf-8')
    except UnicodeDecodeError:
        return None


def transform(path, direction):
    """Literal, boundary-aware and reversible; preserve modes, timestamps and EOLs."""
    text = text_content(path)
    if text is None:
        return
    home = os.environ['HOME'].rstrip('/') or '/'
    config = os.environ.get('XDG_CONFIG_HOME') or home + '/.config'
    replacements = [('@CONFIG_HOME@', config), ('@HOME@', home)]
    quoted = path.suffix in ('.json', '.jsonc', '.kdl', '.toml')
    for token, value in replacements:
        value = json.dumps(value, ensure_ascii=False)[1:-1] if quoted else value
        if direction == 'render':
            text = text.replace(token, value)
        else:
            # A sibling home with the same prefix must not be rewritten.
            text = re.sub(r'(?<![\w/.-])' + re.escape(value) + r'(?=$|[/\s"\'\\:;,\)])', lambda _: token, text)
    data = text.encode('utf-8')
    if data != path.read_bytes():
        info = path.stat()
        path.write_bytes(data)
        os.utime(path, ns=(info.st_atime_ns, info.st_mtime_ns))


def files(path):
    if path.is_file():
        yield path
    elif path.is_dir():
        yield from sorted(p for p in path.rglob('*') if p.is_file())


def reject_links(path):
    for item in (path, *path.parents):
        if item.is_symlink():
            raise ValueError('symbolic links are not config sources: ' + str(item))
    if path.is_dir():
        for item in path.rglob('*'):
            if item.is_symlink():
                raise ValueError('symbolic links are not config sources: ' + str(item))


def copy(source, target):
    reject_links(source)
    if source.is_dir():
        shutil.copytree(source, target, dirs_exist_ok=True)
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def check_fragments(overlay, relative):
    """Only named machine fragments may shadow shared files, in either direction."""
    reject_links(overlay)
    for path in files(overlay):
        name = relative / path.relative_to(overlay) if overlay.is_dir() else relative
        if str(name) not in MACHINE_FILES:
            raise ValueError('host overlay file is not a machine fragment: ' + str(name))


def prepare(source, overlay, target, relative):
    check_fragments(overlay, relative)
    if source.exists():
        copy(source, target)
    if overlay.exists():
        copy(overlay, target)
    for path in files(target):
        transform(path, 'render')


def split_niri(path):
    """Move top-level outputs and only the GPU selector out of a legacy config.

    Use the already-vendored KDL parser and its source ranges, preserving every
    unrelated byte. Invalid input fails rather than being treated as empty.
    """
    text = path.read_bytes().decode('utf-8')
    if not re.search(r'\b(?:output|render-drm-device)\b', text):
        return ''
    vendor = Path(__file__).resolve().parents[1] / 'configs/config/waybar/scripts/display-backend/vendor'
    sys.path.insert(0, str(vendor))
    import kdl
    from kdl import parsefuncs
    from kdl.stream import Stream
    nodes = kdl.parse(text).nodes
    changes, machine = [], []

    def start_with_comments(node):
        start = text.rfind('\n', 0, node.source_start) + 1
        if text[start:node.source_start].strip():
            return node.source_start
        while start:
            previous = text.rfind('\n', 0, start - 1) + 1
            if not text[previous:start].lstrip().startswith('//'):
                break
            start = previous
        return start

    # parse() omits /- nodes. Walk its top-level spans as well so disabled
    # legacy hardware examples move intact, without ever enabling them.
    stream = Stream(text, kdl.ParseConfig())
    _, position = parsefuncs.parseLinespace(stream, 0)
    while not stream.eof(position):
        node, end = parsefuncs.parseNode(stream, position)
        if node is None:
            hidden = kdl.parse(text[position + 2:end]).nodes[0]
            if hidden.name == 'output' or (hidden.name == 'debug' and any(
                    child.name == 'render-drm-device' for child in hidden.nodes)):
                hidden.source_start = position
                start = start_with_comments(hidden)
                machine.append(text[start:end])
                changes.append((start, end, ''))
        _, position = parsefuncs.parseLinespace(stream, end)

    for node in nodes:
        if node.name == 'output':
            start = start_with_comments(node)
            machine.append(text[start:node.source_end])
            changes.append((start, node.source_end, ''))
        elif node.name == 'debug':
            devices = [n for n in node.nodes if n.name == 'render-drm-device']
            if not devices:
                continue
            if len(devices) == len(node.nodes):
                start = start_with_comments(node)
                machine.append(text[start:node.source_end])
                changes.append((start, node.source_end, ''))
            else:
                machine.append('debug {\n' + ''.join(
                    '    ' + text[n.source_start:n.source_end].strip() + '\n' for n in devices) + '}\n')
                changes.extend((n.source_start, n.source_end, '') for n in devices)
    for start, end, replacement in sorted(changes, reverse=True):
        text = text[:start] + replacement + text[end:]
    if machine and not any(n.name == 'include' and n.args == ['machine.kdl'] for n in nodes):
        text += '\ninclude optional=true "machine.kdl"\n'
    path.write_bytes(text.encode('utf-8'))
    return '\n'.join(machine)


def merge_machine(path, incoming):
    """Keep an existing fragment's debug options without duplicating its debug node."""
    import kdl
    text = path.read_text() if path.exists() else ''
    old_debug = next((node for node in kdl.parse(text).nodes if node.name == 'debug'), None)
    new_debug = next((node for node in kdl.parse(incoming).nodes if node.name == 'debug'), None)
    if old_debug is not None and new_debug is not None:
        changes = [(node.source_start, node.source_end, '') for node in old_debug.nodes
                   if node.name == 'render-drm-device']
        selectors = ''.join('    ' + incoming[node.source_start:node.source_end].strip() + '\n'
                            for node in new_debug.nodes)
        changes.append((old_debug.children_end, old_debug.children_end, '\n' + selectors))
        for start, end, replacement in sorted(changes, reverse=True):
            text = text[:start] + replacement + text[end:]
        incoming = incoming[:new_debug.source_start] + incoming[new_debug.source_end:]
    path.write_text(text + '\n' + incoming if text else incoming)


def capture(repo, relative, staged, hostname):
    """Route only machine fragments; main configs and libraries always stay shared."""
    host = repo / 'configs/hosts' / host_name(hostname)
    reject_links(host)
    check_fragments(host / relative, relative)
    # Inline hardware from a pre-portability config must not become a shared default.
    main = staged / 'config.kdl' if relative == Path('config/niri') else None
    if main and main.is_file():
        machine = split_niri(main)
        if machine:
            merge_machine(staged / 'machine.kdl', machine)
    # A host overlay owns its path, including deletions. Restore the shared default
    # into the staged tree after capturing the host version.
    paths = {relative / p.relative_to(staged) if staged.is_dir() else relative for p in files(staged)}
    host_scope = host / relative
    paths.update(relative / p.relative_to(host_scope) if host_scope.is_dir() else relative
                 for p in files(host_scope))
    for name in sorted(paths):
        if str(name) not in MACHINE_FILES:
            continue
        incoming = staged / name.relative_to(relative) if staged.is_dir() else staged
        target = host / name
        if incoming.is_file():
            copy(incoming, target)
            transform(target, 'capture')
        elif target.exists():
            target.unlink()
        original = repo / 'configs' / name
        if original.is_file():
            copy(original, incoming)
        elif incoming.exists():
            incoming.unlink()
    for path in files(staged):
        transform(path, 'capture')
    # The bash caller performs the final rsync, retaining its runtime exclusions.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('prepare', 'capture', 'render', 'encode'))
    parser.add_argument('paths', nargs='+')
    args = parser.parse_args()
    if args.operation == 'prepare':
        prepare(*(Path(p) for p in args.paths))
    elif args.operation == 'capture':
        repo, relative, staged, hostname = args.paths
        capture(Path(repo), Path(relative), Path(staged), hostname)
    else:
        for root in args.paths:
            for path in files(Path(root)):
                transform(path, 'render' if args.operation == 'render' else 'capture')


if __name__ == '__main__':
    main()

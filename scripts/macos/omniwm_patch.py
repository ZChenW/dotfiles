#!/usr/bin/env python3
"""Apply the dotfiles overlay to OmniWM's settings.toml.

OmniWM validates settings.toml strictly: a missing required key or an unknown
hotkey id rejects the whole file. So we never ship a full file. OmniWM writes
its own canonical defaults on first launch, and this script edits that file in
place:

* every [[hotkeys]] block is replaced by the bindings in hotkeys.tsv (actions
  left out are unassigned, which is what OmniWM does with missing ids);
* each `table.key` in settings.tsv has its value replaced where it already is;
* the [[appRules]] in app-rules.toml are added after OmniWM's own rules,
  replacing any earlier copy with the same id.

Ids are checked against the pristine default file, so a typo or an id removed
by an OmniWM update stops the patch before anything is written.
"""

import argparse
import os
import re
import sys
import tempfile

HEADER_RE = re.compile(r"^\s*(\[\[?)\s*([^\]]+?)\s*\]\]?\s*(#.*)?$")
ID_RE = re.compile(r'^\s*id\s*=\s*"([^"]+)"')


def read_tsv(path):
    rows = []
    with open(path, encoding="utf-8") as handle:
        for number, raw in enumerate(handle, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 2 or not parts[0].strip() or not parts[1].strip():
                raise SystemExit(f"{path}:{number}: expected two tab-separated columns")
            rows.append((parts[0].strip(), parts[1].strip(), number))
    return rows


def split_sections(lines):
    """Split into (header, kind, lines) sections; the preamble has header None."""
    sections = [[None, None, []]]
    for line in lines:
        match = HEADER_RE.match(line)
        if match:
            kind = "array" if match.group(1) == "[[" else "table"
            sections.append([match.group(2), kind, [line]])
        else:
            sections[-1][2].append(line)
    return sections


def schema_version(text):
    match = re.search(r"^schemaVersion\s*=\s*(\d+)", text, re.M)
    return match.group(1) if match else None


def hotkey_ids(lines):
    ids = []
    for header, kind, body in split_sections(lines):
        if header == "hotkeys" and kind == "array":
            for line in body:
                match = ID_RE.match(line)
                if match:
                    ids.append(match.group(1))
    return ids


def hotkey_blocks(rows):
    out = []
    for action, binding, _ in rows:
        out += ["[[hotkeys]]", f'binding = "{binding}"', f'id = "{action}"', ""]
    return out


def replace_hotkeys(sections, rows):
    result = []
    inserted = False
    for section in sections:
        header, kind, _ = section
        if header == "hotkeys" and kind == "array":
            if not inserted:
                result.append([None, None, hotkey_blocks(rows)])
                inserted = True
            continue
        result.append(section)
    if not inserted:
        result.append([None, None, [""] + hotkey_blocks(rows)])
    return result


def merge_app_rules(sections, rule_lines):
    """Add our [[appRules]] after OmniWM's, dropping older copies by id."""
    ours = [s for s in split_sections(rule_lines) if s[0] == "appRules" and s[1] == "array"]
    ids = []
    for section in ours:
        found = [ID_RE.match(line).group(1) for line in section[2] if ID_RE.match(line)]
        if not found:
            raise SystemExit("app-rules.toml: every [[appRules]] needs a fixed id")
        ids.extend(found)
    if len(set(ids)) != len(ids):
        raise SystemExit("app-rules.toml: duplicate rule id")

    def is_ours(section):
        return section[0] == "appRules" and section[1] == "array" and any(
            ID_RE.match(line) and ID_RE.match(line).group(1) in ids for line in section[2]
        )

    kept = [s for s in sections if not is_ours(s)]
    last = max((i for i, s in enumerate(kept) if s[0] == "appRules" and s[1] == "array"), default=None)
    blocks = []
    for section in ours:
        body = section[2]
        while body and not body[-1].strip():
            body = body[:-1]
        blocks.append([section[0], section[1], body + [""]])
    if last is None:
        return kept + blocks, len(ours)
    return kept[: last + 1] + blocks + kept[last + 1 :], len(ours)


def set_in_line(line, key, value):
    """Replace `key = old` in a plain line, or `key = x` inside an inline table."""
    plain = re.match(r"^(\s*" + re.escape(key) + r"\s*=\s*)(.*?)\s*$", line)
    if plain and not plain.group(2).startswith("{"):
        return plain.group(1) + value
    return None


def set_inline(line, outer, key, value):
    match = re.match(r"^(\s*" + re.escape(outer) + r"\s*=\s*\{)(.*)(\}\s*)$", line)
    if not match:
        return None
    inner, count = re.subn(
        r"(\b" + re.escape(key) + r"\s*=\s*)([^,}]+?)(\s*(,|$))",
        lambda m: m.group(1) + value + m.group(3),
        match.group(2),
        count=1,
    )
    if count == 0:
        return None
    return match.group(1) + inner + match.group(3)


def apply_setting(sections, path, value):
    """Set `path` (dotted) to `value`. Returns a note when the key was added."""
    parts = path.split(".")
    # Try [a.b] key=, then [a] b.key= / b = {key=...}, and so on outwards.
    for split in range(len(parts) - 1, 0, -1):
        table = ".".join(parts[:split])
        rest = parts[split:]
        for section in sections:
            if section[0] != table or section[1] != "table":
                continue
            body = section[2]
            dotted = ".".join(rest)
            for index, line in enumerate(body):
                new = set_in_line(line, dotted, value)
                if new is None and len(rest) == 2:
                    new = set_inline(line, rest[0], rest[1], value)
                if new is not None:
                    body[index] = new
                    return None
    # Not present: add it to the exact table if that table exists.
    table, key = ".".join(parts[:-1]), parts[-1]
    for section in sections:
        if section[0] == table and section[1] == "table":
            body = section[2]
            position = len(body)
            while position > 1 and not body[position - 1].strip():
                position -= 1
            body.insert(position, f"{key} = {value}")
            return f"added {path} (optional key, not in the generated file)"
    raise SystemExit(f"settings.tsv: no [{table}] table in settings.toml for {path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("settings_toml")
    parser.add_argument("--defaults", required=True, help="pristine OmniWM-generated settings.toml")
    parser.add_argument("--hotkeys", required=True)
    parser.add_argument("--settings", required=True)
    parser.add_argument("--app-rules")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    with open(args.defaults, encoding="utf-8") as handle:
        default_text = handle.read()
    known = set(hotkey_ids(default_text.splitlines()))
    if not known:
        raise SystemExit(f"{args.defaults}: no [[hotkeys]] entries; is this an OmniWM settings.toml?")

    rows = read_tsv(args.hotkeys)
    seen = {}
    errors = []
    for action, binding, number in rows:
        if action not in known:
            errors.append(f"hotkeys.tsv:{number}: unknown OmniWM action id {action!r}")
        if action in seen:
            errors.append(f"hotkeys.tsv:{number}: {action} already bound on line {seen[action]}")
        seen.setdefault(action, number)
    chords = {}
    for action, binding, number in rows:
        if binding != "Unassigned" and binding in chords:
            errors.append(f"hotkeys.tsv:{number}: {binding} also used by {chords[binding]}")
        chords.setdefault(binding, action)
    if errors:
        raise SystemExit("\n".join(errors))

    with open(args.settings_toml, encoding="utf-8") as handle:
        original = handle.read()
    # Hotkey ids change between schema versions (OmniWM migrates its own file),
    # so ids checked against an older default file would now be rejected.
    if schema_version(original) != schema_version(default_text):
        raise SystemExit(
            f"OmniWM upgraded settings.toml to schemaVersion {schema_version(original)} "
            f"(the id reference {args.defaults} is {schema_version(default_text)}).\n"
            "Update the ids in hotkeys.tsv for the new version, delete that reference file, "
            "and run apply again."
        )
    sections = replace_hotkeys(split_sections(original.splitlines()), rows)
    notes = []
    for path, value, _ in read_tsv(args.settings):
        note = apply_setting(sections, path, value)
        if note:
            notes.append(note)

    rule_count = 0
    if args.app_rules:
        with open(args.app_rules, encoding="utf-8") as handle:
            sections, rule_count = merge_app_rules(sections, handle.read().splitlines())

    lines = [line for section in sections for line in section[2]]
    text = "\n".join(lines).rstrip("\n") + "\n"

    for note in notes:
        print(f"note: {note}")
    print(f"{len(rows)} hotkeys bound; {len(known) - len(rows)} other actions unassigned")
    if args.app_rules:
        print(f"{rule_count} app rules")
    if text == original:
        print("settings.toml already up to date")
        return
    if args.dry_run:
        print(f"would rewrite {args.settings_toml}")
        return

    directory = os.path.dirname(os.path.abspath(args.settings_toml))
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".settings.", suffix=".toml")
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.chmod(tmp, os.stat(args.settings_toml).st_mode & 0o777)
    os.replace(tmp, args.settings_toml)
    print(f"rewrote {args.settings_toml}")


if __name__ == "__main__":
    sys.exit(main())

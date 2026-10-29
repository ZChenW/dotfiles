#!/usr/bin/env python3
"""Save, set and restore single macOS preference keys for scripts/macos.sh.

A key is addressed by DOMAIN and KEYPATH. DOMAIN is a `defaults` domain,
optionally prefixed with `currentHost:` for ByHost preferences. KEYPATH is
`/`-separated because preference keys themselves contain dots
(e.g. `AppleSymbolicHotKeys/64`).

    prefs.py save    DOMAIN KEYPATH FILE   # record the current value (or absence)
    prefs.py set     DOMAIN KEYPATH JSON   # write a value given as JSON
    prefs.py restore DOMAIN KEYPATH FILE   # put back what `save` recorded
    prefs.py get     DOMAIN KEYPATH        # print the current value as JSON

Values go through `defaults export` / `defaults import`, so types (bool vs int,
nested dicts) round-trip exactly.
"""

import json
import plistlib
import subprocess
import sys


def defaults_cmd(domain, verb):
    if domain.startswith("currentHost:"):
        return ["defaults", "-currentHost", verb, domain.split(":", 1)[1], "-"]
    return ["defaults", verb, domain, "-"]


def export(domain):
    result = subprocess.run(defaults_cmd(domain, "export"), capture_output=True)
    if result.returncode != 0 or not result.stdout.strip():
        return {}
    return plistlib.loads(result.stdout)


def import_(domain, data):
    payload = plistlib.dumps(data, fmt=plistlib.FMT_XML)
    subprocess.run(defaults_cmd(domain, "import"), input=payload, check=True)


def lookup(data, keys):
    node = data
    for key in keys:
        if not isinstance(node, dict) or key not in node:
            return False, None
        node = node[key]
    return True, node


def assign(data, keys, value):
    node = data
    for key in keys[:-1]:
        node = node.setdefault(key, {})
    node[keys[-1]] = value


def remove(data, keys):
    present, parent = lookup(data, keys[:-1])
    if present and isinstance(parent, dict):
        parent.pop(keys[-1], None)


def main(argv):
    if len(argv) < 3:
        raise SystemExit(__doc__)
    command, domain, keypath = argv[0], argv[1], argv[2]
    keys = keypath.split("/")

    if command == "get":
        present, value = lookup(export(domain), keys)
        print(json.dumps(value, default=str) if present else "<unset>")
    elif command == "save":
        present, value = lookup(export(domain), keys)
        record = {"domain": domain, "keypath": keypath, "present": present}
        if present:
            record["value"] = value
        with open(argv[3], "wb") as handle:
            plistlib.dump(record, handle)
    elif command == "set":
        data = export(domain)
        assign(data, keys, json.loads(argv[3]))
        import_(domain, data)
    elif command == "restore":
        with open(argv[3], "rb") as handle:
            record = plistlib.load(handle)
        data = export(domain)
        if record["present"]:
            assign(data, keys, record["value"])
        else:
            remove(data, keys)
        import_(domain, data)
        # `defaults import` merges top-level keys into the domain rather than
        # replacing it, so a key that was unset has to be deleted outright.
        # (A nested key goes with its parent, which import does replace.)
        if not record["present"] and len(keys) == 1:
            delete = defaults_cmd(domain, "delete")[:-1] + [keys[0]]
            subprocess.run(delete, capture_output=True)
    else:
        raise SystemExit(f"unknown command {command!r}")


if __name__ == "__main__":
    main(sys.argv[1:])

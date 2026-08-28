# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Config materialization: .conf.dist -> .conf, merging forward on
upgrade/repair rather than overwriting a user's existing tuning.

Generalizes the pattern this project's dml-start.sh already uses for
playerbots.conf (_ensure_playerbots_conf-style: instantiate from .dist if
missing, otherwise only ADD genuinely new keys, never touch an existing
value)."""

import os
import re

_KEY_LINE = re.compile(r"^\s*([A-Za-z0-9_.]+)\s*=\s*(.*?)\s*$")


def _parse_conf(path):
    """Return an ordered dict of key -> raw value string, ignoring comments
    and blank lines. Best-effort -- this is not a full AzerothCore .conf
    parser, just enough to detect existing keys for the merge-forward
    behavior below."""
    values = {}
    if not os.path.isfile(path):
        return values
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            m = _KEY_LINE.match(line)
            if m:
                values[m.group(1)] = m.group(2)
    return values


def materialize(dist_path, target_path, overrides=None):
    """Instantiate target_path from dist_path if target_path doesn't exist
    yet (fresh install). If target_path already exists (upgrade/repair),
    leave every existing key's value untouched and only append keys present
    in dist_path but missing from target_path -- never silently overwrites
    a user's tuning.

    overrides: dict of key -> value applied ONLY when writing a brand-new
    file (fresh install), e.g. {"EchoesStats.Enable": "1"} for this
    project's public-release defaults. Never applied to an existing file --
    that would be exactly the "silently overwrite custom tuning" behavior
    this function exists to avoid.
    """
    if not os.path.isfile(dist_path):
        raise FileNotFoundError(f"template not found: {dist_path}")

    if not os.path.isfile(target_path):
        with open(dist_path, "r", encoding="utf-8") as f:
            content = f.read()
        if overrides:
            for key, value in overrides.items():
                pattern = re.compile(rf"^{re.escape(key)}\s*=\s*.*$", re.MULTILINE)
                if pattern.search(content):
                    content = pattern.sub(f"{key} = {value}", content, count=1)
        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        with open(target_path, "w", encoding="utf-8") as f:
            f.write(content)
        return {"action": "created", "keys_added": []}

    existing_keys = set(_parse_conf(target_path))
    dist_keys = _parse_conf(dist_path)
    new_keys = [k for k in dist_keys if k not in existing_keys]
    if not new_keys:
        return {"action": "unchanged", "keys_added": []}

    with open(dist_path, "r", encoding="utf-8") as dist_f:
        dist_lines = dist_f.readlines()

    appended = []
    with open(target_path, "a", encoding="utf-8") as target_f:
        target_f.write("\n# --- keys added by installer merge-forward ---\n")
        for key in new_keys:
            pattern = re.compile(rf"^{re.escape(key)}\s*=")
            for line in dist_lines:
                if pattern.match(line.strip()):
                    target_f.write(line if line.endswith("\n") else line + "\n")
                    appended.append(key)
                    break

    return {"action": "merged", "keys_added": appended}

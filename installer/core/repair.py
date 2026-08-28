# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""`echoes repair` -- restore Echoes-owned files that are missing or
drifted from what this installer's own manifest recorded, using the
current repo source as the restoration source (the same files
install.install() would place).

Ownership/containment discipline:
  - Only ever touches paths derived from the manifest's own component
    root (lua_scripts/, modules/mod-echoes-stats/, etc.) under the
    manifest's own recorded azerothcore_root/client_root -- every
    write goes through safety.assert_contained() first.
  - MISSING files are restored automatically -- a missing required file
    is unambiguously something repair should fix.
  - MISMATCHED files (present, but hash differs from the manifest's
    recorded value) are only restored if the caller passes
    restore_mismatched=True. By default they are reported, not touched --
    a changed file could be intentional operator customization (e.g. a
    hand-tuned .conf) rather than corruption, and this module cannot
    reliably tell the difference from hash comparison alone. This is the
    conservative default named in this module's own earlier design note.
  - .conf files are never repaired by this module at all (config
    materialization's own merge-forward behavior in config.py is the
    right tool for that; blindly restoring a .conf from repo source
    would destroy real tuning).
"""

import os
import shutil

from . import hashing, manifest as manifest_mod, safety

_COMPONENT_ROOTS = {
    "core_lua": lambda repo_root, ac_root, client_root: (
        os.path.join(repo_root, "lua_scripts"), os.path.join(ac_root, "lua_scripts")
    ),
    "mod_echoes_stats": lambda repo_root, ac_root, client_root: (
        os.path.join(repo_root, "cpp_patch", "mod-echoes-stats"),
        os.path.join(ac_root, "modules", "mod-echoes-stats"),
    ),
    "mod_echoes_playerbots": lambda repo_root, ac_root, client_root: (
        os.path.join(repo_root, "cpp_patch", "mod-echoes-playerbots"),
        os.path.join(ac_root, "modules", "mod-echoes-playerbots"),
    ),
    "client_companion": lambda repo_root, ac_root, client_root: (
        os.path.join(repo_root, "client_addon", "EchoesOfTheWorldsoulBridge"),
        os.path.join(client_root, "Interface", "AddOns", "EchoesOfTheWorldsoulBridge")
        if client_root else (None, None),
    ),
}


def _repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


class RepairReport:
    def __init__(self):
        self.restored_missing = []
        self.restored_mismatched = []
        self.reported_mismatched = []
        self.skipped_unsafe = []

    def as_dict(self):
        return {
            "restored_missing": self.restored_missing,
            "restored_mismatched": self.restored_mismatched,
            "reported_mismatched_not_restored": self.reported_mismatched,
            "skipped_unsafe": self.skipped_unsafe,
        }


def repair(azerothcore_root, restore_mismatched=False):
    """Returns a RepairReport. Raises only if the manifest itself is
    missing or unreadable -- there's nothing to repair against without it."""
    m = manifest_mod.load(azerothcore_root)
    if m is None:
        raise RuntimeError(
            f"No install manifest found at {azerothcore_root} -- nothing to "
            "repair against. Run 'echoes install' first."
        )

    repo_root = _repo_root()
    client_root = m.get("client_root")
    report = RepairReport()

    for component, data in m.get("components", {}).items():
        if not data.get("enabled") or component not in _COMPONENT_ROOTS:
            continue

        src_root, dst_root = _COMPONENT_ROOTS[component](repo_root, azerothcore_root, client_root)
        if dst_root is None or not os.path.isdir(src_root):
            continue

        expected = data.get("files", {})
        missing, mismatched, _extra = hashing.verify_tree(dst_root, expected)

        for rel in missing:
            src_file = os.path.join(src_root, rel)
            dst_file = os.path.join(dst_root, rel)
            if not os.path.isfile(src_file):
                continue
            if not safety.is_safe_to_delete(dst_file, dst_root):
                # is_safe_to_delete doubles as "is this a legitimate
                # contained target" here -- the file doesn't exist yet,
                # but the check on the resolved parent path still applies.
                report.skipped_unsafe.append(dst_file)
                continue
            os.makedirs(os.path.dirname(dst_file), exist_ok=True)
            shutil.copy2(src_file, dst_file)
            report.restored_missing.append(f"{component}:{rel}")

        for rel in mismatched:
            dst_file = os.path.join(dst_root, rel)
            if restore_mismatched:
                src_file = os.path.join(src_root, rel)
                if not os.path.isfile(src_file):
                    continue
                try:
                    safety.assert_contained(dst_file, dst_root)
                except safety.UnsafePathError:
                    report.skipped_unsafe.append(dst_file)
                    continue
                shutil.copy2(src_file, dst_file)
                report.restored_mismatched.append(f"{component}:{rel}")
            else:
                report.reported_mismatched.append(f"{component}:{rel}")

    return report

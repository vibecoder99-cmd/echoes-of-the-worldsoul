# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""`echoes uninstall` -- standard (non-purge) uninstall.

Removes only manifest-recorded Echoes-owned files/directories:
  - lua_scripts/: only the individual files the manifest recorded (not
    the whole directory -- it may be shared with other Eluna scripts on
    some installs), each containment-checked before removal.
  - modules/mod-echoes-stats/, modules/mod-echoes-playerbots/: whole
    directories, since these are dedicated Echoes-owned module trees.
  - The Client Companion AddOn directory, whole tree.
  - patch-E.MPQ, ONLY if its current hash still matches the manifest's
    recorded value (an operator who has since regenerated or replaced it
    outside this installer is not silently overwritten/removed).

NEVER touches: mod-ale, mod-playerbots, any other AzerothCore module,
any `ap_*` database table (persistent-progression retention is the
explicit default -- 15 of 19 tables are classified that way and are
never dropped by a non-purge operation), or the legacy patch-4.MPQ
(that file's disposition is legacy_migration.py's concern, on install,
not uninstall's).

A separate, explicit, confirmation-gated `--purge` mode (dropping the
ap_* schema after a mandatory backup) is future scope -- not implemented
here.
"""

import os

from . import hashing, manifest as manifest_mod, safety


class UninstallReport:
    def __init__(self):
        self.removed = []
        self.skipped_hash_mismatch = []
        self.skipped_unsafe = []
        self.skipped_missing = []
        self.database_action = "retained (standard uninstall never touches ap_* tables)"
        self.external_prerequisites_touched = []  # always empty; asserted by tests


def uninstall(azerothcore_root):
    m = manifest_mod.load(azerothcore_root)
    if m is None:
        raise RuntimeError(
            f"No install manifest found at {azerothcore_root} -- nothing to uninstall."
        )

    roots = manifest_mod.effective_roots(m)
    client_root = roots["client"]
    report = UninstallReport()

    # --- lua_scripts: file-scoped removal only ---
    core_lua = m.get("components", {}).get("core_lua")
    if core_lua and core_lua.get("enabled"):
        lua_root = os.path.join(roots["lua"], "lua_scripts")
        for rel in core_lua.get("files", {}):
            target = os.path.join(lua_root, rel)
            try:
                removed = safety.safe_remove_file(target, lua_root)
            except safety.UnsafePathError:
                report.skipped_unsafe.append(target)
                continue
            if removed:
                report.removed.append(f"core_lua:{rel}")
            else:
                report.skipped_missing.append(f"core_lua:{rel}")

    # --- whole-directory Echoes-owned components ---
    whole_dir_components = {
        "mod_echoes_stats": os.path.join(azerothcore_root, "modules", "mod-echoes-stats"),
        "mod_echoes_playerbots": os.path.join(azerothcore_root, "modules", "mod-echoes-playerbots"),
    }
    if client_root:
        whole_dir_components["client_companion"] = os.path.join(
            client_root, "Interface", "AddOns", "EchoesOfTheWorldsoulBridge"
        )

    for component, path in whole_dir_components.items():
        data = m.get("components", {}).get(component)
        if not data or not data.get("enabled"):
            continue
        root_for_containment = os.path.dirname(path)
        try:
            removed = safety.safe_remove_tree(path, root_for_containment)
        except safety.UnsafePathError:
            report.skipped_unsafe.append(path)
            continue
        if removed:
            report.removed.append(component)
        else:
            report.skipped_missing.append(component)

    # --- patch-E.MPQ: hash-gated ---
    pmpq = m.get("patch_mpq", {})
    if pmpq.get("generated") and pmpq.get("path"):
        path = pmpq["path"]
        current_hash = hashing.sha256_file(path)
        if current_hash is None:
            report.skipped_missing.append("patch_mpq")
        elif current_hash != pmpq.get("sha256"):
            report.skipped_hash_mismatch.append(path)
        else:
            data_dir = os.path.dirname(path)
            try:
                removed = safety.safe_remove_file(path, data_dir)
            except safety.UnsafePathError:
                report.skipped_unsafe.append(path)
                removed = False
            if removed:
                report.removed.append("patch_mpq")

    return report

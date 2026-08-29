# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""The installer's JSON install manifest -- format per
E2J13-INSTALL-UPGRADE-UNINSTALL-MODEL.md ("Format recommendation: JSON").

This is the single source of truth an installed system carries about what
Echoes put there: which components, which files (with hashes, for verify/
repair), which config keys the installer owns (vs. user-tuned), what got
backed up and where, and the current Playerbots-integration state. verify/
repair/upgrade/uninstall all read this file; nothing re-derives ownership
by guessing from file contents or paths.

This is NOT a database-migration framework -- schema evolution stays
entirely inside sql/schema/30_versioned_migrations.sql's own guarded
ALTER/CREATE statements, per the frozen design. The manifest only records
which schema version was last applied.
"""

import json
import os

MANIFEST_FILENAME = "echoes-install-manifest.json"
MANIFEST_FORMAT_VERSION = 1


def default_manifest():
    return {
        "manifest_format_version": MANIFEST_FORMAT_VERSION,
        "product": "echoes-of-the-worldsoul",
        "product_version": None,
        "installed_at": None,
        "last_modified_at": None,
        "azerothcore_root": None,
        "client_root": None,
        "roots": {
            # Effective destination roots used at install time. "lua" and
            # "config" default to azerothcore_root when a deployment's
            # lua_scripts/ and etc/modules/ live alongside modules/ (the
            # traditional bare-metal layout). A split Docker/DML-style
            # layout records its actual runtime distribution root(s) here
            # instead -- see install.py's --lua-root/--config-root.
            # Never None once an install has run; use effective_roots()
            # below to resolve a manifest that predates this field.
            "lua": None,
            "config": None,
        },
        "components": {
            # component name -> {
            #   "enabled": bool,
            #   "files": {relative_path: sha256, ...},
            #   "installed_at": iso8601,
            # }
        },
        "sql": {
            "schema_version_applied": None,
            "applied_at": None,
        },
        "patch_mpq": {
            "generated": False,
            "path": None,
            "sha256": None,
            "internal_files": [],
            "vanilla_dbc_sha256": None,
            "vanilla_dbc_provenance": None,
        },
        "playerbots_integration": {
            "detected_present": False,
            "compatibility_confirmed": False,
            "enabled": False,
            "reason": None,
        },
        "config_ownership": {
            # config file path -> "installer-managed" | "user-modified"
        },
        "backups": [
            # {"timestamp": ..., "label": ..., "path": ..., "of": ...}
        ],
    }


def manifest_path(azerothcore_root):
    return os.path.join(azerothcore_root, MANIFEST_FILENAME)


def load(azerothcore_root):
    """Return the manifest dict, or None if no manifest exists at this
    target (i.e. this is a genuine fresh-install target)."""
    path = manifest_path(azerothcore_root)
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if data.get("manifest_format_version") != MANIFEST_FORMAT_VERSION:
        raise ValueError(
            f"manifest format version {data.get('manifest_format_version')!r} "
            f"is not supported by this installer (expects {MANIFEST_FORMAT_VERSION})"
        )
    return data


def save(azerothcore_root, manifest, timestamp):
    manifest["last_modified_at"] = timestamp
    path = manifest_path(azerothcore_root)
    tmp_path = path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp_path, path)  # atomic on both POSIX and Windows
    return path


def effective_roots(manifest):
    """Resolve the actual destination roots this manifest's components
    were installed under, tolerating a manifest written before the
    "roots" field existed (format version 1 is unchanged -- this is an
    additive, backward-compatible field, not a version bump). A manifest
    with no "roots" block, or one whose "lua"/"config" entries are still
    None, defaults both to the manifest's own azerothcore_root -- exactly
    matching the traditional single-root layout every pre-existing
    installer-managed deployment was actually installed under."""
    ac_root = manifest.get("azerothcore_root")
    roots = manifest.get("roots") or {}
    return {
        "azerothcore": ac_root,
        "lua": roots.get("lua") or ac_root,
        "config": roots.get("config") or ac_root,
        "client": manifest.get("client_root"),
    }


def record_backup(manifest, timestamp, label, backup_path, of_path):
    manifest["backups"].append({
        "timestamp": timestamp,
        "label": label,
        "path": backup_path,
        "of": of_path,
    })

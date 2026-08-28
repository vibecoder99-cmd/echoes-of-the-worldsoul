# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Controlled retirement of historical Echoes-owned artifacts that a real
prior public release (e.g. v1.6.0-rc1) may have installed, but current
source no longer ships.

Found by the E2j17 Compatibility Verification attack pass: upgrading
from an export of the actual v1.6.0-rc1 tag left `ap_gm_aether.lua`
(confirmed DEVELOPMENT ONLY, deliberately excluded from current source)
and the old `modules/mod-attunement-plus/` module directory (superseded
by `mod-echoes-stats`/`mod-echoes-playerbots`) behind, untouched, because
install()'s lua_scripts sync only ever copies from current source and
never deletes a destination-only orphan, and nothing anywhere ever looked
for the old module's name.

This is NOT a general "clean up anything that looks old" mechanism.
Every entry below requires POSITIVE IDENTITY PROOF (filename AND a
stable content signature confirmed present in both the historical
v1.6.0-rc1 release and the current WSL runtime's own copy, where
applicable) before anything is touched. A same-named file that fails the
content-signature check is left completely alone and reported, never
retired on filename alone -- this is deliberate: it is the only way to
avoid ever deleting a user's own same-named script or an unrelated
module.
"""

import os

from . import backup, manifest as manifest_mod, safety

# --- Lua file retirements -----------------------------------------------

# Each entry: filename -> a content signature that must be found in the
# file for it to be positively identified as this specific historical
# Echoes artifact. Confirmed present, verbatim, in both the exported
# v1.6.0-rc1 release and the current (pre-removal) WSL copy -- the file
# was kept in sync with internal API changes across that whole span
# without ever losing this header, which is exactly what makes it a
# reliable signature rather than a brittle single-version hash.
LEGACY_LUA_RETIREMENTS = {
    "ap_gm_aether.lua": {
        "content_signature": "GM Aether Grant Tool",
        "reason": (
            "Confirmed present in the real v1.6.0-rc1 public release, "
            "confirmed DEVELOPMENT ONLY by direct source classification, "
            "confirmed absent from current tracked lua_scripts/ (removed "
            "deliberately during the E2j16 sync) -- safe to retire on "
            "upgrade from any release that still has it."
        ),
    },
}

# --- C++ module retirements ----------------------------------------------

# Each entry: legacy module directory name -> the exact files the
# historical patch created plus a content signature found in them.
# Retirement additionally requires that ALL of this entry's
# "superseded_by" module names are already present (installed as part of
# the SAME operation, before retirement runs) -- never remove old content
# before its replacement is confirmed in place.
LEGACY_MODULE_RETIREMENTS = {
    "mod-attunement-plus": {
        "required_files": ["src/mod_attunement_plus.cpp", "src/mod_attunement_plus_loader.cpp"],
        "content_signature": "Echoes of the Worldsoul stat application module for AzerothCore",
        # mod-attunement-plus was a pure stat-application module -- its
        # own content signature says so, and it predates Playerbots
        # integration entirely (mod-echoes-playerbots is a later, separate
        # addition, not part of what this module did). Its direct
        # successor is mod-echoes-stats only; retirement does not wait on
        # the orthogonal, optional Playerbots module.
        #
        # NOTE: this must match install.py's manifest COMPONENT KEY
        # naming (underscore, e.g. "mod_echoes_stats" as used in
        # m["components"]), not the module DIRECTORY naming (hyphen,
        # "mod-echoes-stats") -- retire_legacy_modules() compares against
        # currently_installed_components, which is m["components"].keys().
        "superseded_by": ["mod_echoes_stats"],
        "reason": (
            "The v1.6.0-rc1-era single-module stat-application patch, "
            "superseded by mod-echoes-stats. Retired only after its "
            "replacement is confirmed installed."
        ),
    },
}


def _file_contains(path, needle):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return needle in f.read()
    except (OSError, UnicodeDecodeError):
        return False


def identify_legacy_lua_file(path, filename):
    entry = LEGACY_LUA_RETIREMENTS.get(filename)
    if entry is None:
        return False
    if not os.path.isfile(path):
        return False
    return _file_contains(path, entry["content_signature"])


def identify_legacy_module_dir(path, dirname):
    entry = LEGACY_MODULE_RETIREMENTS.get(dirname)
    if entry is None:
        return False
    if not os.path.isdir(path):
        return False
    for rel in entry["required_files"]:
        full = os.path.join(path, rel)
        if not os.path.isfile(full):
            return False
    # At least one required file must carry the content signature.
    return any(
        _file_contains(os.path.join(path, rel), entry["content_signature"])
        for rel in entry["required_files"]
    )


def retire_legacy_lua(lua_dir, backups_root, timestamp, manifest, record_backup=True):
    """Scan lua_dir for any file matching a known legacy retirement entry
    by filename, and only actually retire it if the content signature
    also positively matches. Never touches a same-named file that fails
    the signature check -- it's reported, not removed.

    Returns (retired, left_unproven) -- both lists of filenames.
    """
    retired, left_unproven = [], []
    if not os.path.isdir(lua_dir):
        return retired, left_unproven

    for filename in list(LEGACY_LUA_RETIREMENTS.keys()):
        target = os.path.join(lua_dir, filename)
        if not os.path.isfile(target):
            continue
        if identify_legacy_lua_file(target, filename):
            safety.assert_contained(target, lua_dir)
            b = backup.backup_path(target, backups_root, timestamp, "legacy-lua-retirement")
            if b and record_backup:
                manifest_mod.record_backup(manifest, timestamp, "legacy-lua-retirement", b, target)
            os.remove(target)
            retired.append(filename)
        else:
            left_unproven.append(filename)

    return retired, left_unproven


def retire_legacy_modules(modules_root, backups_root, timestamp, manifest, currently_installed_components):
    """Scan modules_root for any directory matching a known legacy module
    retirement entry. Only retires it if:
      1. Positive identity is confirmed (required files + content signature).
      2. Every one of its declared replacement modules is already
         installed (present in currently_installed_components).
    Otherwise leaves it untouched and reports it as unresolved, with a reason.

    Returns (retired, left_unresolved) -- lists of directory names, and
    left_unresolved entries are (dirname, reason) tuples.
    """
    retired, left_unresolved = [], []
    if not os.path.isdir(modules_root):
        return retired, left_unresolved

    for dirname, entry in LEGACY_MODULE_RETIREMENTS.items():
        path = os.path.join(modules_root, dirname)
        if not os.path.isdir(path):
            continue

        if not identify_legacy_module_dir(path, dirname):
            left_unresolved.append((dirname, "present but identity not positively confirmed -- left untouched"))
            continue

        missing_replacements = [m for m in entry["superseded_by"] if m not in currently_installed_components]
        if missing_replacements:
            left_unresolved.append((
                dirname,
                f"positively identified but replacement(s) not yet installed: {missing_replacements} -- left untouched"
            ))
            continue

        safety.assert_contained(path, modules_root)
        b = backup.backup_tree(path, backups_root, timestamp, "legacy-module-retirement")
        if b:
            manifest_mod.record_backup(manifest, timestamp, "legacy-module-retirement", b, path)
        import shutil
        shutil.rmtree(path)
        retired.append(dirname)

    return retired, left_unresolved

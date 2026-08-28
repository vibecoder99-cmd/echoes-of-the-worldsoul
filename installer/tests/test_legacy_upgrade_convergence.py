#!/usr/bin/env python3
# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Regression test: ACTUAL LEGACY RELEASE -> CURRENT CONVERGENCE.

Exports the real `v1.6.0-rc1` git tag from this repository's own history
(never a synthetic placeholder), builds a realistic legacy install layout
from it (including the old `modules/mod-attunement-plus/` module a real
historical install would have had), runs it through `echoes upgrade`,
and proves the result converges to an identical product state as a fresh
current install -- byte-for-byte for every Lua file, and zero stale
legacy artifacts left behind.

This exists because the first Compatibility Verification attack pass
found exactly two real defects this way: a confirmed dev-only Lua file
(`ap_gm_aether.lua`) and the entire old module directory both survived
an upgrade from the real v1.6.0-rc1 tree. Both are fixed in
`legacy_retirement.py` / `install.py`; this test is what proves it stays
fixed.

Requires ECHOES_TEST_MYSQL_* env vars (skipped, not faked, if absent).
Requires the repository to have the `v1.6.0-rc1` tag reachable (skipped,
not faked, if the tag can't be resolved -- e.g. a shallow clone).
"""

import filecmp
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from core import install, manifest as manifest_mod, upgrade as upgrade_mod

FAILURES = []


def check(label, cond):
    if cond:
        print(f"  [PASS] {label}")
    else:
        print(f"  [FAIL] {label}")
        FAILURES.append(label)


def _repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _mysql_args():
    host = os.environ.get("ECHOES_TEST_MYSQL_HOST")
    if not host:
        return None
    return ["-u", os.environ.get("ECHOES_TEST_MYSQL_USER", "root"),
            f"-p{os.environ.get('ECHOES_TEST_MYSQL_PASSWORD', '')}",
            "-h", host, "-P", os.environ.get("ECHOES_TEST_MYSQL_PORT", "3306")]


STUB_SQL = """
CREATE TABLE IF NOT EXISTS item_template (
    entry INT UNSIGNED NOT NULL PRIMARY KEY, class INT NOT NULL DEFAULT 0,
    subclass INT NOT NULL DEFAULT 0, SoundOverrideSubclass INT NOT NULL DEFAULT -1,
    name VARCHAR(255) NOT NULL DEFAULT '', displayid INT NOT NULL DEFAULT 0,
    Quality TINYINT NOT NULL DEFAULT 0, BuyCount INT NOT NULL DEFAULT 1,
    BuyPrice INT NOT NULL DEFAULT 0, SellPrice INT NOT NULL DEFAULT 0,
    InventoryType INT NOT NULL DEFAULT 0, AllowableClass INT NOT NULL DEFAULT -1,
    AllowableRace INT NOT NULL DEFAULT -1, ItemLevel INT NOT NULL DEFAULT 0,
    RequiredLevel INT NOT NULL DEFAULT 0, stackable INT NOT NULL DEFAULT 1,
    maxcount INT NOT NULL DEFAULT 0, spellid_1 INT NOT NULL DEFAULT 0,
    spelltrigger_1 INT NOT NULL DEFAULT 0, spellcharges_1 INT NOT NULL DEFAULT 0,
    spellcooldown_1 INT NOT NULL DEFAULT -1, spellcategory_1 INT NOT NULL DEFAULT 0,
    spellcategorycooldown_1 INT NOT NULL DEFAULT -1, spellid_2 INT NOT NULL DEFAULT 0,
    spellid_3 INT NOT NULL DEFAULT 0, spellid_4 INT NOT NULL DEFAULT 0,
    spellid_5 INT NOT NULL DEFAULT 0, delay INT NOT NULL DEFAULT 0,
    bonding INT NOT NULL DEFAULT 0, description VARCHAR(255) NOT NULL DEFAULT '',
    RequiredDisenchantSkill INT NOT NULL DEFAULT -1, Material INT NOT NULL DEFAULT 0
) ENGINE=InnoDB;
"""


def _reset_db(args, name):
    subprocess.run(["mysql", *args, "-e", f"DROP DATABASE IF EXISTS {name}; CREATE DATABASE {name};"], check=True)


def _export_v160(dest):
    result = subprocess.run(
        ["git", "-C", _repo_root(), "archive", "v1.6.0-rc1"],
        capture_output=True, check=False,
    )
    if result.returncode != 0:
        return False
    tar_path = os.path.join(dest, "v160.tar")
    with open(tar_path, "wb") as f:
        f.write(result.stdout)
    import tarfile
    with tarfile.open(tar_path) as tf:
        tf.extractall(dest)
    os.remove(tar_path)
    return True


LEGACY_MODULE_SIGNATURE = "Echoes of the Worldsoul stat application module for AzerothCore"


def test_legacy_release_converges_to_current():
    print("test_legacy_release_converges_to_current (v1.6.0-rc1 -> current, requires ECHOES_TEST_MYSQL_* env vars + the v1.6.0-rc1 tag)")
    args = _mysql_args()
    if args is None:
        print("  [SKIP] no disposable MySQL configured via ECHOES_TEST_MYSQL_* env vars")
        return

    export_dir = tempfile.mkdtemp(prefix="echoes-v160-export-")
    if not _export_v160(export_dir):
        print("  [SKIP] v1.6.0-rc1 tag not resolvable in this checkout (e.g. shallow clone)")
        shutil.rmtree(export_dir, ignore_errors=True)
        return

    _reset_db(args, "acore_characters_v160test")
    _reset_db(args, "acore_world_v160test")
    subprocess.run(["mysql", *args, "acore_world_v160test", "-e", STUB_SQL], check=True)
    _reset_db(args, "acore_characters_freshtest")
    _reset_db(args, "acore_world_freshtest")
    subprocess.run(["mysql", *args, "acore_world_freshtest", "-e", STUB_SQL], check=True)

    legacy_root = tempfile.mkdtemp(prefix="echoes-legacy-ac-")
    fresh_root = tempfile.mkdtemp(prefix="echoes-fresh-ac-")
    try:
        os.makedirs(os.path.join(legacy_root, "modules", "mod-ale"))
        shutil.copytree(os.path.join(export_dir, "lua_scripts"),
                         os.path.join(legacy_root, "lua_scripts"))

        # Realistic old module layout with the real content signature --
        # a fixture without it would not actually exercise the identity
        # check in legacy_retirement.py.
        old_src = os.path.join(legacy_root, "modules", "mod-attunement-plus", "src")
        os.makedirs(old_src)
        with open(os.path.join(old_src, "mod_attunement_plus.cpp"), "w") as f:
            f.write(f"// {LEGACY_MODULE_SIGNATURE}\n")
        with open(os.path.join(old_src, "mod_attunement_plus_loader.cpp"), "w") as f:
            f.write("// loader\n")

        check("legacy install has no manifest before upgrade", manifest_mod.load(legacy_root) is None)

        upgrade_opts = install.InstallOptions(
            azerothcore_root=legacy_root, mysql_args=args,
            characters_database="acore_characters_v160test", world_database="acore_world_v160test",
        )
        result = upgrade_mod.upgrade(upgrade_opts, target_product_version="1.7.1")
        check("upgrade from real v1.6.0-rc1 tree succeeds", result is not None)
        check("upgrade recorded previous_manifest_present=False for the legacy install",
              result["previous_manifest_present"] is False)

        m = manifest_mod.load(legacy_root)
        retired_lua = m.get("legacy_retirement", {}).get("lua", {}).get("retired", [])
        retired_modules = m.get("legacy_retirement", {}).get("modules", {}).get("retired", [])
        check("manifest records ap_gm_aether.lua as retired", "ap_gm_aether.lua" in retired_lua)
        check("manifest records mod-attunement-plus as retired", "mod-attunement-plus" in retired_modules)

        check("legacy ap_gm_aether.lua no longer present after upgrade",
              not os.path.isfile(os.path.join(legacy_root, "lua_scripts", "ap_gm_aether.lua")))
        check("legacy modules/mod-attunement-plus/ no longer present after upgrade",
              not os.path.isdir(os.path.join(legacy_root, "modules", "mod-attunement-plus")))
        check("a backup of the retired module was made before removal",
              os.path.isdir(os.path.join(legacy_root, "echoes-installer-backups", "legacy-module-retirement")))
        check("a backup of the retired Lua file was made before removal",
              os.path.isdir(os.path.join(legacy_root, "echoes-installer-backups", "legacy-lua-retirement")))

        # --- Fresh install for convergence comparison ---
        os.makedirs(os.path.join(fresh_root, "modules", "mod-ale"))
        fresh_opts = install.InstallOptions(
            azerothcore_root=fresh_root, mysql_args=args,
            characters_database="acore_characters_freshtest", world_database="acore_world_freshtest",
        )
        install.install(fresh_opts)

        fresh_lua = set(os.listdir(os.path.join(fresh_root, "lua_scripts")))
        legacy_lua_after = set(os.listdir(os.path.join(legacy_root, "lua_scripts")))
        check("fresh install and v1.6.0-upgrade converge to the identical Lua file SET",
              fresh_lua == legacy_lua_after)

        mismatched = [
            name for name in sorted(fresh_lua)
            if not filecmp.cmp(
                os.path.join(fresh_root, "lua_scripts", name),
                os.path.join(legacy_root, "lua_scripts", name),
                shallow=False,
            )
        ]
        check("every converged Lua file is byte-identical", len(mismatched) == 0)
        if mismatched:
            print("  MISMATCHED:", mismatched)

        check("no stale mod-attunement-plus survives anywhere under modules/",
              not os.path.isdir(os.path.join(legacy_root, "modules", "mod-attunement-plus")))
        check("current mod-echoes-stats present in both", os.path.isdir(
            os.path.join(fresh_root, "modules", "mod-echoes-stats")) and os.path.isdir(
            os.path.join(legacy_root, "modules", "mod-echoes-stats")))
    finally:
        shutil.rmtree(export_dir, ignore_errors=True)
        shutil.rmtree(legacy_root, ignore_errors=True)
        shutil.rmtree(fresh_root, ignore_errors=True)


if __name__ == "__main__":
    test_legacy_release_converges_to_current()

    print()
    if FAILURES:
        print(f"{len(FAILURES)} check(s) FAILED: {FAILURES}")
        sys.exit(1)
    print("All checks passed (or were explicitly skipped where noted).")

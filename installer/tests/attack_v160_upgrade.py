#!/usr/bin/env python3
"""Disposable attack: upgrade from the ACTUAL exported v1.6.0-rc1 tree
(not a synthetic placeholder) through the current installer, then diff
against a clean fresh install. Not part of the tracked suite."""
import filecmp
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from core import install, manifest as manifest_mod, upgrade as upgrade_mod

V160_EXPORT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/echoes-v160-export"

FAILURES = []


def check(label, cond):
    if cond:
        print(f"  [PASS] {label}")
    else:
        print(f"  [FAIL] {label}")
        FAILURES.append(label)


def mysql_args():
    host = os.environ["ECHOES_TEST_MYSQL_HOST"]
    return ["-u", os.environ.get("ECHOES_TEST_MYSQL_USER", "root"),
            f"-p{os.environ.get('ECHOES_TEST_MYSQL_PASSWORD', '')}",
            "-h", host, "-P", os.environ.get("ECHOES_TEST_MYSQL_PORT", "3306")]


def reset_db(args, dbname):
    subprocess.run(["mysql", *args, "-e", f"DROP DATABASE IF EXISTS {dbname}; CREATE DATABASE {dbname};"], check=True)


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


def main():
    args = mysql_args()
    reset_db(args, "acore_characters_v160")
    reset_db(args, "acore_world_v160")
    subprocess.run(["mysql", *args, "acore_world_v160", "-e", STUB_SQL], check=True)
    reset_db(args, "acore_characters_fresh")
    reset_db(args, "acore_world_fresh")
    subprocess.run(["mysql", *args, "acore_world_fresh", "-e", STUB_SQL], check=True)

    # --- Build a realistic v1.6.0-rc1-era install layout ---
    legacy_root = tempfile.mkdtemp(prefix="echoes-v160-ac-")
    os.makedirs(os.path.join(legacy_root, "modules", "mod-ale"))
    shutil.copytree(os.path.join(V160_EXPORT, "lua_scripts"),
                     os.path.join(legacy_root, "lua_scripts"))
    # The actual OLD module name/layout the v1.6.0 cpp_patch/mod_attunement_plus.patch
    # would have produced -- simulating a real historical install, not a
    # synthetic placeholder.
    old_module_dir = os.path.join(legacy_root, "modules", "mod-attunement-plus", "src")
    os.makedirs(old_module_dir)
    with open(os.path.join(old_module_dir, "mod_attunement_plus.cpp"), "w") as f:
        f.write("// v1.6.0-era stat module source\n")
    with open(os.path.join(old_module_dir, "mod_attunement_plus_loader.cpp"), "w") as f:
        f.write("// v1.6.0-era loader\n")
    check("legacy layout has 20 v1.6.0-era Lua files",
          len(os.listdir(os.path.join(legacy_root, "lua_scripts"))) == 20)
    check("legacy layout has the old mod-attunement-plus module", os.path.isdir(
        os.path.join(legacy_root, "modules", "mod-attunement-plus")))
    check("legacy install has no manifest", manifest_mod.load(legacy_root) is None)

    upgrade_opts = install.InstallOptions(
        azerothcore_root=legacy_root, mysql_args=args,
        characters_database="acore_characters_v160", world_database="acore_world_v160",
    )
    result = upgrade_mod.upgrade(upgrade_opts, target_product_version="1.7.1")
    check("upgrade from actual v1.6.0-rc1 tree succeeds", result is not None)
    check("upgrade recorded previous_manifest_present=False", result["previous_manifest_present"] is False)

    post_upgrade_lua = set(os.listdir(os.path.join(legacy_root, "lua_scripts")))
    check("post-upgrade lua_scripts has current 28-file set",
          len(post_upgrade_lua) == 28)
    check("post-upgrade lua_scripts no longer has only the old 20 files",
          "ap00_compat.lua" in post_upgrade_lua)

    # THE KEY QUESTION: does the stale old module survive?
    old_module_survives = os.path.isdir(os.path.join(legacy_root, "modules", "mod-attunement-plus"))
    if old_module_survives:
        print("  [FINDING] modules/mod-attunement-plus/ (the OLD v1.6.0-era module) "
              "SURVIVES the upgrade -- the installer has no knowledge of the old "
              "module name/layout and never removes it. This is dead code left "
              "behind in the AzerothCore modules/ tree after upgrading, and if the "
              "old cpp_patch was ever actually applied+built, it would remain "
              "compiled into worldserver.exe indefinitely unless the operator "
              "manually removes modules/mod-attunement-plus/ themselves.")
    check("(informational, not a pass/fail gate) old module directory status logged", True)

    new_module_present = os.path.isdir(os.path.join(legacy_root, "modules", "mod-echoes-stats"))
    check("new mod-echoes-stats module installed alongside", new_module_present)

    # --- Fresh install for comparison ---
    fresh_root = tempfile.mkdtemp(prefix="echoes-fresh-ac-")
    os.makedirs(os.path.join(fresh_root, "modules", "mod-ale"))
    fresh_opts = install.InstallOptions(
        azerothcore_root=fresh_root, mysql_args=args,
        characters_database="acore_characters_fresh", world_database="acore_world_fresh",
    )
    install.install(fresh_opts)

    fresh_lua = set(os.listdir(os.path.join(fresh_root, "lua_scripts")))
    check("fresh install and v1.6.0-upgrade converge to the identical Lua file SET",
          fresh_lua == post_upgrade_lua)

    # Byte-compare each converged lua file
    mismatched = []
    for name in sorted(fresh_lua):
        f1 = os.path.join(fresh_root, "lua_scripts", name)
        f2 = os.path.join(legacy_root, "lua_scripts", name)
        if not filecmp.cmp(f1, f2, shallow=False):
            mismatched.append(name)
    check("every converged Lua file is byte-identical between fresh install and v1.6.0-upgrade",
          len(mismatched) == 0)
    if mismatched:
        print("  MISMATCHED:", mismatched)

    shutil.rmtree(legacy_root, ignore_errors=True)
    shutil.rmtree(fresh_root, ignore_errors=True)

    print()
    if FAILURES:
        print(f"{len(FAILURES)} CHECK(S) FAILED: {FAILURES}")
        print(f"OLD MODULE SURVIVES UPGRADE: {old_module_survives}")
        sys.exit(1)
    print("All checks passed.")
    print(f"OLD MODULE SURVIVES UPGRADE: {old_module_survives}")


if __name__ == "__main__":
    main()

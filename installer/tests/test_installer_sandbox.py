#!/usr/bin/env python3
# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Sandbox test suite for the Echoes installer core.

Everything here runs against a scratch filesystem tree (never a real
AzerothCore checkout) and, for the SQL-touching tests, a disposable MySQL
database supplied via environment variables (never a live/production
database). Run directly:

    python installer/tests/test_installer_sandbox.py

Required environment for the SQL-touching tests (skipped if absent):
    ECHOES_TEST_MYSQL_HOST, ECHOES_TEST_MYSQL_PORT,
    ECHOES_TEST_MYSQL_USER, ECHOES_TEST_MYSQL_PASSWORD
"""

import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from core import config, discovery, install, mpq_conflict, prereq, verify  # noqa: E402

FAILURES = []


def check(label, cond):
    if cond:
        print(f"  [PASS] {label}")
    else:
        print(f"  [FAIL] {label}")
        FAILURES.append(label)


def make_scratch_azerothcore_root(with_mod_ale=True, with_mod_playerbots=False, dml_style=False):
    root = tempfile.mkdtemp(prefix="echoes-ac-")
    os.makedirs(os.path.join(root, "modules"))
    if with_mod_ale:
        os.makedirs(os.path.join(root, "modules", "mod-ale"))
    if with_mod_playerbots:
        os.makedirs(os.path.join(root, "modules", "mod-playerbots"))
    if dml_style:
        with open(os.path.join(root, "dml-start.sh"), "w") as f:
            f.write("#!/bin/bash\necho scratch\n")
    return root


def make_scratch_client_root(compatible=True):
    root = tempfile.mkdtemp(prefix="echoes-client-")
    os.makedirs(os.path.join(root, "Data"))
    if compatible:
        open(os.path.join(root, "Wow.exe"), "wb").close()
        open(os.path.join(root, "Data", "common.MPQ"), "wb").close()
    return root


def test_discovery_azerothcore_root():
    print("test_discovery_azerothcore_root")
    root = make_scratch_azerothcore_root(with_mod_ale=True, with_mod_playerbots=True, dml_style=True)
    try:
        info = discovery.describe_azerothcore_root(root)
        check("has_modules_dir True", info["has_modules_dir"] is True)
        check("has_mod_ale True", info["has_mod_ale"] is True)
        check("has_mod_playerbots True", info["has_mod_playerbots"] is True)
        check("looks_like_dml_style_deployment True", info["looks_like_dml_style_deployment"] is True)
    finally:
        shutil.rmtree(root)

    root2 = make_scratch_azerothcore_root(with_mod_ale=False, with_mod_playerbots=False, dml_style=False)
    try:
        info2 = discovery.describe_azerothcore_root(root2)
        check("has_mod_ale False when absent", info2["has_mod_ale"] is False)
        check("looks_like_dml_style_deployment False when absent", info2["looks_like_dml_style_deployment"] is False)
    finally:
        shutil.rmtree(root2)


def test_discovery_client_root():
    print("test_discovery_client_root")
    root = make_scratch_client_root(compatible=True)
    try:
        info = discovery.describe_client_root(root)
        check("looks_like_compatible_335a_client True", info["looks_like_compatible_335a_client"] is True)
    finally:
        shutil.rmtree(root)

    root2 = make_scratch_client_root(compatible=False)
    try:
        info2 = discovery.describe_client_root(root2)
        check("looks_like_compatible_335a_client False when missing markers", info2["looks_like_compatible_335a_client"] is False)
    finally:
        shutil.rmtree(root2)


def test_prereq_mod_ale():
    print("test_prereq_mod_ale")
    root = make_scratch_azerothcore_root(with_mod_ale=True)
    try:
        check("mod-ale present detected", prereq.check_mod_ale(root).present is True)
    finally:
        shutil.rmtree(root)

    root2 = make_scratch_azerothcore_root(with_mod_ale=False)
    try:
        result = prereq.check_mod_ale(root2)
        check("mod-ale absent detected", result.present is False)
        check("mod-ale absent has remediation text", "mod-ale" in result.remediation)
    finally:
        shutil.rmtree(root2)


def test_mpq_conflict_policy():
    print("test_mpq_conflict_policy")
    check("no existing file -> NO_EXISTING_FILE",
          mpq_conflict.resolve(None, None, False) == mpq_conflict.MpqConflictResolution.NO_EXISTING_FILE)
    check("existing matches manifest -> EXISTING_IS_OURS",
          mpq_conflict.resolve("abc", "abc", False) == mpq_conflict.MpqConflictResolution.EXISTING_IS_OURS)
    check("existing unknown, no force -> BLOCKED",
          mpq_conflict.resolve("abc", None, False) == mpq_conflict.MpqConflictResolution.EXISTING_IS_THIRD_PARTY_BLOCKED)
    check("existing unknown, forced -> FORCED",
          mpq_conflict.resolve("abc", None, True) == mpq_conflict.MpqConflictResolution.EXISTING_IS_THIRD_PARTY_FORCED)


def test_config_materialize():
    print("test_config_materialize")
    tmp = tempfile.mkdtemp(prefix="echoes-conf-")
    try:
        dist = os.path.join(tmp, "mod_x.conf.dist")
        with open(dist, "w") as f:
            f.write("[worldserver]\nX.Enable = 0\nX.Other = 5\n")

        target = os.path.join(tmp, "mod_x.conf")
        result = config.materialize(dist, target, overrides={"X.Enable": "1"})
        check("fresh materialize action=created", result["action"] == "created")
        with open(target) as f:
            content = f.read()
        check("override applied on fresh create", "X.Enable = 1" in content)
        check("non-overridden key preserved", "X.Other = 5" in content)

        # Simulate a user editing X.Other, then a new dist key appearing
        with open(target, "w") as f:
            f.write("[worldserver]\nX.Enable = 1\nX.Other = 999\n")
        with open(dist, "a") as f:
            f.write("X.NewKey = 42\n")

        result2 = config.materialize(dist, target, overrides={"X.Enable": "1"})
        check("upgrade materialize action=merged", result2["action"] == "merged")
        check("new key added", "X.NewKey" in result2["keys_added"])
        with open(target) as f:
            content2 = f.read()
        check("user's existing tuning untouched", "X.Other = 999" in content2)
        check("override NOT reapplied over existing value", "X.Enable = 1" in content2)
    finally:
        shutil.rmtree(tmp)


def test_full_install_and_verify_sandbox():
    print("test_full_install_and_verify_sandbox (requires ECHOES_TEST_MYSQL_* env vars)")
    host = os.environ.get("ECHOES_TEST_MYSQL_HOST")
    if not host:
        print("  [SKIP] no disposable MySQL configured via ECHOES_TEST_MYSQL_* env vars")
        return

    mysql_args = [
        "-u", os.environ.get("ECHOES_TEST_MYSQL_USER", "root"),
        f"-p{os.environ.get('ECHOES_TEST_MYSQL_PASSWORD', '')}",
        "-h", host,
        "-P", os.environ.get("ECHOES_TEST_MYSQL_PORT", "3306"),
    ]

    # A real install always targets an existing AzerothCore world database
    # that already has item_template (populated by AzerothCore's own world
    # DB import, which this installer does not perform). Stub the minimal
    # shape here so world_items.sql has something real to guard/insert
    # into -- this mirrors the exact stub used during the E2j16 SQL
    # reproducibility checkpoint.
    stub_sql = """
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
    subprocess.run(["mysql", *mysql_args, "acore_world", "-e", stub_sql], check=True)

    ac_root = make_scratch_azerothcore_root(with_mod_ale=True, with_mod_playerbots=False)
    try:
        opts = install.InstallOptions(
            azerothcore_root=ac_root,
            mysql_args=mysql_args,
            characters_database="acore_characters",
            world_database="acore_world",
        )
        m1 = install.install(opts)
        check("fresh install: manifest returned", m1 is not None)
        check("fresh install: core_lua enabled", m1["components"]["core_lua"]["enabled"] is True)
        check("fresh install: mod-echoes-stats enabled", m1["components"]["mod_echoes_stats"]["enabled"] is True)
        check("fresh install: lua_scripts copied", os.path.isdir(os.path.join(ac_root, "lua_scripts")))
        check("fresh install: mod-echoes-stats copied", os.path.isdir(os.path.join(ac_root, "modules", "mod-echoes-stats")))
        check("fresh install: config materialized with Enable=1",
              "EchoesStats.Enable = 1" in open(os.path.join(ac_root, "etc", "modules", "mod_echoes_stats.conf")).read())

        # Repeat install -- must not fail, must not duplicate/corrupt
        m2 = install.install(opts)
        check("repeat install: succeeds", m2 is not None)

        checks = verify.verify(ac_root, mysql_args, "acore_characters")
        failed = [c for c in checks if c.status == verify.FAIL]
        check("verify: zero FAIL checks after install", len(failed) == 0)
        for c in checks:
            print("   ", repr(c))
    finally:
        shutil.rmtree(ac_root, ignore_errors=True)


if __name__ == "__main__":
    test_discovery_azerothcore_root()
    test_discovery_client_root()
    test_prereq_mod_ale()
    test_mpq_conflict_policy()
    test_config_materialize()
    test_full_install_and_verify_sandbox()

    print()
    if FAILURES:
        print(f"{len(FAILURES)} check(s) FAILED: {FAILURES}")
        sys.exit(1)
    print("All checks passed (or were explicitly skipped where noted).")

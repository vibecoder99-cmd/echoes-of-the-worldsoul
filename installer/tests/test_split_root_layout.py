#!/usr/bin/env python3
# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Regression coverage for split Docker/DML-style runtime layouts.

Found by live E2j17 Compatibility Verification certification: a real DML
deployment keeps modules/ (C++, build-time only) at its checkout root, but
bind-mounts its actual live lua_scripts/ and etc/modules/ from a separate
runtime distribution root (env/dist/ in every deployment of this shape
seen so far). No single --azerothcore-root represents both. Before the
--lua-root/--config-root fix, running install() against either root alone
either missed the real runtime files entirely or created a disconnected,
ineffective, misleadingly-"installer-managed" tree the live server never
reads.

Everything here runs against scratch filesystem trees (never a real
AzerothCore checkout) and, for the SQL-touching tests, a disposable MySQL
database supplied via environment variables (never a live/production
database) -- same convention as test_installer_sandbox.py. Run directly:

    python installer/tests/test_split_root_layout.py

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

from core import discovery, install, manifest as manifest_mod, repair as repair_mod  # noqa: E402
from core import uninstall as uninstall_mod, upgrade as upgrade_mod, verify  # noqa: E402

FAILURES = []


def check(label, cond):
    if cond:
        print(f"  [PASS] {label}")
    else:
        print(f"  [FAIL] {label}")
        FAILURES.append(label)


def make_single_root(with_mod_ale=True):
    """Traditional bare-metal layout: modules/, lua_scripts/, etc/modules/
    all directly under one root -- the pre-existing, unchanged default."""
    root = tempfile.mkdtemp(prefix="echoes-single-ac-")
    os.makedirs(os.path.join(root, "modules"))
    if with_mod_ale:
        os.makedirs(os.path.join(root, "modules", "mod-ale"))
    return root


def make_split_dml_root(with_mod_ale=True, with_mod_playerbots=False):
    """Split layout: modules/ at the checkout root; lua_scripts/ and
    etc/modules/ under env/dist/ instead -- the real production topology
    this fix exists for. Returns (checkout_root, dist_root)."""
    root = tempfile.mkdtemp(prefix="echoes-split-ac-")
    os.makedirs(os.path.join(root, "modules"))
    if with_mod_ale:
        os.makedirs(os.path.join(root, "modules", "mod-ale"))
    if with_mod_playerbots:
        os.makedirs(os.path.join(root, "modules", "mod-playerbots"))
    with open(os.path.join(root, "dml-start.sh"), "w") as f:
        f.write("#!/bin/bash\necho scratch\n")
    dist_root = os.path.join(root, "env", "dist")
    os.makedirs(os.path.join(dist_root, "lua_scripts"))
    os.makedirs(os.path.join(dist_root, "etc", "modules"))
    return root, dist_root


def _mysql_test_args():
    host = os.environ.get("ECHOES_TEST_MYSQL_HOST")
    if not host:
        return None
    return [
        "-u", os.environ.get("ECHOES_TEST_MYSQL_USER", "root"),
        f"-p{os.environ.get('ECHOES_TEST_MYSQL_PASSWORD', '')}",
        "-h", host,
        "-P", os.environ.get("ECHOES_TEST_MYSQL_PORT", "3306"),
    ]


_ITEM_TEMPLATE_STUB_SQL = """
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


def _reset_disposable_databases(mysql_args):
    subprocess.run(["mysql", *mysql_args, "-e",
                     "DROP DATABASE IF EXISTS acore_characters; CREATE DATABASE acore_characters;"],
                    check=True)
    subprocess.run(["mysql", *mysql_args, "-e",
                     "DROP DATABASE IF EXISTS acore_world; CREATE DATABASE acore_world;"],
                    check=True)
    subprocess.run(["mysql", *mysql_args, "acore_world", "-e", _ITEM_TEMPLATE_STUB_SQL], check=True)


def test_discovery_flags_split_layout():
    print("test_discovery_flags_split_layout")
    root, dist_root = make_split_dml_root()
    try:
        info = discovery.describe_azerothcore_root(root)
        check("split layout detected", info["looks_like_split_dml_layout"] is True)
        check("suggested_lua_root points at env/dist",
              info["suggested_lua_root"] == dist_root)
        check("suggested_config_root points at env/dist",
              info["suggested_config_root"] == dist_root)
    finally:
        shutil.rmtree(root)

    single = make_single_root()
    try:
        # A traditional single-root layout (no lua_scripts/etc/modules at
        # all yet, e.g. pre-first-install) must NOT be misidentified as
        # split just because those directories don't exist yet -- only a
        # root with NEITHER present AND an actual env/dist/ pair present
        # counts.
        info2 = discovery.describe_azerothcore_root(single)
        check("bare root with no env/dist/ NOT flagged as split",
              info2["looks_like_split_dml_layout"] is False)
    finally:
        shutil.rmtree(single)


def test_effective_roots_backward_compatible():
    print("test_effective_roots_backward_compatible (old manifest with no 'roots' field)")
    old_manifest = {
        "azerothcore_root": "/some/old/root",
        "client_root": None,
        # deliberately no "roots" key at all -- simulates a manifest
        # written before this field existed
    }
    resolved = manifest_mod.effective_roots(old_manifest)
    check("old manifest: lua defaults to azerothcore_root",
          resolved["lua"] == "/some/old/root")
    check("old manifest: config defaults to azerothcore_root",
          resolved["config"] == "/some/old/root")

    partial_manifest = {
        "azerothcore_root": "/some/root",
        "client_root": None,
        "roots": {"lua": None, "config": None},
    }
    resolved2 = manifest_mod.effective_roots(partial_manifest)
    check("manifest with roots={None,None}: still defaults to azerothcore_root",
          resolved2["lua"] == "/some/root" and resolved2["config"] == "/some/root")


def test_install_single_root_unchanged():
    print("test_install_single_root_unchanged (requires ECHOES_TEST_MYSQL_* env vars)")
    mysql_args = _mysql_test_args()
    if mysql_args is None:
        print("  [SKIP] no disposable MySQL configured via ECHOES_TEST_MYSQL_* env vars")
        return
    _reset_disposable_databases(mysql_args)

    root = make_single_root()
    try:
        opts = install.InstallOptions(
            azerothcore_root=root, mysql_args=mysql_args,
            characters_database="acore_characters", world_database="acore_world",
        )
        check("lua_root defaults to azerothcore_root when omitted", opts.lua_root == root)
        check("config_root defaults to azerothcore_root when omitted", opts.config_root == root)

        m = install.install(opts)
        check("single-root install: lua lands at root/lua_scripts",
              os.path.isdir(os.path.join(root, "lua_scripts")))
        check("single-root install: config lands at root/etc/modules",
              os.path.isfile(os.path.join(root, "etc", "modules", "mod_echoes_stats.conf")))
        check("single-root install: manifest roots.lua == azerothcore_root",
              m["roots"]["lua"] == root)
        check("single-root install: manifest roots.config == azerothcore_root",
              m["roots"]["config"] == root)

        checks = verify.verify(root, mysql_args, "acore_characters")
        check("single-root verify: zero FAIL", all(c.status != verify.FAIL for c in checks))
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_install_split_root_layout():
    print("test_install_split_root_layout (requires ECHOES_TEST_MYSQL_* env vars)")
    mysql_args = _mysql_test_args()
    if mysql_args is None:
        print("  [SKIP] no disposable MySQL configured via ECHOES_TEST_MYSQL_* env vars")
        return
    _reset_disposable_databases(mysql_args)

    root, dist_root = make_split_dml_root()
    try:
        opts = install.InstallOptions(
            azerothcore_root=root, mysql_args=mysql_args,
            characters_database="acore_characters", world_database="acore_world",
            lua_root=dist_root, config_root=dist_root,
        )
        m = install.install(opts)

        # --- C++ lands only under the checkout root ---
        check("split install: mod-echoes-stats lands at root/modules",
              os.path.isdir(os.path.join(root, "modules", "mod-echoes-stats")))
        check("split install: NO mod-echoes-stats under dist_root",
              not os.path.isdir(os.path.join(dist_root, "modules", "mod-echoes-stats")))

        # --- Lua lands only under the runtime distribution root ---
        real_lua_dir = os.path.join(dist_root, "lua_scripts")
        check("split install: Lua lands at dist_root/lua_scripts",
              os.path.isdir(real_lua_dir) and len(os.listdir(real_lua_dir)) > 0)
        check("split install: NO disconnected root/lua_scripts created",
              not os.path.isdir(os.path.join(root, "lua_scripts")))

        # --- Config lands only under the runtime distribution root ---
        real_conf = os.path.join(dist_root, "etc", "modules", "mod_echoes_stats.conf")
        check("split install: config lands at dist_root/etc/modules", os.path.isfile(real_conf))
        check("split install: NO disconnected root/etc/modules created",
              not os.path.isdir(os.path.join(root, "etc")))
        with open(real_conf) as f:
            check("split install: config content correct (Enable=1)",
                  "EchoesStats.Enable = 1" in f.read())

        # --- Manifest records the correct effective roots ---
        check("manifest: azerothcore_root recorded", m["azerothcore_root"] == root)
        check("manifest: roots.lua recorded as dist_root", m["roots"]["lua"] == dist_root)
        check("manifest: roots.config recorded as dist_root", m["roots"]["config"] == dist_root)

        # --- Package equivalence: installed Lua file set matches source ---
        repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        source_lua_files = set(os.listdir(os.path.join(repo_root, "lua_scripts")))
        installed_lua_files = set(os.listdir(real_lua_dir))
        check("package equivalence: installed Lua file set matches source exactly",
              source_lua_files == installed_lua_files)

        # --- verify() resolves the split roots correctly ---
        checks = verify.verify(root, mysql_args, "acore_characters")
        failed = [c for c in checks if c.status == verify.FAIL]
        check("split-root verify: zero FAIL checks", len(failed) == 0)

        # --- repair() operates on the correct (split) roots ---
        removed_file = os.path.join(real_lua_dir, "ap_events.lua")
        os.remove(removed_file)
        report = repair_mod.repair(root, restore_mismatched=False)
        check("split-root repair: missing file restored at dist_root location",
              os.path.isfile(removed_file))
        check("split-root repair: restored_missing references the file",
              any("ap_events.lua" in x for x in report.restored_missing))
        check("split-root repair: did NOT create a disconnected root/lua_scripts",
              not os.path.isdir(os.path.join(root, "lua_scripts")))

        # --- unrelated files under both roots survive ---
        ale_marker = os.path.join(root, "modules", "mod-ale")
        unrelated_dist_file = os.path.join(dist_root, "lua_scripts", "unrelated_third_party.lua")
        with open(unrelated_dist_file, "w") as f:
            f.write("-- not ours\n")

        # --- uninstall() removes only owned files, from the correct roots ---
        uninstall_report = uninstall_mod.uninstall(root)
        check("split-root uninstall: core_lua files removed",
              any(x.startswith("core_lua:") for x in uninstall_report.removed))
        check("split-root uninstall: lua files actually gone from dist_root",
              not os.path.isfile(os.path.join(real_lua_dir, "ap_core.lua")))
        check("split-root uninstall: mod-echoes-stats removed from root/modules",
              not os.path.isdir(os.path.join(root, "modules", "mod-echoes-stats")))
        check("split-root uninstall: mod-ale (root/modules) untouched", os.path.isdir(ale_marker))
        check("split-root uninstall: unrelated dist_root Lua file untouched",
              os.path.isfile(unrelated_dist_file))
        check("split-root uninstall: database retained",
              "retained" in uninstall_report.database_action)
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_upgrade_split_root_legacy_pre_manifest():
    print("test_upgrade_split_root_legacy_pre_manifest (requires ECHOES_TEST_MYSQL_* env vars)")
    mysql_args = _mysql_test_args()
    if mysql_args is None:
        print("  [SKIP] no disposable MySQL configured via ECHOES_TEST_MYSQL_* env vars")
        return
    _reset_disposable_databases(mysql_args)

    root, dist_root = make_split_dml_root()
    try:
        # Simulate a pre-installer legacy deployment: real bot content
        # already sitting at the split runtime location, no manifest yet.
        with open(os.path.join(dist_root, "lua_scripts", "ap_core.lua"), "w") as f:
            f.write("-- pre-installer legacy content, no manifest ever existed\n")
        check("legacy split install has no manifest yet", manifest_mod.load(root) is None)

        opts = install.InstallOptions(
            azerothcore_root=root, mysql_args=mysql_args,
            characters_database="acore_characters", world_database="acore_world",
            lua_root=dist_root, config_root=dist_root,
        )
        result = upgrade_mod.upgrade(opts, target_product_version="2.0.0-rc1")
        check("split upgrade: previous_manifest_present False", result["previous_manifest_present"] is False)

        with open(os.path.join(dist_root, "lua_scripts", "ap_core.lua")) as f:
            content = f.read()
        check("split upgrade: legacy content replaced at the CORRECT (dist_root) location",
              "pre-installer legacy content" not in content)
        check("split upgrade: no disconnected root/lua_scripts ever created",
              not os.path.isdir(os.path.join(root, "lua_scripts")))

        m = manifest_mod.load(root)
        check("split upgrade: manifest created with correct roots",
              m is not None and m["roots"]["lua"] == dist_root and m["roots"]["config"] == dist_root)
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_containment_still_enforced_on_split_roots():
    print("test_containment_still_enforced_on_split_roots (traversal/symlink protection unweakened)")
    from core import safety

    root, dist_root = make_split_dml_root()
    outside = tempfile.mkdtemp(prefix="echoes-outside-")
    try:
        real_lua_dir = os.path.join(dist_root, "lua_scripts")
        # A manifest-recorded relative path that would resolve outside
        # dist_root/lua_scripts must still be rejected -- the split-root
        # change must not weaken traversal protection.
        traversal_target = os.path.join(real_lua_dir, "..", "..", "..", os.path.basename(outside), "evil.txt")
        check("traversal escape from split lua_root rejected",
              safety.is_safe_to_delete(traversal_target, real_lua_dir) is False)

        target_file = os.path.join(outside, "real.txt")
        open(target_file, "w").close()
        link_path = os.path.join(real_lua_dir, "escape_link")
        try:
            os.symlink(target_file, link_path)
            symlink_supported = True
        except (OSError, NotImplementedError):
            symlink_supported = False

        if symlink_supported:
            try:
                safety.safe_remove_file(link_path, real_lua_dir)
                check("symlink escape from split lua_root rejected", False)
            except safety.UnsafePathError:
                check("symlink escape from split lua_root rejected", True)
            check("symlink target outside split root survived", os.path.isfile(target_file))
        else:
            print("  [SKIP] symlink creation not permitted in this environment")
    finally:
        shutil.rmtree(root, ignore_errors=True)
        shutil.rmtree(outside, ignore_errors=True)


if __name__ == "__main__":
    test_discovery_flags_split_layout()
    test_effective_roots_backward_compatible()
    test_install_single_root_unchanged()
    test_install_split_root_layout()
    test_upgrade_split_root_legacy_pre_manifest()
    test_containment_still_enforced_on_split_roots()

    print()
    if FAILURES:
        print(f"{len(FAILURES)} check(s) FAILED: {FAILURES}")
        sys.exit(1)
    print("All checks passed (or were explicitly skipped where noted).")

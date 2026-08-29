#!/usr/bin/env python3
# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Regression coverage for the legacy patch-4.MPQ -> patch-E.MPQ direct
migration path.

Found by live E2j17 Compatibility Verification certification: a real DML
client's Data/patch-4.MPQ was already positively identified as Echoes'
own proven-good output, but the installer's install() unconditionally
tried to reconstruct patch-E.MPQ from a vanilla Item.dbc FIRST (requiring
mpyq and a readable stock archive) before ever attempting legacy
migration -- making a migration that already had a proven source payload
depend on an unrelated, unnecessary extraction step. Renaming/copying an
MPQ archive does not change its internal payload; a positively-identified
legacy archive needs no reconstruction at all.

Everything here runs against scratch filesystem trees. No disposable
MySQL needed -- this feature is entirely file-level. Run directly:

    python installer/tests/test_legacy_patch_migration_flow.py
"""

import os
import shutil
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "dbc_patch"))

from core import hashing, legacy_migration, mpq_conflict  # noqa: E402
from mpq_writer import write_single_file_mpq  # noqa: E402
from patch_item_dbc import patch as patch_item_dbc  # noqa: E402

FAILURES = []


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


def check(label, cond):
    if cond:
        print(f"  [PASS] {label}")
    else:
        print(f"  [FAIL] {label}")
        FAILURES.append(label)


def _genuine_echoes_payload():
    """Build a real, byte-exact Echoes patch payload the same way the
    project's own dbc_patch tooling does -- not a hand-crafted fixture."""
    tmp = tempfile.mkdtemp(prefix="echoes-payload-")
    try:
        vanilla_path = os.path.join(tmp, "vanilla.dbc")
        patched_path = os.path.join(tmp, "patched.dbc")
        with open(vanilla_path, "wb") as f:
            f.write(struct.pack("<4sIIII", b"WDBC", 0, 8, 32, 1))
            f.write(b"\x00")
        patch_item_dbc(vanilla_path, patched_path)
        with open(patched_path, "rb") as f:
            return f.read()
    finally:
        shutil.rmtree(tmp)


def make_client_with_legacy_patch4(genuine=True):
    """A scratch client root with an existing Data/patch-4.MPQ -- either
    genuinely Echoes-owned (byte-exact payload) or an unrelated foreign
    file, per `genuine`."""
    root = tempfile.mkdtemp(prefix="echoes-migclient-")
    data_dir = os.path.join(root, "Data")
    os.makedirs(data_dir)
    open(os.path.join(root, "Wow.exe"), "wb").close()
    open(os.path.join(data_dir, "common.MPQ"), "wb").close()

    legacy_path = os.path.join(data_dir, "patch-4.MPQ")
    if genuine:
        payload = _genuine_echoes_payload()
        write_single_file_mpq(legacy_path, "DBFilesClient\\Item.dbc", payload)
    else:
        write_single_file_mpq(legacy_path, "SomeOther\\File.dat", b"not an Echoes payload")
    return root


def test_positively_identified_legacy_direct_migration():
    print("test_positively_identified_legacy_direct_migration")
    root = make_client_with_legacy_patch4(genuine=True)
    try:
        data_dir = os.path.join(root, "Data")
        legacy_path = os.path.join(data_dir, "patch-4.MPQ")
        new_path = os.path.join(data_dir, "patch-E.MPQ")
        backups_root = os.path.join(root, "backups")

        source_sha = hashing.sha256_file(legacy_path)
        check("precondition: patch-4 positively identified before migration",
              mpq_conflict.identify_legacy_echoes_patch4(legacy_path) is True)
        check("precondition: no patch-E yet", not os.path.isfile(new_path))

        result = legacy_migration.migrate_direct_from_verified_legacy(
            root, backups_root, "20260101T000000Z"
        )
        check("direct migration: action=migrated", result["action"] == "migrated")
        check("direct migration: no mpyq/vanilla DBC needed (function takes none)",
              "vanilla" not in legacy_migration.migrate_direct_from_verified_legacy.__code__.co_varnames)
        check("direct migration: patch-E created", os.path.isfile(new_path))
        check("direct migration: patch-E byte-identical to legacy source",
              hashing.sha256_file(new_path) == source_sha)
        check("direct migration: reported sha256 matches source",
              result["sha256"] == source_sha)
        check("direct migration: legacy patch-4 retired (removed) after verification",
              not os.path.isfile(legacy_path))
        check("direct migration: backup of legacy patch-4 was made",
              result.get("backup_path") and os.path.isfile(result["backup_path"]))
        check("direct migration: backup is byte-identical to original source",
              hashing.sha256_file(result["backup_path"]) == source_sha)
        check("direct migration: source field records verified_legacy_patch4",
              result["source"] == "verified_legacy_patch4")
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_unknown_patch4_not_migrated():
    print("test_unknown_patch4_not_migrated")
    root = make_client_with_legacy_patch4(genuine=False)
    try:
        data_dir = os.path.join(root, "Data")
        legacy_path = os.path.join(data_dir, "patch-4.MPQ")
        new_path = os.path.join(data_dir, "patch-E.MPQ")
        backups_root = os.path.join(root, "backups")
        original_sha = hashing.sha256_file(legacy_path)

        result = legacy_migration.migrate_direct_from_verified_legacy(
            root, backups_root, "20260101T000000Z"
        )
        check("unknown patch-4: action=none", result["action"] == "none")
        check("unknown patch-4: left completely untouched",
              hashing.sha256_file(legacy_path) == original_sha)
        check("unknown patch-4: no patch-E created", not os.path.isfile(new_path))
        check("unknown patch-4: no backup made", not os.path.isdir(backups_root))
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_existing_unknown_patch_e_hard_stop_via_install():
    print("test_existing_unknown_patch_e_hard_stop_via_install (install()-level, requires ECHOES_TEST_MYSQL_* env vars)")
    mysql_args = _mysql_test_args()
    if mysql_args is None:
        print("  [SKIP] no disposable MySQL configured via ECHOES_TEST_MYSQL_* env vars")
        return
    _reset_disposable_databases(mysql_args)

    from core import install

    root = make_client_with_legacy_patch4(genuine=True)
    try:
        data_dir = os.path.join(root, "Data")
        # An existing, unrelated patch-E.MPQ the installer has never seen.
        foreign_patch_e = os.path.join(data_dir, "patch-E.MPQ")
        with open(foreign_patch_e, "wb") as f:
            f.write(b"some third party's own patch-E, not ours")
        original_patch4_sha = hashing.sha256_file(os.path.join(data_dir, "patch-4.MPQ"))
        original_patch_e_content = open(foreign_patch_e, "rb").read()

        ac_root = tempfile.mkdtemp(prefix="echoes-migac-")
        os.makedirs(os.path.join(ac_root, "modules", "mod-ale"))
        try:
            opts = install.InstallOptions(
                azerothcore_root=ac_root, mysql_args=mysql_args,
                characters_database="acore_characters", world_database="acore_world",
                client_root=root,
            )
            raised = False
            try:
                install.install(opts)
            except RuntimeError as e:
                raised = True
                check("hard stop: error mentions namespace collision",
                      "namespace collision" in str(e) or "already exists" in str(e))
            check("existing unknown patch-E: install() raises rather than overwriting", raised is True)
            check("existing unknown patch-E: content unchanged (no overwrite)",
                  open(foreign_patch_e, "rb").read() == original_patch_e_content)
            check("existing unknown patch-E: legacy patch-4 untouched (never reached migration)",
                  hashing.sha256_file(os.path.join(data_dir, "patch-4.MPQ")) == original_patch4_sha)
        finally:
            shutil.rmtree(ac_root, ignore_errors=True)
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_copy_verify_failure_leaves_patch4_active():
    print("test_copy_verify_failure_leaves_patch4_active (induced corruption)")
    root = make_client_with_legacy_patch4(genuine=True)
    try:
        data_dir = os.path.join(root, "Data")
        legacy_path = os.path.join(data_dir, "patch-4.MPQ")
        new_path = os.path.join(data_dir, "patch-E.MPQ")
        backups_root = os.path.join(root, "backups")
        original_sha = hashing.sha256_file(legacy_path)

        # Induce a post-copy corruption: monkeypatch hashing.sha256_file so
        # the temp-file verification step sees a mismatched hash, exactly
        # as if the copy had been corrupted in flight.
        real_sha256_file = hashing.sha256_file
        call_count = {"n": 0}

        def _flaky_sha256_file(path):
            call_count["n"] += 1
            if path.endswith(".migrating-tmp"):
                return "0" * 64  # deliberately wrong
            return real_sha256_file(path)

        hashing.sha256_file = _flaky_sha256_file
        try:
            result = legacy_migration.migrate_direct_from_verified_legacy(
                root, backups_root, "20260101T000000Z"
            )
        finally:
            hashing.sha256_file = real_sha256_file

        check("copy/verify failure: action=failed", result["action"] == "failed")
        check("copy/verify failure: patch-4 still present and unchanged",
              os.path.isfile(legacy_path) and hashing.sha256_file(legacy_path) == original_sha)
        check("copy/verify failure: no patch-E left behind", not os.path.isfile(new_path))
        check("copy/verify failure: no leftover temp file",
              not os.path.isfile(new_path + ".migrating-tmp"))
        check("copy/verify failure: backup of original still made (not destructive)",
              result.get("backup_path") and os.path.isfile(result["backup_path"]))
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_fresh_client_vanilla_dbc_path_unchanged():
    print("test_fresh_client_vanilla_dbc_path_unchanged (no patch-4 at all, requires ECHOES_TEST_MYSQL_* env vars)")
    mysql_args = _mysql_test_args()
    if mysql_args is None:
        print("  [SKIP] no disposable MySQL configured via ECHOES_TEST_MYSQL_* env vars")
        return
    _reset_disposable_databases(mysql_args)

    from core import install

    root = tempfile.mkdtemp(prefix="echoes-migfresh-")
    try:
        data_dir = os.path.join(root, "Data")
        os.makedirs(data_dir)
        open(os.path.join(root, "Wow.exe"), "wb").close()
        open(os.path.join(data_dir, "common.MPQ"), "wb").close()
        # No patch-4.MPQ at all -- genuinely fresh client.

        vanilla_path = os.path.join(root, "vanilla.dbc")
        with open(vanilla_path, "wb") as f:
            f.write(struct.pack("<4sIIII", b"WDBC", 0, 8, 32, 1))
            f.write(b"\x00")

        ac_root = tempfile.mkdtemp(prefix="echoes-migac2-")
        os.makedirs(os.path.join(ac_root, "modules", "mod-ale"))
        try:
            opts = install.InstallOptions(
                azerothcore_root=ac_root, mysql_args=mysql_args,
                characters_database="acore_characters", world_database="acore_world",
                client_root=root, vanilla_dbc_path=vanilla_path,
            )
            m = install.install(opts)
            new_path = os.path.join(data_dir, "patch-E.MPQ")
            check("fresh client: install() succeeds end to end", m is not None)
            check("fresh client: patch-E.MPQ built via vanilla-dbc-path, no legacy patch-4 involved",
                  os.path.isfile(new_path))
            check("fresh client: provenance recorded as freshly built, not migrated",
                  m["patch_mpq"].get("provenance") == "freshly_built_from_vanilla_dbc")
        finally:
            shutil.rmtree(ac_root, ignore_errors=True)
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_migrated_patch_e_ownership_survives_lifecycle():
    print("test_migrated_patch_e_ownership_survives_lifecycle (requires ECHOES_TEST_MYSQL_* env vars)")
    mysql_args = _mysql_test_args()
    if mysql_args is None:
        print("  [SKIP] no disposable MySQL configured via ECHOES_TEST_MYSQL_* env vars")
        return
    _reset_disposable_databases(mysql_args)

    from core import install, uninstall as uninstall_mod, verify

    root = make_client_with_legacy_patch4(genuine=True)
    try:
        data_dir = os.path.join(root, "Data")
        ac_root = tempfile.mkdtemp(prefix="echoes-miglifecycle-")
        os.makedirs(os.path.join(ac_root, "modules", "mod-ale"))
        try:
            opts = install.InstallOptions(
                azerothcore_root=ac_root, mysql_args=mysql_args,
                characters_database="acore_characters", world_database="acore_world",
                client_root=root,
            )
            m = install.install(opts)
            check("lifecycle: install migrated (not freshly built)",
                  m["patch_mpq"]["provenance"] == "migrated_from_verified_legacy_patch4")

            checks = verify.verify(ac_root, mysql_args, "acore_characters")
            patch_e_checks = [c for c in checks if "patch-E" in c.name]
            check("lifecycle: verify() finds and checks the migrated patch-E.MPQ",
                  len(patch_e_checks) == 1 and patch_e_checks[0].status == verify.PASS)

            # A subsequent re-run must not misidentify the now-migrated
            # patch-E as an unrelated conflict (EXISTING_IS_OURS, not
            # EXISTING_IS_THIRD_PARTY_BLOCKED). Legacy patch-4 no longer
            # exists at this point (already retired), so this repeat call
            # necessarily falls back to the ordinary fresh-build path --
            # that fallback's own vanilla-DBC/mpyq requirement is
            # pre-existing, unrelated behavior, not something this fix
            # changes, so a vanilla DBC is supplied here to isolate the
            # one thing actually under test: no false conflict is raised.
            vanilla_path = os.path.join(root, "vanilla_for_repeat.dbc")
            with open(vanilla_path, "wb") as f:
                f.write(struct.pack("<4sIIII", b"WDBC", 0, 8, 32, 1))
                f.write(b"\x00")
            opts_repeat = install.InstallOptions(
                azerothcore_root=ac_root, mysql_args=mysql_args,
                characters_database="acore_characters", world_database="acore_world",
                client_root=root, vanilla_dbc_path=vanilla_path,
            )
            m2 = install.install(opts_repeat)
            check("lifecycle: repeat install after migration does not raise a false conflict",
                  m2 is not None)

            report = uninstall_mod.uninstall(ac_root)
            check("lifecycle: uninstall removes the migrated patch-E (hash still matches)",
                  "patch_mpq" in report.removed)
            check("lifecycle: patch-E actually gone after uninstall",
                  not os.path.isfile(os.path.join(data_dir, "patch-E.MPQ")))
        finally:
            shutil.rmtree(ac_root, ignore_errors=True)
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    test_positively_identified_legacy_direct_migration()
    test_unknown_patch4_not_migrated()
    test_existing_unknown_patch_e_hard_stop_via_install()
    test_copy_verify_failure_leaves_patch4_active()
    test_fresh_client_vanilla_dbc_path_unchanged()
    test_migrated_patch_e_ownership_survives_lifecycle()

    print()
    if FAILURES:
        print(f"{len(FAILURES)} check(s) FAILED: {FAILURES}")
        sys.exit(1)
    print("All checks passed (or were explicitly skipped where noted).")

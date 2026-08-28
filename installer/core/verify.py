# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""`echoes verify` -- read-only. Never mutates anything it inspects."""

import os
import subprocess

from . import discovery, hashing, manifest as manifest_mod, prereq

PASS, WARN, FAIL = "PASS", "WARN", "FAIL"


class Check:
    def __init__(self, name, status, detail=""):
        self.name = name
        self.status = status
        self.detail = detail

    def __repr__(self):
        return f"[{self.status}] {self.name}" + (f" -- {self.detail}" if self.detail else "")


def verify(azerothcore_root, mysql_args=None, characters_database=None):
    checks = []

    m = manifest_mod.load(azerothcore_root)
    if m is None:
        checks.append(Check("manifest present", FAIL, "no install manifest found; nothing to verify"))
        return checks
    checks.append(Check("manifest present", PASS))

    ale = prereq.check_mod_ale(azerothcore_root)
    checks.append(Check("mod-ale prerequisite", PASS if ale.present else FAIL, ale.remediation or ""))

    for component, data in m.get("components", {}).items():
        if not data.get("enabled"):
            continue
        expected = data.get("files", {})
        if component == "core_lua":
            root = os.path.join(azerothcore_root, "lua_scripts")
        elif component in ("mod_echoes_stats", "mod_echoes_playerbots"):
            root = os.path.join(azerothcore_root, "modules", component.replace("_", "-"))
        elif component == "client_companion":
            client_root = m.get("client_root")
            root = os.path.join(client_root, "Interface", "AddOns", "EchoesOfTheWorldsoulBridge") if client_root else None
        else:
            root = None

        if root is None or not os.path.isdir(root):
            checks.append(Check(f"{component} files", FAIL, f"expected directory missing: {root}"))
            continue

        missing, mismatched, extra = hashing.verify_tree(root, expected)
        if missing or mismatched:
            checks.append(Check(
                f"{component} files", FAIL,
                f"{len(missing)} missing, {len(mismatched)} hash-mismatched"
            ))
        else:
            note = f"{len(extra)} extra file(s) present (informational only)" if extra else ""
            checks.append(Check(f"{component} files", PASS, note))

    pmpq = m.get("patch_mpq", {})
    if pmpq.get("generated"):
        path = pmpq.get("path")
        actual = hashing.sha256_file(path) if path else None
        if actual is None:
            checks.append(Check("patch-E.MPQ", FAIL, f"expected file missing: {path}"))
        elif actual != pmpq.get("sha256"):
            checks.append(Check("patch-E.MPQ", WARN, "hash differs from install-time record (may have been replaced)"))
        else:
            checks.append(Check("patch-E.MPQ", PASS))

    if mysql_args and characters_database:
        try:
            result = subprocess.run(
                ["mysql", *mysql_args, characters_database, "-N", "-e",
                 "SELECT version FROM ap_schema_version WHERE id=1"],
                capture_output=True, text=True, check=True,
            )
            version = result.stdout.strip()
            expected_version = m.get("sql", {}).get("schema_files_applied") and m.get("product_version")
            if version:
                checks.append(Check("database schema version", PASS, f"ap_schema_version = {version}"))
            else:
                checks.append(Check("database schema version", FAIL, "ap_schema_version table empty"))
        except subprocess.CalledProcessError as e:
            checks.append(Check("database schema version", FAIL, str(e)))

    pb = m.get("playerbots_integration", {})
    if pb.get("enabled") and not pb.get("compatibility_confirmed"):
        checks.append(Check("playerbots integration state", WARN,
                             "enabled without a recorded compatibility confirmation"))
    else:
        checks.append(Check("playerbots integration state", PASS, str(pb.get("reason", ""))))

    return checks

# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""One-time legacy Patch-4.MPQ -> patch-E.MPQ migration.

Prior Echoes development installs used Data/patch-4.MPQ. This module
detects that specific case (via mpq_conflict.identify_legacy_echoes_patch4's
byte-exact fingerprint, never "any file named patch-4.MPQ") and migrates
it to the new patch-E.MPQ slot:

  1. Positively identify the existing patch-4.MPQ as Echoes' own output.
     If it cannot be proven Echoes-owned, this module does nothing and
     reports that -- the file is left completely untouched.
  2. Back up the old patch-4.MPQ (per the standing backup-before-mutate
     rule).
  3. Write the new patch-E.MPQ.
  4. Verify patch-E.MPQ is present, correctly structured, and carries the
     same payload -- only after that verification succeeds does this
     module remove the old patch-4.MPQ. A failure at this step leaves
     BOTH files in place rather than risk deleting the only known-good
     copy.
"""

import os

from . import backup, hashing, mpq_conflict


def migrate(client_root, backups_root, timestamp, mpq_build_result):
    """mpq_build_result: the dict returned by mpq_build.build() for the
    patch-E.MPQ that was (or will be) written to Data/patch-E.MPQ --
    used only to verify against after the fact.

    Returns a dict describing what happened. Never raises for "nothing to
    migrate" (that's a normal, expected outcome, not an error).
    """
    old_path = os.path.join(client_root, "Data", "patch-4.MPQ")

    if not os.path.isfile(old_path):
        return {"action": "none", "reason": "no legacy patch-4.MPQ present"}

    if not mpq_conflict.identify_legacy_echoes_patch4(old_path):
        return {
            "action": "none",
            "reason": (
                f"{old_path} exists but could not be positively identified as "
                "Echoes' own output (byte-exact fingerprint did not match) -- "
                "left completely untouched"
            ),
        }

    backup_path = backup.backup_path(old_path, backups_root, timestamp, "legacy-patch-4-mpq")

    new_path = os.path.join(client_root, "Data", "patch-E.MPQ")
    new_sha = hashing.sha256_file(new_path)
    if new_sha is None or new_sha != mpq_build_result.get("mpq_sha256"):
        return {
            "action": "backed_up_only",
            "reason": (
                "patch-E.MPQ verification failed after write -- old patch-4.MPQ "
                "was backed up but NOT removed, both files remain in place"
            ),
            "backup_path": backup_path,
        }

    os.remove(old_path)
    return {
        "action": "migrated",
        "backup_path": backup_path,
        "removed": old_path,
        "installed": new_path,
    }

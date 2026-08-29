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
import shutil

from . import backup, hashing, mpq_conflict


def migrate(client_root, backups_root, timestamp, mpq_build_result):
    """Safety-net migration for the FRESH-BUILD path only: patch-E.MPQ was
    already (independently) written by mpq_build.build(), and this only
    retires a leftover, positively-identified legacy patch-4.MPQ if one is
    still present (e.g. a previous partial install already wrote patch-E
    but never got to retire patch-4). The primary migration path for a
    caller who HASN'T built patch-E yet is migrate_direct_from_verified_
    legacy() below, which migrates the legacy archive's own verified
    payload directly and never needs a fresh build at all.

    mpq_build_result: a dict carrying at least "sha256" -- the hash
    patch-E.MPQ is expected to already have (matches the manifest's own
    m["patch_mpq"]["sha256"] field name).

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
    if new_sha is None or new_sha != mpq_build_result.get("sha256"):
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


def migrate_direct_from_verified_legacy(client_root, backups_root, timestamp):
    """Migrate a positively-identified legacy patch-4.MPQ directly to
    patch-E.MPQ by copying its exact bytes. No vanilla Item.dbc, no mpyq,
    no fresh MPQ construction -- the legacy archive's own payload IS
    already the proven-good Echoes payload (identify_legacy_echoes_patch4
    performed a byte-exact fingerprint match on it); copying it under a
    new filename does not change its content, so there is nothing to
    "build."

    This is the primary migration path when the caller has NOT already
    written patch-E.MPQ. The caller is responsible for the pre-condition
    that patch-E.MPQ does not already exist -- an existing patch-E is
    always a hard conflict resolved by mpq_conflict.resolve() before this
    function is ever invoked, so this function does not re-decide that;
    it simply refuses (as a "none" result, not an exception) if it finds
    one anyway, so this function can be called/tested standalone without
    duplicating that decision.

    Transactional: copies to a temp path first, verifies the copy is
    byte-identical to the source BEFORE the atomic rename into the real
    patch-E.MPQ location, and verifies the final file again after the
    rename. Legacy patch-4.MPQ is only ever removed after that final
    verification succeeds. Any failure at any step -- copy error,
    hash mismatch, rename error -- leaves patch-4.MPQ fully in place and
    does not leave a partially-written patch-E.MPQ behind (the temp file
    is cleaned up).

    Returns a dict describing what happened -- same "action" vocabulary
    as migrate() ("none", "migrated", "failed") plus enough fields
    (sha256, source) for the caller to record accurate manifest
    provenance. Never raises.
    """
    old_path = os.path.join(client_root, "Data", "patch-4.MPQ")
    new_path = os.path.join(client_root, "Data", "patch-E.MPQ")

    if not os.path.isfile(old_path):
        return {"action": "none", "reason": "no legacy patch-4.MPQ present"}

    if not mpq_conflict.identify_legacy_echoes_patch4(old_path):
        return {
            "action": "none",
            "reason": (
                f"{old_path} exists but could not be positively identified as "
                "Echoes' own output (byte-exact fingerprint did not match) -- "
                "left completely untouched, no migration attempted"
            ),
        }

    if os.path.isfile(new_path):
        return {
            "action": "none",
            "reason": (
                f"{new_path} already exists -- direct migration refuses to "
                "overwrite; caller must resolve the existing patch-E.MPQ first"
            ),
        }

    source_sha = hashing.sha256_file(old_path)
    backup_path = backup.backup_path(old_path, backups_root, timestamp, "legacy-patch-4-mpq")

    tmp_path = new_path + ".migrating-tmp"
    try:
        shutil.copy2(old_path, tmp_path)
        tmp_sha = hashing.sha256_file(tmp_path)
        if tmp_sha != source_sha:
            os.remove(tmp_path)
            return {
                "action": "failed",
                "reason": (
                    f"copy verification mismatch (expected {source_sha}, got "
                    f"{tmp_sha}) -- patch-4.MPQ left untouched, patch-E.MPQ NOT created"
                ),
                "backup_path": backup_path,
            }
        os.replace(tmp_path, new_path)
    except OSError as e:
        if os.path.isfile(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass
        return {
            "action": "failed",
            "reason": f"copy/rename failed: {e} -- patch-4.MPQ left untouched, patch-E.MPQ NOT created",
            "backup_path": backup_path,
        }

    final_sha = hashing.sha256_file(new_path)
    if final_sha != source_sha:
        # Extremely unlikely given os.replace()'s atomicity, but never
        # retire patch-4 on anything less than a confirmed-verified
        # patch-E already in its final location.
        return {
            "action": "failed",
            "reason": (
                f"post-write verification mismatch (expected {source_sha}, got "
                f"{final_sha}) -- patch-4.MPQ left untouched"
            ),
            "backup_path": backup_path,
        }

    os.remove(old_path)
    return {
        "action": "migrated",
        "backup_path": backup_path,
        "removed": old_path,
        "installed": new_path,
        "sha256": final_sha,
        "source": "verified_legacy_patch4",
    }

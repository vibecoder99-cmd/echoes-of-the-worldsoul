# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Patch-4.MPQ conflict policy.

IMPORTANT PROVENANCE NOTE: no E2J13 design document explicitly defines
"what to do when Data/patch-4.MPQ already exists and is NOT Echoes'
own file" -- the closest applicable text is
E2J13-INSTALL-UPGRADE-UNINSTALL-MODEL.md's general pre-flight principle:
"No conflicting files at target destinations that aren't already
Echoes-owned (per manifest)." The policy below is a direct, conservative
application of that general principle to this specific file, not an
invented new design -- flagged for explicit confirmation at the
E2j16 installer architecture checkpoint rather than treated as
pre-approved.

Policy:
  - If no patch-4.MPQ exists at the target: safe to write directly.
  - If one exists AND its hash matches a hash this installer's own
    manifest already recorded as ours: safe to overwrite (it's an
    Echoes upgrade of Echoes' own prior output) -- but still back it up
    first per the standing backup-before-mutate rule.
  - If one exists and is NOT recorded as Echoes-owned in the manifest:
    treat it as third-party content. Never overwrite silently. Back it
    up and require an explicit --force-mpq-overwrite from the caller
    (a human decision, not an installer default), or offer an alternate
    output filename (patch-Z.mpq, matching this project's own documented
    "any name that sorts after patch-3.MPQ" convention in INSTALL.md) so
    the existing archive is never touched at all.
"""

from enum import Enum


class MpqConflictResolution(Enum):
    NO_EXISTING_FILE = "no_existing_file"
    EXISTING_IS_OURS = "existing_is_ours"
    EXISTING_IS_THIRD_PARTY_BLOCKED = "existing_is_third_party_blocked"
    EXISTING_IS_THIRD_PARTY_FORCED = "existing_is_third_party_forced"


def resolve(existing_path_sha256, manifest_recorded_sha256, force_overwrite):
    """Pure decision function -- no I/O. Callers hash the existing file
    (if present) and pass it in, along with whatever hash (if any) the
    manifest recorded for a previous Echoes-generated patch-4.MPQ.
    """
    if existing_path_sha256 is None:
        return MpqConflictResolution.NO_EXISTING_FILE

    if manifest_recorded_sha256 is not None and existing_path_sha256 == manifest_recorded_sha256:
        return MpqConflictResolution.EXISTING_IS_OURS

    if force_overwrite:
        return MpqConflictResolution.EXISTING_IS_THIRD_PARTY_FORCED

    return MpqConflictResolution.EXISTING_IS_THIRD_PARTY_BLOCKED


def suggest_alternate_name(data_dir, os_path_isfile):
    """Suggest the next patch-N.MPQ name that sorts after any existing
    patch-*.MPQ, per INSTALL.md's own documented convention. os_path_isfile
    is injected (not imported directly) so this stays a pure, testable
    function."""
    import string
    for letter in string.ascii_uppercase:
        candidate = f"patch-{letter}.MPQ"
        if not os_path_isfile(f"{data_dir}/{candidate}"):
            return candidate
    raise RuntimeError("no available patch-<letter>.MPQ name found (A-Z exhausted)")

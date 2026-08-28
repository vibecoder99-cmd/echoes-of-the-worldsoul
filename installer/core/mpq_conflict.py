# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Echoes client patch namespace: patch-E.MPQ ownership policy, plus
legacy patch-4.MPQ detection for the one-time upgrade path.

## Why patch-E, not patch-4

`patch-4.MPQ` is a common first custom-patch slot picked by many other
mods/servers -- a generic numeric slot invites collision. Echoes now
targets `patch-E.MPQ` ("E" for Echoes) as its own reserved slot.

## Load-support evidence (see the governing checkpoint report for full
## detail; summarized here for anyone reading this module directly)

This project's OWN pre-existing, author-written documentation
(`INSTALL.md`, `README.md` -- both predate this installer work) already
recommends and ships client patches under a **letter**-named archive
(`patch-Z.mpq`), explicitly describing it as "any name that sorts after
`patch-3.MPQ`". That is concrete, in-project, presumably-client-tested
evidence that WoW 3.3.5a (build 12340) loads letter-named `patch-<X>.MPQ`
archives as a class. Community documentation of this exact client
build's patch-loading algorithm (converging across many independent
3.3.5a client-modding sources) consistently describes two separate
loops: a NUMERIC loop (`patch.MPQ`, `patch-2.MPQ`, `patch-3.MPQ`, ...)
that stops at the first missing number, and a separate ALPHABETIC loop
(`patch-A.MPQ` through `patch-Z.MPQ`) that checks every letter
independently rather than stopping at a gap -- i.e. `patch-E.MPQ` alone,
with no `patch-A/B/C/D.MPQ` present, is expected to load. Later-loaded
archives win for a given internal file path, so the alphabetic pass
loads after every numeric patch, and within the alphabetic pass, letter
order is load order (patch-E loads before patch-F..Z, after patch-A..D).

**This has NOT been independently confirmed via a live client launch or
binary disassembly this session** -- no live WoW.exe session was
available. The scratch-layout build/round-trip evidence in
`docs/distribution/E2J16-*.md` (WSL repo) and this module's own tests
prove the *archive* is byte-correct and mechanically identical to the
already-proven `patch-4.MPQ`/`patch-Z.mpq` payload; it does not prove the
*client* loads this specific filename. A real live-client check (does
`#additem 900010`/`900011` show correct icons/tooltips with ONLY
patch-E.MPQ present, no patch-4.MPQ) is recommended before this becomes
the unconditional shipped default -- see the governing checkpoint report.

## DBC merge-conflict caveat (documented honestly, not solved)

Renaming the archive avoids Echoes colliding with another mod that also
happens to use the generic `patch-4.MPQ` slot. It does **NOT** solve the
case where some OTHER, later-loaded patch (e.g. a hypothetical
`patch-F.MPQ` from a different mod) also replaces
`DBFilesClient\\Item.dbc` -- whichever patch loads last still wins for
that entire file, and neither patch's changes merge with the other's.
General MPQ/DBC merging across independent third-party patches is
explicitly out of scope for 2.0.

## patch-E ownership model

  - patch-E.MPQ absent           -> install normally.
  - patch-E.MPQ present, proven Echoes-owned (hash matches this
    installer's own manifest record) -> upgrade/repair normally,
    backup before mutation.
  - patch-E.MPQ present, NOT proven Echoes-owned -> BLOCK and report a
    namespace collision. No --force overwrite exists in the ordinary
    install path -- Echoes does not fight over a slot it doesn't already
    own. (An operator who understands the collision can still resolve it
    manually outside this installer; this tool does not provide an
    automated override for that decision.)
"""

import os
import struct
import sys

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_DBC_PATCH_DIR = os.path.join(_REPO_ROOT, "dbc_patch")
if _DBC_PATCH_DIR not in sys.path:
    sys.path.insert(0, _DBC_PATCH_DIR)

from mpq_writer import read_single_file_mpq  # noqa: E402

from enum import Enum

ECHOES_MPQ_INTERNAL_PATH = "DBFilesClient\\Item.dbc"

# Byte-exact provenance fingerprint for the two Echoes custom item
# records -- see dbc_patch/DBC_EDITING_NOTES.md "Verified Custom Records".
# Used only for RECOGNIZING an already-installed legacy patch-4.MPQ as
# Echoes' own output during the one-time upgrade; never used to construct
# new records (that stays entirely inside dbc_patch/patch_item_dbc.py).
_ECHOES_ITEM_900010 = bytes([
    0xAA, 0xBB, 0x0D, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xCB, 0xD7, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
])
_ECHOES_ITEM_900011 = bytes([
    0xAB, 0xBB, 0x0D, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xCA, 0xD7, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
])


class MpqConflictResolution(Enum):
    NO_EXISTING_FILE = "no_existing_file"
    EXISTING_IS_OURS = "existing_is_ours"
    EXISTING_IS_THIRD_PARTY_BLOCKED = "existing_is_third_party_blocked"


def resolve(existing_path_sha256, manifest_recorded_sha256):
    """Pure decision function -- no I/O, no force-overwrite path. Callers
    hash the existing patch-E.MPQ (if present) and pass it in, along with
    whatever hash (if any) the manifest recorded for a previous
    Echoes-generated patch-E.MPQ."""
    if existing_path_sha256 is None:
        return MpqConflictResolution.NO_EXISTING_FILE

    if manifest_recorded_sha256 is not None and existing_path_sha256 == manifest_recorded_sha256:
        return MpqConflictResolution.EXISTING_IS_OURS

    return MpqConflictResolution.EXISTING_IS_THIRD_PARTY_BLOCKED


def identify_legacy_echoes_patch4(path):
    """Inspect an existing Data/patch-4.MPQ (or any file path) and return
    True only if it positively matches Echoes' own known payload
    fingerprint: parses as this project's minimal single-file MPQ v1
    format, carries DBFilesClient\\Item.dbc, and that DBC contains BOTH
    custom records (900010, 900011) with byte-exact field values. Returns
    False for anything else, including a genuine parse/read failure --
    never raises, since "can't prove it's ours" and "definitely isn't
    ours" both mean the same thing here: leave it untouched."""
    if not os.path.isfile(path):
        return False
    try:
        dbc = read_single_file_mpq(path, ECHOES_MPQ_INTERNAL_PATH)
    except Exception:
        return False

    try:
        magic, rec_count, field_count, rec_size, _sbs = struct.unpack_from("<4sIIII", dbc, 0)
    except struct.error:
        return False
    if magic != b"WDBC" or field_count != 8 or rec_size != 32:
        return False

    header = 20
    found_900010 = found_900011 = False
    for i in range(rec_count):
        off = header + i * rec_size
        entry = struct.unpack_from("<I", dbc, off)[0]
        if entry == 900010 and dbc[off:off + rec_size] == _ECHOES_ITEM_900010:
            found_900010 = True
        elif entry == 900011 and dbc[off:off + rec_size] == _ECHOES_ITEM_900011:
            found_900011 = True

    return found_900010 and found_900011

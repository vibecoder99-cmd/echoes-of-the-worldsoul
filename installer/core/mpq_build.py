# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""patch-E.MPQ build pipeline: vanilla Item.dbc discovery/extraction ->
patch_item_dbc.py -> mpq_writer.py.

Named patch-E.MPQ ("E" for Echoes), not the old patch-4.MPQ -- see
mpq_conflict.py's module docstring for the namespace-collision rationale
and load-support evidence. legacy_migration.py handles moving a prior
Echoes-owned patch-4.MPQ install forward to this new slot.

This module contains NO DBC-editing logic and NO MPQ-archive logic of its
own -- both live in dbc_patch/ (this repo's canonical, already-tracked
tooling) and are imported from there, never duplicated. This module only
orchestrates: find a vanilla Item.dbc, hand it to patch_item_dbc, hand the
result to mpq_writer, apply the conflict policy before writing.

Ships no Blizzard client data. The vanilla Item.dbc is always either
(a) extracted from the operator's own client's own stock MPQ archives, or
(b) supplied explicitly by the operator as a fallback -- never bundled,
never downloaded.
"""

import hashlib
import os
import sys

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_DBC_PATCH_DIR = os.path.join(_REPO_ROOT, "dbc_patch")
if _DBC_PATCH_DIR not in sys.path:
    sys.path.insert(0, _DBC_PATCH_DIR)

from patch_item_dbc import patch as patch_item_dbc  # noqa: E402
from mpq_writer import write_single_file_mpq  # noqa: E402

MPQ_INTERNAL_PATH = "DBFilesClient\\Item.dbc"

# Stock archives that have historically carried DBFilesClient/Item.dbc on a
# retail-derived 3.3.5a (build 12340) client. Not every client layout
# includes all of these (some private-server client packages strip DBCs
# out of the MPQs entirely, as the E2j16 checkpoint discovered on this
# project's own test client) -- extraction tries each in turn and falls
# through if none succeed, never assumes success.
_CANDIDATE_ARCHIVES = [
    "common.MPQ",
    "common-2.MPQ",
    "expansion.MPQ",
    "lichking.MPQ",
    "patch.MPQ",
    "patch-2.MPQ",
    "patch-3.MPQ",
]


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def try_extract_vanilla_item_dbc(client_root):
    """Attempt to extract a vanilla Item.dbc from the client's own stock
    archives. Returns (data, source_archive_name) on success, or (None, None)
    if no candidate archive carried it -- callers must fall back to an
    explicit --vanilla-dbc path in that case, never fabricate one.

    Requires the optional `mpyq` dependency for reading standard
    (potentially compressed, multi-file) Blizzard MPQ archives -- this is
    a different, much larger format than the minimal single-file archive
    dbc_patch/mpq_writer.py produces, and deliberately not reimplemented
    here. If mpyq is unavailable, this function reports that plainly
    rather than silently returning nothing.
    """
    try:
        import mpyq
    except ImportError:
        return None, None, "mpyq is not installed (pip install mpyq) -- cannot read stock client MPQ archives"

    data_dir = os.path.join(client_root, "Data")
    for name in _CANDIDATE_ARCHIVES:
        path = os.path.join(data_dir, name)
        if not os.path.isfile(path):
            continue
        try:
            archive = mpyq.MPQArchive(path)
            data = archive.read_file("DBFilesClient\\Item.dbc")
        except Exception:
            continue
        if data:
            return data, name, None

    return None, None, "Item.dbc not found in any recognized stock archive"


def build(vanilla_dbc_bytes, output_dir):
    """Run patch_item_dbc + mpq_writer against already-obtained vanilla DBC
    bytes. Returns a dict describing the result. Raises on failure -- never
    returns a "success" dict for a failed patch/build step."""
    os.makedirs(output_dir, exist_ok=True)
    vanilla_path = os.path.join(output_dir, "vanilla_Item.dbc")
    patched_path = os.path.join(output_dir, "Item.dbc")
    mpq_path = os.path.join(output_dir, "patch-E.MPQ")

    with open(vanilla_path, "wb") as f:
        f.write(vanilla_dbc_bytes)

    ok = patch_item_dbc(vanilla_path, patched_path)
    if not ok:
        raise RuntimeError("patch_item_dbc self-verification failed -- see console output above")

    with open(patched_path, "rb") as f:
        patched_bytes = f.read()

    write_single_file_mpq(mpq_path, MPQ_INTERNAL_PATH, patched_bytes)

    return {
        "vanilla_dbc_sha256": sha256_bytes(vanilla_dbc_bytes),
        "patched_dbc_sha256": sha256_bytes(patched_bytes),
        "mpq_path": mpq_path,
        "mpq_sha256": sha256_bytes(open(mpq_path, "rb").read()),
        "internal_files": [MPQ_INTERNAL_PATH],
    }

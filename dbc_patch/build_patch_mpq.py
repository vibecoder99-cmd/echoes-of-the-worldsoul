#!/usr/bin/env python3
# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
#
# Echoes of the Worldsoul -- Patch-4.MPQ release build orchestrator
#
# Thin wrapper connecting the two independently-testable transformation
# steps this project's client patch requires. It duplicates neither:
#
#   user-supplied vanilla Item.dbc
#       -> patch_item_dbc.patch()   (DBC row construction + self-check)
#       -> patched Item.dbc
#       -> mpq_writer.write_single_file_mpq()   (archive packaging)
#       -> Patch-4.MPQ
#
# This script contains no DBC-editing logic and no MPQ-format logic of
# its own -- see patch_item_dbc.py and mpq_writer.py respectively. It is
# not an installer: it does not discover a client install path, does not
# write into any live client's Data/ folder, and does not fetch or embed
# any Blizzard-copyrighted source data. The vanilla Item.dbc is required
# input, supplied by the person running this script from their own
# legally-owned WoW 3.3.5a (build 12340) client -- see README.md /
# INSTALL.md for how to extract it.
#
# Usage:
#   python build_patch_mpq.py <vanilla_Item.dbc> <output_dir>
#
# Writes <output_dir>/Item.dbc (the patched DBC, kept for inspection)
# and <output_dir>/patch-4.MPQ (the final archive).

import os
import sys

from patch_item_dbc import patch as patch_item_dbc
from mpq_writer import write_single_file_mpq

MPQ_INTERNAL_PATH = "DBFilesClient\\Item.dbc"


def build(vanilla_dbc_path, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    patched_dbc_path = os.path.join(output_dir, "Item.dbc")
    mpq_path = os.path.join(output_dir, "patch-4.MPQ")

    print("=== Step 1: patch Item.dbc ===")
    ok = patch_item_dbc(vanilla_dbc_path, patched_dbc_path)
    if not ok:
        print("DBC patch step failed -- aborting before MPQ packaging.")
        return False

    print()
    print("=== Step 2: package into Patch-4.MPQ ===")
    with open(patched_dbc_path, 'rb') as f:
        patched_bytes = f.read()
    arc_size = write_single_file_mpq(mpq_path, MPQ_INTERNAL_PATH, patched_bytes)
    print(f"  Wrote {mpq_path} ({arc_size} bytes)")
    print(f"  Internal path: {MPQ_INTERNAL_PATH}")
    print()
    print("Done. Copy the generated patch-4.MPQ into your WoW client's Data\\ folder")
    print("(back up any existing patch-4.MPQ first) and distribute it to players")
    print("alongside the EchoesOfTheWorldsoulBridge AddOn.")
    return True


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python build_patch_mpq.py <vanilla_Item.dbc> <output_dir>")
        print()
        print("  <vanilla_Item.dbc> must be an unmodified WoW 3.3.5a (build 12340)")
        print("  Item.dbc, extracted from your own client. This tool does not")
        print("  ship, fetch, or embed any Blizzard client data.")
        sys.exit(1)

    vanilla_path, out_dir = sys.argv[1], sys.argv[2]
    if not os.path.isfile(vanilla_path):
        print(f"ERROR: vanilla DBC not found: {vanilla_path}")
        sys.exit(1)

    sys.exit(0 if build(vanilla_path, out_dir) else 1)

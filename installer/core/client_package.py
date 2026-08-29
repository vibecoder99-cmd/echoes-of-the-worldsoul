# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""`echoes client-package` -- produce the Echoes player-side bundle.

The repository itself does not ship Blizzard client data. If the caller
supplies their own compatible vanilla Item.dbc, this command can generate
patch-E.MPQ (Echoes' reserved client-patch slot -- see
installer/core/mpq_conflict.py) from that operator-supplied client data
and include the generated patch in the output. If no Item.dbc is
supplied, only the AddOn plus patch-build instructions are produced.
"""

import os
import shutil

from . import hashing, mpq_build

_ADDON_VERSION_TOC_KEY = "## Version:"


def _read_toc_version(toc_path):
    with open(toc_path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip().startswith(_ADDON_VERSION_TOC_KEY):
                return line.split(":", 1)[1].strip()
    return "unknown"


def build(output_dir, vanilla_dbc_path=None):
    """Returns a dict describing the produced artifact.

    If vanilla_dbc_path is omitted, no generated MPQ or client data is
    included -- the artifact contains build_patch_mpq.py plus
    instructions instead. If vanilla_dbc_path is supplied, a generated
    patch-E.MPQ is produced from the caller's own Item.dbc and included
    in the output; that generated MPQ does contain client data derived
    from the caller-supplied file."""
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    addon_src = os.path.join(repo_root, "client_addon", "EchoesOfTheWorldsoulBridge")
    toc_path = os.path.join(addon_src, "EchoesOfTheWorldsoulBridge.toc")
    version = _read_toc_version(toc_path)

    os.makedirs(output_dir, exist_ok=True)
    addon_dst = os.path.join(output_dir, "EchoesOfTheWorldsoulBridge")
    if os.path.isdir(addon_dst):
        shutil.rmtree(addon_dst)
    shutil.copytree(addon_src, addon_dst)

    result = {
        "output_dir": output_dir,
        "addon_version": version,
        "addon_files": hashing.sha256_tree(addon_dst),
        "mpq_built": False,
    }

    if vanilla_dbc_path:
        with open(vanilla_dbc_path, "rb") as f:
            vanilla_bytes = f.read()
        build_result = mpq_build.build(vanilla_bytes, output_dir)
        result["mpq_built"] = True
        result["mpq_sha256"] = build_result["mpq_sha256"]
        result["mpq_path"] = build_result["mpq_path"]
    else:
        # Instructed manual step -- never bundle Blizzard data, never
        # silently skip without telling the packager why.
        with open(os.path.join(output_dir, "BUILD-PATCH-E-MPQ.txt"), "w", encoding="utf-8") as f:
            f.write(
                "No vanilla Item.dbc was supplied to client-package, so "
                "patch-E.MPQ was not built.\n\n"
                "To build it yourself:\n"
                "  python dbc_patch/build_patch_mpq.py <your_vanilla_Item.dbc> <output_dir>\n\n"
                "This repository ships no Blizzard client data -- the vanilla "
                "Item.dbc must come from your own legally-owned 3.3.5a (build "
                "12340) client.\n"
            )

    with open(os.path.join(output_dir, "VERSION.txt"), "w", encoding="utf-8") as f:
        f.write(f"EchoesOfTheWorldsoulBridge AddOn version: {version}\n")
        f.write("See INSTALL.md in the source repository for full setup instructions.\n")

    return result

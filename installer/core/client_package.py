# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""`echoes client-package` -- produce a distributable Client Companion
bundle from the public repo's own current source. No Blizzard client data
included; patch-E.MPQ (Echoes' reserved client-patch slot -- see
installer/core/mpq_conflict.py) is either built (if the caller supplies a
vanilla Item.dbc) or left as an instructed manual step.
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
    """Returns a dict describing the produced artifact. Never includes
    Blizzard source data -- if vanilla_dbc_path is omitted, the artifact
    contains build_patch_mpq.py plus instructions instead of a
    pre-built MPQ."""
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

# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Target discovery.

This module NEVER selects a destructive target on its own -- every install/
upgrade/uninstall/repair/client-package operation requires an explicit
--azerothcore-root and/or --client-root from the caller. The functions here
only *describe* what was found at an already-given path, or offer
non-binding suggestions a human-facing wrapper can print, never something
that gets used automatically to decide what to mutate.

No personal-machine path (the WSL development repo's own test paths, e.g.
`/home/dml/wow-server-playerbots` or `C:\\Dad's MMO Lab Test WoW Client\\`)
appears anywhere in this file. Detection is based on real, generic
filesystem markers.
"""

import os


def describe_azerothcore_root(path):
    """Inspect a caller-supplied AzerothCore root and report what's there.
    Returns a dict of booleans/strings -- never raises for "not found"
    conditions, only for a path that doesn't exist at all."""
    if not os.path.isdir(path):
        raise FileNotFoundError(f"not a directory: {path}")

    modules_dir = os.path.join(path, "modules")
    result = {
        "path": path,
        "has_modules_dir": os.path.isdir(modules_dir),
        "has_mod_ale": os.path.isdir(os.path.join(modules_dir, "mod-ale")),
        "has_mod_playerbots": os.path.isdir(os.path.join(modules_dir, "mod-playerbots")),
        "has_mod_echoes_stats": os.path.isdir(os.path.join(modules_dir, "mod-echoes-stats")),
        "has_mod_echoes_playerbots": os.path.isdir(os.path.join(modules_dir, "mod-echoes-playerbots")),
        # dml-start.sh is a real, distinctive, non-personal file this
        # project's own DML deployments ship at the AzerothCore root --
        # its presence (not any personal path) is the DML-style-deployment
        # signal. Absence just means "not this specific deployment
        # pattern," not "incompatible."
        "looks_like_dml_style_deployment": os.path.isfile(os.path.join(path, "dml-start.sh")),
    }
    return result


def describe_client_root(path):
    """Inspect a caller-supplied WoW client root and report what's there.
    Conservative: only recognizes the generic retail 3.3.5a Data/ layout,
    never claims compatibility with an arbitrary repack."""
    if not os.path.isdir(path):
        raise FileNotFoundError(f"not a directory: {path}")

    data_dir = os.path.join(path, "Data")
    wow_exe = os.path.join(path, "Wow.exe")
    common_mpq = os.path.join(data_dir, "common.MPQ")
    existing_patch4 = os.path.join(data_dir, "patch-4.MPQ")
    addons_dir = os.path.join(path, "Interface", "AddOns")

    result = {
        "path": path,
        "has_wow_exe": os.path.isfile(wow_exe),
        "has_data_dir": os.path.isdir(data_dir),
        "has_common_mpq": os.path.isfile(common_mpq),
        "looks_like_compatible_335a_client": (
            os.path.isfile(wow_exe) and os.path.isfile(common_mpq)
        ),
        "existing_patch4_mpq": existing_patch4 if os.path.isfile(existing_patch4) else None,
        "addons_dir": addons_dir if os.path.isdir(addons_dir) else None,
    }
    return result


def echoes_addon_installed(client_root):
    """Return the path to an already-installed EchoesOfTheWorldsoulBridge
    AddOn under this client, or None."""
    candidate = os.path.join(
        client_root, "Interface", "AddOns", "EchoesOfTheWorldsoulBridge"
    )
    return candidate if os.path.isdir(candidate) else None

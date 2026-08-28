# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""External prerequisite checks. Never vendors or modifies these -- only
detects and reports."""

from . import discovery


class PrereqResult:
    def __init__(self, name, present, remediation=None):
        self.name = name
        self.present = present
        self.remediation = remediation

    def __repr__(self):
        return f"PrereqResult({self.name!r}, present={self.present})"


def check_mod_ale(azerothcore_root):
    info = discovery.describe_azerothcore_root(azerothcore_root)
    if info["has_mod_ale"]:
        return PrereqResult("mod-ale", True)
    return PrereqResult(
        "mod-ale",
        False,
        remediation=(
            "mod-ale (the Eluna Lua engine fork Echoes' Lua depends on) was not "
            f"found under {azerothcore_root}/modules/mod-ale. Install it from its "
            "own upstream repository before installing Echoes -- Echoes does not "
            "vendor or install mod-ale itself. This project's Lua targets Lua 5.2 "
            "(build mod-ale with LUA_VERSION=lua52)."
        ),
    )


def check_mod_playerbots(azerothcore_root):
    info = discovery.describe_azerothcore_root(azerothcore_root)
    return PrereqResult("mod-playerbots", info["has_mod_playerbots"])

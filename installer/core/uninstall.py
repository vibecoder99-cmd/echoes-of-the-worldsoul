# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""`echoes uninstall` -- NOT YET IMPLEMENTED beyond this stub.

Design target (per E2J13-DATABASE-OWNERSHIP-AND-MIGRATION-MAP.md and
E2J13-INSTALL-UPGRADE-UNINSTALL-MODEL.md): standard uninstall removes only
manifest-recorded Echoes-owned files/directories (lua_scripts contents
that match the manifest's file list, modules/mod-echoes-stats,
modules/mod-echoes-playerbots if present, the Client Companion AddOn
directory, the generated patch-E.MPQ only if its hash matches the
manifest's recorded value) and NEVER touches mod-ale, mod-playerbots, any
other AzerothCore module, or any `ap_*` database table -- database
retention is the explicit default per the frozen design (15 of 19 tables
are classified "persistent progression," never dropped by a non-purge
operation). A separate, explicit, confirmation-gated `--purge` mode
(dropping the ap_* schema after a mandatory backup) is future scope, not
implemented here or in this stub.
"""


def uninstall(*_args, **_kwargs):
    raise NotImplementedError(
        "echoes uninstall is not yet implemented. Database retention-by-"
        "default and manifest-scoped file removal are both designed (see "
        "this module's docstring) but not yet coded -- see the "
        "architecture checkpoint's BLOCKERS."
    )

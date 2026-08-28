# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""`echoes upgrade` -- NOT YET IMPLEMENTED beyond this stub.

Design target (per E2J13-INSTALL-UPGRADE-UNINSTALL-MODEL.md and the
governing E2j16 installer-wiring checkpoint): back up before mutate,
re-run install.install() against an existing manifest (its component
copy/backup logic is already upgrade-safe -- it backs up and replaces
rather than assuming a fresh target), apply schema via the same
sql_runner.apply_schema_package() (already idempotent/upgrade-safe per
the E2j16 SQL reproducibility evidence), and update manifest version
metadata. Reported as a stub rather than implemented at the architecture
checkpoint so the checkpoint reflects real status, not an assumed one.
"""


def upgrade(*_args, **_kwargs):
    raise NotImplementedError(
        "echoes upgrade is not yet implemented. install.install() is "
        "upgrade-safe for individual components (it backs up and replaces "
        "an existing target rather than assuming a fresh one) and "
        "sql_runner.apply_schema_package() is idempotent against an "
        "existing schema -- upgrade() will compose these once the manifest "
        "version-comparison and 'apply N sequential releases, not a jump' "
        "logic from E2J13 is built."
    )

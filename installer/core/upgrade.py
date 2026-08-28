# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""`echoes upgrade` -- move an existing install (manifest-tracked or a
representative pre-manifest legacy install, e.g. a v1.6.0-era layout)
forward to the current package.

Composes rather than reimplements: install.install()'s own per-component
logic already IS upgrade-safe --

  - every component step backs up whatever's currently there before
    replacing it (backup.py, called unconditionally when the target
    already exists);
  - sql_runner.apply_schema_package() is idempotent against an existing
    schema (guarded ADD COLUMN/CREATE TABLE -- see the E2j16 SQL
    reproducibility evidence: a simulated pre-1.5.0-era schema upgraded
    cleanly with pre-existing player data preserved exactly);
  - config.materialize() merges new keys forward without touching
    existing tuning.

So upgrade() is intentionally a thin wrapper: it records what version was
installed beforehand (or notes "pre-manifest legacy install" if there was
no manifest at all -- exactly the v1.6.0-style case, since that release
predates this installer and never wrote one), then calls install.install()
with the same options, then records the version transition in the
manifest. It does not implement "jump 3 versions at once" logic beyond
what re-running the current package's own idempotent SQL/file steps
already provides, because this project has shipped only one installer
package version so far -- see this module's own limitation note below.
"""

from . import manifest as manifest_mod
from . import install as install_mod


def upgrade(opts, target_product_version):
    """opts: an install.InstallOptions. target_product_version: the
    version string this upgrade should record as installed (e.g. from
    ap_core.lua's AP.VERSION at release-build time).

    Returns a dict: {"previous_version": ..., "previous_manifest_present": bool,
    "target_version": ..., "manifest": <the post-upgrade manifest>}.
    """
    previous = manifest_mod.load(opts.azerothcore_root)
    previous_version = previous.get("product_version") if previous else None
    previous_manifest_present = previous is not None

    m = install_mod.install(opts)
    m["product_version"] = target_product_version
    m["upgrade_history"] = m.get("upgrade_history", [])
    m["upgrade_history"].append({
        "previous_version": previous_version,
        "previous_manifest_present": previous_manifest_present,
        "target_version": target_product_version,
    })
    manifest_mod.save(opts.azerothcore_root, m, m["last_modified_at"])

    return {
        "previous_version": previous_version,
        "previous_manifest_present": previous_manifest_present,
        "target_version": target_product_version,
        "manifest": m,
    }

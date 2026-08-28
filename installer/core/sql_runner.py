# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Runs the sql/schema/*.sql install package against a target MySQL
database via the `mysql` CLI (no extra Python DB-driver dependency --
matches this project's own validation approach during E2j16).

Never touches acore_world/acore_characters except through the files this
package ships; never runs arbitrary SQL a caller supplies."""

import glob
import os
import subprocess

SCHEMA_FILE_ORDER = [
    "00_preflight.sql",
    "10_base_schema.sql",
    "20_indexes_constraints.sql",
    "30_versioned_migrations.sql",
    "40_seed_or_defaults.sql",
    "90_validation.sql",
]


def _repo_sql_schema_dir():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    return os.path.join(repo_root, "sql", "schema")


def _repo_world_items_path():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    return os.path.join(repo_root, "sql", "data", "world_items.sql")


def run_file(mysql_args, database, sql_path):
    """mysql_args: list like ['-u', user, '-p' + password, '-h', host] --
    caller-supplied, never hardcoded. Raises CalledProcessError on failure
    (never swallows a schema error as success)."""
    with open(sql_path, "rb") as f:
        subprocess.run(
            ["mysql", *mysql_args, database],
            stdin=f,
            check=True,
        )


def apply_schema_package(mysql_args, characters_database):
    """Run the full numbered schema package, in order, against the
    characters database. Idempotent -- safe on both fresh installs and
    already-current installs (see the E2j16 reproducibility evidence in
    the WSL development repo's docs/distribution/E2J16-*.md)."""
    schema_dir = _repo_sql_schema_dir()
    applied = []
    for filename in SCHEMA_FILE_ORDER:
        path = os.path.join(schema_dir, filename)
        if not os.path.isfile(path):
            raise FileNotFoundError(f"expected schema file missing: {path}")
        run_file(mysql_args, characters_database, path)
        applied.append(filename)
    return applied


def apply_world_items(mysql_args, world_database):
    """Run the guarded world-item migration against the world database."""
    path = _repo_world_items_path()
    run_file(mysql_args, world_database, path)
    return [os.path.basename(path)]

# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""`echoes repair` -- NOT YET IMPLEMENTED beyond this stub.

Design target: use verify.verify()'s missing/mismatched findings per
component, restore only Echoes-owned files (per manifest) from the
repo's own current source (same files install.install() would place),
backing up whatever's being overwritten first. Must warn rather than
silently overwrite when a "mismatched" file looks like deliberate user
customization vs. drift/corruption -- that distinction is not yet
designed and is exactly why this is a stub, not an implementation.
"""


def repair(*_args, **_kwargs):
    raise NotImplementedError(
        "echoes repair is not yet implemented. verify.verify() already "
        "produces the missing/mismatched file list repair would act on; "
        "the undesigned piece is distinguishing intentional user "
        "customization from drift/corruption before overwriting -- see "
        "the architecture checkpoint's BLOCKERS."
    )

# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Path-safety primitives used by every destructive operation (repair,
uninstall). Nothing in this module trusts a manifest path at face value --
every deletion/overwrite target is resolved and re-checked against its
expected root immediately before acting on it, so a tampered manifest or a
symlink/reparse-point substituted after install cannot redirect a
destructive operation outside the intended tree.
"""

import os


class UnsafePathError(Exception):
    pass


def assert_contained(path, root):
    """Raise UnsafePathError unless the REAL (symlink-resolved) path is
    inside the REAL root. Both no-such-path and outside-root are treated
    as unsafe -- this is a pre-condition check for a destructive
    operation, not a existence check, so "doesn't exist yet" should be
    handled by the caller separately, not silently passed here."""
    real_root = os.path.realpath(root)
    real_path = os.path.realpath(path)
    try:
        common = os.path.commonpath([real_root, real_path])
    except ValueError:
        # Different drives on Windows, for example -- definitely not contained.
        raise UnsafePathError(f"{path!r} is not under {root!r} (different filesystem root)")
    if common != real_root:
        raise UnsafePathError(f"{path!r} resolves outside {root!r} (resolved: {real_path!r})")
    if real_path == real_root:
        raise UnsafePathError(f"refusing to treat the root itself ({root!r}) as a deletable target")


def is_safe_to_delete(path, root):
    """Non-raising convenience wrapper -- returns True/False instead of
    raising, for call sites that want to skip-and-report rather than
    abort the whole operation on one bad entry."""
    try:
        assert_contained(path, root)
        return True
    except UnsafePathError:
        return False


def safe_remove_file(path, root):
    """Remove a single file, after confirming containment and that it is
    a real file (not a symlink pointing elsewhere, not a directory)."""
    assert_contained(path, root)
    if os.path.islink(path):
        raise UnsafePathError(f"refusing to remove a symlink: {path!r}")
    if not os.path.isfile(path):
        return False
    os.remove(path)
    return True


def safe_remove_tree(path, root):
    """Remove a directory tree, after confirming containment and that the
    top-level target itself is not a symlink."""
    assert_contained(path, root)
    if os.path.islink(path):
        raise UnsafePathError(f"refusing to remove a symlink: {path!r}")
    if not os.path.isdir(path):
        return False
    import shutil
    shutil.rmtree(path)
    return True

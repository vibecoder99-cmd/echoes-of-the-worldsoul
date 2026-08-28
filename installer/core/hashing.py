# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Hash helpers used for install verification, repair, and manifest recording."""

import hashlib
import os


def sha256_file(path):
    """Return the SHA-256 hex digest of a file, or None if it doesn't exist."""
    if not os.path.isfile(path):
        return None
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_tree(root):
    """Return {relative_path: sha256} for every file under root, using
    forward-slash-normalized relative paths so the result is stable across
    Windows/Linux/WSL."""
    result = {}
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            result[rel] = sha256_file(full)
    return result


def verify_tree(root, expected):
    """Compare expected {relative_path: sha256} against root's current state.

    Returns (missing, mismatched, extra) -- extra is informational only
    (an installer must never treat "extra file present" as a failure on
    its own; a user's own files may legitimately share a directory).
    """
    actual = sha256_tree(root)
    missing = [p for p in expected if p not in actual]
    mismatched = [p for p in expected if p in actual and actual[p] != expected[p]]
    extra = [p for p in actual if p not in expected]
    return missing, mismatched, extra

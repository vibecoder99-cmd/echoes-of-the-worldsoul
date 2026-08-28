# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Backup-before-mutate helpers.

Formalizes the pattern this project already used, by convention, throughout
its historical env/backups/ history (see the WSL development repo's
E2J13-ROLLBACK-AND-REPAIR-MODEL.md) as an automatic installer behavior
rather than something a human has to remember to do by hand. Every
mutating installer operation must call backup_path() (for a single file)
or backup_tree() (for a directory) on a target BEFORE writing to it.
"""

import os
import shutil

# Timestamps are supplied by the caller (never Date.now()-equivalent
# generated inside this module) so backup naming stays deterministic and
# testable -- see installer/core/clock.py.


def backup_path(target_path, backup_root, timestamp, label):
    """Back up a single file (if it exists) to
    <backup_root>/<label>/<timestamp>/<basename>, returning the backup path
    or None if there was nothing to back up."""
    if not os.path.isfile(target_path):
        return None
    dest_dir = os.path.join(backup_root, label, timestamp)
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, os.path.basename(target_path))
    shutil.copy2(target_path, dest)
    return dest


def backup_tree(target_dir, backup_root, timestamp, label):
    """Back up an entire directory (if it exists) to
    <backup_root>/<label>/<timestamp>/, returning the backup path or None
    if there was nothing to back up. Never backs up backup_root itself."""
    if not os.path.isdir(target_dir):
        return None
    if os.path.abspath(target_dir) == os.path.abspath(backup_root):
        raise ValueError("refusing to back up backup_root onto itself")
    dest = os.path.join(backup_root, label, timestamp)
    shutil.copytree(target_dir, dest)
    return dest


def write_restore_note(backup_dir, target_path, note):
    """Write a plain-language restore procedure alongside a backup,
    matching this project's own env/backups/<phase>/<timestamp>/PRE-DEPLOY-STATE.md
    convention."""
    os.makedirs(backup_dir, exist_ok=True)
    with open(os.path.join(backup_dir, "RESTORE.md"), "w", encoding="utf-8") as f:
        f.write("# Backup restore note\n\n")
        f.write(f"Original target: {target_path}\n\n")
        f.write(note)
        f.write("\n")

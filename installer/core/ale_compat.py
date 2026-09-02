# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
"""Explicit, version-locked preparation of the Echoes mod-ALE compatibility patch."""

from dataclasses import asdict, dataclass
import hashlib
import os
import subprocess


TESTED_ALE_COMMIT = "9eeb1f3c47a81291548874fa4be2f4cde35e2ec3"
PATCH_SHA256 = "87cbd3d08d8ae5a73d4ef7c7e176bdc342d4676c15eb2e4aef9f2ab8a1547b82"
PATCH_RELATIVE_PATH = os.path.join(
    "compat", "mod-ale", "0001-expose-chardb-directexecute.patch"
)
REGISTRATION = os.path.join("src", "LuaEngine", "LuaFunctions.cpp")
METHODS = os.path.join("src", "LuaEngine", "methods", "GlobalMethods.h")


class ALECompatError(RuntimeError):
    pass


@dataclass(frozen=True)
class ALECompatResult:
    status: str
    detected_revision: str
    tested_revision: str
    patch_path: str
    changed: bool
    rebuild_required: bool
    message: str

    def as_dict(self):
        return asdict(self)


def _repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _ale_root(azerothcore_root):
    return os.path.join(os.path.abspath(azerothcore_root), "modules", "mod-ale")


def _run_git(ale_root, *args):
    completed = subprocess.run(
        ["git", "-C", ale_root, *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise ALECompatError(f"git {' '.join(args)} failed: {detail}")
    return completed.stdout.strip()


def _binding_present(ale_root):
    try:
        with open(os.path.join(ale_root, REGISTRATION), encoding="utf-8", errors="ignore") as f:
            registered = '"CharDBDirectExecute"' in f.read()
        with open(os.path.join(ale_root, METHODS), encoding="utf-8", errors="ignore") as f:
            methods = f.read()
            implemented = (
                "int CharDBDirectExecute(lua_State* L)" in methods
                and "CharacterDatabase.DirectExecute(query);" in methods
            )
    except OSError:
        return False
    return registered and implemented


def _verify_patch_artifact(patch_path):
    try:
        with open(patch_path, "rb") as patch_file:
            # Git may check text out with CRLF on Windows. Hash the canonical
            # LF representation so the same reviewed artifact verifies on
            # every supported operator platform.
            content = patch_file.read().replace(b"\r\n", b"\n")
            actual = hashlib.sha256(content).hexdigest()
    except OSError as exc:
        raise ALECompatError(f"Compatibility patch is unavailable: {exc}") from exc
    if actual != PATCH_SHA256:
        raise ALECompatError(
            f"Compatibility patch checksum mismatch: expected {PATCH_SHA256}, got {actual}. "
            "No source was changed."
        )


def prepare(azerothcore_root, apply=False):
    """Check or explicitly apply the compatibility patch; never rebuilds anything."""
    ale_root = _ale_root(azerothcore_root)
    if not os.path.isdir(ale_root):
        raise ALECompatError(f"mod-ALE source was not found at {ale_root}")

    revision = _run_git(ale_root, "rev-parse", "HEAD")
    patch_path = os.path.join(_repo_root(), PATCH_RELATIVE_PATH)

    if _binding_present(ale_root):
        return ALECompatResult(
            "ALREADY_PRESENT", revision, TESTED_ALE_COMMIT, patch_path, False, False,
            "CharDBDirectExecute is already implemented and registered; no source was changed.",
        )

    if revision != TESTED_ALE_COMMIT:
        raise ALECompatError(
            "Detected ALE revision: " + revision + "\n"
            "Compatibility patch tested against: " + TESTED_ALE_COMMIT + "\n"
            "Automatic patching is unavailable for this revision. No source was changed."
        )

    target_changes = _run_git(
        ale_root, "status", "--porcelain", "--", REGISTRATION, METHODS
    )
    if target_changes:
        raise ALECompatError(
            "The ALE files targeted by the compatibility patch already have local changes:\n"
            + target_changes
            + "\nResolve or preserve those changes manually; no source was changed."
        )

    _verify_patch_artifact(patch_path)
    _run_git(ale_root, "apply", "--check", patch_path)
    if not apply:
        return ALECompatResult(
            "READY_FOR_EXPLICIT_APPLY", revision, TESTED_ALE_COMMIT, patch_path, False, False,
            "Patch dry-run passed. Re-run with --apply to consent to changing mod-ALE source.",
        )

    _run_git(ale_root, "apply", patch_path)
    if not _binding_present(ale_root):
        raise ALECompatError("Patch command completed but CharDBDirectExecute was not verified")
    return ALECompatResult(
        "PATCH_APPLIED_REBUILD_REQUIRED", revision, TESTED_ALE_COMMIT, patch_path, True, True,
        "Compatibility patch applied. Reconfigure/rebuild worldserver, restart it safely, then run "
        "'echoes verify' and confirm runtime output reports CharDBDirectExecute: YES. Echoes is not "
        "runtime-compatible until that rebuild and verification succeed.",
    )

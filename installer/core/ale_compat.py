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
STOCK_SOURCE_SHA256 = {
    REGISTRATION: "69627299895105a6de5962e5dd7921b898426d77e084128963f4dfaf81e4ca7e",
    METHODS: "27bc0db383aeb162d27849f7dcb36abca1c7f955e054f2deb0578a57501ef4bd",
}
PATCHED_SOURCE_SHA256 = {
    REGISTRATION: "b31cde94ceff900a21b04ce480eede842be06473c1b16dbd6debe180e3ad93f9",
    METHODS: "a96fd75d1c1e80661743fc3776d600f1d4113a955a0ca0707a8f49d0375d627b",
}


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


def _canonical_file_sha256(path):
    try:
        with open(path, "rb") as source:
            content = source.read().replace(b"\r\n", b"\n")
    except OSError:
        return None
    return hashlib.sha256(content).hexdigest()


def _fingerprint(ale_root):
    return {rel: _canonical_file_sha256(os.path.join(ale_root, rel))
            for rel in (REGISTRATION, METHODS)}


def inspect_identity(azerothcore_root):
    """Identify ALE without ever accepting an enclosing repository's HEAD."""
    ale_root = _ale_root(azerothcore_root)
    if not os.path.isdir(ale_root):
        return {"ale_root": ale_root, "identity_method": "NONE", "git_root": None,
                "git_metadata": "NOT PRESENT", "revision": None,
                "source_fingerprint": "NO MATCH", "supported": False,
                "snapshot_state": None}
    git_root = None
    revision = None
    try:
        git_root = _run_git(ale_root, "rev-parse", "--show-toplevel")
    except ALECompatError:
        pass
    independent = git_root is not None and os.path.normcase(os.path.realpath(git_root)) == \
        os.path.normcase(os.path.realpath(ale_root))
    if independent:
        revision = _run_git(ale_root, "rev-parse", "HEAD")
    fingerprints = _fingerprint(ale_root)
    snapshot_state = None
    if fingerprints == STOCK_SOURCE_SHA256:
        snapshot_state = "STOCK"
    elif fingerprints == PATCHED_SOURCE_SHA256:
        snapshot_state = "PATCHED"
    if independent:
        return {"ale_root": ale_root, "identity_method": "Git", "git_root": git_root,
                "git_metadata": "INDEPENDENT CHECKOUT", "revision": revision,
                "source_fingerprint": snapshot_state or "NO MATCH",
                "supported": revision == TESTED_ALE_COMMIT,
                "snapshot_state": snapshot_state}
    parent_note = "PARENT REPOSITORY DETECTED; NOT VALID ALE IDENTITY" if git_root else "NOT PRESENT"
    return {"ale_root": ale_root, "identity_method": "Certified source fingerprint",
            "git_root": git_root, "git_metadata": parent_note, "revision": None,
            "source_fingerprint": "MATCH" if snapshot_state else "NO MATCH",
            "supported": snapshot_state is not None, "snapshot_state": snapshot_state}


def _apply_outside_repository(ale_root, patch_path, check_only):
    env = os.environ.copy()
    env["GIT_CEILING_DIRECTORIES"] = os.path.dirname(ale_root)
    args = ["git", "-C", ale_root, "apply"]
    if check_only:
        args.append("--check")
    args.append(patch_path)
    completed = subprocess.run(args, check=False, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, env=env)
    if completed.returncode != 0:
        raise ALECompatError(completed.stderr.strip() or "git apply failed")


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

    identity = inspect_identity(azerothcore_root)
    revision = identity["revision"] or "UNAVAILABLE (no independent ALE Git checkout)"
    patch_path = os.path.join(_repo_root(), PATCH_RELATIVE_PATH)

    if _binding_present(ale_root):
        if not identity["supported"] or identity["snapshot_state"] not in (None, "PATCHED"):
            raise ALECompatError(
                "CharDBDirectExecute is present, but ALE identity is unsupported/unverified.\n"
                f"Git metadata: {identity['git_metadata']}\n"
                f"Source fingerprint: {identity['source_fingerprint']}\nNo source was changed."
            )
        return ALECompatResult(
            "ALREADY_PRESENT", revision, TESTED_ALE_COMMIT, patch_path, False, False,
            "CharDBDirectExecute is already implemented and registered; no source was changed.",
        )

    if not identity["supported"] or identity["snapshot_state"] == "PATCHED":
        raise ALECompatError(
            "ALE source: " + ale_root + "\n"
            "Identity method: " + identity["identity_method"] + "\n"
            "Git metadata: " + identity["git_metadata"] + "\n"
            "ALE revision: " + revision + "\n"
            "Source fingerprint: " + identity["source_fingerprint"] + "\n"
            "Compatibility patch tested against: " + TESTED_ALE_COMMIT + "\n"
            "This ALE source is unsupported/unverified. Automatic patching is unavailable; "
            "revision-locked patching cannot continue. "
            "Use an independent Git clone of the certified commit. No source was changed."
        )

    if identity["identity_method"] == "Git":
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
    if identity["identity_method"] == "Git":
        _run_git(ale_root, "apply", "--check", patch_path)
    else:
        _apply_outside_repository(ale_root, patch_path, True)
    if not apply:
        return ALECompatResult(
            "READY_FOR_EXPLICIT_APPLY", revision, TESTED_ALE_COMMIT, patch_path, False, False,
            "Patch dry-run passed. Re-run with --apply to consent to changing mod-ALE source.",
        )

    if identity["identity_method"] == "Git":
        _run_git(ale_root, "apply", patch_path)
    else:
        _apply_outside_repository(ale_root, patch_path, False)
    if not _binding_present(ale_root):
        raise ALECompatError("Patch command completed but CharDBDirectExecute was not verified")
    return ALECompatResult(
        "PATCH_APPLIED_REBUILD_REQUIRED", revision, TESTED_ALE_COMMIT, patch_path, True, True,
        "Compatibility patch applied. Reconfigure/rebuild worldserver, restart it safely, then run "
        "'echoes verify' and confirm runtime output reports CharDBDirectExecute: YES. Echoes is not "
        "runtime-compatible until that rebuild and verification succeed.",
    )

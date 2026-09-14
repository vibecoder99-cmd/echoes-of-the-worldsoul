import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core import ale_compat, discovery


UPSTREAM = os.environ.get("ECHOES_STOCK_ALE_CHECKOUT")


def git(path, *args):
    return subprocess.run(["git", "-C", str(path), *args], check=True,
                          capture_output=True, text=True).stdout.strip()


def archive_root(tmp_path, parent_git=False):
    if not UPSTREAM:
        pytest.skip("set ECHOES_STOCK_ALE_CHECKOUT to the clean certified checkout")
    root = tmp_path / "azerothcore"
    ale = root / "modules" / "mod-ale"
    ale.parent.mkdir(parents=True)
    shutil.copytree(UPSTREAM, ale, ignore=shutil.ignore_patterns(".git"))
    if parent_git:
        git(root, "init", "-q")
        git(root, "config", "user.email", "test@example.invalid")
        git(root, "config", "user.name", "Echoes Test")
        (root / "parent.txt").write_text("different parent\n", encoding="utf-8")
        git(root, "add", "parent.txt")
        git(root, "commit", "-q", "-m", "parent")
    return root, ale


def test_independent_checkout_uses_its_own_git_root(tmp_path):
    if not UPSTREAM:
        pytest.skip("set ECHOES_STOCK_ALE_CHECKOUT to the clean certified checkout")
    root = tmp_path / "azerothcore"
    ale = root / "modules" / "mod-ale"
    ale.parent.mkdir(parents=True)
    subprocess.run(["git", "clone", "--local", UPSTREAM, str(ale)], check=True)
    identity = ale_compat.inspect_identity(str(root))
    assert identity["identity_method"] == "Git"
    assert Path(identity["git_root"]).resolve() == ale.resolve()
    assert identity["revision"] == ale_compat.TESTED_ALE_COMMIT


@pytest.mark.parametrize("parent_git", [False, True])
def test_archive_uses_fingerprint_and_never_parent_head(tmp_path, parent_git):
    root, ale = archive_root(tmp_path, parent_git)
    parent_head = git(root, "rev-parse", "HEAD") if parent_git else None
    identity = ale_compat.inspect_identity(str(root))
    assert identity["identity_method"] == "Certified source fingerprint"
    assert identity["revision"] is None
    assert identity["source_fingerprint"] == "MATCH"
    assert identity["supported"]
    if parent_git:
        assert identity["git_metadata"] == "PARENT REPOSITORY DETECTED; NOT VALID ALE IDENTITY"
        assert parent_head not in repr(identity)
    info = discovery.describe_azerothcore_root(str(root))
    assert info["ale_revision"] is None


def test_archive_dry_run_apply_and_patched_identity(tmp_path):
    root, _ = archive_root(tmp_path, True)
    checked = ale_compat.prepare(str(root))
    assert checked.status == "READY_FOR_EXPLICIT_APPLY"
    applied = ale_compat.prepare(str(root), apply=True)
    assert applied.status == "PATCH_APPLIED_REBUILD_REQUIRED"
    identity = ale_compat.inspect_identity(str(root))
    assert identity["snapshot_state"] == "PATCHED"
    assert ale_compat.prepare(str(root)).status == "ALREADY_PRESENT"


def test_modified_archive_fingerprint_is_rejected(tmp_path):
    root, ale = archive_root(tmp_path)
    target = ale / ale_compat.REGISTRATION
    target.write_text(target.read_text(encoding="utf-8") + "\n// modified\n", encoding="utf-8")
    identity = ale_compat.inspect_identity(str(root))
    assert not identity["supported"]
    with pytest.raises(ale_compat.ALECompatError, match="unsupported/unverified"):
        ale_compat.prepare(str(root), apply=True)


def test_parent_head_is_never_used_even_if_it_equals_certified_sha(tmp_path, monkeypatch):
    root, ale = archive_root(tmp_path)
    parent = str(root.resolve())
    calls = []
    def fake_git(_ale_root, *args):
        calls.append(args)
        if args == ("rev-parse", "--show-toplevel"):
            return parent
        if args == ("rev-parse", "HEAD"):
            return ale_compat.TESTED_ALE_COMMIT
        raise AssertionError(args)
    monkeypatch.setattr(ale_compat, "_run_git", fake_git)
    identity = ale_compat.inspect_identity(str(root))
    assert identity["revision"] is None
    assert ("rev-parse", "HEAD") not in calls


def test_python_and_powershell_newcomer_contracts():
    repo = Path(__file__).resolve().parents[2]
    cli = (repo / "installer/cli.py").read_text(encoding="utf-8")
    wrapper = (repo / "installer/bin/echoes.ps1").read_text(encoding="utf-8")
    install = (repo / "INSTALL.md").read_text(encoding="utf-8")
    assert cli.index("sys.version_info < MINIMUM_PYTHON") < cli.index("from core import")
    assert "requires Python 3.7 or newer. Detected:" in cli
    assert "sys.version_info >= (3, 7)" in wrapper
    assert ".\\installer\\bin\\echoes.ps1" in install
    assert "do not double-click" in install

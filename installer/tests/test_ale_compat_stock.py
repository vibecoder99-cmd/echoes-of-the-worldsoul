import os
from pathlib import Path
import subprocess
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core import ale_compat, prereq


UPSTREAM = os.environ.get("ECHOES_STOCK_ALE_CHECKOUT")


def _git(path, *args):
    return subprocess.run(
        ["git", "-C", str(path), *args], check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    ).stdout.strip()


@pytest.fixture
def stock_root(tmp_path):
    if not UPSTREAM:
        pytest.skip("set ECHOES_STOCK_ALE_CHECKOUT to the clean official checkout")
    upstream = Path(UPSTREAM)
    assert _git(upstream, "rev-parse", "HEAD") == ale_compat.TESTED_ALE_COMMIT
    assert not _git(upstream, "status", "--porcelain")
    root = tmp_path / "azerothcore"
    ale = root / "modules" / "mod-ale"
    ale.parent.mkdir(parents=True)
    subprocess.run(["git", "clone", "--local", str(upstream), str(ale)], check=True)
    return root


def test_actual_unpatched_stock_ale_is_identified_truthfully(stock_root):
    result = prereq.check_mod_ale_direct_execute(str(stock_root))
    assert not result.present
    assert "Current stock ALE does not publish this binding" in result.remediation
    checked = ale_compat.prepare(str(stock_root))
    assert checked.status == "READY_FOR_EXPLICIT_APPLY"
    assert not checked.changed
    assert not _git(stock_root / "modules" / "mod-ale", "status", "--porcelain")


def test_actual_stock_ale_patch_requires_consent_and_then_passes(stock_root):
    ale = stock_root / "modules" / "mod-ale"
    checked = ale_compat.prepare(str(stock_root))
    assert checked.status == "READY_FOR_EXPLICIT_APPLY"
    assert not _git(ale, "status", "--porcelain")

    applied = ale_compat.prepare(str(stock_root), apply=True)
    assert applied.status == "PATCH_APPLIED_REBUILD_REQUIRED"
    assert applied.changed and applied.rebuild_required
    assert prereq.check_mod_ale_direct_execute(str(stock_root)).present
    changed = _git(ale, "status", "--short").splitlines()
    assert len(changed) == 2
    assert any("src/LuaEngine/LuaFunctions.cpp" in line for line in changed)
    assert any("src/LuaEngine/methods/GlobalMethods.h" in line for line in changed)


def test_unknown_revision_is_refused_without_changes(stock_root):
    ale = stock_root / "modules" / "mod-ale"
    marker = ale / "unknown-revision-marker.txt"
    marker.write_text("revision drift\n", encoding="utf-8")
    _git(ale, "add", marker.name)
    _git(ale, "-c", "user.name=Echoes Test", "-c", "user.email=test@invalid", "commit", "-m", "test drift")
    before = _git(ale, "status", "--porcelain")
    with pytest.raises(ale_compat.ALECompatError, match="Automatic patching is unavailable"):
        ale_compat.prepare(str(stock_root), apply=True)
    assert _git(ale, "status", "--porcelain") == before
    assert not ale_compat._binding_present(str(ale))


def test_shipped_patch_checksum_matches():
    patch = Path(__file__).resolve().parents[2] / ale_compat.PATCH_RELATIVE_PATH
    ale_compat._verify_patch_artifact(str(patch))


def test_local_changes_to_patch_targets_are_refused(stock_root):
    ale = stock_root / "modules" / "mod-ale"
    target = ale / ale_compat.REGISTRATION
    target.write_text(target.read_text(encoding="utf-8") + "\n// local operator edit\n", encoding="utf-8")
    before = _git(ale, "diff")
    with pytest.raises(ale_compat.ALECompatError, match="already have local changes"):
        ale_compat.prepare(str(stock_root), apply=True)
    assert _git(ale, "diff") == before
    assert not ale_compat._binding_present(str(ale))

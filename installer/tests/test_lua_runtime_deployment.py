import json
import os
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, os.fspath(Path(__file__).resolve().parents[1]))

from core import install, verify


def test_install_excludes_lua_test_directories_and_verify_passes(tmp_path, monkeypatch):
    repo = tmp_path / "source"
    lua_source = repo / "lua_scripts"
    lua_tests = lua_source / "tests"
    lua_tests.mkdir(parents=True)
    (lua_source / "ap_core.lua").write_text("AP = {}\n", encoding="utf-8")
    (lua_source / "ap_runtime.lua").write_text("return true\n", encoding="utf-8")
    (lua_source / "README.md").write_text("developer note\n", encoding="utf-8")
    (lua_tests / "regression.lua").write_text("error('must not deploy')\n", encoding="utf-8")

    stats = repo / "cpp_patch" / "mod-echoes-stats" / "conf"
    stats.mkdir(parents=True)
    (stats / "mod_echoes_stats.conf.dist").write_text(
        "[worldserver]\nEchoesStats.Enable = 0\n", encoding="utf-8"
    )

    ac_root = tmp_path / "azerothcore"
    (ac_root / "modules" / "mod-ale").mkdir(parents=True)
    destination = ac_root / "lua_scripts"
    destination.mkdir()
    (destination / "unrelated_third_party.lua").write_text("return 'mine'\n", encoding="utf-8")

    available = SimpleNamespace(present=True, remediation=None)
    monkeypatch.setattr(install, "_repo_root", lambda: os.fspath(repo))
    monkeypatch.setattr(install.prereq, "check_mod_ale", lambda _root: available)
    monkeypatch.setattr(install.prereq, "check_mod_ale_direct_execute", lambda _root: available)
    monkeypatch.setattr(install.sql_runner, "apply_schema_package", lambda *_args: ["schema.sql"])
    monkeypatch.setattr(install.sql_runner, "apply_world_items", lambda *_args: ["world.sql"])

    opts = install.InstallOptions(
        azerothcore_root=os.fspath(ac_root),
        mysql_args=[],
        characters_database="characters",
        world_database="world",
    )
    manifest = install.install(opts)

    assert lua_tests.is_dir()
    assert not (destination / "tests").exists()
    assert sorted(path.name for path in destination.iterdir()) == [
        "ap_core.lua", "ap_runtime.lua", "unrelated_third_party.lua"
    ]
    assert set(manifest["components"]["core_lua"]["files"]) == {"ap_core.lua", "ap_runtime.lua"}
    assert "tests/regression.lua" not in manifest["components"]["core_lua"]["files"]

    monkeypatch.setattr(verify.prereq, "check_mod_ale", lambda _root: available)
    monkeypatch.setattr(verify.prereq, "check_mod_ale_direct_execute", lambda _root: available)
    checks = verify.verify(os.fspath(ac_root))
    assert checks
    assert all(check.status != verify.FAIL for check in checks)

    stored = json.loads((ac_root / "echoes-install-manifest.json").read_text(encoding="utf-8"))
    assert set(stored["components"]["core_lua"]["files"]) == {"ap_core.lua", "ap_runtime.lua"}

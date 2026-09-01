import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from core import prereq


def _root(registration, implementation):
    root = tempfile.mkdtemp(prefix="echoes-ale-api-")
    engine = os.path.join(root, "modules", "mod-ale", "src", "LuaEngine")
    methods = os.path.join(engine, "methods")
    os.makedirs(methods)
    with open(os.path.join(engine, "LuaFunctions.cpp"), "w") as f:
        f.write(registration)
    with open(os.path.join(methods, "GlobalMethods.h"), "w") as f:
        f.write(implementation)
    return root


def test_direct_execute_supported_source():
    root = _root('"CharDBDirectExecute"', "int CharDBDirectExecute(lua_State* L)")
    assert prereq.check_mod_ale_direct_execute(root).present


def test_old_ale_source_is_rejected():
    root = _root('"CharDBExecute"', "int CharDBExecute(lua_State* L)")
    result = prereq.check_mod_ale_direct_execute(root)
    assert not result.present
    assert "CharDBDirectExecute" in result.remediation


def test_directory_presence_without_inspectable_api_is_rejected():
    root = tempfile.mkdtemp(prefix="echoes-ale-empty-")
    os.makedirs(os.path.join(root, "modules", "mod-ale"))
    result = prereq.check_mod_ale_direct_execute(root)
    assert not result.present
    assert "CharDBDirectExecute" in result.remediation

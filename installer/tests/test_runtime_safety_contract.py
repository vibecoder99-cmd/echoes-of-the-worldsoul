from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def source(name):
    return (ROOT / "lua_scripts" / name).read_text(encoding="utf-8")


def test_startup_self_check_requires_direct_execute():
    text = source("ap_tests.lua")
    assert 'expect("SUPPORTED DATABASE WRITE API: CharDBDirectExecute"' in text
    assert 'AP.Cap.Check("CharDBDirectExecute")' in text
    assert "guarded purchases fail closed" in text


def test_aptest_refuses_non_gm_and_missing_sync_fixture_api():
    text = source("ap_tests.lua")
    run = text[text.index("function AP.RunTests"):text.index("-- ============================================================\n-- CHAT TRIGGER")]
    assert "AP.RT.IsGM(player, 1)" in run
    assert "GM/developer regression harness" in run
    assert 'AP.Cap.Check("CharDBDirectExecute")' in run
    assert "no tests were run" in run


def test_dead_talent_sender_removed():
    assert "SENDER_TALENT_STAT" not in source("ap_ui.lua")


def test_startup_signal_is_factual_ale_lifecycle_event():
    for name in ("ap00_compat.lua", "ap02_runtime_eluna.lua", "ap_core.lua"):
        assert "DMLMode =" not in source(name)
    runtime = source("ap02_runtime_eluna.lua")
    startup = runtime[runtime.index("AP.RT.RegisterStartup"):runtime.index("AP.RT.RegisterItemEvent")]
    assert "eventId = 33" in startup
    assert "eventId = 3\n" not in startup
    assert "eventId = 13\n" not in startup
    assert "if delivered then return end" in startup


def test_startup_consumers_use_lifecycle_api():
    assert "AP.RT.RegisterStartup(function()" in source("ap_core.lua")
    assert "AP.RT.RegisterStartup(function()" in source("ap_tests.lua")

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_fresh_install_documents_ale_before_build():
    install = (ROOT / "INSTALL.md").read_text(encoding="utf-8")
    compat = install.index("ale-compat --azerothcore-root /path/to/your/azerothcore")
    build = install.index("Build/relink worldserver now")
    managed_install = install.index("installer/bin/echoes.sh install")
    assert compat < build < managed_install
    assert "incrementally rebuild/reinstall **worldserver only**" in install


def test_specific_protected_write_error_is_packaged():
    server = (ROOT / "lua_scripts/ap_ui.lua").read_text(encoding="utf-8")
    client = (ROOT / "client_addon/EchoesOfTheWorldsoulBridge/EchoesUI/Screens/ProgressionScreen.lua").read_text(encoding="utf-8")
    for text in (server, client):
        assert "required database-write capability missing" in text
        assert "Essence was not spent" in text


def test_no_unsafe_database_fallback_added():
    db = (ROOT / "lua_scripts/ap04_db.lua").read_text(encoding="utf-8")
    critical = db[db.index("function AP.DB.ExecuteCritical"):db.index("function AP.DB.GetUInt64")]
    assert "pcall(CharDBDirectExecute" in critical
    assert "CharDBExecute(sql)" not in critical
    assert "CharDBQuery" not in critical


def test_release_notes_state_no_schema_or_gameplay_change():
    notes = (ROOT / "ECHOES-2.1.6-RELEASE-NOTES.md").read_text(encoding="utf-8")
    assert "no gameplay, schema, save, client-item-data, or progression changes" in notes

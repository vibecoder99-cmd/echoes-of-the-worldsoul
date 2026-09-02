from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_current_release_versions_are_reconciled():
    assert '## Version: 2.1.4' in (ROOT / 'client_addon/EchoesOfTheWorldsoulBridge/EchoesOfTheWorldsoulBridge.toc').read_text(encoding='utf-8')
    assert 'UI.version = "2.1.4"' in (ROOT / 'client_addon/EchoesOfTheWorldsoulBridge/EchoesUI/Bootstrap.lua').read_text(encoding='utf-8')
    assert 'AP.VERSION = "2.1.4"' in (ROOT / 'lua_scripts/ap_core.lua').read_text(encoding='utf-8')
    commands = (ROOT / 'lua_scripts/ap_commands.lua').read_text(encoding='utf-8')
    assert 'AP.CLIENT_ADDON_VERSION = "2.1.4"' in commands
    assert 'AP.CLIENT_ADDON_VERSION = "1.5.9"' not in commands
    assert 'AP.CLIENT_ADDON_VERSION = "2.0.0-rc1"' not in commands


def test_protocol_version_is_intentionally_unchanged():
    bridge = (ROOT / 'client_addon/EchoesOfTheWorldsoulBridge/EchoesOfTheWorldsoulBridge.lua').read_text(encoding='utf-8')
    protocol = (ROOT / 'lua_scripts/ap_protocol.lua').read_text(encoding='utf-8')
    assert 'local ECHOES_PROTOCOL_VERSION = 1' in bridge
    assert 'AP.PROTOCOL_VERSION = 1' in protocol


def test_chaos_schema_is_fresh_install_upgrade_and_validation_visible():
    base = (ROOT / 'sql/schema/10_base_schema.sql').read_text(encoding='utf-8')
    migration = (ROOT / 'sql/schema/30_versioned_migrations.sql').read_text(encoding='utf-8')
    validation = (ROOT / 'sql/schema/90_validation.sql').read_text(encoding='utf-8')
    seed = (ROOT / 'sql/schema/40_seed_or_defaults.sql').read_text(encoding='utf-8')
    assert '`chaos_enabled` TINYINT(1) NOT NULL DEFAULT 0' in base
    assert "COLUMN_NAME = 'chaos_enabled'" in migration
    assert 'ADD COLUMN `chaos_enabled` TINYINT(1) NOT NULL DEFAULT 0' in migration
    assert "'chaos_enabled'" in validation
    assert "VALUES (1, '2.1.4')" in seed

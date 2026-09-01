from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def test_structured_rack_route_is_currency_specific_and_truthful():
    rack = (ROOT / "lua_scripts/ap_rack.lua").read_text(encoding="utf-8")
    api = (ROOT / "lua_scripts/ap_botapi.lua").read_text(encoding="utf-8")
    protocol = (ROOT / "lua_scripts/ap_protocol.lua").read_text(encoding="utf-8")
    client = (ROOT / "client_addon/EchoesOfTheWorldsoulBridge/EchoesUI/Screens/RackScreen.lua").read_text(encoding="utf-8")
    assert "function AP.Rack.PurchaseEssenceExpand" in rack
    assert "return AP.Rack.PurchaseEssenceExpand(" in api
    assert "return AP.Rack.PurchaseExpand(" in api
    assert "preview.expectedEssence" in protocol
    assert 'fields.status=="SUCCESS" and "Rack state committed."' in client

def test_executecritical_law_is_documented_next_to_critical_write():
    db = (ROOT / "lua_scripts/ap04_db.lua").read_text(encoding="utf-8")
    assert "does not prove that a guarded statement matched or changed a" in db

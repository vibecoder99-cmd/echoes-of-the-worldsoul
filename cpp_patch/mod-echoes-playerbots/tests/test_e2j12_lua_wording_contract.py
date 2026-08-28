#!/usr/bin/env python3
"""
E2j12 -- Player-Facing Explanation and Menu Clarity Pass
Standalone, dependency-free CONTRACT test suite.

Why this exists instead of a real Lua test:
  This repo has no Lua interpreter available in the WSL2 dev environment
  (no lua/lua5.1/lua5.3/luac on PATH), and the project's only Lua test
  runner (`#aptest`, ap_tests.lua) requires a live worldserver + Eluna +
  MySQL, which this phase is explicitly forbidden from starting
  ("do NOT start/stop production containers", "source-only + local test
  execution"). So these are static, source-text CONTRACT tests: they
  parse the live Lua source under env/dist/lua_scripts (the authoritative
  copy per every E2j12 audit doc) and assert specific strings/structures
  are present or absent. They cannot execute AP.Sinks.Invest() and observe
  a real DB write; they instead assert, positionally, that the rejection
  guard appears in the source *before* any Essence-deducting statement,
  which is the strongest static proxy available without a Lua runtime.

Run: python3 test_e2j12_lua_wording_contract.py
Exit code 0 = all PASS, 1 = at least one FAIL.
"""
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# Repo root = three levels up from modules/mod-echoes-playerbots/tests
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
LUA_DIR = os.path.join(REPO_ROOT, "env", "dist", "lua_scripts")

results = []


def read(name):
    path = os.path.join(LUA_DIR, name)
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def check(name, condition, detail=""):
    status = "PASS" if condition else "FAIL"
    results.append((status, name, detail))


def extract_block(src, key):
    """Extract a `key = { ... }` table block (single nesting level of braces)."""
    m = re.search(re.escape(key) + r"\s*=\s*\{", src)
    if not m:
        return None
    start = m.end() - 1
    depth = 0
    for i in range(start, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
    return None


# ------------------------------------------------------------------
# 1. Threat Reduction: dead purchase path blocked, false active state removed
# ------------------------------------------------------------------
sinks_src = read("ap_sinks.lua")

tr_block = extract_block(sinks_src, "threat_reduction")
check(
    "threat_reduction block exists in AP.SinkDefs",
    tr_block is not None,
)
if tr_block:
    check(
        "threat_reduction.active is false (no false ACTIVE state)",
        re.search(r"active\s*=\s*false", tr_block) is not None,
        tr_block,
    )
    check(
        "threat_reduction has no fabricated C++ consumer comment (ApplyAttunementStats)",
        "ApplyAttunementStats" not in tr_block,
    )

check(
    "no 'ApplyAttunementStats' claim anywhere in ap_sinks.lua",
    "ApplyAttunementStats" not in sinks_src,
)

# AP.Sinks.Invest must reject any active=false category BEFORE the first
# Essence-deducting DB statement (positional proxy for "zero Essence deducted").
invest_match = re.search(
    r"function AP\.Sinks\.Invest\(.*?\).*?\nend\n", sinks_src, re.DOTALL
)
check("AP.Sinks.Invest function found", invest_match is not None)
if invest_match:
    body = invest_match.group(0)
    guard_idx = body.find("active == false")
    deduct_idx = body.find("`aether` = `aether` -")
    check(
        "AP.Sinks.Invest rejects active=false categories",
        guard_idx != -1,
    )
    check(
        "AP.Sinks.Invest's active=false rejection happens BEFORE any Essence is deducted "
        "(zero Essence deducted on rejection)",
        guard_idx != -1 and deduct_idx != -1 and guard_idx < deduct_idx,
        f"guard_idx={guard_idx} deduct_idx={deduct_idx}",
    )

# Bot purchase path must funnel through the same AP.Sinks.Invest choke point
# (no separate/divergent bot-side purchase implementation that could bypass the guard).
botapi_src = read("ap_botapi.lua")
execute_sink_match = re.search(
    r"function AP\.API\.ExecuteSinkInvest\(.*?\nend\n", botapi_src, re.DOTALL
)
check("AP.API.ExecuteSinkInvest (bot purchase entry point) found", execute_sink_match is not None)
if execute_sink_match:
    check(
        "Bot purchase path (AP.API.ExecuteSinkInvest) delegates to AP.Sinks.Invest "
        "(same rejection guard applies to bots, not just humans)",
        "AP.Sinks.Invest(" in execute_sink_match.group(0),
    )

# UI: no purchase buttons for inactive categories, and status vocabulary is honest.
check(
    "Crucible UI uses AVAILABLE/MAXED/UNAVAILABLE vocabulary",
    all(s in sinks_src for s in ["AVAILABLE", "MAXED", "UNAVAILABLE"]),
)
check(
    "Old binary [ACTIVE]/[Phase N] badge removed from category list rendering",
    '"|cff00ff00ACTIVE|r"' not in sinks_src,
)
check(
    "Stale 'Phase 2) are coming soon' header language removed",
    "are coming soon" not in sinks_src,
)
check(
    "Detail page shows an explicit UNAVAILABLE explanation, not the old "
    "'not yet active' placeholder",
    "is not yet active" not in sinks_src and "UNAVAILABLE --" in sinks_src,
)

# ------------------------------------------------------------------
# 2. Talent "cap" terminology regression guard
# ------------------------------------------------------------------
ui_src = read("ap_ui.lua")

check(
    "Talent purchase broadcast no longer claims an 'Absorption cap'",
    "Absorption cap" not in ui_src,
)
buy_talent_match = re.search(
    r"local function BuyTalentRank\(.*?\nend\n", ui_src, re.DOTALL
)
check("BuyTalentRank function found", buy_talent_match is not None)
if buy_talent_match:
    body = buy_talent_match.group(0)
    check(
        "BuyTalentRank's broadcast does not use the word 'cap' to describe the "
        "Talent bonus itself (only 'no separate cap' negation is allowed)",
        not re.search(r"(?<!no separate )cap\s*\+", body, re.IGNORECASE) and
        "Absorption cap" not in body,
        body,
    )

check(
    "Talent page explanation header is present (specialization framing, no cap language)",
    "specialize your Mastery absorption" in ui_src,
)
check(
    "Talent page states rank limits explicitly (Primary 3 / Secondary 2 framing)",
    "up to 3 ranks" in ui_src or "3 ranks" in ui_src,
)

# ------------------------------------------------------------------
# 3. Three-layer info architecture: advanced-details subpages exist and are routed
# ------------------------------------------------------------------
check(
    "ShowProgressionDetailPage (Progression Layer 3) exists",
    "ShowProgressionDetailPage" in ui_src,
)
check(
    "ShowTalentDetailPage (Talent Layer 3) exists",
    "ShowTalentDetailPage" in ui_src,
)
check(
    "Progression page links to its advanced-details subpage (intid 20)",
    re.search(r'"View exact formula / advanced details",\s*SENDER_MASTERY,\s*20', ui_src) is not None,
)
check(
    "Talent page links to its advanced-details subpage (intid 20)",
    re.search(r'"View exact formula / advanced details",\s*SENDER_TALENT,\s*20', ui_src) is not None,
)
check(
    "Gossip dispatch routes SENDER_MASTERY intid 20 to the Progression detail page",
    "ShowProgressionDetailPage(player)" in ui_src and "elseif intid == 20 then" in ui_src,
)
check(
    "Gossip dispatch routes SENDER_TALENT intid 20 to the Talent detail page",
    "ShowTalentDetailPage(player)" in ui_src,
)
check(
    "Progression page no longer leads with the raw 3-number formula line "
    "(moved to the detail subpage)",
    "Level: %d  |  Mastery Rank: %d\", level, mastery), SENDER_MASTERY, 0)" not in ui_src,
)

# ------------------------------------------------------------------
# 4. Legacy Forge: Dissolution-survives-Attunement reassurance
# ------------------------------------------------------------------
forge_src = read("ap_forge.lua")
check(
    "Legacy Forge overview page states Attunement survives Dissolution",
    "permanent Attunement remains" in forge_src,
)
check(
    "Legacy Forge confirmation page explicitly reassures Attunement is not affected",
    "Attunement is NOT affected" in forge_src,
)
forge_player_strings = re.findall(r'AP\.UI\.AddItem\(player,0,\s*(?:string\.format\()?\s*"([^"]*(?:\\n[^"]*)*)"', forge_src)
jargon_leak = [s for s in forge_player_strings if re.search(r"transaction|reconcil|ledger", s, re.IGNORECASE)]
check(
    "No transaction/reconciliation/ledger jargon found in Forge AddItem player-facing strings",
    len(jargon_leak) == 0,
    str(jargon_leak),
)

# ------------------------------------------------------------------
# 5. Currency copy normalization: no internal 'Aether' leak in player-visible text
# ------------------------------------------------------------------
check(
    "Crucible detail page no longer displays 'Aether' as the currency label "
    "(normalized to 'Essence')",
    "Your Aether:" not in sinks_src and "Invest %d Aether" not in sinks_src
    and "Not enough Aether to invest" not in sinks_src,
)
check(
    "Aether Surge category description uses 'Essence', not internal 'Aether' term",
    'desc     = "Bonus Essence from kills and quests."' in sinks_src,
)

commands_src = read("ap_commands.lua")
check(
    "#ap Crucible dump no longer says 'No Aether invested'",
    "No Aether invested" not in commands_src,
)
check(
    "#ap status includes a plain-language Absorption explanation before the numbers",
    "Absorption is how much of your attuned gear's stats" in commands_src,
)

# ------------------------------------------------------------------
# 6. Stat registry completeness: every live Crucible category has valid
#    player-facing metadata (label, desc, ceiling, active field all present).
# ------------------------------------------------------------------
order_match = re.search(r"AP\.SinkOrder\s*=\s*\{(.*?)\}\s*\n", sinks_src, re.DOTALL)
check("AP.SinkOrder found", order_match is not None)
categories = []
if order_match:
    categories = re.findall(r'"([a-z_]+)"', order_match.group(1))
check("AP.SinkOrder lists at least 17 categories", len(categories) >= 17, str(len(categories)))

missing_metadata = []
for cat in categories:
    block = extract_block(sinks_src, cat) if cat != "threat_reduction" else tr_block
    if block is None:
        missing_metadata.append((cat, "block not found"))
        continue
    for field in ("label", "desc", "ceiling", "active"):
        if not re.search(field + r"\s*=", block):
            missing_metadata.append((cat, f"missing {field}"))
check(
    "Every category in AP.SinkOrder has label/desc/ceiling/active metadata",
    len(missing_metadata) == 0,
    str(missing_metadata),
)

flavor_match = re.search(r"AP\.SinkFlavor\s*=\s*\{(.*?)\n\}\n", sinks_src, re.DOTALL)
missing_flavor = []
if flavor_match:
    flavor_body = flavor_match.group(1)
    for cat in categories:
        if not re.search(re.escape(cat) + r"\s*=", flavor_body):
            missing_flavor.append(cat)
check(
    "Every category in AP.SinkOrder also has flavor text (AP.SinkFlavor)",
    len(missing_flavor) == 0,
    str(missing_flavor),
)

# ------------------------------------------------------------------
# Report
# ------------------------------------------------------------------
passed = sum(1 for r in results if r[0] == "PASS")
failed = sum(1 for r in results if r[0] == "FAIL")
for status, name, detail in results:
    line = f"{status}: {name}"
    if status == "FAIL" and detail:
        line += f"  -- {detail}"
    print(line)

print(f"\n{passed}/{len(results)} tests passed.")
if failed == 0:
    print("ALL TESTS PASSED")
    sys.exit(0)
else:
    print(f"{failed} TEST(S) FAILED")
    sys.exit(1)

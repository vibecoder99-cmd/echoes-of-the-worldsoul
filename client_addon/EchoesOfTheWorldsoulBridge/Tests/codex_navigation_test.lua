-- Regression test: rapid Codex page navigation (NEXT/PREVIOUS clicked or
-- held faster than the server's codex_page rate window) must coalesce into
-- a single paced request for the latest desired page, never flooding the
-- transport. Behavioral test against the real client bridge file with the
-- mocked WoW host (mock_wow.lua) -- not a Lua-table unit test.

local ADDON_DIR = arg[1]
assert(ADDON_DIR, "usage: lua5.1 codex_navigation_test.lua <addon-dir> <mock-file>")
dofile(arg[2])

local function pass(msg) print("PASS: " .. msg) end
local function fail(msg) print("FAIL: " .. msg); os.exit(1) end

AttunementPlusBridgeDB = { cache = {} }

do
    local chunk, err = loadfile(ADDON_DIR .. "/EchoesOfTheWorldsoulBridge.lua")
    if not chunk then fail("could not load EchoesOfTheWorldsoulBridge.lua: " .. tostring(err)) end
    local ok, runErr = pcall(chunk)
    if not ok then fail("runtime error loading EchoesOfTheWorldsoulBridge.lua: " .. tostring(runErr)) end
    pass("loaded EchoesOfTheWorldsoulBridge.lua")
end

APB.playerName = "TestPlayer"

-- ============================================================
-- First click on a topic sends immediately (instant response is expected).
-- Then four rapid NEXT clicks, faster than the pacing window, must
-- coalesce into a single follow-up request for the LAST desired page.
-- ============================================================
ClearMockChatMessages()
APB:RequestCodexPage(3, 1)
local firstSend = GetMockChatMessages()
if #firstSend ~= 1 or firstSend[1][1] ~= "#ap codex page 3 1" then
    fail("first navigation into a topic did not send immediately")
end

for page = 2, 5 do
    APB:RequestCodexPage(3, page)
end
local sentDuringBurst = GetMockChatMessages()
if #sentDuringBurst ~= 1 then
    fail("rapid follow-up clicks sent immediately instead of coalescing (" .. #sentDuringBurst .. " total sent)")
end

RunAllTimers()
local sentAfterFlush = GetMockChatMessages()
if #sentAfterFlush ~= 2 then
    fail("coalesced burst should add exactly one more request, got " .. #sentAfterFlush .. " total")
end
if sentAfterFlush[2][1] ~= "#ap codex page 3 5" then
    fail("coalesced request did not target the latest desired page: got '" .. tostring(sentAfterFlush[2][1]) .. "'")
end
pass("four rapid NEXT clicks after the first coalesce into one request for the final desired page")

-- ============================================================
-- sentTopic/sentPage record what was actually sent, for staleness checks
-- ============================================================
local state = APB.echoes.codexPage
if state.sentTopic ~= 3 or state.sentPage ~= 5 then
    fail("codexPage state did not record the actually-sent topic/page")
end
pass("codexPage bridge state records the authoritative outstanding request")

-- ============================================================
-- After the pending request settles, a fresh call sends immediately if
-- enough time has passed (paced, not blocked forever)
-- ============================================================
ClearMockChatMessages()
AdvanceClock(2)
APB:RequestCodexPage(3, 6)
local immediate = GetMockChatMessages()
if #immediate ~= 1 or immediate[1][1] ~= "#ap codex page 3 6" then
    fail("a request issued well after the pacing window did not send immediately")
end
pass("navigation resumes sending immediately once the pacing window has passed")

print("ALL CODEX NAVIGATION TESTS PASSED")

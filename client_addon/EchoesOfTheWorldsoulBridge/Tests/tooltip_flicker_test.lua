-- Regression test: ineligible-item tooltip hover must never show any Echoes
-- UI, not even a transient "fetching..." placeholder. Behavioral test against
-- the real client bridge file with the mocked WoW host (mock_wow.lua) -- not
-- a Lua-table unit test.

local ADDON_DIR = arg[1]
assert(ADDON_DIR, "usage: lua5.1 tooltip_flicker_test.lua <addon-dir> <mock-file>")
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

local chaosEnabled = true
APB:RegisterItemTooltipAugmenter(function(tooltip)
    if chaosEnabled then
        tooltip:AddLine("Chaos Weapon Reference")
        tooltip:AddLine("12.0M - 18.0M effective base damage")
    end
end)

local function HasEchoesLine(tooltip)
    for _, line in ipairs(tooltip._lines or {}) do
        if type(line) == "string" and line:find("EotW", 1, true) then return true end
    end
    return false
end

local function Hover(entry)
    -- A real hover on a new item starts from a fresh Blizzard tooltip;
    -- clear any lines left over from a previous mock hover before firing
    -- OnTooltipSetItem, so the mock matches that real-world reset.
    GameTooltip._lines = { "Mock Item", "12 - 18 Damage" }
    GameTooltip._shown = true
    GameTooltip:SetHyperlink("item:" .. entry .. ":0:0:0:0:0:0:0")
end

local function CountLine(needle)
    local count = 0
    for _, line in ipairs(GameTooltip._lines or {}) do
        if type(line) == "string" and line:find(needle, 1, true) then count = count + 1 end
    end
    return count
end

local function FindLine(needle)
    for index, line in ipairs(GameTooltip._lines or {}) do
        if type(line) == "string" and line:find(needle, 1, true) then return index end
    end
end

local function Unhover()
    local fn = GameTooltip._scripts.OnTooltipCleared
    if fn then fn(GameTooltip) end
    GameTooltip._shown = false
end

local function DeliverAPTIP(payload)
    SimulateChatMessageEvent("CHAT_MSG_SYSTEM", payload)
    RunAllTimers()
end

-- ============================================================
-- First hover, uncached ineligible (e.g. Shiny Red Apple)
-- ============================================================
ClearMockChatMessages()
Hover(9001)
if HasEchoesLine(GameTooltip) then
    fail("ineligible item showed an Echoes line (placeholder or otherwise) before any server response")
end
local sent = GetMockChatMessages()
if #sent == 0 or sent[#sent][1] ~= "#ap tip 9001" then
    fail("uncached hover did not request server eligibility")
end
DeliverAPTIP("[APTIP] id=9001|ineligible=1")
if HasEchoesLine(GameTooltip) then
    fail("ineligible response injected an Echoes line into the tooltip")
end
if not AttunementPlusBridgeDB.cache[9001] or not AttunementPlusBridgeDB.cache[9001].ineligible then
    fail("ineligible response was not cached")
end
Unhover()
pass("first hover of an uncached ineligible item never shows Echoes UI, not even transiently")

-- ============================================================
-- Second hover, cached ineligible (within cache freshness window)
-- ============================================================
ClearMockChatMessages()
Hover(9001)
if HasEchoesLine(GameTooltip) then
    fail("re-hover of a cached-ineligible item showed an Echoes line")
end
if #GetMockChatMessages() ~= 0 then
    fail("re-hover of a cached-ineligible item re-requested the server unnecessarily")
end
Unhover()
pass("second hover of a cached-ineligible item re-flashes nothing and does not re-request")

-- ============================================================
-- First hover, eligible zero-progress equipment
-- ============================================================
ClearMockChatMessages()
Hover(9002)
if HasEchoesLine(GameTooltip) then
    fail("eligible item showed an Echoes line before the server responded")
end
DeliverAPTIP("[APTIP] id=9002|prog=0|cap=10000|snap=0/0/0/0/0|absorb=0/0/0/0/0")
local found0 = false
for _, line in ipairs(GameTooltip._lines or {}) do
    if type(line) == "string" and line:find("0%%", 1, false) then found0 = true end
end
if not found0 then fail("eligible zero-progress equipment did not show 0% after the response") end
local eotwIndex, chaosIndex = FindLine("[EotW]"), FindLine("Chaos Weapon Reference")
if not eotwIndex or not chaosIndex or eotwIndex >= chaosIndex then
    fail("ordered seam did not keep Attunement above the Chaos block")
end
if CountLine("[EotW]") ~= 1 or CountLine("Chaos Weapon Reference") ~= 1 then
    fail("first finalized tooltip did not contain exactly one block from each augmenter")
end
local beforeRepeat = #GameTooltip._lines
GameTooltip:SetHyperlink("item:9002:0:0:0:0:0:0:0")
if #GameTooltip._lines ~= beforeRepeat or CountLine("[EotW]") ~= 1 or CountLine("Chaos Weapon Reference") ~= 1 then
    fail("repeated OnTooltipSetItem duplicated or reordered augmentation lines")
end
Unhover()
pass("eligible tooltip finalizes once in native -> Attunement -> Chaos order")

-- ============================================================
-- Chaos OFF / ON lifecycle and different-item reset
-- ============================================================
chaosEnabled = false
Hover(9010)
DeliverAPTIP("[APTIP] id=9010|prog=10000|cap=10000|snap=0/0/0/0/0|absorb=0/0/0/0/0")
if CountLine("Chaos Weapon Reference") ~= 0 or CountLine("[EotW] Attuned") ~= 1 then
    fail("Chaos OFF changed Attunement or left a Chaos tooltip block")
end
Unhover()
chaosEnabled = true
Hover(9010)
if CountLine("[EotW] Attuned") ~= 1 or CountLine("Chaos Weapon Reference") ~= 1 then
    fail("Chaos ON re-hover did not restore exactly one ordered Chaos block")
end
if FindLine("[EotW] Attuned") >= FindLine("Chaos Weapon Reference") then
    fail("Chaos ON re-hover changed canonical block order")
end
Unhover()
pass("Chaos OFF/ON and different tooltip lifecycles reset cleanly")

-- ============================================================
-- Eligible progressed equipment
-- ============================================================
ClearMockChatMessages()
Hover(9003)
DeliverAPTIP("[APTIP] id=9003|prog=2500|cap=10000|snap=0/0/0/0/0|absorb=0/0/0/0/0")
local found25 = false
for _, line in ipairs(GameTooltip._lines or {}) do
    if type(line) == "string" and line:find("25%%", 1, false) then found25 = true end
end
if not found25 then fail("eligible progressed equipment did not show the correct percentage") end
Unhover()
pass("eligible progressed equipment shows the correct percentage")

-- ============================================================
-- Server timeout: no response ever arrives
-- ============================================================
ClearMockChatMessages()
Hover(9004)
if HasEchoesLine(GameTooltip) then
    fail("hover before any response showed an Echoes line")
end
if not GameTooltip:IsVisible() then
    fail("tooltip was hidden while a request was pending -- Blizzard tooltip must remain usable")
end
-- No DeliverAPTIP call: simulate the response never arriving.
if HasEchoesLine(GameTooltip) then
    fail("a never-answered request left a stuck Echoes line on the tooltip")
end
Unhover()
pass("a request that never resolves leaves the Blizzard tooltip usable with no stuck placeholder")

print("ALL TOOLTIP FLICKER TESTS PASSED")

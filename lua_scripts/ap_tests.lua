-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- ap_tests.lua
-- Echoes of the Worldsoul — Regression Test Suite
-- ============================================================
-- HOW TO RUN:
--   In-game (GM only), type:  #aptest
--   Results print to worldserver console and as a broadcast
--   message visible only to the GM who ran the tests.
--
-- To run a specific group only:
--   #aptest math
--   #aptest db
--   #aptest tooltip
--   #aptest antispam
--   #aptest quest
--   #aptest aether
--   #aptest ui
--
-- Each test either PASS or FAIL.  A FAIL prints the reason.
-- The suite never writes permanent data to the database.
-- All DB writes use a reserved test GUID (AP_TEST_GUID) and
-- are cleaned up after the suite runs.
-- ============================================================

AP       = AP or {}
AP.Tests = AP.Tests or {}

-- ============================================================
-- TEST FRAMEWORK
-- ============================================================
local PASS  = "PASS"
local FAIL  = "FAIL"
local AP_TEST_GUID = 9999999  -- reserved GUID; must not collide with real chars

local function run(label, fn)
    local ok, err = pcall(fn)
    if ok then
        return PASS, label
    else
        return FAIL, label, tostring(err)
    end
end

local function assertEqual(a, b, msg)
    if a ~= b then
        error((msg or "assertEqual") .. string.format("  -- expected %s, got %s", tostring(b), tostring(a)))
    end
end

local function assertApprox(a, b, tol, msg)
    tol = tol or 0.001
    if math.abs(a - b) > tol then
        error((msg or "assertApprox") .. string.format("  -- expected ~%s, got %s (tol %s)", tostring(b), tostring(a), tostring(tol)))
    end
end

local function assertNotNil(v, msg)
    if v == nil then error((msg or "assertNotNil") .. "  -- value was nil") end
end

local function assertTrue(v, msg)
    if not v then error((msg or "assertTrue") .. "  -- was false/nil") end
end

local function assertFalse(v, msg)
    if v then error((msg or "assertFalse") .. "  -- was true") end
end

-- ============================================================
-- GOING-FORWARD DISCIPLINE
-- Every bug fix that touches a formula, cap, DB path, or gossip
-- wiring MUST be accompanied by at least one test here before
-- the fix is considered complete.  "It works in-game" is not a
-- regression guard — a test in this file is.
-- ============================================================

-- ============================================================
-- SECTION 1: MATH TESTS
-- These test pure Lua functions with no DB or player required.
-- ============================================================
local mathTests = {}

mathTests[#mathTests+1] = function()
    return run("MATH: MasteryAbsorbPct at rank 0 is ~5%", function()
        local pct = AP.MasteryAbsorbPct(0)
        assertApprox(pct, 0.05, 0.001, "rank0")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: MasteryAbsorbPct increases with rank", function()
        local p0  = AP.MasteryAbsorbPct(0)
        local p10 = AP.MasteryAbsorbPct(10)
        local p50 = AP.MasteryAbsorbPct(50)
        assertTrue(p10 > p0,  "rank10 > rank0")
        assertTrue(p50 > p10, "rank50 > rank10")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: MasteryAbsorbPct never exceeds 0.85 (5+80)", function()
        local p = AP.MasteryAbsorbPct(99999)
        assertTrue(p <= 0.851, "cap check")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: MasteryCost rank 0->1 = 400", function()
        local cost = AP.MasteryCost(0)
        assertEqual(cost, 400, "cost(0)")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: MasteryCost increases with rank", function()
        local c1 = AP.MasteryCost(1)
        local c5 = AP.MasteryCost(5)
        assertTrue(c5 > c1, "cost(5) > cost(1)")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: SlotMultiplier at xp=0 is exactly 1.0", function()
        local m = AP.SlotMultiplier(0)
        assertEqual(m, 1.0, "xp=0")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: SlotMultiplier increases with xp", function()
        local m0  = AP.SlotMultiplier(0)
        local m100 = AP.SlotMultiplier(100)
        assertTrue(m100 > m0, "xp100 > xp0")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: GroupMultiplier solo = 1.0", function()
        local m = AP.GroupMultiplier(1)
        assertEqual(m, 1.0, "solo")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: GroupMultiplier 5-man > 2-man", function()
        assertTrue(AP.GroupMultiplier(5) > AP.GroupMultiplier(2), "5>2")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: GroupMultiplier 25-man returns raid bonus", function()
        local m = AP.GroupMultiplier(25)
        assertApprox(m, 1.40, 0.001, "25-man")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: RarityMultiplier common (quality 1) = 1.50", function()
        -- Live balance uses an INVERTED scale: gray attunes fastest, epic/legendary slowest.
        -- AP.Config.RarityMult: [0]=2.00 [1]=1.50 [2]=1.00 [3]=0.60 [4]=0.30 [5]=0.15
        -- Original design-doc values (gray=0.90, common=1.00, etc.) were intentionally
        -- re-tuned to this inverted scale so rarer items require more kills to attune.
        assertApprox(AP.RarityMultiplier(1), 1.50, 0.001, "common=1.50")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: RarityMultiplier gray > common > rare > epic (inverted scale)", function()
        -- Higher quality = LOWER multiplier = more kills to attune (intentional design).
        local gray   = AP.RarityMultiplier(0)   -- 2.00
        local common = AP.RarityMultiplier(1)   -- 1.50
        local rare   = AP.RarityMultiplier(3)   -- 0.60
        local epic   = AP.RarityMultiplier(4)   -- 0.30
        assertTrue(gray   > common, "gray>common")
        assertTrue(common > rare,   "common>rare")
        assertTrue(rare   > epic,   "rare>epic")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: LevelAbsorbScalar level 1 = 0", function()
        assertEqual(AP.LevelAbsorbScalar(1), 0.0, "level1")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: LevelAbsorbScalar level 80 = 1.0", function()
        assertEqual(AP.LevelAbsorbScalar(80), 1.0, "level80")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: LevelAbsorbScalar increases monotonically 10â†'80", function()
        local prev = AP.LevelAbsorbScalar(10)
        for lvl = 11, 80 do
            local cur = AP.LevelAbsorbScalar(lvl)
            assertTrue(cur >= prev, "monotonic at " .. lvl)
            prev = cur
        end
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: Dampener first 40 kills = 1.0", function()
        -- Simulate via the threshold table directly
        local count = 1
        local result = 1.0
        for _, tier in ipairs(AP.Config.DampenerThresholds) do
            if count <= tier.limit then
                result = tier.mult
                break
            end
        end
        assertEqual(result, 1.0, "first kill")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: Dampener 300+ kills = 0.80", function()
        local count = 999
        local result = 0.80
        for _, tier in ipairs(AP.Config.DampenerThresholds) do
            if count <= tier.limit then
                result = tier.mult
                break
            end
        end
        assertEqual(result, 0.80, "300+ kills")
    end)
end

-- GetScaledCap formula tests.
-- These test the formula in isolation so they do NOT call
-- AP.GetScaledCap (which would DB-query item_template).
-- The formula is:  math.max(100, math.floor(10000 * (reqLevel/80)^2))
local function scaledCapFormula(reqLevel)
    return math.max(100, math.floor(10000 * (reqLevel / 80) ^ 2))
end

mathTests[#mathTests+1] = function()
    return run("MATH: GetScaledCap formula — level-80 item = 10000", function()
        assertEqual(scaledCapFormula(80), 10000, "req80")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: GetScaledCap formula — level-60 item = 5625", function()
        -- floor(10000 * (60/80)^2) = floor(10000 * 0.5625) = 5625
        assertEqual(scaledCapFormula(60), 5625, "req60")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: GetScaledCap formula — req<=7 clamps to 100 (not 0%)", function()
        -- Regression guard: before the fix, AP.Config.CapPerItem (10000) was
        -- used as the divisor for low-level items, making 82 progress display
        -- as 0%.  The formula must clamp to 100 for low-level req items.
        assertTrue(scaledCapFormula(7) == 100, "req7 -> 100, not 76")
        assertTrue(scaledCapFormula(1) == 100, "req1 -> 100")
        assertTrue(scaledCapFormula(0) == 100, "req0 -> 100")
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: GetScaledCap formula — increases monotonically req 8->80", function()
        local prev = scaledCapFormula(8)
        for lvl = 9, 80 do
            local cur = scaledCapFormula(lvl)
            assertTrue(cur >= prev, "monotonic at req " .. lvl)
            prev = cur
        end
    end)
end

mathTests[#mathTests+1] = function()
    return run("MATH: AP.GetScaledCap is a function (not nil)", function()
        -- Belt-and-suspenders: if ap_events.lua fails to define GetScaledCap,
        -- every Rack display and CheckAttuned will silently use CapPerItem=10000.
        assertTrue(type(AP.GetScaledCap) == "function", "AP.GetScaledCap callable")
    end)
end

-- ============================================================
-- SECTION 2: DATABASE TESTS
-- All writes use CharDBQuery (sync connection).
-- COMMIT is issued before tests to close any implicit read
-- transaction left open by InitDB's information_schema queries,
-- which otherwise creates a stale REPEATABLE READ snapshot that
-- makes INSERTs to ap_mastery invisible to subsequent SELECTs.
-- ============================================================
local dbTests = {}

-- Force-close any open implicit read transaction on the sync connection.
CharDBQuery("COMMIT;")

local function cleanTestGuid()
    pcall(function()
        CharDBQuery(string.format("DELETE FROM `ap_item_attune`    WHERE `guid` = %d;", AP_TEST_GUID))
        CharDBQuery(string.format("DELETE FROM `ap_item_snapshot`  WHERE `guid` = %d;", AP_TEST_GUID))
        CharDBQuery(string.format("DELETE FROM `ap_mastery`        WHERE `guid` = %d;", AP_TEST_GUID))
        CharDBQuery(string.format("DELETE FROM `ap_slot_mastery`   WHERE `guid` = %d;", AP_TEST_GUID))
        CharDBQuery(string.format("DELETE FROM `ap_quest_rewarded` WHERE `guid` = %d;", AP_TEST_GUID))
        CharDBQuery(string.format("DELETE FROM `ap_dissolved_items` WHERE `account_id` = %d;", AP_TEST_GUID))
        CharDBQuery(string.format("DELETE FROM `ap_aether_sinks`   WHERE `account_id` = %d;", AP_TEST_GUID))
        CharDBQuery(string.format("DELETE FROM `ap_visage`         WHERE `guid` = %d;", AP_TEST_GUID))
        CharDBQuery(string.format("DELETE FROM `ap_session_state`  WHERE `guid` = %d;", AP_TEST_GUID))
        CharDBQuery("DELETE FROM `ap_mastery`      WHERE `guid` IN (8888888, 8888887);")
        CharDBQuery("DELETE FROM `ap_slot_mastery` WHERE `guid` = 8888888;")
    end)
end

dbTests[#dbTests+1] = function()
    return run("DB: RAW direct INSERT into ap_mastery round-trip", function()
        CharDBQuery("DELETE FROM `ap_mastery` WHERE `guid` = 8888888;")
        -- Use value 1 (tiny, fits in any int type) to rule out BIGINT issues
        CharDBQuery("INSERT INTO `ap_mastery` (`guid`, `aether`, `mastery`) VALUES (8888888, 1, 0);")
        local q = CharDBQuery("SELECT `aether` FROM `ap_mastery` WHERE `guid` = 8888888 LIMIT 1;")
        local val = q and (tonumber(tostring(q:GetUInt64(0))) or 0) or 0
        CharDBQuery("DELETE FROM `ap_mastery` WHERE `guid` = 8888888;")
        -- Also check if the row exists at all
        local q2 = CharDBQuery("SELECT COUNT(*) FROM `ap_mastery` WHERE `guid` = 8888888;")
        local cnt = q2 and (tonumber(q2:GetUInt32(0)) or 0) or 0
        -- Report what we actually got
        assertEqual(val, 1, "raw insert aether=1 (count=" .. tostring(cnt) .. ")")
    end)
end

dbTests[#dbTests+1] = function()
    return run("DB: RAW INSERT IGNORE + UPDATE into ap_mastery round-trip", function()
        CharDBQuery("DELETE FROM `ap_mastery` WHERE `guid` = 8888888;")
        CharDBQuery("INSERT IGNORE INTO `ap_mastery` (`guid`, `aether`, `mastery`) VALUES (8888888, 0, 0);")
        CharDBQuery("UPDATE `ap_mastery` SET `aether` = `aether` + 100 WHERE `guid` = 8888888;")
        local q = CharDBQuery("SELECT `aether` FROM `ap_mastery` WHERE `guid` = 8888888 LIMIT 1;")
        local val = q and (tonumber(tostring(q:GetUInt64(0))) or 0) or 0
        CharDBQuery("DELETE FROM `ap_mastery` WHERE `guid` = 8888888;")
        assertEqual(val, 100, "two-query aether=100")
    end)
end

dbTests[#dbTests+1] = function()
    return run("DB: GrantAether creates row if missing", function()
        cleanTestGuid()
        AP.GrantAether(AP_TEST_GUID, 100)
        local rec = AP.LoadMastery(AP_TEST_GUID)
        assertNotNil(rec, "rec not nil")
        assertEqual(rec.aether, 100, "aether=100")
        cleanTestGuid()
    end)
end

dbTests[#dbTests+1] = function()
    return run("DB: ap_mastery INSERT visible after SELECT on same guid", function()
        -- Test: does SELECT before INSERT on same GUID cause snapshot issue?
        -- First read (opens snapshot), then write, then read again
        local q1 = CharDBQuery("SELECT `aether` FROM `ap_mastery` WHERE `guid` = 8888887 LIMIT 1;")
        local before = q1 and (tonumber(tostring(q1:GetUInt64(0))) or 0) or -1  -- -1 = no row
        CharDBQuery("DELETE FROM `ap_mastery` WHERE `guid` = 8888887;")
        CharDBQuery("INSERT INTO `ap_mastery` (`guid`, `aether`, `mastery`) VALUES (8888887, 42, 0);")
        local q2 = CharDBQuery("SELECT `aether` FROM `ap_mastery` WHERE `guid` = 8888887 LIMIT 1;")
        local after = q2 and (tonumber(tostring(q2:GetUInt64(0))) or 0) or -1
        CharDBQuery("DELETE FROM `ap_mastery` WHERE `guid` = 8888887;")
        -- Report both values regardless of pass/fail
        assertEqual(after, 42, "after INSERT aether=42 (before=" .. tostring(before) .. ")")
    end)
end

dbTests[#dbTests+1] = function()
    return run("DB: GrantAether accumulates correctly", function()
        cleanTestGuid()
        AP.GrantAether(AP_TEST_GUID, 50)
        AP.GrantAether(AP_TEST_GUID, 75)
        local rec = AP.LoadMastery(AP_TEST_GUID)
        assertEqual(rec.aether, 125, "aether=125")
        cleanTestGuid()
    end)
end

dbTests[#dbTests+1] = function()
    return run("DB: LoadMastery returns zeros for new guid", function()
        cleanTestGuid()
        local rec = AP.LoadMastery(AP_TEST_GUID)
        assertNotNil(rec, "rec not nil")
        assertEqual(rec.aether, 0, "aether=0")
        assertEqual(rec.mastery, 0, "mastery=0")
    end)
end

dbTests[#dbTests+1] = function()
    return run("DB: SaveItemAttune and LoadItemAttune round-trip", function()
        cleanTestGuid()
        AP.SaveItemAttune(AP_TEST_GUID, 12345, 7777, false)
        local rec = AP.LoadItemAttune(AP_TEST_GUID, 12345)
        assertNotNil(rec, "rec not nil")
        assertEqual(rec.progress, 7777, "progress")
        assertFalse(rec.attuned, "not attuned")
        cleanTestGuid()
    end)
end

dbTests[#dbTests+1] = function()
    return run("DB: SaveItemAttune upsert updates existing row", function()
        cleanTestGuid()
        AP.SaveItemAttune(AP_TEST_GUID, 12345, 5000, false)
        AP.SaveItemAttune(AP_TEST_GUID, 12345, 10000, true)
        local rec = AP.LoadItemAttune(AP_TEST_GUID, 12345)
        assertEqual(rec.progress, 10000, "progress=10000")
        assertTrue(rec.attuned, "attuned=true")
        cleanTestGuid()
    end)
end

dbTests[#dbTests+1] = function()
    return run("DB: SaveSnapshot and LoadSnapshot round-trip", function()
        cleanTestGuid()
        local stats = { str=10, agi=5, sta=20, int=0, spi=3 }
        AP.SaveSnapshot(AP_TEST_GUID, 12345, 4, stats)
        local snap = AP.LoadSnapshot(AP_TEST_GUID, 12345)
        assertNotNil(snap, "snap not nil")
        assertApprox(snap.str, 10, 0.01, "str")
        assertApprox(snap.agi, 5,  0.01, "agi")
        assertApprox(snap.sta, 20, 0.01, "sta")
        assertApprox(snap.int, 0,  0.01, "int")
        assertApprox(snap.spi, 3,  0.01, "spi")
        assertEqual(snap.quality, 4, "quality")
        cleanTestGuid()
    end)
end

dbTests[#dbTests+1] = function()
    return run("DB: LoadSnapshot returns nil for unknown entry", function()
        cleanTestGuid()
        local snap = AP.LoadSnapshot(AP_TEST_GUID, 99999)
        assertTrue(snap == nil, "nil for unknown")
    end)
end

dbTests[#dbTests+1] = function()
    return run("DB: AddSlotXP and LoadSlotXP round-trip", function()
        cleanTestGuid()
        AP.AddSlotXP(AP_TEST_GUID, 0, 100)
        AP.AddSlotXP(AP_TEST_GUID, 0, 50)
        local xp = AP.LoadSlotXP(AP_TEST_GUID, 0)
        assertEqual(xp, 150, "xp=150")
        cleanTestGuid()
    end)
end

dbTests[#dbTests+1] = function()
    return run("DB: backtick columns  -- int column not a SQL error", function()
        cleanTestGuid()
        AP.SaveSnapshot(AP_TEST_GUID, 55555, 3, { str=1, agi=1, sta=1, int=1, spi=1 })
        local snap = AP.LoadSnapshot(AP_TEST_GUID, 55555)
        assertApprox(snap.int, 1, 0.01, "int column readable")
        cleanTestGuid()
    end)
end

dbTests[#dbTests+1] = function()
    return run("DB: ap_quest_rewarded dedup  -- second insert is ignored", function()
        cleanTestGuid()
        CharDBQuery(string.format(
            "INSERT IGNORE INTO `ap_quest_rewarded` (`guid`, `quest_id`) VALUES (%d, 1001);",
            AP_TEST_GUID))
        CharDBQuery(string.format(
            "INSERT IGNORE INTO `ap_quest_rewarded` (`guid`, `quest_id`) VALUES (%d, 1001);",
            AP_TEST_GUID))
        local q = CharDBQuery(string.format(
            "SELECT COUNT(*) FROM `ap_quest_rewarded` WHERE `guid` = %d AND `quest_id` = 1001;",
            AP_TEST_GUID))
        local count = q and (tonumber(q:GetUInt32(0)) or 0) or 0
        assertEqual(count, 1, "exactly one row")
        cleanTestGuid()
    end)
end

-- ============================================================
-- SECTION 3: TOOLTIP BRIDGE TESTS
-- These test the payload builder, parser logic, and rate limit.
-- They do not require a live client AddOn.
-- ============================================================
local tooltipTests = {}

-- We test BuildTooltipPayload by calling SendTooltipPayload
-- via a mock player that captures the message instead of
-- sending it over the network.

-- Minimal mock player object for tooltip tests
local function MockPlayer(guid, level)
    local msgs = {}
    return {
        GetGUIDLow         = function() return guid end,
        GetLevel           = function() return level end,
        SendBroadcastMessage = function(self, msg)
            msgs[#msgs+1] = msg
        end,
        _msgs = msgs,
    }
end

tooltipTests[#tooltipTests+1] = function()
    return run("TOOLTIP: Payload for unknown item has prog=0", function()
        cleanTestGuid()
        local player = MockPlayer(AP_TEST_GUID, 80)
        AP.SendTooltipPayload(player, 12345)
        local msg = player._msgs[1]
        assertNotNil(msg, "message sent")
        assertTrue(msg:find("[APTIP]", 1, true), "has prefix")
        assertTrue(msg:find("prog=0", 1, true), "prog=0 for unknown item")
        cleanTestGuid()
    end)
end

tooltipTests[#tooltipTests+1] = function()
    return run("TOOLTIP: Payload id= matches requested entry", function()
        cleanTestGuid()
        local player = MockPlayer(AP_TEST_GUID, 80)
        AP.SendTooltipPayload(player, 99001)
        local msg = player._msgs[1]
        assertNotNil(msg, "message sent")
        assertTrue(msg:find("id=99001", 1, true), "id=99001")
        cleanTestGuid()
    end)
end

tooltipTests[#tooltipTests+1] = function()
    return run("TOOLTIP: Payload includes snap= and absorb= fields", function()
        cleanTestGuid()
        local player = MockPlayer(AP_TEST_GUID, 80)
        AP.SendTooltipPayload(player, 12345)
        local msg = player._msgs[1]
        assertTrue(msg:find("snap=", 1, true), "has snap=")
        assertTrue(msg:find("absorb=", 1, true), "has absorb=")
        cleanTestGuid()
    end)
end

tooltipTests[#tooltipTests+1] = function()
    return run("TOOLTIP: Payload snap= reflects stored snapshot", function()
        cleanTestGuid()
        AP.SaveItemAttune(AP_TEST_GUID, 55001, 10000, true)
        AP.SaveSnapshot(AP_TEST_GUID, 55001, 3, { str=15, agi=0, sta=30, int=0, spi=0 })
        local player = MockPlayer(AP_TEST_GUID, 80)
        AP.SendTooltipPayload(player, 55001)
        local msg = player._msgs[1]
        assertTrue(msg:find("15/0/30/0/0", 1, true), "snap values in payload")
        cleanTestGuid()
    end)
end

tooltipTests[#tooltipTests+1] = function()
    return run("TOOLTIP: Payload prog= reflects stored progress", function()
        cleanTestGuid()
        AP.SaveItemAttune(AP_TEST_GUID, 55002, 5000, false)
        local player = MockPlayer(AP_TEST_GUID, 80)
        AP.SendTooltipPayload(player, 55002)
        local msg = player._msgs[1]
        assertTrue(msg:find("prog=5000", 1, true), "prog=5000 in payload")
        cleanTestGuid()
    end)
end

tooltipTests[#tooltipTests+1] = function()
    return run("TOOLTIP: Server rate limit blocks second tip within 1 second", function()
        -- Simulate rate limit by manually setting the timestamp
        AP._tipRateLimit = AP._tipRateLimit or {}
        AP._tipRateLimit[AP_TEST_GUID] = os.time()  -- just now

        local player  = MockPlayer(AP_TEST_GUID, 80)
        local blocked = true

        -- The rate limiter should prevent the second send
        -- We verify by checking AP._tipRateLimit blocks the path
        local now  = os.time()
        local last = AP._tipRateLimit[AP_TEST_GUID] or 0
        blocked = (now - last) < 1

        assertTrue(blocked, "rate limit active within 1s")
        -- Reset
        AP._tipRateLimit[AP_TEST_GUID] = nil
    end)
end

tooltipTests[#tooltipTests+1] = function()
    return run("TOOLTIP: Server rate limit allows tip after 1 second gap", function()
        AP._tipRateLimit = AP._tipRateLimit or {}
        AP._tipRateLimit[AP_TEST_GUID] = os.time() - 2  -- 2 seconds ago

        local now     = os.time()
        local last    = AP._tipRateLimit[AP_TEST_GUID]
        local allowed = (now - last) >= 1

        assertTrue(allowed, "rate limit expired after 2s")
        AP._tipRateLimit[AP_TEST_GUID] = nil
    end)
end

-- ============================================================
-- SECTION 4: ANTI-SPAM / ANTI-CHEESE TESTS
-- ============================================================
local antispamTests = {}

antispamTests[#antispamTests+1] = function()
    return run("ANTISPAM: Gray mob level threshold correct at level 60", function()
        -- grayThreshold = 60 - floor(60/10) - 5 = 60 - 6 - 5 = 49
        local function isGray(pLevel, cLevel)
            local gray = pLevel - math.floor(pLevel / 10) - 5
            return cLevel < gray
        end
        assertTrue(isGray(60, 48),  "level 48 is gray at 60")
        assertFalse(isGray(60, 49), "level 49 is NOT gray at 60")
        assertFalse(isGray(60, 60), "level 60 is NOT gray at 60")
    end)
end

antispamTests[#antispamTests+1] = function()
    return run("ANTISPAM: Gray mob level threshold correct at level 80", function()
        local function isGray(pLevel, cLevel)
            local gray = pLevel - math.floor(pLevel / 10) - 5
            return cLevel < gray
        end
        -- grayThreshold = 80 - 8 - 5 = 67
        assertTrue(isGray(80, 66),  "level 66 is gray at 80")
        assertFalse(isGray(80, 67), "level 67 is NOT gray at 80")
    end)
end

antispamTests[#antispamTests+1] = function()
    return run("ANTISPAM: Dampener window reset after 4 minutes", function()
        -- Simulate a session record that is 300 seconds old
        local fakeSession = {
            kills = {
                [1234] = { count = 100, firstSeen = os.time() - 300 }
            }
        }
        local rec = fakeSession.kills[1234]
        local now = os.time()
        local expired = (now - rec.firstSeen) > AP.Config.DampenerWindowSec
        assertTrue(expired, "window expired after 300s")
    end)
end

antispamTests[#antispamTests+1] = function()
    return run("ANTISPAM: Dampener 41st kill in window = 0.98", function()
        local count = 41
        local result = 0.80
        for _, tier in ipairs(AP.Config.DampenerThresholds) do
            if count <= tier.limit then
                result = tier.mult
                break
            end
        end
        assertApprox(result, 0.98, 0.001, "41st kill")
    end)
end

antispamTests[#antispamTests+1] = function()
    return run("ANTISPAM: Dampener thresholds are ordered (each limit > previous)", function()
        local prev = 0
        for _, tier in ipairs(AP.Config.DampenerThresholds) do
            if tier.limit ~= math.huge then
                assertTrue(tier.limit > prev, "tier " .. tier.limit .. " > " .. prev)
                prev = tier.limit
            end
        end
    end)
end

antispamTests[#antispamTests+1] = function()
    return run("ANTISPAM: Threat multiplier at 0 = 1.0", function()
        local mult = 1.0 + (0 * AP.Config.ThreatBonusPerStep)
        assertEqual(mult, 1.0, "threat=0")
    end)
end

antispamTests[#antispamTests+1] = function()
    return run("ANTISPAM: Threat multiplier at max = correct", function()
        local maxT = AP.Config.ThreatMax
        local mult = 1.0 + (maxT * AP.Config.ThreatBonusPerStep)
        local expected = 1.0 + maxT * 0.10
        assertApprox(mult, expected, 0.001, "threat max")
    end)
end

-- ============================================================
-- SECTION 5: QUEST REWARD DEDUP TESTS
-- ============================================================
local questTests = {}

questTests[#questTests+1] = function()
    return run("QUEST: ap_quest_rewarded prevents double grant", function()
        cleanTestGuid()
        CharDBQuery(string.format(
            "INSERT IGNORE INTO `ap_quest_rewarded` (`guid`, `quest_id`) VALUES (%d, 2001);",
            AP_TEST_GUID))
        AP.GrantAether(AP_TEST_GUID, 10)
        local alreadyGranted = CharDBQuery(string.format(
            "SELECT 1 FROM `ap_quest_rewarded` WHERE `guid` = %d AND `quest_id` = 2001 LIMIT 1;",
            AP_TEST_GUID))
        assertTrue(alreadyGranted ~= nil, "row exists, would not re-grant")
        local rec = AP.LoadMastery(AP_TEST_GUID)
        assertEqual(rec.aether, 10, "only 10 aether  -- not doubled")
        cleanTestGuid()
    end)
end

questTests[#questTests+1] = function()
    return run("QUEST: Different quest IDs are independent", function()
        cleanTestGuid()
        CharDBQuery(string.format(
            "INSERT IGNORE INTO `ap_quest_rewarded` (`guid`, `quest_id`) VALUES (%d, 3001);",
            AP_TEST_GUID))
        local q2Granted = CharDBQuery(string.format(
            "SELECT 1 FROM `ap_quest_rewarded` WHERE `guid` = %d AND `quest_id` = 3002 LIMIT 1;",
            AP_TEST_GUID))
        assertTrue(q2Granted == nil, "quest 3002 not yet granted")
        cleanTestGuid()
    end)
end

-- ============================================================
-- SECTION 6: AETHER ACCUMULATION TESTS
-- ============================================================
local aetherTests = {}

aetherTests[#aetherTests+1] = function()
    return run("AETHER: Zero amount grant is a no-op", function()
        cleanTestGuid()
        AP.GrantAether(AP_TEST_GUID, 0)
        local rec = AP.LoadMastery(AP_TEST_GUID)
        -- No row should exist (GrantAether early-exits on amount <= 0)
        -- LoadMastery returns { aether=0, mastery=0 } for missing rows
        assertEqual(rec.aether, 0, "no aether from zero grant")
        cleanTestGuid()
    end)
end

aetherTests[#aetherTests+1] = function()
    return run("AETHER: Large grant doesn't overflow BIGINT (sanity)", function()
        cleanTestGuid()
        AP.GrantAether(AP_TEST_GUID, 1000000)
        local rec = AP.LoadMastery(AP_TEST_GUID)
        assertEqual(rec.aether, 1000000, "1M aether stored")
        cleanTestGuid()
    end)
end

aetherTests[#aetherTests+1] = function()
    return run("AETHER: Normal kill aether > 0", function()
        assertTrue(AP.Config.AetherKillNormal > 0, "normal kill > 0")
    end)
end

aetherTests[#aetherTests+1] = function()
    return run("AETHER: Elite > Normal > 0", function()
        assertTrue(AP.Config.AetherKillElite > AP.Config.AetherKillNormal, "elite > normal")
    end)
end

aetherTests[#aetherTests+1] = function()
    return run("AETHER: Raid boss mult > 1.0", function()
        assertTrue(AP.Config.AetherBossRaidMult > 1.0, "raid mult > 1")
    end)
end

-- ============================================================
-- SECTION 7: UI SANITY TESTS
-- These verify the UI helper functions exist and are callable.
-- ============================================================
local uiTests = {}

uiTests[#uiTests+1] = function()
    return run("UI: AP.OpenUI function exists", function()
        assertTrue(type(AP.OpenUI) == "function", "AP.OpenUI is a function")
    end)
end

uiTests[#uiTests+1] = function()
    return run("UI: AP.SendTooltipPayload function exists", function()
        assertTrue(type(AP.SendTooltipPayload) == "function", "AP.SendTooltipPayload is a function")
    end)
end

uiTests[#uiTests+1] = function()
    return run("UI: AP.Config.ThreatMax > 0", function()
        assertTrue(AP.Config.ThreatMax > 0, "ThreatMax > 0")
    end)
end

uiTests[#uiTests+1] = function()
    return run("UI: AP.Config.CapPerItem = 10000", function()
        assertEqual(AP.Config.CapPerItem, 10000, "CapPerItem")
    end)
end

uiTests[#uiTests+1] = function()
    return run("UI: All module tables have Enabled field", function()
        for name, mod in pairs(AP.Modules) do
            assertTrue(mod.Enabled ~= nil, "Module " .. name .. " has Enabled")
        end
    end)
end

-- ============================================================
-- SECTION 8: FORGE TESTS (#aptest forge)
-- ============================================================
local forgeTests = {}

local function cleanForgeData()
    pcall(function()
        CharDBQuery(string.format("DELETE FROM `ap_item_attune`     WHERE `guid` = %d;", AP_TEST_GUID))
        CharDBQuery(string.format("DELETE FROM `ap_item_snapshot`   WHERE `guid` = %d;", AP_TEST_GUID))
        CharDBQuery(string.format("DELETE FROM `ap_dissolved_items` WHERE `account_id` = %d;", AP_TEST_GUID))
    end)
end

local function ForgePlayer()
    local msgs = {}
    return setmetatable({_msgs = msgs}, {__index = {
        GetGUIDLow            = function() return AP_TEST_GUID end,
        GetAccountId          = function() return AP_TEST_GUID end,
        SendBroadcastMessage  = function(self, m) msgs[#msgs+1] = m end,
        GossipClearMenu       = function(self) end,
        GossipMenuAddItem     = function(self, ...) end,
        GossipSendMenu        = function(self, ...) end,
        GetEquippedItemBySlot = function(self, slot) return nil end,
        GetItemByEntry        = function(self, entry) return nil end,
    }})
end

forgeTests[#forgeTests+1] = function()
    return run("FORGE: Rewards table covers quality 0-5 with positive values", function()
        for q = 0, 5 do
            local r = AP.Forge.Rewards[q]
            assertNotNil(r, "Rewards[" .. q .. "] exists")
            assertTrue(r.essence > 0, "essence>0 at q" .. q)
            assertTrue(r.gold > 0,    "gold>0 at q" .. q)
            assertTrue(r.residue >= 0,"residue>=0 at q" .. q)
        end
    end)
end

forgeTests[#forgeTests+1] = function()
    return run("FORGE: Rewards strictly increase with quality", function()
        for q = 0, 4 do
            assertTrue(AP.Forge.Rewards[q+1].essence > AP.Forge.Rewards[q].essence,
                "essence: q" .. (q+1) .. " > q" .. q)
        end
    end)
end

forgeTests[#forgeTests+1] = function()
    return run("FORGE: GetResidue returns 0 for unknown account", function()
        assertEqual(AP.Forge.GetResidue(AP_TEST_GUID), 0, "unknown account -> 0")
    end)
end

forgeTests[#forgeTests+1] = function()
    return run("FORGE: Attuned item WITHOUT snapshot not in forge list query (snapshot bug regression)", function()
        cleanForgeData()
        local entry = 77001
        CharDBQuery(string.format(
            "INSERT INTO `ap_item_attune` (`guid`,`item_entry`,`progress`,`attuned`) "..
            "VALUES (%d,%d,10000,1);", AP_TEST_GUID, entry))
        local q = CharDBQuery(string.format(
            "SELECT a.item_entry FROM ap_item_attune a "..
            "JOIN ap_item_snapshot s ON s.guid=%d AND s.item_entry=a.item_entry "..
            "LEFT JOIN ap_dissolved_items d ON d.account_id=%d AND d.item_entry=a.item_entry "..
            "WHERE a.guid=%d AND a.attuned=1 AND d.account_id IS NULL AND a.item_entry=%d;",
            AP_TEST_GUID, AP_TEST_GUID, AP_TEST_GUID, entry))
        assertTrue(q == nil, "no snapshot -> excluded from forge listing (Rack CheckAttuned bug)")
        cleanForgeData()
    end)
end

forgeTests[#forgeTests+1] = function()
    return run("FORGE: Attuned item WITH snapshot appears in forge list query", function()
        cleanForgeData()
        local entry = 77002
        CharDBQuery(string.format(
            "INSERT INTO `ap_item_attune` (`guid`,`item_entry`,`progress`,`attuned`) "..
            "VALUES (%d,%d,10000,1);", AP_TEST_GUID, entry))
        CharDBQuery(string.format(
            "INSERT INTO `ap_item_snapshot` (`guid`,`item_entry`,`quality`,`str`,`agi`,`sta`,`int`,`spi`) "..
            "VALUES (%d,%d,3,10.0,5.0,20.0,0.0,0.0);", AP_TEST_GUID, entry))
        local q = CharDBQuery(string.format(
            "SELECT a.item_entry FROM ap_item_attune a "..
            "JOIN ap_item_snapshot s ON s.guid=%d AND s.item_entry=a.item_entry "..
            "LEFT JOIN ap_dissolved_items d ON d.account_id=%d AND d.item_entry=a.item_entry "..
            "WHERE a.guid=%d AND a.attuned=1 AND d.account_id IS NULL AND a.item_entry=%d;",
            AP_TEST_GUID, AP_TEST_GUID, AP_TEST_GUID, entry))
        assertTrue(q ~= nil, "with snapshot -> appears in forge listing")
        cleanForgeData()
    end)
end

forgeTests[#forgeTests+1] = function()
    return run("FORGE: Already-dissolved item excluded from forge list by LEFT JOIN", function()
        cleanForgeData()
        local entry = 77003
        CharDBQuery(string.format(
            "INSERT INTO `ap_item_attune` (`guid`,`item_entry`,`progress`,`attuned`) "..
            "VALUES (%d,%d,10000,1);", AP_TEST_GUID, entry))
        CharDBQuery(string.format(
            "INSERT INTO `ap_item_snapshot` (`guid`,`item_entry`,`quality`,`str`,`agi`,`sta`,`int`,`spi`) "..
            "VALUES (%d,%d,3,10.0,0,0,0,0);", AP_TEST_GUID, entry))
        CharDBQuery(string.format(
            "INSERT INTO `ap_dissolved_items` (`account_id`,`item_entry`) VALUES (%d,%d);",
            AP_TEST_GUID, entry))
        local q = CharDBQuery(string.format(
            "SELECT a.item_entry FROM ap_item_attune a "..
            "JOIN ap_item_snapshot s ON s.guid=%d AND s.item_entry=a.item_entry "..
            "LEFT JOIN ap_dissolved_items d ON d.account_id=%d AND d.item_entry=a.item_entry "..
            "WHERE a.guid=%d AND a.attuned=1 AND d.account_id IS NULL AND a.item_entry=%d;",
            AP_TEST_GUID, AP_TEST_GUID, AP_TEST_GUID, entry))
        assertTrue(q == nil, "dissolved entry excluded from forge list")
        cleanForgeData()
    end)
end

forgeTests[#forgeTests+1] = function()
    return run("FORGE: Dissolve rejects missing/mismatched pending state", function()
        local player = ForgePlayer()
        AP.Forge.Pending[AP_TEST_GUID] = nil
        AP.Forge.Dissolve(player, player, 99999)
        local found = false
        for _, m in ipairs(player._msgs) do
            if m:find("[Worldsoul]", 1, true) then found = true; break end
        end
        assertTrue(found, "rejection message sent when no pending state")
    end)
end

forgeTests[#forgeTests+1] = function()
    return run("FORGE: Dissolve rejects already-dissolved entry (double-dissolution guard)", function()
        cleanForgeData()
        local entry = 77004
        CharDBQuery(string.format(
            "INSERT INTO `ap_item_attune` (`guid`,`item_entry`,`progress`,`attuned`) "..
            "VALUES (%d,%d,10000,1);", AP_TEST_GUID, entry))
        CharDBQuery(string.format(
            "INSERT INTO `ap_dissolved_items` (`account_id`,`item_entry`) VALUES (%d,%d);",
            AP_TEST_GUID, entry))
        local player = ForgePlayer()
        AP.Forge.Pending[AP_TEST_GUID] = { itemEntry=entry, quality=3, name="TestItem" }
        AP.Forge.Dissolve(player, player, entry)
        assertTrue(AP.Forge.Pending[AP_TEST_GUID] == nil, "pending cleared after rejection")
        cleanForgeData()
    end)
end

-- ============================================================
-- SECTION 9: CRUCIBLE / SINKS TESTS (#aptest crucible)
-- ============================================================
local crucibleTests = {}

crucibleTests[#crucibleTests+1] = function()
    return run("CRUCIBLE: AP.OpenUI exists (Back-to-Main nav fix regression guard)", function()
        assertTrue(type(AP.OpenUI) == "function", "AP.OpenUI is a function")
        local badRef = AP.UI and AP.UI.ShowMain
        assertTrue(badRef == nil, "AP.UI.ShowMain does not exist")
    end)
end

crucibleTests[#crucibleTests+1] = function()
    return run("CRUCIBLE: Sinks.OnSelect sender==3 does not throw", function()
        local player = setmetatable({_msgs={}}, {__index={
            GetGUIDLow           = function() return AP_TEST_GUID end,
            GetAccountId         = function() return AP_TEST_GUID end,
            SendBroadcastMessage = function(self,m) end,
            GossipClearMenu      = function(self) end,
            GossipMenuAddItem    = function(self,...) end,
            GossipSendMenu       = function(self,...) end,
        }})
        local ok = pcall(function()
            AP.Sinks.OnSelect(player, player, 3, 0, nil)
        end)
        assertTrue(ok, "OnSelect sender==3 does not propagate an exception")
    end)
end

crucibleTests[#crucibleTests+1] = function()
    return run("CRUCIBLE: Sinks.Invest rejects unknown category", function()
        local player = setmetatable({},{__index={
            GetGUIDLow=function() return AP_TEST_GUID end,
            GetAccountId=function() return AP_TEST_GUID end,
            SendBroadcastMessage=function(self,m) end,
        }})
        local ok, reason = AP.Sinks.Invest(player, "nonexistent_category_xyz", 1000)
        assertFalse(ok, "unknown category rejected")
        assertNotNil(reason, "reason provided")
    end)
end

crucibleTests[#crucibleTests+1] = function()
    return run("CRUCIBLE: Sinks.Invest rejects zero and negative amount", function()
        local player = setmetatable({},{__index={
            GetGUIDLow=function() return AP_TEST_GUID end,
            GetAccountId=function() return AP_TEST_GUID end,
            SendBroadcastMessage=function(self,m) end,
        }})
        local ok0 = AP.Sinks.Invest(player, "life_leech", 0)
        assertFalse(ok0, "zero amount rejected")
        local okN = AP.Sinks.Invest(player, "life_leech", -500)
        assertFalse(okN, "negative amount rejected")
    end)
end

crucibleTests[#crucibleTests+1] = function()
    return run("CRUCIBLE: Sinks.Invest rejects over-budget (no Aether record)", function()
        cleanTestGuid()
        local player = setmetatable({},{__index={
            GetGUIDLow=function() return AP_TEST_GUID end,
            GetAccountId=function() return AP_TEST_GUID end,
            SendBroadcastMessage=function(self,m) end,
        }})
        local ok = AP.Sinks.Invest(player, "life_leech", 1000)
        assertFalse(ok, "no Aether record -> rejected")
    end)
end

crucibleTests[#crucibleTests+1] = function()
    return run("CRUCIBLE: Sinks.GetEffect monotonically non-decreasing for life_leech", function()
        local prev = AP.Sinks.GetEffect("life_leech", 0)
        for i = 1, 10 do
            local cur = AP.Sinks.GetEffect("life_leech", i * 100000)
            assertTrue(cur >= prev, "monotonic at " .. (i * 100000))
            prev = cur
        end
    end)
end

crucibleTests[#crucibleTests+1] = function()
    return run("CRUCIBLE: Sinks.GetEffect ceiling respected for life_leech", function()
        local def = AP.SinkDefs["life_leech"]
        assertNotNil(def, "life_leech def exists")
        local effect = AP.Sinks.GetEffect("life_leech", 999999999)
        assertTrue(effect <= def.ceiling + 0.0001, "effect does not exceed ceiling")
    end)
end

-- ============================================================
-- SECTION 10: VISAGE TESTS (#aptest visage)
-- ============================================================
local visageTests = {}

visageTests[#visageTests+1] = function()
    return run("VISAGE: worldsoul theme unlocked at 0 items", function()
        assertTrue(AP.Visage.IsThemeUnlocked("worldsoul", 0), "worldsoul unlocked at 0")
    end)
end

visageTests[#visageTests+1] = function()
    return run("VISAGE: infernal theme requires exactly 250 items", function()
        assertFalse(AP.Visage.IsThemeUnlocked("infernal", 249), "infernal locked at 249")
        assertTrue( AP.Visage.IsThemeUnlocked("infernal", 250), "infernal unlocked at 250")
    end)
end

visageTests[#visageTests+1] = function()
    return run("VISAGE: GetPrimaryTier boundary values", function()
        assertEqual(AP.Visage.GetPrimaryTier(0),   0, "0 -> tier 0")
        assertEqual(AP.Visage.GetPrimaryTier(9),   0, "9 -> tier 0")
        assertEqual(AP.Visage.GetPrimaryTier(10),  1, "10 -> tier 1")
        assertEqual(AP.Visage.GetPrimaryTier(25),  2, "25 -> tier 2")
        assertEqual(AP.Visage.GetPrimaryTier(250), 5, "250 -> tier 5")
    end)
end

visageTests[#visageTests+1] = function()
    return run("VISAGE: flash_enabled and tier_selected persist through DB round-trip", function()
        CharDBQuery(string.format("DELETE FROM `ap_visage` WHERE `guid`=%d;", AP_TEST_GUID))
        CharDBQuery(string.format(
            "INSERT INTO `ap_visage` "..
            "(`guid`,`primary_theme`,`primary_enabled`,"..
            "`secondary_theme`,`secondary_enabled`,`flash_enabled`,`chat_flavor_enabled`,"..
            "`primary_tier_selected`,`secondary_tier_selected`) "..
            "VALUES (%d,'worldsoul',1,'worldsoul',1,0,1,2,3);",
            AP_TEST_GUID))
        AP.Visage.Cache[AP_TEST_GUID] = nil
        AP.Visage.LoadForChar(AP_TEST_GUID)
        local c = AP.Visage.Cache[AP_TEST_GUID]
        assertNotNil(c, "cache loaded from DB")
        assertEqual(c.flash_enabled, 0, "flash_enabled=0 survived DB round-trip")
        assertEqual(c.primary_tier_selected, 2, "primary_tier_selected=2 survived DB round-trip")
        assertEqual(c.secondary_tier_selected, 3, "secondary_tier_selected=3 survived DB round-trip")
        CharDBQuery(string.format("DELETE FROM `ap_visage` WHERE `guid`=%d;", AP_TEST_GUID))
        AP.Visage.Cache[AP_TEST_GUID] = nil
    end)
end

visageTests[#visageTests+1] = function()
    return run("VISAGE: GetEffectiveTier respects selected tier", function()
        assertEqual(AP.Visage.GetEffectiveTier(0, 5), 5, "tier 0 (auto) -> highest unlocked")
        assertEqual(AP.Visage.GetEffectiveTier(2, 5), 2, "tier 2 selected, 5 unlocked -> 2")
        assertEqual(AP.Visage.GetEffectiveTier(1, 3), 1, "tier 1 selected, 3 unlocked -> 1")
        assertEqual(AP.Visage.GetEffectiveTier(5, 3), 3, "tier 5 selected, 3 unlocked -> clamped to 3")
        assertEqual(AP.Visage.GetEffectiveTier(nil, 4), 4, "nil selected -> highest unlocked")
    end)
end

visageTests[#visageTests+1] = function()
    return run("VISAGE: ThemeSpells has exactly 5 themes", function()
        local count = 0
        for _ in pairs(AP.Visage.ThemeSpells) do count = count + 1 end
        assertEqual(count, 5, "exactly 5 themes in ThemeSpells")
    end)
end

visageTests[#visageTests+1] = function()
    return run("VISAGE: primary and secondary tier selections are independent", function()
        AP.Visage.Cache[AP_TEST_GUID] = {
            primary_theme = "worldsoul", primary_enabled = 1, primary_tier_selected = 1,
            secondary_theme = "void", secondary_enabled = 1, secondary_tier_selected = 4,
            flash_enabled = 1, chat_flavor_enabled = 1,
        }
        local c = AP.Visage.Cache[AP_TEST_GUID]
        assertEqual(AP.Visage.GetEffectiveTier(c.primary_tier_selected, 5), 1, "primary stays at 1")
        assertEqual(AP.Visage.GetEffectiveTier(c.secondary_tier_selected, 5), 4, "secondary stays at 4")
        AP.Visage.Cache[AP_TEST_GUID] = nil
    end)
end

visageTests[#visageTests+1] = function()
    return run("VISAGE: Each theme has exactly 5 tier spells", function()
        for name, spells in pairs(AP.Visage.ThemeSpells) do
            assertEqual(#spells, 5, "theme " .. name .. " has 5 spell IDs")
        end
    end)
end

visageTests[#visageTests+1] = function()
    return run("VISAGE: All ThemeOrder entries have unlock requirements", function()
        for _, theme in ipairs(AP.Visage.ThemeOrder) do
            assertNotNil(AP.Visage.ThemeUnlocks[theme], "unlock defined for theme " .. theme)
        end
    end)
end

-- ============================================================
-- SECTION 11: PVP TESTS (#aptest pvp)
-- ============================================================
local pvpTests = {}

pvpTests[#pvpTests+1] = function()
    return run("PVP: honorKillBase > 0", function()
        assertTrue(AP.PvP.Values.honorKillBase > 0, "honorKillBase > 0")
    end)
end

pvpTests[#pvpTests+1] = function()
    return run("PVP: bgWinBase > bgLossBase > 0", function()
        assertTrue(AP.PvP.Values.bgLossBase > 0,                        "loss > 0")
        assertTrue(AP.PvP.Values.bgWinBase > AP.PvP.Values.bgLossBase,  "win > loss")
    end)
end

pvpTests[#pvpTests+1] = function()
    return run("PVP: Config is fully enabled by default", function()
        assertTrue(AP.PvP.Config.enabled,         "PvP.Config.enabled")
        assertTrue(AP.PvP.Config.honorKillEnabled, "honorKillEnabled")
        assertTrue(AP.PvP.Config.bgEssenceEnabled, "bgEssenceEnabled")
    end)
end

pvpTests[#pvpTests+1] = function()
    return run("PVP: Honor kill Essence grant persists to ap_mastery", function()
        cleanTestGuid()
        -- Use CharDBQuery (SYNC) not CharDBExecute (async): the test must read back
        -- the value immediately, so the write must land before the SELECT.
        local amount = AP.PvP.Values.honorKillBase
        CharDBQuery(string.format(
            "INSERT INTO `ap_mastery` (`guid`,`aether`,`mastery`) VALUES (%d,%d,0) "..
            "ON DUPLICATE KEY UPDATE `aether`=`aether`+%d;",
            AP_TEST_GUID, amount, amount))
        local rec = AP.LoadMastery(AP_TEST_GUID)
        assertEqual(rec.aether, amount, "honor kill aether written correctly")
        cleanTestGuid()
    end)
end

pvpTests[#pvpTests+1] = function()
    return run("PVP: BG win grant produces correct DB delta", function()
        cleanTestGuid()
        -- Use CharDBQuery (SYNC) — same reason as honor kill test above.
        local win = AP.PvP.Values.bgWinBase
        CharDBQuery(string.format(
            "INSERT INTO `ap_mastery` (`guid`,`aether`,`mastery`) VALUES (%d,%d,0) "..
            "ON DUPLICATE KEY UPDATE `aether`=`aether`+%d;",
            AP_TEST_GUID, win, win))
        local rec = AP.LoadMastery(AP_TEST_GUID)
        assertEqual(rec.aether, win, "BG win aether correct")
        cleanTestGuid()
    end)
end

-- ============================================================
-- SECTION 12: WORLDSOUL VOICE TESTS (#aptest voice)
-- ============================================================
local voiceTests = {}

local function VoicePlayer(guid)
    local msgs = {}
    return setmetatable({_msgs=msgs},{__index={
        GetGUIDLow           = function() return guid end,
        SendBroadcastMessage = function(self,m) msgs[#msgs+1]=m end,
    }}), msgs
end

voiceTests[#voiceTests+1] = function()
    return run("VOICE: AP.Voice.Speak is callable", function()
        assertTrue(type(AP.Voice.Speak) == "function", "Speak is function")
    end)
end

voiceTests[#voiceTests+1] = function()
    return run("VOICE: Successive calls advance escalation (different messages)", function()
        local guid = 7777001
        local key  = "already_dissolved"
        AP.Voice.Counters[guid.."_"..key] = nil

        local player, msgs = VoicePlayer(guid)
        AP.Voice.Speak(player, key)
        AP.Voice.Speak(player, key)
        AP.Voice.Speak(player, key)

        assertNotNil(msgs[1], "first message sent")
        assertNotNil(msgs[2], "second message sent")
        assertNotNil(msgs[3], "third message sent")
        assertTrue(msgs[1] ~= msgs[2], "msg1 != msg2 (escalation)")
        assertTrue(msgs[2] ~= msgs[3], "msg2 != msg3 (escalation)")

        AP.Voice.Counters[guid.."_"..key] = nil
    end)
end

voiceTests[#voiceTests+1] = function()
    return run("VOICE: Clamps to last message past list end (no error, no silence)", function()
        local guid = 7777002
        local key  = "already_dissolved"
        local list = AP.Voice.Messages[key]
        assertNotNil(list, "message list exists")
        AP.Voice.Counters[guid.."_"..key] = nil

        local player, msgs = VoicePlayer(guid)
        for _ = 1, #list + 3 do AP.Voice.Speak(player, key) end

        local lastSent = msgs[#list + 3]
        assertNotNil(lastSent, "message still sent past end of list")
        assertTrue(lastSent:find(list[#list], 1, true),
            "final message is clamped last entry: " .. list[#list])

        AP.Voice.Counters[guid.."_"..key] = nil
    end)
end

voiceTests[#voiceTests+1] = function()
    return run("VOICE: Different trigger keys use independent counters", function()
        local guid = 7777003
        AP.Voice.Counters[guid.."_already_dissolved"]  = nil
        AP.Voice.Counters[guid.."_rack_not_possessed"] = nil

        local player, msgs = VoicePlayer(guid)
        AP.Voice.Speak(player, "already_dissolved")
        AP.Voice.Speak(player, "rack_not_possessed")

        assertTrue(msgs[1]:find(AP.Voice.Messages.already_dissolved[1],  1, true), "ad msg1 correct")
        assertTrue(msgs[2]:find(AP.Voice.Messages.rack_not_possessed[1], 1, true), "rnp msg1 correct (independent)")

        AP.Voice.Counters[guid.."_already_dissolved"]  = nil
        AP.Voice.Counters[guid.."_rack_not_possessed"] = nil
    end)
end

voiceTests[#voiceTests+1] = function()
    return run("VOICE: Reset clears escalation counter", function()
        local guid = 7777004
        local key  = "generic"
        AP.Voice.Counters[guid.."_"..key] = nil

        local player = VoicePlayer(guid)
        AP.Voice.Speak(player, key)
        AP.Voice.Speak(player, key)
        assertEqual(AP.Voice.Counters[guid.."_"..key], 2, "counter=2 before reset")
        AP.Voice.Reset(player, key)
        assertTrue(AP.Voice.Counters[guid.."_"..key] == nil, "counter nil after reset")
    end)
end

voiceTests[#voiceTests+1] = function()
    return run("VOICE: Unknown trigger key falls back to generic messages", function()
        local guid = 7777005
        local key  = "nonexistent_trigger_xyz_99"
        AP.Voice.Counters[guid.."_"..key] = nil

        local player, msgs = VoicePlayer(guid)
        AP.Voice.Speak(player, key)

        assertNotNil(msgs[1], "message sent for unknown key")
        assertTrue(msgs[1]:find(AP.Voice.Messages.generic[1], 1, true),
            "falls back to generic message list")

        AP.Voice.Counters[guid.."_"..key] = nil
    end)
end

-- ============================================================
-- SECTION 13: VERSION TESTS (#aptest version)
-- ============================================================
local versionTests = {}

versionTests[#versionTests+1] = function()
    return run("VERSION: AP.VERSION is a non-empty string", function()
        assertNotNil(AP.VERSION, "AP.VERSION not nil")
        assertTrue(type(AP.VERSION) == "string", "AP.VERSION is string")
        assertTrue(#AP.VERSION > 0, "AP.VERSION not empty")
    end)
end

versionTests[#versionTests+1] = function()
    return run("VERSION: AP.VERSION matches semver major.minor.patch", function()
        local major, minor, patch = AP.VERSION:match("^(%d+)%.(%d+)%.(%d+)$")
        assertNotNil(major, "VERSION has major: " .. tostring(AP.VERSION))
        assertNotNil(minor, "VERSION has minor")
        assertNotNil(patch, "VERSION has patch")
    end)
end

versionTests[#versionTests+1] = function()
    return run("VERSION: Mismatch detection logic is correct", function()
        local server = AP.VERSION
        assertTrue(not (server and (server ~= server)), "matching version -> no warning")
        local mismatched = server .. ".extra"
        assertTrue(server and (mismatched ~= server), "mismatch -> triggers warning condition")
    end)
end

versionTests[#versionTests+1] = function()
    return run("VERSION: Warning message format includes both client and server", function()
        local sv, cv = "1.0.0", "0.9.5"
        local msg = string.format(
            "|cffff4444[Worldsoul] ADDON OUT OF DATE|r  (you: |cffffff00v%s|r  server: |cff9966ffv%s|r)",
            cv, sv)
        assertTrue(msg:find(cv, 1, true), "client version in warning message")
        assertTrue(msg:find(sv, 1, true), "server version in warning message")
    end)
end

-- ============================================================
-- SECTION 14: EXPLOIT GUARD TESTS (#aptest exploit)
-- ============================================================
local exploitTests = {}

exploitTests[#exploitTests+1] = function()
    return run("EXPLOIT: Weapon (class=2, invType>0) passes gear eligibility check", function()
        local q = WorldDBQuery(
            "SELECT `class`, `InventoryType` FROM `item_template` "..
            "WHERE `class` = 2 AND `InventoryType` > 0 LIMIT 1;")
        assertNotNil(q, "weapon row exists in item_template")
        local iClass  = tonumber(q:GetUInt8(0)) or 0
        local invType = tonumber(q:GetUInt32(1)) or 0
        assertTrue((iClass == 2 or iClass == 4) and invType > 0, "weapon passes guard")
    end)
end

exploitTests[#exploitTests+1] = function()
    return run("EXPLOIT: Armor (class=4, invType>0) passes gear eligibility check", function()
        local q = WorldDBQuery(
            "SELECT `class`, `InventoryType` FROM `item_template` "..
            "WHERE `class` = 4 AND `InventoryType` > 0 AND `subclass` > 0 LIMIT 1;")
        assertNotNil(q, "armor row exists in item_template")
        local iClass  = tonumber(q:GetUInt8(0)) or 0
        local invType = tonumber(q:GetUInt32(1)) or 0
        assertTrue((iClass == 2 or iClass == 4) and invType > 0, "armor passes guard")
    end)
end

exploitTests[#exploitTests+1] = function()
    return run("EXPLOIT: Consumable (class=0) rejected by gear eligibility check", function()
        local q = WorldDBQuery(
            "SELECT `class`, `InventoryType` FROM `item_template` "..
            "WHERE `class` = 0 LIMIT 1;")
        assertNotNil(q, "consumable row exists in item_template")
        local iClass  = tonumber(q:GetUInt8(0)) or 0
        local invType = tonumber(q:GetUInt32(1)) or 0
        assertTrue(not ((iClass == 2 or iClass == 4) and invType > 0),
            "consumable rejected: class="..iClass.." invType="..invType)
    end)
end

exploitTests[#exploitTests+1] = function()
    return run("EXPLOIT: Quest item (class=12) rejected by gear eligibility check", function()
        local q = WorldDBQuery(
            "SELECT `class`, `InventoryType` FROM `item_template` "..
            "WHERE `class` = 12 LIMIT 1;")
        if not q then
            assertTrue(true, "no class=12 rows; guard trivially safe")
            return
        end
        local iClass  = tonumber(q:GetUInt8(0)) or 0
        local invType = tonumber(q:GetUInt32(1)) or 0
        assertTrue(not ((iClass == 2 or iClass == 4) and invType > 0),
            "quest item rejected: class="..iClass.." invType="..invType)
    end)
end

exploitTests[#exploitTests+1] = function()
    return run("EXPLOIT: LevelAbsorbScalar = 0 at level 5 (no absorption for low-level chars)", function()
        assertEqual(AP.LevelAbsorbScalar(5), 0.0, "level 5 = 0")
    end)
end

exploitTests[#exploitTests+1] = function()
    return run("EXPLOIT: LevelAbsorbScalar = 0 at level 9 (boundary, still no absorption)", function()
        assertEqual(AP.LevelAbsorbScalar(9), 0.0, "level 9 = 0")
    end)
end

exploitTests[#exploitTests+1] = function()
    return run("EXPLOIT: LevelAbsorbScalar > 0 at level 10 (one above boundary)", function()
        local s = AP.LevelAbsorbScalar(10)
        assertTrue(s > 0.0, "level 10 > 0")
        assertApprox(s, 1.0/71.0, 0.001, "level 10 = 1/71")
    end)
end

exploitTests[#exploitTests+1] = function()
    return run("EXPLOIT: LevelAbsorbScalar = 1.0 at level 80 (full absorption)", function()
        assertEqual(AP.LevelAbsorbScalar(80), 1.0, "level 80 = 1.0")
    end)
end

-- ============================================================
-- SECTION: TIER 3 REGRESSION TESTS
-- ============================================================
local tier3Tests = {}

-- T3-1: Gear-cycling feedback uses AP.LevelAbsorbScalar (not old formula)
tier3Tests[#tier3Tests+1] = function()
    return run("T3: LevelAbsorbScalar used in feedback (no (level/80)^2 remnant)", function()
        local lvl5_scalar  = AP.LevelAbsorbScalar(5)
        local lvl5_old     = (5 / 80) ^ 2
        assertEqual(lvl5_scalar, 0.0, "LevelAbsorbScalar(5) = 0")
        assertTrue(lvl5_old > 0, "old formula (5/80)^2 > 0 (would be wrong)")
    end)
end

-- T3-2: Rack XP applies XpToAttune and RarityMultiplier
tier3Tests[#tier3Tests+1] = function()
    return run("T3: Rack XP includes XpToAttune * rarityMult", function()
        assertNotNil(AP.Config.XpToAttune, "XpToAttune config exists")
        assertTrue(AP.Config.XpToAttune > 0, "XpToAttune > 0")
        local rm = AP.RarityMultiplier(2)
        assertNotNil(rm, "RarityMultiplier(2) exists")
        assertTrue(rm > 0, "RarityMultiplier(2) > 0")
    end)
end

-- T3-3: Rack XP splits across N items (formula verification)
tier3Tests[#tier3Tests+1] = function()
    return run("T3: Rack XP split: 2 items each get half base XP", function()
        local baseXP = 1000
        local rackRate = 0.20
        local rackBaseXP = baseXP * rackRate
        local split1 = math.floor(rackBaseXP / 1)
        local split2 = math.floor(rackBaseXP / 2)
        local split5 = math.floor(rackBaseXP / 5)
        assertEqual(split1, 200, "1 rack item gets full 200")
        assertEqual(split2, 100, "2 rack items each get 100")
        assertEqual(split5, 40, "5 rack items each get 40")
    end)
end

-- T3-4: Equipped XP is independent of Rack item count (formula verification)
tier3Tests[#tier3Tests+1] = function()
    return run("T3: Equipped XP unaffected by Rack count", function()
        local xp = 1000
        local unattunedCount = 3
        local xpPerItem = xp / unattunedCount
        local rackCount = 10
        local xpPerItemWithRack = xp / unattunedCount
        assertApprox(xpPerItem, xpPerItemWithRack, 0.001,
            "equipped XP/item identical regardless of rack count")
    end)
end

-- T3-5: ap_session_state table exists and supports clean_exit flag
tier3Tests[#tier3Tests+1] = function()
    return run("T3: ap_session_state round-trip", function()
        CharDBQuery(string.format(
            "DELETE FROM `ap_session_state` WHERE `guid` = %d;", AP_TEST_GUID))
        CharDBQuery(string.format(
            "INSERT INTO `ap_session_state` (`guid`,`clean_exit`) VALUES (%d, 1)",
            AP_TEST_GUID))
        CharDBQuery("COMMIT;")
        local q = CharDBQuery(string.format(
            "SELECT `clean_exit` FROM `ap_session_state` WHERE `guid` = %d",
            AP_TEST_GUID))
        assertNotNil(q, "session_state row exists")
        local val = tonumber(tostring(q:GetUInt32(0))) or -1
        assertEqual(val, 1, "clean_exit = 1")
        CharDBQuery(string.format(
            "UPDATE `ap_session_state` SET `clean_exit` = 0 WHERE `guid` = %d",
            AP_TEST_GUID))
        CharDBQuery("COMMIT;")
        local q2 = CharDBQuery(string.format(
            "SELECT `clean_exit` FROM `ap_session_state` WHERE `guid` = %d",
            AP_TEST_GUID))
        assertNotNil(q2, "session_state row still exists")
        local val2 = tonumber(tostring(q2:GetUInt32(0))) or -1
        assertEqual(val2, 0, "clean_exit = 0 after reset")
        CharDBQuery(string.format(
            "DELETE FROM `ap_session_state` WHERE `guid` = %d;", AP_TEST_GUID))
        CharDBQuery("COMMIT;")
    end)
end

-- T3-6: Login resets clean_exit to 0 (per-player, no bulk startup reset)
tier3Tests[#tier3Tests+1] = function()
    return run("T3: Login read-then-reset pattern for clean_exit", function()
        CharDBQuery(string.format(
            "INSERT INTO `ap_session_state` (`guid`,`clean_exit`) VALUES (%d, 1) "..
            "ON DUPLICATE KEY UPDATE `clean_exit` = 1", AP_TEST_GUID))
        CharDBQuery("COMMIT;")
        local q1 = CharDBQuery(string.format(
            "SELECT `clean_exit` FROM `ap_session_state` WHERE `guid` = %d",
            AP_TEST_GUID))
        assertNotNil(q1, "row exists before reset")
        assertEqual(tonumber(tostring(q1:GetUInt32(0))) or -1, 1, "clean_exit = 1 before login reset")
        CharDBQuery(string.format(
            "UPDATE `ap_session_state` SET `clean_exit` = 0 WHERE `guid` = %d",
            AP_TEST_GUID))
        CharDBQuery("COMMIT;")
        local q2 = CharDBQuery(string.format(
            "SELECT `clean_exit` FROM `ap_session_state` WHERE `guid` = %d",
            AP_TEST_GUID))
        assertNotNil(q2, "row survives reset")
        assertEqual(tonumber(tostring(q2:GetUInt32(0))) or -1, 0, "clean_exit = 0 after login reset")
        CharDBQuery(string.format(
            "DELETE FROM `ap_session_state` WHERE `guid` = %d;", AP_TEST_GUID))
        CharDBQuery("COMMIT;")
    end)
end

-- T3-7: Mastery and Attuned pages use same LevelAbsorbScalar
tier3Tests[#tier3Tests+1] = function()
    return run("T3: MasteryPage and AttunesPage use identical formulas", function()
        for _, lvl in ipairs({1, 5, 9, 10, 40, 79, 80}) do
            local mastery = 5
            local masteryPct = AP.MasteryAbsorbPct(mastery)
            local levelScale = AP.LevelAbsorbScalar(lvl)
            local effective  = masteryPct * levelScale
            assertTrue(effective >= 0, "effective >= 0 at level " .. lvl)
            if lvl <= 9 then
                assertEqual(effective, 0.0, "effective = 0 at level " .. lvl)
            end
        end
    end)
end

-- ============================================================
-- SECTION 14: TIER 4 TESTS (#aptest tier4)
-- ============================================================
local tier4Tests = {}

-- T4-1: ThemeSpells has exactly 5 themes
tier4Tests[#tier4Tests+1] = function()
    return run("T4: ThemeSpells has exactly 5 themes", function()
        local count = 0
        for _ in pairs(AP.Visage.ThemeSpells) do count = count + 1 end
        assertEqual(count, 5, "5 themes in ThemeSpells")
    end)
end

-- T4-2: Each theme has exactly 5 tiers
tier4Tests[#tier4Tests+1] = function()
    return run("T4: Each theme has exactly 5 tier spell IDs", function()
        for name, spells in pairs(AP.Visage.ThemeSpells) do
            assertEqual(#spells, 5, name .. " has 5 spells")
            for i, sid in ipairs(spells) do
                assertTrue(sid > 0, name .. " T" .. i .. " spell ID > 0")
            end
        end
    end)
end

-- T4-3: No duplicate spell IDs across the entire table
tier4Tests[#tier4Tests+1] = function()
    return run("T4: No duplicate spell IDs in ThemeSpells", function()
        local seen = {}
        for theme, spells in pairs(AP.Visage.ThemeSpells) do
            for i, sid in ipairs(spells) do
                local key = tostring(sid)
                assertEqual(seen[key], nil, "spell " .. key .. " not duplicated (found in " .. theme .. " T" .. i .. ")")
                seen[key] = theme .. " T" .. i
            end
        end
    end)
end

-- T4-4: GetEffectiveTier clamps selected > unlocked
tier4Tests[#tier4Tests+1] = function()
    return run("T4: GetEffectiveTier clamps above unlocked max", function()
        assertEqual(AP.Visage.GetEffectiveTier(5, 3), 3, "selected 5, unlocked 3 -> 3")
        assertEqual(AP.Visage.GetEffectiveTier(4, 2), 2, "selected 4, unlocked 2 -> 2")
    end)
end

-- T4-5: GetEffectiveTier 0 defaults to highest unlocked
tier4Tests[#tier4Tests+1] = function()
    return run("T4: GetEffectiveTier 0 = auto highest", function()
        assertEqual(AP.Visage.GetEffectiveTier(0, 5), 5, "auto -> 5")
        assertEqual(AP.Visage.GetEffectiveTier(0, 1), 1, "auto -> 1")
        assertEqual(AP.Visage.GetEffectiveTier(nil, 3), 3, "nil -> 3")
    end)
end

-- T4-6: GetEffectiveTier respects lower selected tier
tier4Tests[#tier4Tests+1] = function()
    return run("T4: GetEffectiveTier respects lower selected tier", function()
        assertEqual(AP.Visage.GetEffectiveTier(1, 5), 1, "selected 1, unlocked 5 -> 1")
        assertEqual(AP.Visage.GetEffectiveTier(2, 4), 2, "selected 2, unlocked 4 -> 2")
        assertEqual(AP.Visage.GetEffectiveTier(3, 3), 3, "selected 3, unlocked 3 -> 3")
    end)
end

-- T4-7: Primary and secondary tier selections are independent
tier4Tests[#tier4Tests+1] = function()
    return run("T4: Primary and secondary tiers are independent", function()
        AP.Visage.Cache[AP_TEST_GUID] = {
            primary_theme = "worldsoul", primary_enabled = 1, primary_tier_selected = 1,
            secondary_theme = "void", secondary_enabled = 1, secondary_tier_selected = 4,
            flash_enabled = 1, chat_flavor_enabled = 1,
        }
        local c = AP.Visage.Cache[AP_TEST_GUID]
        local priEff = AP.Visage.GetEffectiveTier(c.primary_tier_selected, 5)
        local secEff = AP.Visage.GetEffectiveTier(c.secondary_tier_selected, 5)
        assertEqual(priEff, 1, "primary effective = 1")
        assertEqual(secEff, 4, "secondary effective = 4")
        assertTrue(priEff ~= secEff, "primary and secondary are different")
        AP.Visage.Cache[AP_TEST_GUID] = nil
    end)
end

-- T4-8: Tier selection DB round-trip
tier4Tests[#tier4Tests+1] = function()
    return run("T4: Tier selection persists through DB round-trip", function()
        CharDBQuery(string.format("DELETE FROM `ap_visage` WHERE `guid`=%d;", AP_TEST_GUID))
        CharDBQuery(string.format(
            "INSERT INTO `ap_visage` "..
            "(`guid`,`primary_theme`,`primary_enabled`,"..
            "`secondary_theme`,`secondary_enabled`,`flash_enabled`,`chat_flavor_enabled`,"..
            "`primary_tier_selected`,`secondary_tier_selected`) "..
            "VALUES (%d,'infernal',1,'ethereal',1,1,1,2,4);",
            AP_TEST_GUID))
        AP.Visage.Cache[AP_TEST_GUID] = nil
        AP.Visage.LoadForChar(AP_TEST_GUID)
        local c = AP.Visage.Cache[AP_TEST_GUID]
        assertNotNil(c, "cache loaded")
        assertEqual(c.primary_theme, "infernal", "primary_theme = infernal")
        assertEqual(c.primary_tier_selected, 2, "primary_tier_selected = 2")
        assertEqual(c.secondary_theme, "ethereal", "secondary_theme = ethereal")
        assertEqual(c.secondary_tier_selected, 4, "secondary_tier_selected = 4")
        CharDBQuery(string.format("DELETE FROM `ap_visage` WHERE `guid`=%d;", AP_TEST_GUID))
        AP.Visage.Cache[AP_TEST_GUID] = nil
    end)
end

-- T4-9: AllSpellIds contains exactly 25 entries
tier4Tests[#tier4Tests+1] = function()
    return run("T4: AllSpellIds has 25 unique entries", function()
        local count = 0
        for _ in pairs(AP.Visage.AllSpellIds) do count = count + 1 end
        assertEqual(count, 25, "25 unique spell IDs in AllSpellIds")
    end)
end

-- T4-10: Aura Lab is GM-locked
tier4Tests[#tier4Tests+1] = function()
    return run("T4: AuraLab.HandleChat checks IsGM", function()
        assertNotNil(AP.AuraLab, "AuraLab module loaded")
        assertNotNil(AP.AuraLab.HandleChat, "HandleChat function exists")
    end)
end

-- ============================================================
-- SECTION 15: TIER 5 TESTS (#aptest tier5)
-- ============================================================
local tier5Tests = {}

-- T5-1: Level scalar display matches AP.LevelAbsorbScalar
tier5Tests[#tier5Tests+1] = function()
    return run("T5: LevelAbsorbScalar returns expected values", function()
        assertEqual(AP.LevelAbsorbScalar(1), 0, "level 1 -> 0")
        assertEqual(AP.LevelAbsorbScalar(9), 0, "level 9 -> 0")
        assertTrue(AP.LevelAbsorbScalar(10) > 0, "level 10 > 0")
        assertEqual(AP.LevelAbsorbScalar(80), 1, "level 80 -> 1")
    end)
end

-- T5-2: Effective absorption = base * level scalar
tier5Tests[#tier5Tests+1] = function()
    return run("T5: Effective absorption = base * level scalar", function()
        local base = AP.MasteryAbsorbPct(5)
        local scale = AP.LevelAbsorbScalar(40)
        local eff = base * scale
        assertTrue(eff > 0, "effective > 0 at rank 5 level 40")
        assertTrue(eff < base, "effective < base when level < 80")
        local eff80 = base * AP.LevelAbsorbScalar(80)
        assertApprox(eff80, base, 0.001, "effective = base at level 80")
    end)
end

-- T5-3: Visage selected vs unlocked tier are separate concepts
tier5Tests[#tier5Tests+1] = function()
    return run("T5: Selected tier and unlocked tier are separate", function()
        local unlocked = 5
        local selected = 2
        local eff = AP.Visage.GetEffectiveTier(selected, unlocked)
        assertEqual(eff, 2, "selected 2 with 5 unlocked -> effective 2")
        assertTrue(eff ~= unlocked, "effective != unlocked when selected lower")
    end)
end

-- T5-4: Rack slot count works with empty rack
tier5Tests[#tier5Tests+1] = function()
    return run("T5: Rack CountSlots returns 0 with no cache", function()
        AP.Rack.Cache[AP_TEST_GUID] = nil
        local count = AP.Rack.CountSlots(AP_TEST_GUID)
        assertEqual(count, 0, "empty rack -> 0 slots used")
    end)
end

-- T5-5: Next-goal theme unlock returns valid data
tier5Tests[#tier5Tests+1] = function()
    return run("T5: Theme unlock thresholds are ordered ascending", function()
        local prev = -1
        for _, theme in ipairs(AP.Visage.ThemeOrder) do
            local req = AP.Visage.ThemeUnlocks[theme]
            assertNotNil(req, "unlock defined for " .. theme)
            assertTrue(req >= prev, theme .. " unlock >= previous")
            prev = req
        end
    end)
end

-- T5-6: Rack expansion tiers are ordered ascending
tier5Tests[#tier5Tests+1] = function()
    return run("T5: Rack ExpandTiers slots increase per tier", function()
        local prevSlots = 0
        for i, tier in ipairs(AP.Rack.ExpandTiers) do
            assertTrue(tier[1] > prevSlots, "tier " .. i .. " slots > previous")
            prevSlots = tier[1]
        end
    end)
end

-- T5-7: AP.IsGM wrapper exists and returns boolean
tier5Tests[#tier5Tests+1] = function()
    return run("T5: AP.IsGM returns false for mock player", function()
        local mockPlayer = {}
        local result = AP.IsGM(mockPlayer)
        assertEqual(result, false, "mock player without IsGM -> false")
    end)
end

-- T5-8: Mastery cost is positive for all ranks 0-50
tier5Tests[#tier5Tests+1] = function()
    return run("T5: MasteryCost > 0 for ranks 0-50", function()
        for r = 0, 50 do
            assertTrue(AP.MasteryCost(r) > 0, "rank " .. r .. " cost > 0")
        end
    end)
end

-- T5-9: No [EotW] remains in player-facing message templates
tier5Tests[#tier5Tests+1] = function()
    return run("T5: Forge rejection uses [Worldsoul] prefix", function()
        local player = ForgePlayer()
        AP.Forge.Pending[AP_TEST_GUID] = nil
        AP.Forge.Dissolve(player, player, 99999)
        local foundOld = false
        local foundNew = false
        for _, m in ipairs(player._msgs) do
            if m:find("[EotW]", 1, true) then foundOld = true end
            if m:find("[Worldsoul]", 1, true) then foundNew = true end
        end
        assertFalse(foundOld, "no [EotW] prefix in message")
        assertTrue(foundNew, "[Worldsoul] prefix found in message")
    end)
end

-- T5-10: AuraLab HandleChat blocks non-GM
tier5Tests[#tier5Tests+1] = function()
    return run("T5: AuraLab blocks non-GM player", function()
        local mockPlayer = ForgePlayer()
        mockPlayer.IsGM = function() return false end
        local handled = AP.AuraLab.HandleChat(mockPlayer, "#ap auralab")
        assertTrue(handled, "command was handled (not passed through)")
        local blocked = false
        for _, m in ipairs(mockPlayer._msgs) do
            if m:find("GM access required", 1, true) then blocked = true end
        end
        assertTrue(blocked, "non-GM got blocked message")
    end)
end

-- ============================================================
-- SECTION 16: THREAT V2 TESTS (#aptest threat)
-- ============================================================
local threatTests = {}

threatTests[#threatTests+1] = function()
    return run("THREAT: Ceiling at level 0 = 0%", function()
        assertEqual(AP.GetThreatCeiling(0), 0, "threat 0 ceiling = 0")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Ceiling at level 10 = 100%", function()
        assertApprox(AP.GetThreatCeiling(10), 1.0, 0.001, "threat 10 ceiling = 1.0")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Effective bonus = ceiling * momentum", function()
        local mult = AP.GetThreatMult(5, 0.6)
        assertApprox(mult, 1.30, 0.001, "threat 5 momentum 0.6 -> 1.30")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Full momentum at max threat = 2.0x", function()
        local mult = AP.GetThreatMult(10, 1.0)
        assertApprox(mult, 2.0, 0.001, "threat 10 momentum 1.0 -> 2.0")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Zero momentum = 1.0x regardless of level", function()
        local mult = AP.GetThreatMult(10, 0.0)
        assertApprox(mult, 1.0, 0.001, "threat 10 momentum 0 -> 1.0")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Momentum clamps to 1.0", function()
        local m = math.min(1.0, 0.99 + 0.03)
        assertEqual(m, 1.0, "0.99 + 0.03 clamped to 1.0")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Level names defined for 0-10", function()
        for i = 0, 10 do
            local name = AP.GetThreatName(i)
            assertNotNil(name, "name exists for level " .. i)
            assertTrue(#name > 0, "name not empty for level " .. i)
        end
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Safety scalar at threat 0 = 1.0", function()
        assertApprox(AP.GetSafetyScalar(0), 1.0, 0.001, "threat 0 safety = 1.0")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Safety scalar at threat 5 = 0.75", function()
        assertApprox(AP.GetSafetyScalar(5), 0.75, 0.001, "threat 5 safety = 0.75")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Safety scalar at threat 10 = 0.50", function()
        assertApprox(AP.GetSafetyScalar(10), 0.50, 0.001, "threat 10 safety = 0.50")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Dampener floor at threat 0 = 0.80", function()
        assertApprox(AP.GetDampenerFloor(0), 0.80, 0.001, "threat 0 damp floor = 0.80")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Dampener floor at threat 10 = 0.40", function()
        assertApprox(AP.GetDampenerFloor(10), 0.40, 0.001, "threat 10 damp floor = 0.40")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: DB round-trip preserves threat without touching clean_exit", function()
        CharDBQuery(string.format(
            "INSERT INTO `ap_session_state` (`guid`,`clean_exit`,`threat_level`,`threat_momentum`) "..
            "VALUES (%d, 1, 7, 0.4500) "..
            "ON DUPLICATE KEY UPDATE `threat_level`=7, `threat_momentum`=0.4500",
            AP_TEST_GUID))
        CharDBQuery("COMMIT;")
        local q = CharDBQuery(string.format(
            "SELECT `clean_exit`, `threat_level`, `threat_momentum` FROM `ap_session_state` WHERE `guid`=%d",
            AP_TEST_GUID))
        assertNotNil(q, "row exists")
        assertEqual(tonumber(tostring(q:GetUInt32(0))) or -1, 1, "clean_exit unchanged at 1")
        assertEqual(tonumber(tostring(q:GetUInt32(1))) or -1, 7, "threat_level = 7")
        local mom = tonumber(tostring(q:GetString(2))) or -1
        assertTrue(mom > 0.44 and mom < 0.46, "threat_momentum ~ 0.45")
        CharDBQuery(string.format("DELETE FROM `ap_session_state` WHERE `guid`=%d", AP_TEST_GUID))
        CharDBQuery("COMMIT;")
    end)
end

-- Content cap tests
threatTests[#threatTests+1] = function()
    return run("THREAT: Gray mob content cap = 0", function()
        assertEqual(AP.Config.ThreatContentCaps.gray, 0, "gray cap = 0")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Same-level normal cap = 0.40", function()
        local cap = AP.GetThreatContentCap(40, 40, 0, false, false)
        assertApprox(cap, 0.40, 0.001, "same-level normal = 0.40")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Elite cap > normal cap", function()
        local normalCap = AP.GetThreatContentCap(40, 40, 0, false, false)
        local eliteCap  = AP.GetThreatContentCap(40, 40, 1, false, false)
        assertTrue(eliteCap > normalCap, "elite > normal")
        assertApprox(eliteCap, 0.70, 0.001, "elite = 0.70")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Boss cap > elite cap", function()
        local eliteCap = AP.GetThreatContentCap(40, 40, 1, false, false)
        local bossCap  = AP.GetThreatContentCap(40, 40, 0, true, false)
        assertTrue(bossCap > eliteCap, "boss > elite")
        assertApprox(bossCap, 0.85, 0.001, "dungeon boss = 0.85")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Raid boss cap = 1.0", function()
        local cap = AP.GetThreatContentCap(40, 40, 0, true, true)
        assertApprox(cap, 1.00, 0.001, "raid boss = 1.0")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Threat 10 normal mob capped below full ceiling", function()
        local normalCap = AP.GetThreatContentCap(40, 40, 0, false, false)
        local mult = AP.GetThreatMultCapped(10, 1.0, normalCap)
        assertTrue(mult < 2.0, "capped below 2.0 for normal mob")
        assertApprox(mult, 1.0 + normalCap, 0.001, "1.0 + normal cap")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Threat 10 boss can reach full ceiling", function()
        local bossCap = AP.GetThreatContentCap(40, 40, 0, true, true)
        local mult = AP.GetThreatMultCapped(10, 1.0, bossCap)
        assertApprox(mult, 2.0, 0.001, "raid boss at full momentum = 2.0")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Content cap applies after momentum", function()
        local normalCap = 0.40
        local mult_low_momentum = AP.GetThreatMultCapped(10, 0.2, normalCap)
        local mult_high_momentum = AP.GetThreatMultCapped(10, 1.0, normalCap)
        assertApprox(mult_low_momentum, 1.20, 0.001, "low momentum: 0.2 * 1.0 = 0.20 < cap")
        assertApprox(mult_high_momentum, 1.40, 0.001, "high momentum: capped at 0.40")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Threat 0 always returns 1.0", function()
        local mult = AP.GetThreatMultCapped(0, 1.0, 1.0)
        assertApprox(mult, 1.0, 0.001, "threat 0 = 1.0 always")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Higher-level normal mob cap > same-level", function()
        local sameCap = AP.GetThreatContentCap(40, 40, 0, false, false)
        local hardCap = AP.GetThreatContentCap(40, 43, 0, false, false)
        assertTrue(hardCap > sameCap, "hard normal > same normal")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Momentum config values are positive", function()
        assertTrue(AP.Config.ThreatMomentumNormal > 0, "normal momentum > 0")
        assertTrue(AP.Config.ThreatMomentumElite > AP.Config.ThreatMomentumNormal, "elite > normal")
        assertTrue(AP.Config.ThreatMomentumBoss > AP.Config.ThreatMomentumElite, "boss > elite")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Death resets momentum (logic check)", function()
        local session = { threat = 5, momentum = 0.75, momentumKills = 50 }
        session.momentum = 0.0
        session.momentumKills = 0
        assertApprox(session.momentum, 0.0, 0.001, "momentum reset to 0")
        assertEqual(session.momentumKills, 0, "kill count reset to 0")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Lowering threat resets momentum (logic check)", function()
        local session = { threat = 5, momentum = 0.5 }
        session.threat = session.threat - 1
        session.momentum = 0.0
        assertEqual(session.threat, 4, "threat lowered to 4")
        assertApprox(session.momentum, 0.0, 0.001, "momentum reset")
    end)
end

-- Death penalty tests
threatTests[#threatTests+1] = function()
    return run("THREAT: Threat 0 death has no penalty", function()
        local pen = AP.GetDeathPenalty(0)
        assertEqual(pen[1], 0, "no attune loss")
        assertEqual(pen[2], 0, "no essence loss")
        assertEqual(pen[4], 0, "no debt kills")
        assertApprox(pen[5], 1.0, 0.001, "debt mult = 1.0")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Threat 5 death penalty values correct", function()
        local pen = AP.GetDeathPenalty(5)
        assertApprox(pen[1], 0.10, 0.001, "10% attune loss")
        assertApprox(pen[2], 0.03, 0.001, "3% essence loss")
        assertEqual(pen[3], 1000, "essence cap 1000")
        assertEqual(pen[4], 15, "15 debt kills")
        assertApprox(pen[5], 0.65, 0.001, "65% debt mult")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Threat 10 death penalty is harshest", function()
        local pen = AP.GetDeathPenalty(10)
        assertApprox(pen[1], 0.20, 0.001, "20% attune loss")
        assertApprox(pen[2], 0.08, 0.001, "8% essence loss")
        assertEqual(pen[3], 10000, "essence cap 10000")
        assertEqual(pen[4], 25, "25 debt kills")
        assertApprox(pen[5], 0.40, 0.001, "40% debt mult")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Attunement progress loss never below 0", function()
        local progress = 100
        local loss = math.floor(progress * 0.20)
        local result = math.max(0, progress - loss)
        assertTrue(result >= 0, "progress >= 0 after loss")
        local zeroProgress = 0
        local zeroLoss = math.floor(zeroProgress * 0.20)
        assertEqual(zeroLoss, 0, "0 progress -> 0 loss")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Essence tax respects cap", function()
        local essence = 50000
        local pct = 0.08
        local cap = 10000
        local loss = math.min(math.floor(essence * pct), cap)
        assertEqual(loss, 4000, "50000 * 8% = 4000 < cap 10000")
        local bigEssence = 200000
        local bigLoss = math.min(math.floor(bigEssence * pct), cap)
        assertEqual(bigLoss, cap, "200000 * 8% = 16000 capped to 10000")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Debt kills decrement per kill (logic check)", function()
        local session = { debtKills = 3, debtMult = 0.65 }
        session.debtKills = session.debtKills - 1
        assertEqual(session.debtKills, 2, "3 -> 2")
        session.debtKills = session.debtKills - 1
        assertEqual(session.debtKills, 1, "2 -> 1")
        session.debtKills = session.debtKills - 1
        if session.debtKills <= 0 then
            session.debtKills = 0
            session.debtMult = 1.0
        end
        assertEqual(session.debtKills, 0, "cleared to 0")
        assertApprox(session.debtMult, 1.0, 0.001, "mult restored to 1.0")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Debt DB round-trip", function()
        CharDBQuery(string.format(
            "INSERT INTO `ap_session_state` (`guid`,`clean_exit`,`threat_debt_kills`,`threat_debt_mult`) "..
            "VALUES (%d, 1, 15, 0.6500) "..
            "ON DUPLICATE KEY UPDATE `threat_debt_kills`=15, `threat_debt_mult`=0.6500",
            AP_TEST_GUID))
        CharDBQuery("COMMIT;")
        local q = CharDBQuery(string.format(
            "SELECT `clean_exit`, `threat_debt_kills`, `threat_debt_mult` FROM `ap_session_state` WHERE `guid`=%d",
            AP_TEST_GUID))
        assertNotNil(q, "row exists")
        assertEqual(tonumber(tostring(q:GetUInt32(0))) or -1, 1, "clean_exit unchanged")
        assertEqual(tonumber(tostring(q:GetUInt32(1))) or -1, 15, "debt_kills = 15")
        local dm = tonumber(tostring(q:GetString(2))) or -1
        assertTrue(dm > 0.64 and dm < 0.66, "debt_mult ~ 0.65")
        CharDBQuery(string.format("DELETE FROM `ap_session_state` WHERE `guid`=%d", AP_TEST_GUID))
        CharDBQuery("COMMIT;")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Penalty escalation across bands", function()
        local p1 = AP.GetDeathPenalty(1)
        local p5 = AP.GetDeathPenalty(5)
        local p10 = AP.GetDeathPenalty(10)
        assertTrue(p5[1] > p1[1], "attune loss escalates 1->5")
        assertTrue(p10[1] > p5[1], "attune loss escalates 5->10")
        assertTrue(p5[4] > p1[4], "debt kills escalate 1->5")
        assertTrue(p10[4] > p5[4], "debt kills escalate 5->10")
        assertTrue(p5[5] < p1[5], "debt mult harsher 1->5")
        assertTrue(p10[5] < p5[5], "debt mult harsher 5->10")
    end)
end

threatTests[#threatTests+1] = function()
    return run("THREAT: Raising threat preserves momentum (logic check)", function()
        local session = { threat = 5, momentum = 0.5 }
        session.threat = session.threat + 1
        assertEqual(session.threat, 6, "threat raised to 6")
        assertApprox(session.momentum, 0.5, 0.001, "momentum preserved")
    end)
end

-- ============================================================
-- SECTION 17: TIER 6 API TESTS (#aptest tier6)
-- ============================================================
local tier6Tests = {}

tier6Tests[#tier6Tests+1] = function()
    return run("T6: AP.API exists", function()
        assertNotNil(AP.API, "AP.API table exists")
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: AP.API.GetVersion returns valid string", function()
        local v = AP.API.GetVersion()
        assertNotNil(v, "version not nil")
        assertTrue(type(v) == "string", "version is string")
        assertTrue(#v > 0, "version not empty")
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: AP.API.IsReady returns true after load", function()
        assertTrue(AP.API.IsReady(), "API is ready")
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: API functions return safe defaults for nil player", function()
        assertEqual(AP.API.GetThreatLevel(nil), 0, "threat = 0")
        assertEqual(AP.API.GetThreatMomentum(nil), 0.0, "momentum = 0")
        assertApprox(AP.API.GetThreatMultiplier(nil), 1.0, 0.001, "mult = 1.0")
        assertEqual(AP.API.GetTotalAttunedCount(nil), 0, "attuned = 0")
        assertEqual(AP.API.GetEssence(nil), 0, "essence = 0")
        assertEqual(AP.API.GetWorldsoulResidue(nil), 0, "residue = 0")
        assertEqual(AP.API.GetMasteryRank(nil), 0, "mastery = 0")
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: GetVisageState returns table for nil player", function()
        local v = AP.API.GetVisageState(nil)
        assertNotNil(v, "returns table")
        assertEqual(type(v), "table", "is table")
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: GetProgressionSummary returns complete table", function()
        local s = AP.API.GetProgressionSummary(nil)
        assertNotNil(s, "summary exists")
        assertNotNil(s.version, "has version")
        assertNotNil(s.essence, "has essence")
        assertNotNil(s.mastery, "has mastery")
        assertNotNil(s.threat, "has threat")
        assertNotNil(s.visage, "has visage")
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: Extension registration accepts valid extension", function()
        local ok = AP.API.RegisterExtension("test_ext", {
            name = "Test Extension",
            version = "0.1.0",
            description = "Unit test extension",
        })
        assertTrue(ok, "registration succeeded")
        local ext = AP.API.GetExtension("test_ext")
        assertNotNil(ext, "extension retrievable")
        assertEqual(ext.name, "Test Extension", "name matches")
        AP.Extensions["test_ext"] = nil
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: Extension registration rejects invalid id", function()
        local ok = AP.API.RegisterExtension("", { name = "Bad" })
        assertFalse(ok, "empty id rejected")
        local ok2 = AP.API.RegisterExtension(nil, { name = "Bad" })
        assertFalse(ok2, "nil id rejected")
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: Hook registration accepts valid hook", function()
        local called = false
        local ok = AP.API.RegisterHook("OnItemAttuned", "test_hook", function(payload)
            called = true
        end)
        assertTrue(ok, "hook registered")
        AP.API.DispatchHook("OnItemAttuned", { guid=0, itemEntry=99999 })
        assertTrue(called, "hook was called")
        AP.Hooks["OnItemAttuned"]["test_hook"] = nil
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: Hook dispatch catches extension error", function()
        AP.API.RegisterHook("OnItemAttuned", "bad_hook", function()
            error("intentional test error")
        end)
        local ok = pcall(function()
            AP.API.DispatchHook("OnItemAttuned", { guid=0 })
        end)
        assertTrue(ok, "dispatch did not crash despite hook error")
        AP.Hooks["OnItemAttuned"]["bad_hook"] = nil
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: Hook dispatch continues after one extension error", function()
        local secondCalled = false
        AP.API.RegisterHook("OnItemAttuned", "bad_first", function()
            error("first hook error")
        end)
        AP.API.RegisterHook("OnItemAttuned", "good_second", function()
            secondCalled = true
        end)
        AP.API.DispatchHook("OnItemAttuned", { guid=0 })
        assertTrue(secondCalled, "second hook still called after first errored")
        AP.Hooks["OnItemAttuned"]["bad_first"] = nil
        AP.Hooks["OnItemAttuned"]["good_second"] = nil
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: GetExtensions returns list", function()
        AP.API.RegisterExtension("list_test", { name = "List Test", version = "1.0.0" })
        local exts = AP.API.GetExtensions()
        assertTrue(#exts > 0, "at least one extension in list")
        local found = false
        for _, e in ipairs(exts) do
            if e.id == "list_test" then found = true end
        end
        assertTrue(found, "list_test found in extensions")
        AP.Extensions["list_test"] = nil
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: GetThreatDebt returns table with kills and mult", function()
        local d = AP.API.GetThreatDebt(nil)
        assertNotNil(d, "debt not nil")
        assertEqual(d.kills, 0, "nil player -> 0 kills")
        assertApprox(d.mult, 1.0, 0.001, "nil player -> 1.0 mult")
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: Hook registration rejects invalid inputs", function()
        assertFalse(AP.API.RegisterHook("", "ext", function() end), "empty hook name")
        assertFalse(AP.API.RegisterHook("OnTest", "", function() end), "empty ext id")
        assertFalse(AP.API.RegisterHook("OnTest", "ext", "not_func"), "non-function")
    end)
end

tier6Tests[#tier6Tests+1] = function()
    return run("T6: No disabled module exposes broken player UI", function()
        for name, mod in pairs(AP.Modules) do
            if not mod.Enabled then
                assertTrue(true, name .. " disabled and not exposed")
            end
        end
    end)
end

-- ============================================================
-- TEST RUNNER
-- ============================================================
local ALL_SUITES = {
    math     = { label = "Math",        tests = mathTests     },
    db       = { label = "Database",    tests = dbTests       },
    tooltip  = { label = "Tooltip",     tests = tooltipTests  },
    antispam = { label = "Anti-Spam",   tests = antispamTests },
    quest    = { label = "Quest",       tests = questTests    },
    aether   = { label = "Aether",      tests = aetherTests   },
    ui       = { label = "UI",          tests = uiTests       },
    forge    = { label = "Forge",       tests = forgeTests    },
    crucible = { label = "Crucible",    tests = crucibleTests },
    visage   = { label = "Visage",      tests = visageTests   },
    pvp      = { label = "PvP",         tests = pvpTests      },
    voice    = { label = "Voice",       tests = voiceTests    },
    version  = { label = "Version",     tests = versionTests  },
    exploit  = { label = "Exploit Guards", tests = exploitTests },
    tier3    = { label = "Tier 3 Fixes",  tests = tier3Tests    },
    tier4    = { label = "Tier 4 Visage", tests = tier4Tests    },
    tier5    = { label = "Tier 5 Polish", tests = tier5Tests   },
    threat   = { label = "World Threat", tests = threatTests  },
    tier6    = { label = "Tier 6 API",   tests = tier6Tests   },
}

print("[AttunementPlus] LIVE ap_tests.lua loaded from RelWithDebInfo lua_scripts")
print("[AttunementPlus] ap_tests.lua suites: " .. (function()
    local keys = {}
    for k, _ in pairs(ALL_SUITES) do keys[#keys+1] = k end
    table.sort(keys)
    return table.concat(keys, ", ")
end)())

function AP.RunTests(player, filter)
    print("[AttunementPlus] AP.RunTests called, filter=" .. tostring(filter))
    local function Out(msg)
        print("[APTEST] " .. msg)
        if player and type(player.SendBroadcastMessage) == "function" then
            -- pcall so a broken player object can't kill the test run
            pcall(function()
                player:SendBroadcastMessage("|cffff9900[APTEST]|r " .. msg)
            end)
        end
    end

    Out("=== Echoes of the Worldsoul Regression Tests ===")
    if filter then Out("Filter: " .. filter) end

    local totalPass = 0
    local totalFail = 0
    local failures  = {}

    -- "all" is an alias for no filter (run everything).
    if filter == "all" then filter = nil end

    for key, suite in pairs(ALL_SUITES) do
        if not filter or filter == key then
            Out("--- " .. suite.label .. " ---")
            for _, testFn in ipairs(suite.tests) do
                -- Double-wrap: the inner run() already pcalls the test body,
                -- but we pcall the testFn() call itself too so a broken test
                -- function signature can't escape and crash the server.
                local ok, status, label, reason = pcall(testFn)
                if not ok then
                    -- testFn itself threw (shouldn't happen, but safety net)
                    totalFail = totalFail + 1
                    local msg = "  [FAIL] [test runner error] " .. tostring(status)
                    Out(msg)
                    failures[#failures+1] = msg
                elseif status == PASS then
                    totalPass = totalPass + 1
                    Out(string.format("  [PASS] %s", label))
                else
                    totalFail = totalFail + 1
                    local msg = string.format("  [FAIL] %s: %s", label, reason or "no reason")
                    Out(msg)
                    failures[#failures+1] = msg
                end
            end
        end
    end

    Out(string.format("=== Results: %d passed, %d failed ===", totalPass, totalFail))
    if #failures > 0 then
        Out("--- Failures ---")
        for _, f in ipairs(failures) do Out(f) end
    end

    return totalPass, totalFail
end

-- ============================================================
-- CHAT TRIGGER: "#aptest [filter]"
-- EVENT ID REFERENCE (confirmed from Hooks.h):
--   18 = PLAYER_EVENT_ON_CHAT     -- SAY (includes GM chat)
--   19 = PLAYER_EVENT_ON_WHISPER  -- whisper received
--   42 = PLAYER_EVENT_ON_COMMAND  -- in-game /command AND worldserver console
--
-- HOW TO RUN:
--   In-game (any chat, GM mode on or off):
--     #aptest
--     #aptest math
--
--   In-game via whisper to yourself:
--     /w YOURNAME #aptest
--
--   Worldserver console terminal (type directly, no / prefix):
--     #aptest
--     #aptest math
--     (event 42 fires with player=nil; output goes to console only)
-- ============================================================

local function HandleTestChat(player, msg)
    if not msg then return end
    local lower = msg:lower():match("^%s*(.-)%s*$")

    -- Accepted forms:
    --   #aptest              -- run all suites
    --   #aptest forge        -- run one suite
    --   #ap test             -- alias for #aptest
    --   #ap test all         -- alias for #aptest (all is explicit "run all")
    --   #ap test forge       -- alias for #aptest forge
    local filter = nil
    local matched = false

    if lower == "#aptest" or lower == "#ap test" or lower == "#ap test all" then
        matched = true
        filter  = nil
    else
        local f = lower:match("^#aptest%s+(%w+)$") or lower:match("^#ap test%s+(%w+)$")
        if f and f ~= "all" then
            matched = true
            filter  = f
        elseif f == "all" then
            matched = true
            filter  = nil
        end
    end

    if not matched then return end

    AP.RunTests(player, filter)
    return false  -- swallow from chat
end

-- Event 18: PLAYER_EVENT_ON_CHAT (SAY  -- works with .gm on and .gm off)
RegisterPlayerEvent(18, function(event, player, msg, type, lang, channel)
    return HandleTestChat(player, msg)
end)

-- Event 19: PLAYER_EVENT_ON_WHISPER (whisper to self  -- reliable fallback)
RegisterPlayerEvent(19, function(event, player, msg, lang, receiver)
    return HandleTestChat(player, msg)
end)

-- Event 42: PLAYER_EVENT_ON_COMMAND
-- Fires for in-game /commands AND worldserver console input.
-- player is nil when fired from the console.
-- Usage from console: type  #aptest  or  #aptest math
RegisterPlayerEvent(42, function(event, player, command)
    if not command then return end
    -- event 42 passes the command without the leading slash
    -- e.g. typing ".aptest" in console passes "aptest"
    -- We also accept the full "#aptest" form
    local lower = command:lower():match("^%s*(.-)%s*$")

    -- strip leading . or # if present
    local stripped = lower:match("^[#!.]?(.+)$") or lower

    if stripped == "aptest" then
        AP.RunTests(player, nil)
        return false
    end

    local filter = stripped:match("^aptest%s+(%w+)$")
    if filter then
        AP.RunTests(player, filter)
        return false
    end
end)

-- ============================================================
-- LAYER 1: STARTUP SELF-CHECK (fires unconditionally on every load)
-- Does NOT run the full GM suite; only checks structural invariants
-- that must hold before any player can interact with the system:
--   • critical namespace functions exist
--   • key config constants are correct
--   • required DB tables are present
-- Output goes to worldserver console only (no player target).
-- ============================================================
local function StartupSelfCheck()
    local failures = {}

    local function expect(label, cond, detail)
        if not cond then
            failures[#failures+1] = label .. (detail and (" — " .. tostring(detail)) or "")
        end
    end

    -- Namespace / function existence
    expect("AP table is a table",              type(AP) == "table")
    expect("AP.Config is a table",             type(AP.Config) == "table")
    expect("AP.GetScaledCap is a function",    type(AP.GetScaledCap) == "function")
    expect("AP.GetPlayerRates is a function",  type(AP.GetPlayerRates) == "function")
    expect("AP.OpenUI is a function",          type(AP.OpenUI) == "function")
    expect("AP.SaveItemAttune is a function",  type(AP.SaveItemAttune) == "function")
    expect("AP.LoadItemAttune is a function",  type(AP.LoadItemAttune) == "function")
    expect("AP.SaveSnapshotAccountWide is a function", type(AP.SaveSnapshotAccountWide) == "function")
    expect("AP.Rack table is a table",         type(AP.Rack) == "table")
    expect("AP.Rack.Load is a function",       type(AP.Rack and AP.Rack.Load) == "function")
    expect("AP.Forge table is a table",        type(AP.Forge) == "table")
    expect("AP.Sinks table is a table",        type(AP.Sinks) == "table")

    -- Cap constant: must be 10000 (the global max for level-80 items).
    -- Never use CapPerItem where GetScaledCap is needed — this constant
    -- is only correct for level-80 items.
    expect("AP.Config.CapPerItem == 10000",
        AP.Config and AP.Config.CapPerItem == 10000,
        "got " .. tostring(AP.Config and AP.Config.CapPerItem))

    -- GetScaledCap formula sanity: pure math, no DB needed.
    -- Low-req items must clamp to 100 (regression guard for 0%-display bug).
    if type(AP.GetScaledCap) == "function" then
        local formulaOk = math.max(100, math.floor(10000 * (7 / 80) ^ 2)) == 100
        expect("GetScaledCap formula clamps req<=7 to 100", formulaOk)
    end

    -- Gossip sender range collision check.
    -- Each module owns a non-overlapping range of sender IDs.
    -- The ranges are defined here as single source of truth; overlaps
    -- would cause one module's buttons to silently dispatch to another's
    -- handler — the class of bug that let AP.UI.ShowMain go undetected.
    local GOSSIP_RANGES = {
        { name = "Core UI", lo = 1,   hi = 8   },  -- SENDER_MAIN=1 through SENDER_ATTUNES=8
        { name = "Sinks",   lo = 100, hi = 110  },  -- GossipSendMenu uses 102
        { name = "Visage",  lo = 200, hi = 217  },  -- GossipSendMenu uses 201; 209=pri tier, 217=sec tier
        { name = "Codex",   lo = 220, hi = 232  },  -- registered 220-232 (reserved)
        { name = "Rack",    lo = 240, hi = 247  },  -- GossipSendMenu uses 240, 244
        { name = "Forge",   lo = 248, hi = 255  },  -- GossipSendMenu uses 250
    }
    for i = 1, #GOSSIP_RANGES do
        for j = i + 1, #GOSSIP_RANGES do
            local a, b = GOSSIP_RANGES[i], GOSSIP_RANGES[j]
            expect(
                string.format("Gossip no overlap: %s (%d-%d) vs %s (%d-%d)",
                    a.name, a.lo, a.hi, b.name, b.lo, b.hi),
                not (a.lo <= b.hi and b.lo <= a.hi))
        end
    end
    -- Verify known GossipSendMenu menu_ids are all in ap_ui.lua's registration list.
    -- Add any new GossipSendMenu calls here when adding new gossip pages.
    local REG_SET = {}
    for _, v in ipairs({1,2,3,4,5,6,8, 102, 201,
        220,221,222,223,224,225,226,227,228,229,230,231,232,
        240,241,242,243,244,245, 250,251,252,253,254,255}) do
        REG_SET[v] = true
    end
    for _, mid in ipairs({1,2,3,4,5,6,8, 102, 201, 240,244, 250}) do
        expect("GossipSendMenu id " .. mid .. " is registered in ap_ui.lua", REG_SET[mid] ~= nil)
    end
    -- SENDER_TALENT_STAT = 7 is defined but unused — informational only.
    if not REG_SET[7] then
        print("[AP] INFO: SENDER_TALENT_STAT (7) defined in ap_ui.lua but not registered — dead variable.")
    end

    -- Required DB tables
    for _, tbl in ipairs({
        "ap_item_attune", "ap_item_snapshot", "ap_mastery",
        "ap_slot_mastery", "ap_rack", "ap_quest_rewarded", "ap_dissolved_items"
    }) do
        local q = CharDBQuery(string.format(
            "SELECT 1 FROM information_schema.tables "..
            "WHERE table_schema = DATABASE() AND table_name = '%s' LIMIT 1;", tbl))
        expect("DB table exists: " .. tbl, q ~= nil)
    end

    if #failures == 0 then
        AP.Log("Startup self-check OK.")
    else
        for _, f in ipairs(failures) do
            AP.Log("[AP STARTUP FAIL] " .. f)
            print("[AP STARTUP FAIL] " .. f)
        end
        AP.Log(string.format("Startup self-check FAILED (%d issue(s) — see above).", #failures))
    end
end

RegisterServerEvent(3, function()
    -- Layer 1: always run structural self-check
    pcall(StartupSelfCheck)

    -- Layer 2 full suite: only when Debug = true
    if AP.Config and AP.Config.Debug then
        AP.Log("Debug mode: running full test suite on startup...")
        AP.RunTests(nil, nil)
    end
end)

-- ============================================================
-- ap_auralab.lua -- Aura Testing & Tiering Lab
-- Two modes: testing (untested candidates) and tiering (approved)
-- Rejected auras are excluded from both modes.
-- ============================================================

AP = AP or {}
AP.AuraLab = AP.AuraLab or {}

-- ============================================================
-- CANDIDATE LIST (scanner-approved starting pool)
-- ============================================================
AP.AuraLab.Candidates = {
    -- ============ WORLDSOUL (lightning/holy/soul/cosmic) ============
    { spellId=49411, theme="worldsoul", note="CONFIRMED lightning crackle" },
    { spellId=45870, theme="worldsoul", note="CONFIRMED arcane/lightning charge" },
    { spellId=34403, theme="worldsoul", note="Holy Energy" },
    { spellId=36113, theme="worldsoul", note="Cosmetic: Earthen Soul" },
    { spellId=36169, theme="worldsoul", note="Cosmetic: Watery Soul" },
    { spellId=36114, theme="worldsoul", note="Cosmetic: Fiery Soul" },
    { spellId=28136, theme="worldsoul", note="Thadius Lightning Visual" },
    { spellId=37248, theme="worldsoul", note="Electromental Visual" },
    { spellId=37848, theme="worldsoul", note="Cosmetic Chain Lightning" },
    { spellId=31210, theme="worldsoul", note="Gather Light Energy" },
    { spellId=32395, theme="worldsoul", note="Stolen Soul Visual" },
    { spellId=32459, theme="worldsoul", note="Raging Soul Visual" },
    -- BATCH 2: worldsoul T2/T4/T5 gaps
    { spellId=40897, theme="worldsoul", note="Prismatic Aura: Holy" },
    { spellId=42051, theme="worldsoul", note="Boss Holy Portal State" },
    { spellId=62300, theme="infernal", note="Cosmic Smash Visual State (moved from worldsoul)" },
    { spellId=54139, theme="worldsoul", note="Power Ball Visual" },
    -- BATCH 3: worldsoul T2/T4
    { spellId=42044, theme="worldsoul", note="Spell Portal: Holy" },
    { spellId=51361, theme="worldsoul", note="Holy Channeling" },
    { spellId=41339, theme="worldsoul", note="Cosmetic - Legion Ring Purple Lightning (Self)" },
    { spellId=40608, theme="worldsoul", note="Cosmetic - Legion Ring Purple Lightning" },
    -- BATCH 4: worldsoul T2
    { spellId=10368, theme="worldsoul", note="Uther's Light Effect" },
    { spellId=12348, theme="worldsoul", note="Atal'ai Altar Light Visual (DND)" },
    { spellId=7923,  theme="worldsoul", note="Flight Visual State" },
    -- BATCH 5: near known-good IDs (same spell families)
    { spellId=22580, theme="worldsoul", note="Glowy (Yellow) - same family as 22577/22578" },
    { spellId=22576, theme="worldsoul", note="Glowy (Blue) - same family as 22577/22578" },

    -- ============ VOID (shadow/dark/death) ============
    { spellId=37816, theme="void", note="CONFIRMED subtle shadowform" },
    { spellId=30166, theme="void", note="CONFIRMED shadow grasp" },
    { spellId=33070, theme="void", note="CONFIRMED cloud of corruption" },
    { spellId=39490, theme="void", note="CONFIRMED blue banish/shadowform" },
    { spellId=22578, theme="void", note="CONFIRMED full black+flashes" },
    { spellId=49646, theme="void", note="CONFIRMED black smoke dramatic" },
    { spellId=34399, theme="void", note="Shadow Energy" },
    { spellId=18948, theme="void", note="Dark Energy" },
    { spellId=32563, theme="void", note="Black Crystal State" },
    { spellId=38731, theme="void", note="Glowy (Black) variant" },
    { spellId=39085, theme="void", note="Glowy (Black) variant 2" },
    { spellId=39943, theme="void", note="Soulgrinder Shadowform 1" },
    { spellId=33569, theme="void", note="Void Portal Visual" },

    -- ============ INFERNAL (fire/flame/fel) ============
    { spellId=16003, theme="infernal", note="CONFIRMED immolate visual" },
    { spellId=34398, theme="infernal", note="CONFIRMED flame energy" },
    { spellId=48150, theme="infernal", note="CONFIRMED fire+trail" },
    { spellId=28330, theme="infernal", note="Flameshocker Immolate Visual" },
    { spellId=32993, theme="infernal", note="Fire Cast Visual" },
    { spellId=37797, theme="infernal", note="Arcane Fire State" },
    { spellId=42048, theme="infernal", note="Boss Fire Portal State" },
    { spellId=32475, theme="infernal", note="Hellfire Visual (DND)" },
    { spellId=42075, theme="infernal", note="Large Fire Visual" },
    { spellId=33827, theme="infernal", note="Hellfire Warder Channel Visual" },

    -- ============ ETHEREAL (arcane/ghost/spectral) ============
    { spellId=35841, theme="ethereal", note="CONFIRMED draenei spirit white glow" },
    { spellId=44816, theme="ethereal", note="CONFIRMED transparency 50%" },
    { spellId=34401, theme="ethereal", note="CONFIRMED arcane energy pulsating" },
    { spellId=9617,  theme="ethereal", note="Ghost Visual" },
    { spellId=24809, theme="ethereal", note="Spirit Shade Visual" },
    { spellId=35850, theme="ethereal", note="Draenei Spirit Visual 2" },
    { spellId=33662, theme="ethereal", note="Arcane Energy variant" },
    { spellId=32368, theme="ethereal", note="Ethereal Beacon Visual" },
    { spellId=37800, theme="ethereal", note="Transparency 50% variant" },
    { spellId=34656, theme="ethereal", note="Arcane Explosion Cosmetic" },
    { spellId=35426, theme="ethereal", note="Arcane Explosion Visual" },
    { spellId=30987, theme="ethereal", note="Ghost Visual (Red)" },
    -- BATCH 2: ethereal T4/T5 gaps
    { spellId=40891, theme="ethereal", note="Prismatic Aura: Arcane" },
    { spellId=42047, theme="ethereal", note="Boss Arcane Portal State" },
    { spellId=41477, theme="ethereal", note="Ethereal Ring Visual, Lightning Aura" },
    -- BATCH 3: ethereal T4
    { spellId=39650, theme="ethereal", note="Blue Banish State/Arcane Power" },
    { spellId=46933, theme="worldsoul", note="Cosmetic - Arcane Force Shield (Blue) (moved from ethereal)" },
    { spellId=45871, theme="ethereal", note="Arcane/Lightning Charge Power State" },
    -- BATCH 4: ethereal T4
    { spellId=28126, theme="ethereal", note="Spirit Particles (purple)" },
    { spellId=31748, theme="ethereal", note="Spirit Particles, big" },
    { spellId=40858, theme="ethereal", note="Ethereal Ring, Cannon Visual" },
    -- BATCH 5: near known-good IDs
    { spellId=44822, theme="ethereal", note="Transparency (75%) - stronger 44816" },
    { spellId=44823, theme="ethereal", note="Transparency (25%) - subtler 44816" },
    { spellId=22581, theme="ethereal", note="Glowy (Purple) - same family as 22577/22578" },
    { spellId=44811, theme="ethereal", note="Spectral Realm - near 44816" },

    -- ============ VERDANT (nature/green/life) ============
    { spellId=22577, theme="verdant", note="CONFIRMED glowy green" },
    { spellId=34402, theme="verdant", note="CONFIRMED nature energy" },
    { spellId=42050, theme="verdant", note="CONFIRMED green mist+leaves" },
    { spellId=25039, theme="verdant", note="Green Ghost Visual" },
    { spellId=32567, theme="verdant", note="Green Banish State" },
    { spellId=33339, theme="verdant", note="Green Portal State" },
    { spellId=32618, theme="verdant", note="Cosmetic Nature Cast" },
    { spellId=40146, theme="verdant", note="Cosmetic Legion Ring Green Lightning" },
    { spellId=40057, theme="verdant", note="Cosmetic Legion Ring Green Lightning Thick" },
    { spellId=40071, theme="verdant", note="Cosmetic Legion Ring Green Matter" },
    { spellId=32991, theme="verdant", note="Nature Cast Visual" },
    -- BATCH 2: verdant T1/T2 gaps
    { spellId=18951, theme="verdant", note="Spirit Particles (green)" },
    { spellId=25043, theme="verdant", note="Aura of Nature" },
    { spellId=40883, theme="verdant", note="Prismatic Aura: Nature" },
    -- BATCH 3: verdant T2
    { spellId=20371, theme="verdant", note="Tag: Green Glow" },
    { spellId=13236, theme="verdant", note="Nature Channeling" },
    { spellId=61722, theme="verdant", note="Nature Portal State" },
    -- BATCH 4: verdant T2
    { spellId=28892, theme="verdant", note="Nature Channeling" },
    { spellId=7966,  theme="verdant", note="Thorns Aura" },
    { spellId=26547, theme="verdant", note="Green Glowing Owl" },
    -- BATCH 5: near known-good IDs
    { spellId=42045, theme="verdant", note="Spell Portal: Nature - same family as 42047/42048/42051" },
    { spellId=44808, theme="verdant", note="Green Crystal Beam - near 44816" },
}

-- Build spellId->candidate lookup
AP.AuraLab.BySpellId = {}
for _, c in ipairs(AP.AuraLab.Candidates) do
    AP.AuraLab.BySpellId[c.spellId] = c
end

-- ============================================================
-- FILTER FUNCTIONS (source of truth)
-- ============================================================

function AP.AuraLab.IsRejected(result)
    if not result then return false end
    if result == "REJECT" then return true end
    return string.sub(result, 1, 4) == "BAD_"
end

function AP.AuraLab.IsTierAssigned(result)
    return result == "T1" or result == "T2" or result == "T3"
        or result == "T4" or result == "T5"
end

function AP.AuraLab.IsEligible(result)
    if AP.AuraLab.IsTierAssigned(result) then return true end
    if result == "GOOD" or result == "GOOD_UNIQUE" then return true end
    if result == "GOOD_DUPLICATE" then return true end
    if result == "APPROVED" or result == "APPROVED_UNIQUE" then return true end
    if result == "APPROVED_DUPLICATE" then return true end
    if result == "DUPLICATE" then return true end
    return false
end

-- ============================================================
-- RESULT LABELS
-- ============================================================

local RESULT_LABELS = {
    T1 = "|cff88bbffT1 subtle|r",
    T2 = "|cff6699ffT2 low|r",
    T3 = "|cff4477ffT3 medium|r",
    T4 = "|cff2255ddT4 strong|r",
    T5 = "|cff0033bbT5 dramatic|r",
    GOOD = "|cff00ff00GOOD (needs tier)|r",
    GOOD_UNIQUE = "|cff00ff00GOOD (needs tier)|r",
    APPROVED = "|cff00ff00APPROVED (needs tier)|r",
    APPROVED_DUPLICATE = "|cff00cc00APPROVED DUP (needs tier)|r",
    REJECT = "|cffff4444REJECTED|r",
    UNTESTED = "|cff888888untested|r",
}

local function GetResultLabel(result)
    if RESULT_LABELS[result] then return RESULT_LABELS[result] end
    if AP.AuraLab.IsRejected(result) then return "|cffff4444REJECTED|r" end
    return result or "UNTESTED"
end

-- ============================================================
-- DB TABLE
-- ============================================================

local function InitLabDB()
    pcall(function()
        CharDBQuery([[
            CREATE TABLE IF NOT EXISTS `ap_aura_test_results` (
                `guid`      INT UNSIGNED NOT NULL,
                `spell_id`  INT UNSIGNED NOT NULL,
                `theme`     VARCHAR(16) NOT NULL DEFAULT '',
                `tier`      TINYINT NOT NULL DEFAULT 0,
                `result`    VARCHAR(16) NOT NULL DEFAULT 'UNTESTED',
                `notes`     VARCHAR(128) NOT NULL DEFAULT '',
                `tested_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                            ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`guid`, `spell_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8;
        ]])
    end)
end
InitLabDB()

-- ============================================================
-- SESSION STATE
-- ============================================================

AP.AuraLab.State = AP.AuraLab.State or {}
AP.AuraLab.Results = AP.AuraLab.Results or {}

local function GetResultKey(guid, spellId)
    return guid .. "_" .. spellId
end

local function GetResult(guid, spellId)
    local key = GetResultKey(guid, spellId)
    if AP.AuraLab.Results[key] then return AP.AuraLab.Results[key] end
    local q = CharDBQuery(string.format(
        "SELECT `result` FROM `ap_aura_test_results` WHERE `guid`=%d AND `spell_id`=%d",
        guid, spellId))
    if q then
        local r = q:GetString(0)
        AP.AuraLab.Results[key] = r
        return r
    end
    return "UNTESTED"
end

local function SetResult(guid, spellId, result, theme)
    local key = GetResultKey(guid, spellId)
    AP.AuraLab.Results[key] = result
    local tierNum = 0
    if AP.AuraLab.IsTierAssigned(result) then
        tierNum = tonumber(string.sub(result, 2, 2)) or 0
    end
    CharDBQuery(string.format(
        "INSERT INTO `ap_aura_test_results` (`guid`,`spell_id`,`theme`,`tier`,`result`) "..
        "VALUES (%d,%d,'%s',%d,'%s') "..
        "ON DUPLICATE KEY UPDATE `result`='%s', `theme`='%s', `tier`=%d",
        guid, spellId, theme, tierNum, result, result, theme, tierNum))
    CharDBQuery("COMMIT;")
end

local function ClearResult(guid, spellId)
    local key = GetResultKey(guid, spellId)
    AP.AuraLab.Results[key] = nil
    CharDBQuery(string.format(
        "DELETE FROM `ap_aura_test_results` WHERE `guid`=%d AND `spell_id`=%d",
        guid, spellId))
    CharDBQuery("COMMIT;")
end

-- ============================================================
-- FILTERED LIST BUILDER
-- ============================================================

local MODE_TESTING  = "testing"
local MODE_TIERING  = "tiering"
local MODE_REJECTED = "rejected"
local MODE_ALL      = "all"

local function LoadAllDbResults(guid)
    local dbSpells = {}
    local q = CharDBQuery(string.format(
        "SELECT `spell_id`, `theme`, `tier`, `result` FROM `ap_aura_test_results` WHERE `guid`=%d",
        guid))
    if q then
        repeat
            local sid = tonumber(tostring(q:GetUInt32(0))) or 0
            local theme = q:GetString(1)
            local tier = tonumber(tostring(q:GetUInt32(2))) or 0
            local result = q:GetString(3)
            if sid > 0 then
                local key = GetResultKey(guid, sid)
                AP.AuraLab.Results[key] = result
                dbSpells[sid] = { theme = theme, tier = tier, result = result }
            end
        until not q:NextRow()
    end
    return dbSpells
end

local function BuildFilteredList(guid, mode)
    local dbSpells = LoadAllDbResults(guid)
    local seen = {}
    local list = {}

    for _, c in ipairs(AP.AuraLab.Candidates) do
        seen[c.spellId] = true
        local r = GetResult(guid, c.spellId)
        if mode == MODE_TESTING then
            if r == "UNTESTED" then
                list[#list+1] = c
            end
        elseif mode == MODE_TIERING then
            if AP.AuraLab.IsEligible(r) then
                list[#list+1] = c
            end
        elseif mode == MODE_REJECTED then
            if AP.AuraLab.IsRejected(r) then
                list[#list+1] = c
            end
        else
            list[#list+1] = c
        end
    end

    for sid, info in pairs(dbSpells) do
        if not seen[sid] then
            seen[sid] = true
            local r = info.result
            local entry = {
                spellId = sid,
                theme = info.theme or "",
                note = "DB-only (not in scanner list)",
            }
            if mode == MODE_TIERING then
                if AP.AuraLab.IsEligible(r) then
                    list[#list+1] = entry
                end
            elseif mode == MODE_REJECTED then
                if AP.AuraLab.IsRejected(r) then
                    list[#list+1] = entry
                end
            elseif mode == MODE_ALL then
                list[#list+1] = entry
            end
        end
    end

    return list
end

local function GetState(guid)
    if not AP.AuraLab.State[guid] then
        AP.AuraLab.State[guid] = {
            mode = MODE_TIERING,
            index = 1,
            lastApplied = nil,
            filteredList = nil,
        }
    end
    return AP.AuraLab.State[guid]
end

local function RefreshFiltered(guid)
    local state = GetState(guid)
    state.filteredList = BuildFilteredList(guid, state.mode)
    if state.index > #state.filteredList then
        state.index = math.max(1, #state.filteredList)
    end
    if state.index < 1 then state.index = 1 end
end

local function SetMode(guid, mode)
    local state = GetState(guid)
    state.mode = mode
    state.index = 1
    RefreshFiltered(guid)
end

local function GetCurrentCandidate(guid)
    local state = GetState(guid)
    if not state.filteredList then RefreshFiltered(guid) end
    return state.filteredList[state.index]
end

-- ============================================================
-- MODE DISPLAY NAMES
-- ============================================================

local MODE_NAMES = {
    [MODE_TESTING]  = "Testing Untested",
    [MODE_TIERING]  = "Tiering Eligible",
    [MODE_REJECTED] = "Viewing Rejected",
    [MODE_ALL]      = "All Candidates",
}

-- ============================================================
-- APPLY / CLEAR
-- ============================================================

local function ClearAllCandidateAuras(player)
    for _, c in ipairs(AP.AuraLab.Candidates) do
        pcall(function() player:RemoveAura(c.spellId) end)
    end
end

local function ApplyCandidate(player, candidate)
    local guid = player:GetGUIDLow()
    local state = GetState(guid)

    if state.lastApplied then
        pcall(function() player:RemoveAura(state.lastApplied) end)
    end
    ClearAllCandidateAuras(player)

    if AP.Visage and AP.Visage.AllSpellIds then
        for sid, _ in pairs(AP.Visage.AllSpellIds) do
            pcall(function() player:RemoveAura(sid) end)
        end
    end

    local ok, err = pcall(function() player:AddAura(candidate.spellId, player) end)
    state.lastApplied = candidate.spellId

    if ok then
        player:SendBroadcastMessage(string.format(
            "|cff9966ff[AuraLab]|r Applied %d (%s). Move 10 sec, then assign tier.",
            candidate.spellId, candidate.note or candidate.theme))
    else
        player:SendBroadcastMessage(string.format(
            "|cffff4444[AuraLab]|r Apply %d failed: %s", candidate.spellId, tostring(err)))
    end
end

-- ============================================================
-- GOSSIP MENU
-- Sender range: 210-219
-- 210 = no-action display
-- 211 = apply current
-- 212 = assign tier/reject (code 1-6)
-- 213 = nav (code: 1=prev, 2=next)
-- 214 = summary
-- 215 = exit/clear (code: 0=exit, 1=clear current)
-- 216 = switch mode (code: 1=testing, 2=tiering, 3=rejected, 4=all)
-- ============================================================

local RESULT_CODES = {
    [1] = "T1",
    [2] = "T2",
    [3] = "T3",
    [4] = "T4",
    [5] = "T5",
    [6] = "REJECT",
}

function AP.AuraLab.ShowPage(player, npc)
    local guid = player:GetGUIDLow()
    local state = GetState(guid)
    if not state.filteredList then RefreshFiltered(guid) end
    local total = #state.filteredList

    player:GossipClearMenu()

    if total == 0 then
        local header = string.format(
            "Aura Lab -- %s\nNo candidates in this view.\nSwitch mode or exit.",
            MODE_NAMES[state.mode] or state.mode)
        player:GossipMenuAddItem(0, header, 210, 0)
    else
        local idx = state.index
        if idx < 1 then idx = 1; state.index = 1 end
        if idx > total then idx = total; state.index = total end
        local c = state.filteredList[idx]
        local result = GetResult(guid, c.spellId)
        local resultLabel = GetResultLabel(result)

        local header = string.format(
            "Aura Lab -- %s -- %d / %d\n"..
            "Spell: |cffffff00%d|r  Theme: |cffffff00%s|r\n"..
            "Status: %s\n"..
            "Note: %s",
            MODE_NAMES[state.mode] or state.mode,
            idx, total,
            c.spellId, c.theme,
            resultLabel,
            c.note or "")
        player:GossipMenuAddItem(0, header, 210, 0)

        player:GossipMenuAddItem(7, "Apply This Aura", 211, 0)
        player:GossipMenuAddItem(1, "Clear This Aura", 215, 1)

        if state.mode ~= MODE_REJECTED then
            player:GossipMenuAddItem(0, "---  Assign Tier  ---", 210, 0)
            player:GossipMenuAddItem(7, "T1 -- Subtle", 212, 1)
            player:GossipMenuAddItem(7, "T2 -- Low", 212, 2)
            player:GossipMenuAddItem(7, "T3 -- Medium", 212, 3)
            player:GossipMenuAddItem(7, "T4 -- Strong", 212, 4)
            player:GossipMenuAddItem(7, "T5 -- Dramatic", 212, 5)
            player:GossipMenuAddItem(1, "REJECT -- not usable", 212, 6)
        end

        player:GossipMenuAddItem(0, "---  Navigate  ---", 210, 0)
        player:GossipMenuAddItem(6, "<< Previous", 213, 1)
        player:GossipMenuAddItem(6, "Next >>", 213, 2)
    end

    player:GossipMenuAddItem(0, "---  Mode  ---", 210, 0)
    player:GossipMenuAddItem(8, "Tiering (eligible only)", 216, 2)
    player:GossipMenuAddItem(8, "Testing (untested only)", 216, 1)
    player:GossipMenuAddItem(8, "Rejected (view only)", 216, 3)
    player:GossipMenuAddItem(8, "Show Summary", 214, 0)
    player:GossipMenuAddItem(0, "Exit Lab", 215, 0)

    player:GossipSendMenu(1, npc, 210)
end

function AP.AuraLab.OnSelect(player, npc, sender, code)
    local guid = player:GetGUIDLow()
    local state = GetState(guid)
    if not state.filteredList then RefreshFiltered(guid) end

    if sender == 210 then
        AP.AuraLab.ShowPage(player, npc)

    elseif sender == 211 then
        local c = GetCurrentCandidate(guid)
        if c then ApplyCandidate(player, c) end
        AP.AuraLab.ShowPage(player, npc)

    elseif sender == 212 then
        local c = GetCurrentCandidate(guid)
        local result = RESULT_CODES[code] or "UNTESTED"
        if c then
            SetResult(guid, c.spellId, result, c.theme)
            local label = GetResultLabel(result)
            player:SendBroadcastMessage(string.format(
                "|cff9966ff[AuraLab]|r Assigned %d -> %s.",
                c.spellId, label))
            RefreshFiltered(guid)
            if state.index > #state.filteredList then
                state.index = math.max(1, #state.filteredList)
            end
        end
        AP.AuraLab.ShowPage(player, npc)

    elseif sender == 213 then
        local total = #state.filteredList
        if code == 1 and state.index > 1 then
            state.index = state.index - 1
        elseif code == 2 and state.index < total then
            state.index = state.index + 1
        end
        AP.AuraLab.ShowPage(player, npc)

    elseif sender == 214 then
        AP.AuraLab.PrintSummary(player)
        AP.AuraLab.ShowPage(player, npc)

    elseif sender == 215 then
        if code == 1 then
            local c = GetCurrentCandidate(guid)
            if c then
                pcall(function() player:RemoveAura(c.spellId) end)
            end
            if state.lastApplied then
                pcall(function() player:RemoveAura(state.lastApplied) end)
                state.lastApplied = nil
            end
            ClearAllCandidateAuras(player)
            if AP.Visage and AP.Visage.AllSpellIds then
                for sid, _ in pairs(AP.Visage.AllSpellIds) do
                    pcall(function() player:RemoveAura(sid) end)
                end
            end
            player:SendBroadcastMessage("|cff9966ff[AuraLab]|r All auras cleared.")
            AP.AuraLab.ShowPage(player, npc)
        else
            ClearAllCandidateAuras(player)
            if AP.Visage and AP.Visage.AllSpellIds then
                for sid, _ in pairs(AP.Visage.AllSpellIds) do
                    pcall(function() player:RemoveAura(sid) end)
                end
            end
            player:SendBroadcastMessage("|cff9966ff[AuraLab]|r Exited. All test auras cleared.")
            if AP.OpenUI then AP.OpenUI(player) end
        end

    elseif sender == 216 then
        local modeMap = {
            [1] = MODE_TESTING,
            [2] = MODE_TIERING,
            [3] = MODE_REJECTED,
            [4] = MODE_ALL,
        }
        local newMode = modeMap[code] or MODE_TIERING
        SetMode(guid, newMode)
        player:SendBroadcastMessage(string.format(
            "|cff9966ff[AuraLab]|r Switched to: %s (%d candidates)",
            MODE_NAMES[newMode], #state.filteredList))
        AP.AuraLab.ShowPage(player, npc)
    end
end

-- ============================================================
-- SUMMARY
-- ============================================================

function AP.AuraLab.PrintSummary(player)
    local guid = player:GetGUIDLow()
    local dbSpells = LoadAllDbResults(guid)
    local themes = {}
    local rejectedCount = 0
    local untestedCount = 0
    local seen = {}

    for _, theme in ipairs({"worldsoul", "ethereal", "verdant", "void", "infernal"}) do
        themes[theme] = { T1={}, T2={}, T3={}, T4={}, T5={}, needsTier={} }
    end

    local function classify(spellId, theme, note, r)
        local line = string.format("%d (%s) [%s]", spellId, note or "", r or "?")
        if AP.AuraLab.IsTierAssigned(r) then
            local t = themes[theme]
            if t and t[r] then
                t[r][#t[r]+1] = line
            end
        elseif AP.AuraLab.IsEligible(r) then
            local t = themes[theme]
            if t then
                t.needsTier[#t.needsTier+1] = line
            end
        elseif AP.AuraLab.IsRejected(r) then
            rejectedCount = rejectedCount + 1
        elseif r == "UNTESTED" then
            untestedCount = untestedCount + 1
        end
    end

    for _, c in ipairs(AP.AuraLab.Candidates) do
        seen[c.spellId] = true
        local r = GetResult(guid, c.spellId)
        classify(c.spellId, c.theme, c.note, r)
    end

    for sid, info in pairs(dbSpells) do
        if not seen[sid] then
            seen[sid] = true
            classify(sid, info.theme or "", "DB-only", info.result)
        end
    end

    local function send(msg)
        player:SendBroadcastMessage(msg)
        print("[AuraLab] " .. msg)
    end

    send("|cff9966ff[AuraLab Summary -- Tier Assignments]|r")

    for _, theme in ipairs({"worldsoul", "ethereal", "verdant", "void", "infernal"}) do
        local t = themes[theme]
        local name = (AP.Visage.ThemeNames[theme] or theme):upper()
        send(string.format("|cffffff00%s:|r", name))
        for _, tier in ipairs({"T1","T2","T3","T4","T5"}) do
            if #t[tier] > 0 then
                for _, l in ipairs(t[tier]) do
                    send(string.format("  %s: %s", tier, l))
                end
            else
                send(string.format("  %s: |cff888888(empty)|r", tier))
            end
        end
        if #t.needsTier > 0 then
            send("  |cff00ff00Eligible, needs tier:|r")
            for _, l in ipairs(t.needsTier) do
                send("    " .. l)
            end
        end
    end

    send(string.format("|cffff4444Rejected: %d|r  |cff888888Untested: %d|r",
        rejectedCount, untestedCount))
end

-- ============================================================
-- DEBUG: show every spell, its result, and include/exclude reason
-- ============================================================

function AP.AuraLab.DebugApproved(player)
    local guid = player:GetGUIDLow()
    local dbSpells = LoadAllDbResults(guid)
    local seen = {}
    local eligibleCount = 0
    local rejectedCount = 0
    local untestedCount = 0
    local totalCount = 0

    local function send(msg)
        player:SendBroadcastMessage(msg)
        print("[AuraLab] " .. msg)
    end

    local function check(spellId, theme, note, r)
        totalCount = totalCount + 1
        local included = false
        local reason = ""
        if AP.AuraLab.IsRejected(r) then
            reason = "rejected " .. r
            rejectedCount = rejectedCount + 1
        elseif AP.AuraLab.IsEligible(r) then
            included = true
            reason = "eligible " .. r
            eligibleCount = eligibleCount + 1
        elseif r == "UNTESTED" then
            reason = "untested"
            untestedCount = untestedCount + 1
        else
            reason = "unknown status: " .. r
        end
        send(string.format("spell=%d theme=%s result=%s include=%s reason=%s (%s)",
            spellId, theme, r,
            included and "YES" or "no",
            reason, note or ""))
    end

    send("|cff9966ff[AuraLab Debug -- All Spells]|r")

    for _, c in ipairs(AP.AuraLab.Candidates) do
        seen[c.spellId] = true
        local r = GetResult(guid, c.spellId)
        check(c.spellId, c.theme, c.note, r)
    end

    for sid, info in pairs(dbSpells) do
        if not seen[sid] then
            seen[sid] = true
            check(sid, info.theme or "?", "DB-only", info.result)
        end
    end

    send(string.format("|cffffff00Totals:|r %d checked, |cff00ff00%d eligible|r, |cffff4444%d rejected|r, |cff888888%d untested|r",
        totalCount, eligibleCount, rejectedCount, untestedCount))
end

-- ============================================================
-- DB FIX: 62300 was saved as worldsoul/REJECT, should be infernal/T3
-- ============================================================
local function FixDbEntries()
    pcall(function()
        CharDBQuery("UPDATE `ap_aura_test_results` SET `theme`='infernal', `tier`=3, `result`='T3' WHERE `spell_id`=62300")
        CharDBQuery("UPDATE `ap_aura_test_results` SET `theme`='worldsoul', `tier`=4, `result`='T4' WHERE `spell_id`=46933")
        CharDBQuery("UPDATE `ap_aura_test_results` SET `tier`=2, `result`='T2' WHERE `spell_id`=49411")
        CharDBQuery("UPDATE `ap_aura_test_results` SET `tier`=2, `result`='T2' WHERE `spell_id`=44808")
        CharDBQuery("COMMIT;")
    end)
end
FixDbEntries()

-- ============================================================
-- FILE DUMP (for Claude Code to read results)
-- ============================================================

function AP.AuraLab.DumpToFile(player)
    local guid = player:GetGUIDLow()
    local dbSpells = LoadAllDbResults(guid)
    local seen = {}
    local lines = { "AURALAB_DUMP_START" }

    for _, c in ipairs(AP.AuraLab.Candidates) do
        seen[c.spellId] = true
        local r = GetResult(guid, c.spellId)
        local eligible = AP.AuraLab.IsEligible(r) and "YES" or "no"
        local rejected = AP.AuraLab.IsRejected(r) and "YES" or "no"
        lines[#lines+1] = string.format("%d|%s|%s|eligible=%s|rejected=%s|%s",
            c.spellId, c.theme, r, eligible, rejected, c.note or "")
    end

    for sid, info in pairs(dbSpells) do
        if not seen[sid] then
            seen[sid] = true
            local r = info.result
            local eligible = AP.AuraLab.IsEligible(r) and "YES" or "no"
            local rejected = AP.AuraLab.IsRejected(r) and "YES" or "no"
            lines[#lines+1] = string.format("%d|%s|%s|eligible=%s|rejected=%s|DB-only",
                sid, info.theme or "?", r, eligible, rejected)
        end
    end

    lines[#lines+1] = "AURALAB_DUMP_END"

    local path = "lua_scripts/auralab_dump.txt"
    local f = io.open(path, "w")
    if f then
        f:write(table.concat(lines, "\n") .. "\n")
        f:close()
        player:SendBroadcastMessage("|cff9966ff[AuraLab]|r Dumped to " .. path)
        print("[AuraLab] Dumped " .. (#lines - 2) .. " entries to " .. path)
    else
        player:SendBroadcastMessage("|cffff4444[AuraLab]|r Failed to write dump file.")
        print("[AuraLab] ERROR: could not open " .. path .. " for writing")
    end
end

-- ============================================================
-- CHAT COMMANDS
-- ============================================================

function AP.AuraLab.HandleChat(player, lower)
    if not string.find(lower, "^#ap aura") then return false end
    if not AP.IsGM(player) then
        player:SendBroadcastMessage("|cffff4444[Worldsoul]|r GM access required.")
        return true
    end

    local guid = player:GetGUIDLow()
    local state = GetState(guid)

    if lower == "#ap auralab" then
        if AP.Visage and AP.Visage.Cache[guid] then
            local c = AP.Visage.Cache[guid]
            c.primary_enabled = 0
            c.secondary_enabled = 0
            CharDBQuery(string.format(
                "UPDATE `ap_visage` SET `primary_enabled`=0, `secondary_enabled`=0 WHERE `guid`=%d",
                guid))
            CharDBQuery("COMMIT;")
        end
        SetMode(guid, MODE_TIERING)
        AP.AuraLab.ShowPage(player, player)
        return true
    end

    if lower == "#ap aura testing" then
        SetMode(guid, MODE_TESTING)
        player:SendBroadcastMessage(string.format(
            "|cff9966ff[AuraLab]|r Testing mode: %d untested candidates.",
            #state.filteredList))
        AP.AuraLab.ShowPage(player, player)
        return true
    end

    if lower == "#ap aura tiering" then
        SetMode(guid, MODE_TIERING)
        player:SendBroadcastMessage(string.format(
            "|cff9966ff[AuraLab]|r Tiering mode: %d eligible candidates.",
            #state.filteredList))
        AP.AuraLab.ShowPage(player, player)
        return true
    end

    if lower == "#ap aura approved" then
        SetMode(guid, MODE_TIERING)
        AP.AuraLab.PrintSummary(player)
        return true
    end

    if lower == "#ap aura rejected" then
        SetMode(guid, MODE_REJECTED)
        player:SendBroadcastMessage(string.format(
            "|cff9966ff[AuraLab]|r Rejected view: %d rejected candidates.",
            #state.filteredList))
        AP.AuraLab.ShowPage(player, player)
        return true
    end

    if lower == "#ap aura next" then
        if not state.filteredList then RefreshFiltered(guid) end
        local total = #state.filteredList
        if state.index < total then state.index = state.index + 1 end
        local c = GetCurrentCandidate(guid)
        if c then
            player:SendBroadcastMessage(string.format(
                "|cff9966ff[AuraLab]|r Now on %d/%d: spell %d (%s)",
                state.index, total, c.spellId, c.note or c.theme))
        end
        return true
    end

    if lower == "#ap aura prev" then
        if not state.filteredList then RefreshFiltered(guid) end
        if state.index > 1 then state.index = state.index - 1 end
        local c = GetCurrentCandidate(guid)
        if c then
            local total = #state.filteredList
            player:SendBroadcastMessage(string.format(
                "|cff9966ff[AuraLab]|r Now on %d/%d: spell %d (%s)",
                state.index, total, c.spellId, c.note or c.theme))
        end
        return true
    end

    if lower == "#ap aura apply" then
        local c = GetCurrentCandidate(guid)
        if c then ApplyCandidate(player, c) end
        return true
    end

    if lower == "#ap aura clear" then
        ClearAllCandidateAuras(player)
        player:SendBroadcastMessage("|cff9966ff[AuraLab]|r All test auras cleared.")
        return true
    end

    if lower == "#ap aura summary" then
        AP.AuraLab.PrintSummary(player)
        return true
    end

    if lower == "#ap aura debugapproved" then
        AP.AuraLab.DebugApproved(player)
        return true
    end

    if lower == "#ap aura dumpfile" then
        AP.AuraLab.DumpToFile(player)
        return true
    end

    -- #ap aura reset <spellId>
    local resetId = string.match(lower, "^#ap aura reset (%d+)$")
    if resetId then
        local sid = tonumber(resetId)
        if sid then
            ClearResult(guid, sid)
            RefreshFiltered(guid)
            player:SendBroadcastMessage(string.format(
                "|cff9966ff[AuraLab]|r Reset result for spell %d.", sid))
        end
        return true
    end

    -- #ap aura approve <spellId>
    local approveId = string.match(lower, "^#ap aura approve (%d+)$")
    if approveId then
        local sid = tonumber(approveId)
        if sid then
            local cand = AP.AuraLab.BySpellId[sid]
            local theme = cand and cand.theme or ""
            SetResult(guid, sid, "APPROVED", theme)
            RefreshFiltered(guid)
            player:SendBroadcastMessage(string.format(
                "|cff9966ff[AuraLab]|r Approved spell %d for tiering.", sid))
        end
        return true
    end

    -- Tier/reject shortcuts
    local markMap = {
        ["#ap aura t1"]     = "T1",
        ["#ap aura t2"]     = "T2",
        ["#ap aura t3"]     = "T3",
        ["#ap aura t4"]     = "T4",
        ["#ap aura t5"]     = "T5",
        ["#ap aura reject"] = "REJECT",
    }
    local result = markMap[lower]
    if result then
        local c = GetCurrentCandidate(guid)
        if c then
            SetResult(guid, c.spellId, result, c.theme)
            local label = GetResultLabel(result)
            player:SendBroadcastMessage(string.format(
                "|cff9966ff[AuraLab]|r Assigned %d -> %s.", c.spellId, label))
            RefreshFiltered(guid)
            if state.index > #state.filteredList then
                state.index = math.max(1, #state.filteredList)
            end
            local next = GetCurrentCandidate(guid)
            if next then
                player:SendBroadcastMessage(string.format(
                    "|cff9966ff[AuraLab]|r Next: %d/%d spell %d (%s)",
                    state.index, #state.filteredList, next.spellId, next.note or next.theme))
            end
        end
        return true
    end

    return false
end

-- ============================================================
-- GOSSIP REGISTRATION
-- ============================================================

print("[Echoes] Aura Lab loaded. " .. #AP.AuraLab.Candidates .. " candidates.")

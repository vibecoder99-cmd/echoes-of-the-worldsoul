-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- ap_events.lua
-- Echoes of the Worldsoul â€” Game Event Handlers
-- ============================================================
-- EVENT ID REFERENCE (confirmed from Hooks.h):
--   3  = PLAYER_EVENT_ON_LOGIN
--   4  = PLAYER_EVENT_ON_LOGOUT
--   7  = PLAYER_EVENT_ON_KILL_CREATURE
--   12 = PLAYER_EVENT_ON_GIVE_XP      (xp, creature, group_bonus â€” creature nil for quests)
--   18 = PLAYER_EVENT_ON_CHAT          (SAY/YELL â€” all players incl. GM)
--   19 = PLAYER_EVENT_ON_WHISPER       (whisper received)
--   20 = PLAYER_EVENT_ON_GROUP_CHAT
--   21 = PLAYER_EVENT_ON_GUILD_CHAT
--   22 = PLAYER_EVENT_ON_CHANNEL_CHAT  (NOT "GM chat" â€” it's channel chat)
--   29 = PLAYER_EVENT_ON_EQUIP
--   42 = PLAYER_EVENT_ON_COMMAND       (works from console AND in-game /)
--   54 = PLAYER_EVENT_ON_COMPLETE_QUEST
-- ============================================================

AP = AP or {}

-- ap_commands.lua (alphabetically first) normally defines AP.GetPlayerRates before
-- this file loads. This guard activates only if that file fails to load, keeping
-- attunement functional at default 1.0x rates rather than erroring every kill.
if not AP.GetPlayerRates then
    AP.GetPlayerRates = function(_guid) return { xp = 1.0, aether = 1.0, boss = 1.0 } end
end

-- ============================================================
-- ONE-TIME MILESTONE HELPER
-- Grant Aether for a one-time account-wide milestone.
-- Returns true if granted, false if already claimed.
-- ============================================================
local function GrantMilestoneAether(player, milestoneType, milestoneId, amount, label)
    local accountId = AP.RT.GetAccountId(player)

    local q = AP.DB.Query(string.format(
        "SELECT 1 FROM `ap_aether_milestones` "..
        "WHERE `account_id` = %d AND `milestone_type` = '%s' AND `milestone_id` = %d LIMIT 1;",
        accountId, milestoneType, milestoneId
    ))
    if q then return false end

    AP.DB.ExecuteCritical(string.format(
        "INSERT IGNORE INTO `ap_aether_milestones` "..
        "(`account_id`, `milestone_type`, `milestone_id`) VALUES (%d, '%s', %d)",
        accountId, milestoneType, milestoneId
    ), "ap_events.milestone_claim")

    local guid = AP.RT.GetGUID(player)
    AP.DB.ExecuteCritical(string.format(
        "INSERT INTO `ap_mastery` (`guid`, `aether`, `mastery`) VALUES (%d, %d, 0) "..
        "ON DUPLICATE KEY UPDATE `aether` = `aether` + %d",
        guid, amount, amount
    ), "ap_events.milestone_aether")
    AP.DB.Execute("COMMIT")

    AP.RT.SendMessage(player,string.format(
        "|cff9966ff[Worldsoul]|r %s: |cffffff00+%d Essence|r",
        label, amount
    ))
    return true
end

-- ============================================================
-- PROFESSION SKILL MILESTONE TABLES (Task 7)
-- ============================================================
local AP_PRIMARY_PROFESSIONS = {
    [182]=true, -- Herbalism
    [186]=true, -- Mining
    [393]=true, -- Skinning
    [171]=true, -- Alchemy
    [164]=true, -- Blacksmithing
    [333]=true, -- Enchanting
    [202]=true, -- Engineering
    [165]=true, -- Leatherworking
    [197]=true, -- Tailoring
    [755]=true, -- Jewelcrafting
    [773]=true, -- Inscription
}
local AP_SECONDARY_PROFESSIONS = {
    [185]=true, -- Cooking
    [356]=true, -- Fishing
    [129]=true, -- First Aid
}
local AP_SKILL_TIERS = {
    {threshold=75,  tier=1, aether=100,  label="Apprentice"},
    {threshold=150, tier=2, aether=200,  label="Journeyman"},
    {threshold=225, tier=3, aether=400,  label="Expert"},
    {threshold=300, tier=4, aether=600,  label="Artisan"},
    {threshold=375, tier=5, aether=800,  label="Master"},
    {threshold=450, tier=6, aether=1000, label="Grand Master"},
}

-- ============================================================
-- LOREMASTER ACHIEVEMENT IDs (Task 8)
-- account_id-wide, handled as special cases inside OnAchievementComplete
-- ============================================================
local AP_LOREMASTER_MAJOR = {
    [1189] = { label = "Loremaster of Eastern Kingdoms", aether = 15000 },
    [1185] = { label = "Loremaster of Kalimdor",         aether = 15000 },
    [1187] = { label = "Loremaster of Outland",          aether = 8000  },
    [1186] = { label = "Loremaster of Northrend",        aether = 5000  },
}
-- Northrend per-zone loremasters (2,000 each)
-- IDs from WotLK 3.3.5a achievement DB; add verified IDs as needed
local AP_LOREMASTER_NORTHREND_ZONES = {
    [1239]=true, -- Borean Tundra
    [1273]=true, -- Howling Fjord
    [1242]=true, -- Dragonblight
    [1245]=true, -- Grizzly Hills
    [1247]=true, -- Zul'Drak
    [1249]=true, -- The Storm Peaks
    [1250]=true, -- Icecrown
    [1252]=true, -- Sholazar Basin
}

-- ============================================================
-- SESSION STATE
-- ============================================================
AP._session      = AP._session or {}
AP._questPending = AP._questPending or {}

-- Threat schema installation/repair is externalized to the database package.
-- AP.DB.ValidateSchema performs read-only table/column readiness checks.

local function GetSession(guid)
    if not AP._session[guid] then
        AP._session[guid] = {
            threat = 0,
            momentum = 0.0,
            momentumKills = 0,
            debtKills = 0,
            debtMult = 1.0,
            kills  = {},
        }
    end
    return AP._session[guid]
end

local function LoadThreatFromDB(guid, session)
    pcall(function()
        local q = AP.DB.Query(string.format(
            "SELECT `threat_level`, `threat_momentum`, `threat_debt_kills`, `threat_debt_mult` "..
            "FROM `ap_session_state` WHERE `guid` = %d", guid))
        if q then
            session.threat   = tonumber(tostring(q:GetUInt32(0))) or 0
            session.momentum = tonumber(tostring(q:GetString(1))) or 0.0
            session.debtKills = tonumber(tostring(q:GetUInt32(2))) or 0
            session.debtMult  = tonumber(tostring(q:GetString(3))) or 1.0
        end
    end)
end

local function SaveThreatToDB(guid, session)
    pcall(function()
        AP.DB.ExecuteAsync(string.format(
            "UPDATE `ap_session_state` SET `threat_level`=%d, `threat_momentum`=%.4f, "..
            "`threat_debt_kills`=%d, `threat_debt_mult`=%.4f WHERE `guid`=%d",
            session.threat, session.momentum,
            session.debtKills or 0, session.debtMult or 1.0, guid))
        AP.DB.ExecuteAsync("COMMIT;")
    end)
end
AP.SaveThreatToDB = SaveThreatToDB

-- ============================================================
-- PARTY SIZE HELPER
-- ============================================================
local function GetPartySize(player)
    local group = AP.RT.GetGroup(player)
    if not group then return 1 end
    local count = AP.RT.GetGroupMembersCount(group)
    if not count then return 1 end
    return math.max(1, count)
end

-- ============================================================
-- CREATURE RANK HELPER
-- Rank cache: avoids querying creature_template on every mob kill.
-- Only queries WorldDB once per unique creature entry, then caches the result.
-- nil = unchecked, else the cached rank value.
-- ============================================================
AP._creatureRankCache = AP._creatureRankCache or {}

local function GetCreatureRank(creature)
    local entry = AP.RT.GetCreatureEntry(creature)
    if AP._creatureRankCache[entry] ~= nil then return AP._creatureRankCache[entry] end
    local rank  = 0
    AP.Try(function()
        local q = AP.DB.WorldQuery(string.format(
            "SELECT `rank` FROM `creature_template` WHERE `entry` = %d LIMIT 1;", entry))
        if q then rank = tonumber(q:GetUInt8(0)) or 0 end
    end, "GetCreatureRank")
    AP._creatureRankCache[entry] = rank
    return rank
end

-- ============================================================
-- INSTANCE CHECK
-- ============================================================
local function IsInInstance(player)
    local map = AP.RT.GetMap(player)
    if not map then return false end
    local result = AP.RT.IsMapInstance(map)
    if result ~= nil then return result end
    local mapId = AP.RT.GetMapId(player)
    return mapId ~= 0 and mapId ~= 1 and mapId ~= 530 and mapId ~= 571
end

-- ============================================================
-- ANTI-CHEESE: REPEAT-KILL DAMPENER
-- World-only, entry-based, 4-minute sliding window.
-- ============================================================
local function GetDampener(session, entry, rank, inInstance)
    if inInstance then return 1.0 end
    if rank >= 1  then return 1.0 end

    local now  = os.time()
    local kills = session.kills

    if not kills[entry] then
        kills[entry] = { count = 0, firstSeen = now }
    end

    local rec = kills[entry]
    if now - rec.firstSeen > AP.Config.DampenerWindowSec then
        rec.count     = 0
        rec.firstSeen = now
    end
    rec.count = rec.count + 1

    local floor = AP.GetDampenerFloor(session.threat or 0)
    for _, tier in ipairs(AP.Config.DampenerThresholds) do
        if rec.count <= tier.limit then return math.max(floor, tier.mult) end
    end
    return floor
end

-- ============================================================
-- GRAY MOB CHECK
-- ============================================================
local function IsGrayMob(playerLevel, creatureLevel)
    if creatureLevel <= 0 then return true end
    local grayThreshold = playerLevel - math.floor(playerLevel / 10) - 5
    return creatureLevel < grayThreshold
end

-- Boss detection cache: avoids querying instance_encounters on every mob kill.
-- Only queries WorldDB once per unique creature entry, then caches the result.
-- nil = unchecked, true = confirmed boss, false = confirmed non-boss.
AP._bossCache = AP._bossCache or {}

local function IsInstanceBoss(entry, inInstance)
    -- World mobs are never dungeon/raid bosses.
    if not inInstance or entry <= 0 then return false end
    -- Return cached result if we've seen this entry before.
    if AP._bossCache[entry] ~= nil then return AP._bossCache[entry] end
    -- Query instance_encounters â€” fires at most once per unique entry.
    local isBoss = false
    AP.Try(function()
        local q = AP.DB.WorldQuery(string.format(
            "SELECT 1 FROM `instance_encounters` WHERE `creditEntry` = %d LIMIT 1;",
            entry))
        isBoss = (q ~= nil)
    end, "IsInstanceBoss")
    AP._bossCache[entry] = isBoss
    if isBoss then AP.Log("Boss confirmed: entry=" .. entry) end
    return isBoss
end
AP.IsInstanceBoss = IsInstanceBoss

-- ============================================================
-- XP GAIN HANDLER â€” PLAYER_EVENT_ON_GIVE_XP = 12
-- Confirmed from live probe: fires with (event, player, xp, creature, bonus)
-- creature is nil for quest/exploration XP.
-- This is the Synastria design: attunement progress is tied to
-- XP earned, not kill count. All XP sources contribute naturally.
-- ============================================================
AP.RT.RegisterEvent("player", 12, function(event, player, xp, creature, bonus)
    AP.Try(function()
        if not player or not xp or xp <= 0 then return end

        local guid        = AP.RT.GetGUID(player)
        local rates       = AP.GetPlayerRates(guid)
        local accountId   = AP.RT.GetAccountId(player)
        local session     = GetSession(guid)
        local inInstance  = IsInInstance(player)

        -- Sink multipliers: pure memory lookup, no DB hit per kill
        local surgeInvested = AP.Sinks and AP.Sinks.GetInvested(accountId, "aether_surge") or 0
        local surgeMult     = 1.0 + (AP.Sinks and AP.Sinks.GetEffect("aether_surge", surgeInvested) or 0)
        local echoInvested  = AP.Sinks and AP.Sinks.GetInvested(accountId, "attunement_echo") or 0
        local echoMult      = 1.0 + (AP.Sinks and AP.Sinks.GetEffect("attunement_echo", echoInvested) or 0)

        -- Determine rank for slot XP and Aether scaling
        -- creature is nil for quest/exploration XP
        local rank = 0
        local entry = 0
        local creatureLevel = 0
        if creature then
            entry = AP.RT.GetCreatureEntry(creature)
            rank  = GetCreatureRank(creature)
            creatureLevel = AP.RT.GetCreatureLevel(creature)
        end

        -- Gray mob check â€” only relevant for creature kills
        if creature then
            local playerLevel = AP.RT.GetLevel(player)
            if IsGrayMob(playerLevel, creatureLevel) then
                AP.Debug("Gray mob skip: entry=" .. entry)
                return
            end
        end

        -- Multipliers
        local dampener   = GetDampener(session, entry, rank, inInstance)
        local groupMult  = AP.GroupMultiplier(GetPartySize(player))

        -- Threat: content cap limits how much of the threat bonus applies
        local isBoss = creature and ((rank == 3) or IsInstanceBoss(entry, inInstance)) or false
        local isRaid = false
        if isBoss and creature then
            local map = AP.RT.GetMap(player)
            if map then
                local rval = AP.RT.IsMapRaid(map)
                if rval ~= nil then isRaid = rval end
            end
        end
        local playerLevel = AP.RT.GetLevel(player)
        local contentCap = creature
            and AP.GetThreatContentCap(playerLevel, creatureLevel, rank, isBoss, isRaid)
            or 0.0
        local threatMult = AP.GetThreatMultCapped(session.threat, session.momentum or 0, contentCap)

        -- XP debt: reduced base rewards after death
        local debtMult = 1.0
        if (session.debtKills or 0) > 0 then
            debtMult = session.debtMult or 1.0
            session.debtKills = session.debtKills - 1
            if session.debtKills <= 0 then
                session.debtKills = 0
                session.debtMult = 1.0
                if player then
                    pcall(function()
                        AP.RT.SendMessage(player,
                            "|cff00ff00[Worldsoul]|r Worldsoul Debt cleared. Full gains restored.")
                    end)
                end
                SaveThreatToDB(guid, session)
            end
        end

        local totalMult  = dampener * groupMult * threatMult * debtMult

        -- Build momentum from level-appropriate kills (momentum builds regardless of cap)
        if session.threat > 0 and creature then
            local momentumGain = AP.Config.ThreatMomentumNormal
            if isBoss then
                momentumGain = AP.Config.ThreatMomentumBoss
            elseif rank >= 1 then
                momentumGain = AP.Config.ThreatMomentumElite
            end
            session.momentum = math.min(1.0, (session.momentum or 0) + momentumGain)
            session.momentumKills = (session.momentumKills or 0) + 1
            if session.momentumKills % AP.Config.ThreatSaveInterval == 0 then
                SaveThreatToDB(guid, session)
            end
        end

        -- Aether: scale with XP earned so quests and bosses feel rewarding
        local aetherGrant = 0
        if creature then
            local aetherBase = AP.Config.AetherKillNormal

            local raidMult = isRaid and AP.Config.AetherBossRaidMult or 1.0

            if isBoss then
                local bossLevel  = creatureLevel > 0 and creatureLevel or 1
                local levelRatio = math.min(1.0, bossLevel / 80)
                aetherBase = math.max(5, math.floor(
                    AP.Config.AetherBossBase
                    * (levelRatio ^ AP.Config.AetherBossLevelExp)
                    * raidMult))
            elseif rank == 1 or rank == 2 or rank == 4 then
                aetherBase = AP.Config.AetherKillElite
            end
            aetherGrant = math.floor(aetherBase * totalMult)
            if isBoss then
                aetherGrant = math.floor(aetherGrant * rates.boss * surgeMult)
                -- Visage: send Dark Souls flash for boss kill (dedup'd against
                -- the kill-creature-path handler for gray-XP-suppressed bosses)
                if AP.Visage and AP.Visage.TryBossFlash then
                    local isBossRaid = (raidMult > 1.0)
                    AP.Visage.TryBossFlash(player, entry, isBossRaid, false)
                end
                if AP.Tutorial and AP.Tutorial.Trigger then
                    AP.Tutorial.Trigger(player, "first_boss")
                end
                -- Dungeon Mastery: record first conquest of this dungeon (non-raid instances only)
                if inInstance and raidMult == 1.0 then
                    AP.Try(function()
                        local mapId     = AP.RT.GetMapId(player)
                        local accountId = AP.RT.GetAccountId(player)
                        if mapId and mapId > 0 then
                            local qc = AP.DB.Query(string.format(
                                "SELECT 1 FROM `ap_aether_milestones` "..
                                "WHERE `account_id` = %d AND `milestone_type` = 'dungeon_conquest' AND `milestone_id` = %d LIMIT 1",
                                accountId, mapId))
                            if not qc then
                                AP.DB.ExecuteCritical(string.format(
                                    "INSERT IGNORE INTO `ap_aether_milestones` "..
                                    "(`account_id`, `milestone_type`, `milestone_id`) "..
                                    "VALUES (%d, 'dungeon_conquest', %d)",
                                    accountId, mapId), "ap_events.dungeon_conquest")
                                AP.DB.Execute("COMMIT")
                                AP.RT.SendMessage(player,
                                    "|cffffd700[Worldsoul]|r Dungeon conquered. "..
                                    "The Worldsoul remembers your mastery here.")
                                if AP.Tutorial and AP.Tutorial.Trigger then
                                    AP.Tutorial.Trigger(player, "first_conquest",
                                        "|cff9966ff[Worldsoul]|r You will move faster through dungeons you have conquered. "..
                                        "Familiarity is its own power.")
                                end
                            end
                        end
                    end, "dungeon conquest")
                end
            else
                aetherGrant = math.floor(aetherGrant * rates.aether * surgeMult)
            end
        end
        -- Quest/exploration Aether handled by quest event (event 54)

        if aetherGrant > 0 then
            -- Read old total for hundred-Essence tutorial check
            local oldAether = 0
            AP.Try(function()
                local aq = AP.DB.Query(string.format(
                    "SELECT `aether` FROM `ap_mastery` WHERE `guid` = %d", guid))
                if aq then oldAether = tonumber(tostring(aq:GetUInt32(0))) or 0 end
            end, "tutorial aether read")

            AP.GrantAether(guid, aetherGrant)
            AP.Debug(string.format("Kill Aether: +%d", aetherGrant))

            -- Tutorial triggers (fire once, then suppressed by milestone table)
            if AP.Tutorial and AP.Tutorial.Trigger then
                -- 1500ms delay so the kill XP settles before the whisper arrives
                local playerGuid = guid
                AP.RT.CreateTimer(function()
                    local livePlayer = AP.RT.GetPlayerByGUID(playerGuid)
                    if not livePlayer then return end
                    AP.Tutorial.Trigger(livePlayer, "first_essence")
                    local newAether = oldAether + aetherGrant
                    if newAether >= 100 and oldAether < 100 then
                        AP.Tutorial.Trigger(livePlayer, "first_hundred_essence")
                    end
                end, 1500, 1)
            end
        end

        -- Item attunement: progress = XP * XpToAttune * rarityMult * totalMult
        -- XpToAttune converts raw XP into attunement progress points.
        -- At XpToAttune=1.0: earning 10000 XP fully attunes a common item.
        -- Gray/white items have higher rarityMult so they attune faster.
        local slotXPBase = AP.Config.SlotXpPerKill
        if rank == 3 then slotXPBase = AP.Config.SlotXpPerBoss
        elseif rank >= 1 then slotXPBase = AP.Config.SlotXpPerElite
        end
        local slotXP = math.max(1, math.floor(slotXPBase * threatMult))

        local attunSlots = {0,1,2,4,5,6,7,8,9,10,11,12,13,14,15,16,17}

        -- Count equipped unattuned items first so XP is divided among them.
        -- Synastria design: XP is split across all equipped items, not given
        -- to each simultaneously. This makes attunement feel like a long-term
        -- investment rather than something that happens in one dungeon run.
        local unattunedCount = 0
        for _, slot in ipairs(attunSlots) do
            local item = AP.RT.GetEquippedItem(player, slot)
            if item then
                local rec = AP.LoadItemAttune(guid, AP.RT.GetItemEntry(item))
                if not rec or not rec.attuned then
                    unattunedCount = unattunedCount + 1
                end
            end
        end
        -- Equipped item XP: skip if all equipped items are already attuned
        -- (Rack items always receive XP below, regardless of this check)
        if unattunedCount > 0 then
        -- XP per item = total XP scaled by rate and echo sink, divided across items
        local xpPerItem = xp * rates.xp * echoMult / unattunedCount

        for _, slot in ipairs(attunSlots) do
            AP.Try(function()
                local item = AP.RT.GetEquippedItem(player, slot)
                if not item then return end

                local itemEntry = AP.RT.GetItemEntry(item)
                local quality   = AP.RT.GetItemQuality(item) or 1
                local rarityM   = AP.RarityMultiplier(quality)
                local rec       = AP.LoadItemAttune(guid, itemEntry)
                if not rec or rec.attuned then return end

                -- Item-level-scaled cap via shared helper
                local scaledCap = AP.GetScaledCap(itemEntry)

                -- Progress = XP per item * conversion factor * rarity * multipliers
                local addedProgress = math.max(1, math.floor(
                    xpPerItem * AP.Config.XpToAttune * rarityM * totalMult))
                local newProgress   = math.min(rec.progress + addedProgress, scaledCap)
                local nowAttuned    = (newProgress >= scaledCap)

                AP.SaveItemAttune(guid, itemEntry, newProgress, nowAttuned)
                if creature then
                    AP.AddSlotXP(guid, slot, slotXP)
                end

                if nowAttuned and not rec.attuned then
                    AP.CaptureSnapshot(player, item)
                    AP.Try(function()
                        AP.RT.SendMessage(player,
                            "|cff9966ff[Worldsoul]|r Item fully attuned! Progress absorbed.")
                    end, "broadcast attune")
                    AP.Log("Item attuned: entry=" .. itemEntry .. " guid=" .. guid)
                    if AP.API and AP.API.DispatchHook then
                        AP.API.DispatchHook("OnItemAttuned", { guid=guid, itemEntry=itemEntry, progress=newProgress })
                    end
                    -- Visage: check for new primary tier or theme unlock
                    local newCount = 0
                    if AP.Visage and AP.Visage.CheckAttunementMilestone then
                        newCount = AP.Visage.GetAttunedCount(guid)
                        AP.Visage.CheckAttunementMilestone(player, newCount)
                    end
                    -- Tutorial milestones for attunement count
                    if AP.Tutorial and AP.Tutorial.Trigger then
                        AP.Tutorial.Trigger(player, "first_attune")
                        if newCount == 5 then
                            AP.Tutorial.Trigger(player, "five_attuned")
                        elseif newCount == 25 then
                            AP.Tutorial.Trigger(player, "twenty_five_attuned")
                        end
                    end
                    -- Gear cycling feedback: show absorbed stats after snapshot commits
                    do
                        local fEntry    = itemEntry
                        local fGuid     = guid
                        local fAccId    = accountId
                        local fLevel    = AP.RT.GetLevel(player)
                        local fMastery  = 0
                        local fItemName = "Item"
                        pcall(function()
                            local nq = AP.DB.WorldQuery(string.format(
                                "SELECT `name` FROM `item_template` WHERE `entry`=%d", fEntry))
                            if nq then fItemName = nq:GetString(0) end
                            local mq = AP.DB.Query(string.format(
                                "SELECT `mastery` FROM `ap_mastery` WHERE `guid`=%d", fGuid))
                            if mq then fMastery = tonumber(tostring(mq:GetUInt32(0))) or 0 end
                        end)
                        AP.RT.CreateTimer(function()
                            local lp = AP.RT.GetPlayerByGUID(fGuid)
                            if not lp then return end
                            pcall(function()
                                local sq = AP.DB.Query(string.format(
                                    "SELECT `str`,`agi`,`sta`,`int`,`spi` "..
                                    "FROM `ap_item_snapshot` WHERE `guid`=%d AND `item_entry`=%d",
                                    fAccId, fEntry
                                ))
                                if not sq then return end
                                local str  = tonumber(sq:GetString(0)) or 0
                                local agi  = tonumber(sq:GetString(1)) or 0
                                local sta  = tonumber(sq:GetString(2)) or 0
                                local int_ = tonumber(sq:GetString(3)) or 0
                                local spi  = tonumber(sq:GetString(4)) or 0
                                local effective = AP.MasteryAbsorbPct(fMastery)
                                               * AP.LevelAbsorbScalar(fLevel)
                                local parts = {}
                                if str  > 0 then parts[#parts+1] = string.format("+%.0f STR", str  * effective) end
                                if agi  > 0 then parts[#parts+1] = string.format("+%.0f AGI", agi  * effective) end
                                if sta  > 0 then parts[#parts+1] = string.format("+%.0f STA", sta  * effective) end
                                if int_ > 0 then parts[#parts+1] = string.format("+%.0f INT", int_ * effective) end
                                if spi  > 0 then parts[#parts+1] = string.format("+%.0f SPI", spi  * effective) end
                                if #parts > 0 then
                                    AP.RT.SendMessage(lp,string.format(
                                        "|cff9966ff[Worldsoul]|r %s echo claimed. Absorbing: %s",
                                        fItemName, table.concat(parts, " | ")
                                    ))
                                end
                            end)
                        end, 1000, 1)
                    end
                end

                AP.Debug(string.format("Slot %d entry=%d xp=%d +%d â†’ %d",
                    slot, itemEntry, xp, addedProgress, newProgress))
            end, "attune slot " .. slot)
        end
        end -- if unattunedCount > 0

        -- Distribute XP to Rack items at 20% rate, split across all active entries
        local rackEntries = AP.Rack and AP.Rack.GetXPRecipients(guid) or {}
        local rackXPRate  = (AP.Rack and AP.Rack.XP_RATE) or 0.20
        local rackBaseXP  = xp * rates.xp * echoMult * rackXPRate
        if rackBaseXP > 0 and #rackEntries > 0 then
            local rackXPPerItem = math.floor(rackBaseXP / #rackEntries)
            for _, rackEntry in ipairs(rackEntries) do
                local rackCap = AP.GetScaledCap(rackEntry)
                local rq = AP.DB.Query(string.format(
                    "SELECT `progress`,`attuned` FROM `ap_item_attune` "..
                    "WHERE `guid`=%d AND `item_entry`=%d",
                    guid, rackEntry
                ))
                local curProgress = 0
                local isAttuned   = false
                if rq then
                    curProgress = tonumber(tostring(rq:GetUInt32(0))) or 0
                    isAttuned   = (tonumber(tostring(rq:GetUInt32(1))) or 0) == 1
                end
                if not isAttuned then
                    local rackQuality = 1
                    local rwq = AP.DB.WorldQuery(string.format(
                        "SELECT `Quality` FROM `item_template` WHERE `entry`=%d LIMIT 1",
                        rackEntry))
                    if rwq then rackQuality = tonumber(rwq:GetUInt8(0)) or 1 end
                    local rackRarityM = AP.RarityMultiplier(rackQuality)
                    local addedRackXP = math.max(1, math.floor(
                        rackXPPerItem * AP.Config.XpToAttune * rackRarityM * totalMult))
                    local newProgress = math.min(rackCap, curProgress + addedRackXP)
                    AP.DB.Execute(string.format(
                        "INSERT INTO `ap_item_attune` "..
                        "(`guid`,`item_entry`,`progress`,`attuned`) "..
                        "VALUES (%d,%d,%d,0) "..
                        "ON DUPLICATE KEY UPDATE `progress`=%d",
                        guid, rackEntry, newProgress, newProgress
                    ))
                end
            end
            AP.DB.Execute("COMMIT")
            for _, rackEntry in ipairs(rackEntries) do
                AP.Rack.CheckAttuned(player, rackEntry)
            end
        end

        -- Commit after each XP event's write batch.
        -- Without this, InnoDB REPEATABLE READ keeps a stale snapshot
        -- on the sync connection, making attuned=1 writes invisible to
        -- subsequent LoadItemAttune reads in the same session.
        AP.DB.Execute("COMMIT;")

    end, "AP xp event")
end)


-- ============================================================
-- BOSS FLASH FALLBACK: PLAYER_EVENT_ON_KILL_CREATURE (event 7)
-- Fires from Unit::Kill() independent of XP calculation. Exists
-- specifically to catch bosses the event-12 XP handler above can
-- never reach: legacy raid bosses (typically level 60-63) that
-- are "gray" to a level-80 killer under AzerothCore's gray-mob
-- formula, and therefore yield 0 XP and never dispatch
-- PLAYER_EVENT_ON_GIVE_XP at all. AP.Visage.TryBossFlash's
-- encounter-keyed dedup prevents any double-fire for bosses that
-- happen to qualify on both paths.
--
-- Known limitation (documented, not fixed here): this event does
-- NOT fire for the Lich King, because boss_the_lich_king.cpp
-- ends the encounter via a scripted self-kill
-- (Unit::Kill(&_owner, &_owner)) rather than a player-attributed
-- kill, so killer->ToPlayer() is never true for that death. This
-- is not a gap in practice: the Lich King already clears the
-- XP-gray threshold (level 83) and is fully handled by the
-- event-12 path above.
--
-- KNOWN LIMITATION (documented, accepted for this repair): this
-- event fires ONLY for the single killing-blow attributor
-- (Unit::Kill's `killer` argument), not once per raid member.
-- The XP-gated event-12 path fires per-player because
-- KillRewarder loops over the whole group; this fallback does
-- not replicate that fan-out. Practical effect: for a
-- gray-suppressed legacy boss, only the player who lands the
-- killing blow sees the flash, not the whole raid. Fixing that
-- would require explicit group iteration and was judged out of
-- scope for this narrowly scoped repair.
-- ============================================================
AP.RT.RegisterEvent("player", 7, function(event, killer, killed)
    AP.Try(function()
        if not killer or not killed then return end

        local entry = AP.RT.GetCreatureEntry(killed)
        if not entry or entry <= 0 then return end

        local inInstance = IsInInstance(killer)
        if not inInstance then return end

        local rank = GetCreatureRank(killed)
        local isBoss = (rank == 3) or AP.IsInstanceBoss(entry, inInstance)
        if not isBoss then return end

        local isBossRaid = false
        local map = AP.RT.GetMap(killer)
        if map then
            isBossRaid = AP.RT.IsMapRaid(map) or false
        end

        if AP.Visage and AP.Visage.TryBossFlash then
            AP.Visage.TryBossFlash(killer, entry, isBossRaid, false)
        end
    end, "BossFlashOnKillCreature")
end)


-- ============================================================
-- QUEST COMPLETE HANDLER
-- PLAYER_EVENT_ON_COMPLETE_QUEST = 54
-- Fires when the player fully completes and turns in a quest.
-- ============================================================
AP.RT.RegisterEvent("player", 54, function(event, player, quest)
    AP.Try(function()
        if not player or not quest then return end

        local guid    = AP.RT.GetGUID(player)
        local questId = AP.RT.GetQuestId(quest)
        if questId == 0 then return end

        local key = guid .. ":" .. questId
        if AP._questPending[key] then
            AP.Debug("Quest " .. questId .. " already pending for guid " .. guid)
            return
        end
        AP._questPending[key] = true

        -- Capture player name now while player object is still valid.
        -- After 500ms the original userdata may be invalidated.
        local playerName = nil
        AP.Try(function() playerName = AP.RT.GetName(player) end, "quest player:GetName")

        -- Delay 500ms: character_queststatus_rewarded row may not exist yet.
        -- We capture guid/questId/playerName by value, NOT the player object.
        AP.RT.CreateTimer(function()
            AP.Try(function()
                local already = AP.DB.Query(string.format(
                    "SELECT 1 FROM `ap_quest_rewarded` WHERE `guid` = %d AND `quest_id` = %d LIMIT 1;",
                    guid, questId))
                if already then
                    AP.Debug("Quest " .. questId .. " already rewarded (ap_quest_rewarded).")
                    AP._questPending[key] = nil
                    return
                end

                local coreCheck = AP.DB.Query(string.format(
                    "SELECT 1 FROM `character_queststatus_rewarded` WHERE `guid` = %d AND `quest` = %d LIMIT 1;",
                    guid, questId))
                if not coreCheck then
                    AP.Debug("Quest " .. questId .. " not in character_queststatus_rewarded; skipping.")
                    AP._questPending[key] = nil
                    return
                end

                AP.DB.ExecuteCritical(string.format(
                    "INSERT IGNORE INTO `ap_quest_rewarded` (`guid`, `quest_id`) VALUES (%d, %d);",
                    guid, questId), "ap_events.quest_rewarded")

                local rates         = AP.GetPlayerRates(guid)
                local questAccId    = AP.GetAccountId(guid)
                local qSurgeInv     = AP.Sinks and AP.Sinks.GetInvested(questAccId, "aether_surge") or 0
                local qSurgeMult    = 1.0 + (AP.Sinks and AP.Sinks.GetEffect("aether_surge", qSurgeInv) or 0)
                local amount = math.floor(AP.Config.AetherQuestNormal * rates.aether * qSurgeMult)
                AP.GrantAether(guid, amount)

                -- Auto-attune ALL reward items from this quest.
                -- Synastria design: completing a quest auto-attunes every
                -- reward option, not just the one the player selected.
                AP.Try(function()
                    local freshPlayer = AP.RT.GetPlayerByName(playerName)
                    if not freshPlayer then return end

                    -- Query all reward items from quest_template
                    local q = AP.DB.WorldQuery(string.format([[
                        SELECT
                            `RewardChoiceItemID1`, `RewardChoiceItemID2`, `RewardChoiceItemID3`,
                            `RewardChoiceItemID4`, `RewardChoiceItemID5`, `RewardChoiceItemID6`,
                            `RewardItem1`, `RewardItem2`, `RewardItem3`, `RewardItem4`
                        FROM `quest_template`
                        WHERE `Id` = %d
                        LIMIT 1;
                    ]], questId))

                    if not q then return end

                    local rewardEntries = {
                        tonumber(q:GetUInt32(0)) or 0,
                        tonumber(q:GetUInt32(1)) or 0,
                        tonumber(q:GetUInt32(2)) or 0,
                        tonumber(q:GetUInt32(3)) or 0,
                        tonumber(q:GetUInt32(4)) or 0,
                        tonumber(q:GetUInt32(5)) or 0,
                        tonumber(q:GetUInt32(6)) or 0,
                        tonumber(q:GetUInt32(7)) or 0,
                        tonumber(q:GetUInt32(8)) or 0,
                        tonumber(q:GetUInt32(9)) or 0,
                    }

                    local attuneCount = 0

                    for _, itemEntry in ipairs(rewardEntries) do
                        if itemEntry and itemEntry > 0 then
                            -- Only auto-attune equippable gear (weapon=2, armor=4 with a valid slot).
                            -- Consumables (class=0), quest items (class=12), reagents, etc. must
                            -- NEVER reach attuned=1 â€” they can be dissolved at the Forge for
                            -- Residue/gold, and vendor-bought consumables that also appear as
                            -- quest rewards create an infinite buy->attune->dissolve loop.
                            local iq = AP.DB.WorldQuery(string.format([[
                                    SELECT `stat_type1`, `stat_value1`,
                                           `stat_type2`, `stat_value2`,
                                           `stat_type3`, `stat_value3`,
                                           `stat_type4`, `stat_value4`,
                                           `stat_type5`, `stat_value5`,
                                           `stat_type6`, `stat_value6`,
                                           `stat_type7`, `stat_value7`,
                                           `stat_type8`, `stat_value8`,
                                           `stat_type9`, `stat_value9`,
                                           `stat_type10`, `stat_value10`,
                                           `Quality`, `RequiredLevel`,
                                           `class`, `InventoryType`
                                    FROM `item_template`
                                    WHERE `entry` = %d LIMIT 1;
                                ]], itemEntry))

                                if iq then
                                    local iClass  = tonumber(iq:GetUInt8(22)) or 0
                                    local invType = tonumber(iq:GetUInt32(23)) or 0
                                    if not ((iClass == 2 or iClass == 4) and invType > 0) then
                                        AP.Debug(string.format(
                                            "Quest auto-attune REJECTED: entry=%d class=%d invType=%d",
                                            itemEntry, iClass, invType))
                                    else

                                    local reqLevel = tonumber(iq:GetUInt8(21)) or 1
                                    if reqLevel <= 0 then reqLevel = 1 end
                                    -- E2j5a: armor/weapon_dps restoration - shared helper (ap_core.lua),
                                    -- same historical formula proven in cpp_patch/mod_attunement_plus.patch.
                                    local stats, quality = AP.ComputeSnapshotStatsFromItemTemplate(itemEntry)

                                    -- Save snapshot account-wide
                                    local accountId = AP.GetAccountId(guid)
                                    AP.SaveSnapshotAccountWide(guid, itemEntry, quality, stats)

                                    -- Mark as attuned for this character
                                    local scaledCap = AP.GetScaledCap(itemEntry)
                                    AP.DB.ExecuteCritical(string.format([[
                                        INSERT INTO `ap_item_attune` (`guid`, `item_entry`, `progress`, `attuned`)
                                        VALUES (%d, %d, %d, 1)
                                        ON DUPLICATE KEY UPDATE `progress` = %d, `attuned` = 1;
                                    ]], guid, itemEntry, scaledCap, scaledCap), "ap_events.quest_item_attune")

                                    attuneCount = attuneCount + 1
                                    AP.Debug(string.format("Quest auto-attuned: entry=%d", itemEntry))
                                    end  -- class/invType guard
                                end
                        end
                    end

                    AP.DB.Execute("COMMIT;")

                    if attuneCount > 0 then
                        AP.Log(string.format("Quest auto-attune: questId=%d attuned=%d items", questId, attuneCount))
                    end
                end, "quest auto-attune rewards")

                AP.DB.Execute("COMMIT;")

                -- Look up player fresh by name â€” safe after any delay.
                AP.Try(function()
                    if playerName then
                        local freshPlayer = AP.RT.GetPlayerByName(playerName)
                        if freshPlayer then
                            AP.RT.SendMessage(freshPlayer,string.format(
                                "|cff9966ff[Worldsoul]|r Quest complete! +%d Essence.", amount))
                        end
                    end
                end, "broadcast quest")

                AP.Log(string.format("Quest Aether: guid=%d questId=%d amount=%d",
                    guid, questId, amount))
                AP._questPending[key] = nil
            end, "quest delayed verify")
        end, 500, 1)

    end, "AP quest event")
end)

-- ============================================================
-- EQUIP EVENT
-- PLAYER_EVENT_ON_EQUIP = 29
-- Reserved for future use; slot XP is granted on kills.
-- ============================================================
AP.RT.RegisterEvent("player", 29, function(event, player, item, bag, slot)
    AP.Try(function()
        if not player or not item then return end
        local itemEntry = AP.RT.GetItemEntry(item)
        AP.Debug("Equip: slot=" .. tostring(slot) .. " entry=" .. tostring(itemEntry))

        -- Auto-remove from Rack on equip.
        -- EXPLOIT GUARD: the equipped-item XP loop and the Rack XP loop both
        -- write to ap_item_attune independently. An item that is BOTH equipped
        -- AND on the Rack receives both grants per kill (confirmed double-dip).
        -- Removing from the Rack at equip time is the clean structural fix:
        -- equipped items attune naturally through the combat loop; they don't
        -- need and must not also receive the Rack's 20% bonus rate.
        if AP.Rack then
            local guid = AP.RT.GetGUID(player)
            if not AP.Rack.Cache[guid] then AP.Rack.Load(guid) end
            local cache = AP.Rack.Cache[guid]
            if cache then
                local rackSlot = nil
                local itemName = "The item"
                for i, s in pairs(cache) do
                    if s and s.item_entry == itemEntry then
                        rackSlot = i
                        itemName = s.item_name or itemName
                        break
                    end
                end
                if rackSlot then
                    AP.DB.Execute(string.format(
                        "UPDATE `ap_rack` SET `item_entry`=0,`item_name`='',`item_quality`=1 "..
                        "WHERE `guid`=%d AND `slot_index`=%d",
                        guid, rackSlot
                    ))
                    AP.DB.Execute("COMMIT")
                    cache[rackSlot] = nil
                    AP.RT.SendMessage(player,string.format(
                        "|cff9966ff[Worldsoul]|r %s unsheathed from the Rack. "..
                        "Equipped items attune through combat â€” no Rack slot needed.",
                        itemName
                    ))
                end
            end
        end
    end, "AP equip event")
end)

-- ============================================================
-- CHAT COMMAND PARSER
-- HandleChatLine is called from both PLAYER_EVENT_ON_CHAT (18)
-- and PLAYER_EVENT_ON_WHISPER (19).
--
-- Tooltip requests come in as WHISPER-to-self from the AddOn.
-- UI open commands can come from either SAY or WHISPER.
--
-- PLAYER_EVENT_ON_COMMAND (42) is handled separately in ap_gm.lua
-- and ap_tests.lua because it also fires from the console.
-- ============================================================
AP._tipRateLimit = AP._tipRateLimit or {}
local TIP_RATE_LIMIT_SEC = 0.2  -- 200ms â€” fast enough for smooth hover, slow enough to prevent spam

local function HandleChatLine(player, msg)
    if not player or not msg then return end
    local lower = msg:lower():match("^%s*(.-)%s*$")

    -- UI openers
    if lower == "ap" or lower == "#ap" or lower == "!ap" or lower == ".ap" then
        AP.Try(function() AP.OpenUI(player) end, "AP open UI")
        return false
    end

    if lower == "#ap doctor" then
        if AP.Doctor and AP.Doctor.Report then
            AP.Doctor.Report(player)
        else
            AP.RT.SendMessage(
                player,
                "|cffff4444[Echoes]|r System Doctor is unavailable.")
        end
        return false
    end

    -- Aura Lab chat shortcuts
    if AP.AuraLab and AP.AuraLab.HandleChat then
        if AP.AuraLab.HandleChat(player, lower) then return false end
    end

    -- Aura test harness (GM-only)
    local testauraId = lower:match("^#ap testaura%s+(%d+)$")
    local testauraForce = lower:match("^#ap testaura force%s+(%d+)$")
    if testauraId or testauraForce then
        if not AP.IsGM(player) then
            AP.RT.SendMessage(player,"|cffff4444[Worldsoul]|r GM access required.")
            return false
        end
        local spellId = tonumber(testauraForce or testauraId)
        local forced = (testauraForce ~= nil)
        local guid = AP.RT.GetGUID(player)

        -- Safety: only allow scanner-approved IDs unless forced
        if not forced and AP.AuraLab then
            local approved = false
            for _, c in ipairs(AP.AuraLab.Candidates) do
                if c.spellId == spellId then approved = true; break end
            end
            if not approved then
                AP.RT.SendMessage(player,string.format(
                    "|cffff4444[Echoes]|r Spell %d is NOT scanner-approved. "..
                    "Use '#ap testaura force %d' to override (unsafe).", spellId, spellId))
                return false
            end
        end

        print(string.format("[Echoes] testaura spellId=%d player=%s forced=%s",
            spellId, AP.RT.GetName(player), tostring(forced)))
        if forced then
            AP.RT.SendMessage(player,
                "|cffff4444[Echoes]|r WARNING: forced unapproved spell. May cause harm.")
        end

        -- Disable Visage auras
        if AP.Visage and AP.Visage.Cache[guid] then
            local vc = AP.Visage.Cache[guid]
            vc.primary_enabled = 0
            vc.secondary_enabled = 0
            AP.DB.Execute(string.format(
                "UPDATE `ap_visage` SET `primary_enabled`=0, `secondary_enabled`=0 WHERE `guid`=%d", guid))
            AP.DB.Execute("COMMIT;")
            for sid, _ in pairs(AP.Visage.AllSpellIds) do
                AP.RT.RemoveAura(player, sid)
            end
        end

        local ok, err = AP.RT.AddAura(player, spellId)
        if ok then
            AP.RT.SendMessage(player,string.format(
                "|cff9966ff[Echoes]|r Testing aura %d. Move around, wait 10 sec.", spellId))
        else
            AP.RT.SendMessage(player,string.format(
                "|cffff4444[Echoes]|r AddAura(%d) failed: %s", spellId, tostring(err)))
        end
        return false
    end

    local clearauraId = lower:match("^#ap clearaura%s+(%d+)$")
    if clearauraId then
        if not AP.IsGM(player) then
            AP.RT.SendMessage(player,"|cffff4444[Worldsoul]|r GM access required.")
            return false
        end
        local spellId = tonumber(clearauraId)
        local ok, err = AP.RT.RemoveAura(player, spellId)
        if ok then
            AP.RT.SendMessage(player,string.format(
                "|cff9966ff[Echoes]|r Removed aura %d.", spellId))
        else
            AP.RT.SendMessage(player,string.format(
                "|cffff4444[Echoes]|r RemoveAura(%d) failed: %s", spellId, tostring(err)))
        end
        return false
    end

    if lower == "#ap aurastatus" then
        if not AP.IsGM(player) then
            AP.RT.SendMessage(player,"|cffff4444[Worldsoul]|r GM access required.")
            return false
        end
        local guid = AP.RT.GetGUID(player)
        if AP.Visage and AP.Visage.Cache[guid] then
            local c = AP.Visage.Cache[guid]
            local attunedCount = AP.Visage.GetAttunedCount(guid)
            local totalInvested = AP.Visage.GetTotalCrucibleInvested(AP.RT.GetAccountId(player))
            local pTier = AP.Visage.GetPrimaryTier(attunedCount)
            local sTier = AP.Visage.GetSecondaryTier(totalInvested)
            local pSpells = AP.Visage.ThemeSpells[c.primary_theme]
            local sSpells = AP.Visage.ThemeSpells[c.secondary_theme]
            local pId = (pSpells and pTier > 0) and pSpells[pTier] or 0
            local sId = (sSpells and sTier > 0) and sSpells[sTier] or 0
            AP.RT.SendMessage(player,string.format(
                "|cff9966ff[Echoes]|r Attuned: %d | Primary: %s T%d enabled=%d spellId=%d | "..
                "Secondary: %s T%d enabled=%d spellId=%d | Crucible: %d",
                attunedCount,
                c.primary_theme, pTier, c.primary_enabled, pId,
                c.secondary_theme, sTier, c.secondary_enabled, sId,
                totalInvested))
        else
            AP.RT.SendMessage(player,"|cffff4444[Echoes]|r No Visage cache for this character.")
        end
        return false
    end

    -- Test runner: #aptest [filter]
    if lower:sub(1, 7) == "#aptest" or lower:sub(1, 8) == "#ap test" then
        if AP.RunTests then
            local filter = lower:match("^#aptest%s+(%w+)$") or lower:match("^#ap test%s+(%w+)$")
            if filter == "all" then filter = nil end
            AP.RunTests(player, filter)
        else
            AP.Try(function()
                AP.RT.SendMessage(player,"|cffff4444[Worldsoul]|r AP.RunTests not loaded.")
            end, "aptest missing")
        end
        return false
    end

    -- Find quest command
    if lower == "#apfind" or lower == "apfind" then
        AP.Try(function()
            local guid   = AP.RT.GetGUID(player)
            local zoneId = AP.RT.GetZoneId(player)
            local mapId  = AP.RT.GetMapId(player)

            if not zoneId or zoneId == 0 then
                AP.RT.SendMessage(player,"|cff9966ff[Worldsoul]|r Could not detect your current zone.")
                return false
            end

            -- Quality color codes matching WoW item quality
            local qualityColors = {
                [0] = "|cff9d9d9d",  -- Gray
                [1] = "|cffffffff",  -- White
                [2] = "|cff1eff00",  -- Green
                [3] = "|cff0070dd",  -- Blue
                [4] = "|cffa335ee",  -- Purple (Epic)
                [5] = "|cffff8000",  -- Orange (Legendary)
                [6] = "|cffe6cc80",  -- Artifact
            }

            -- Build quest list from creature AND gameobject starters
            -- UNION ensures we catch both NPC-started and object-started quests
            local q = AP.DB.WorldQuery(string.format([[
                SELECT DISTINCT
                    qt.`Id`,
                    qt.`LogTitle`,
                    qt.`RewardChoiceItemID1`, qt.`RewardChoiceItemID2`,
                    qt.`RewardChoiceItemID3`, qt.`RewardChoiceItemID4`,
                    qt.`RewardChoiceItemID5`, qt.`RewardChoiceItemID6`,
                    qt.`RewardItem1`, qt.`RewardItem2`,
                    qt.`RewardItem3`, qt.`RewardItem4`,
                    ct.`name` AS starterName
                FROM `quest_template` qt
                JOIN `creature_queststarter` cqs ON cqs.`quest` = qt.`Id`
                JOIN `creature` c ON c.`id` = cqs.`id`
                JOIN `creature_template` ct ON ct.`entry` = cqs.`id`
                WHERE (c.`zoneId` = %d OR (c.`zoneId` = 0 AND c.`map` = %d))
                AND (
                    qt.`RewardChoiceItemID1` > 0 OR qt.`RewardChoiceItemID2` > 0 OR
                    qt.`RewardChoiceItemID3` > 0 OR qt.`RewardChoiceItemID4` > 0 OR
                    qt.`RewardChoiceItemID5` > 0 OR qt.`RewardChoiceItemID6` > 0 OR
                    qt.`RewardItem1` > 0 OR qt.`RewardItem2` > 0 OR
                    qt.`RewardItem3` > 0 OR qt.`RewardItem4` > 0
                )

                UNION

                SELECT DISTINCT
                    qt.`Id`,
                    qt.`LogTitle`,
                    qt.`RewardChoiceItemID1`, qt.`RewardChoiceItemID2`,
                    qt.`RewardChoiceItemID3`, qt.`RewardChoiceItemID4`,
                    qt.`RewardChoiceItemID5`, qt.`RewardChoiceItemID6`,
                    qt.`RewardItem1`, qt.`RewardItem2`,
                    qt.`RewardItem3`, qt.`RewardItem4`,
                    got.`name` AS starterName
                FROM `quest_template` qt
                JOIN `gameobject_queststarter` gqs ON gqs.`quest` = qt.`Id`
                JOIN `gameobject` go ON go.`id` = gqs.`id`
                JOIN `gameobject_template` got ON got.`entry` = gqs.`id`
                WHERE (go.`zoneId` = %d OR (go.`zoneId` = 0 AND go.`map` = %d))
                AND (
                    qt.`RewardChoiceItemID1` > 0 OR qt.`RewardChoiceItemID2` > 0 OR
                    qt.`RewardChoiceItemID3` > 0 OR qt.`RewardChoiceItemID4` > 0 OR
                    qt.`RewardChoiceItemID5` > 0 OR qt.`RewardChoiceItemID6` > 0 OR
                    qt.`RewardItem1` > 0 OR qt.`RewardItem2` > 0 OR
                    qt.`RewardItem3` > 0 OR qt.`RewardItem4` > 0
                )

                LIMIT 30;
            ]], zoneId, mapId, zoneId, mapId))

            if not q then
                AP.RT.SendMessage(player,"|cff9966ff[Worldsoul]|r No attunable quests found in this zone.")
                return false
            end

            local found = 0
            AP.RT.SendMessage(player,"|cff9966ff[Worldsoul]|r Quests with unattuned rewards in this zone:")

            repeat
                local questId     = tonumber(q:GetUInt32(0)) or 0
                local title       = q:GetString(1) or ("Quest " .. questId)
                local starterName = q:GetString(12) or "Unknown"

                -- Collect all reward item entries
                local items = {}
                for i = 2, 11 do
                    local entry = tonumber(q:GetUInt32(i)) or 0
                    if entry > 0 then items[#items+1] = entry end
                end

                -- Check if any reward item has something worth attuning
                -- (stats, armor value, or weapon damage)
                local unattunedItems = {}
                for _, itemEntry in ipairs(items) do
                    local rec = AP.LoadItemAttune(guid, itemEntry)
                    if not rec or not rec.attuned then
                        -- Check if item has anything worth attuning
                        local iq = AP.DB.WorldQuery(string.format([[
                            SELECT `name`, `Quality`,
                                   `stat_value1`+`stat_value2`+`stat_value3`+
                                   `stat_value4`+`stat_value5`+`stat_value6`+
                                   `stat_value7`+`stat_value8`+`stat_value9`+`stat_value10`,
                                   `armor`, `dmg_min1`, `class`
                            FROM `item_template`
                            WHERE `entry` = %d LIMIT 1;
                        ]], itemEntry))
                        if iq then
                            local itemName   = iq:GetString(0) or ("Item "..itemEntry)
                            local quality    = tonumber(iq:GetUInt8(1))   or 0
                            local totalStats = tonumber(iq:GetFloat(2))   or 0
                            local armor      = tonumber(iq:GetUInt32(3))  or 0
                            local dmgMin     = tonumber(iq:GetFloat(4))   or 0
                            local iClass     = tonumber(iq:GetUInt8(5))   or 0
                            -- Include if: has stats, has armor, or is a weapon with damage
                            local hasValue = totalStats > 0 or armor > 0 or (iClass == 2 and dmgMin > 0)
                            if hasValue then
                                unattunedItems[#unattunedItems+1] = {
                                    entry   = itemEntry,
                                    name    = itemName,
                                    quality = quality,
                                }
                            end
                        end
                    end
                end

                if #unattunedItems > 0 then
                    -- Check if quest is already completed
                    local done = AP.DB.Query(string.format(
                        "SELECT 1 FROM `character_queststatus_rewarded` WHERE `guid` = %d AND `quest` = %d LIMIT 1;",
                        guid, questId))

                    if not done then
                        -- Check if this quest leads to more quests (chain indicator)
                        local chainQ = AP.DB.WorldQuery(string.format(
                            "SELECT `RewardNextQuest` FROM `quest_template` WHERE `Id` = %d LIMIT 1;",
                            questId))
                        local hasChain = chainQ and (tonumber(chainQ:GetUInt32(0)) or 0) > 0
                        local chainSuffix = hasChain and " |cff888888[chain]|r" or ""

                        AP.RT.SendMessage(player,string.format(
                            "|cffffff00%s|r%s |cff888888(from %s)|r",
                            title, chainSuffix, starterName))

                        for _, item in ipairs(unattunedItems) do
                            local color = qualityColors[item.quality] or qualityColors[1]
                            AP.RT.SendMessage(player,string.format(
                                "  %s%s|r", color, item.name))
                        end

                        found = found + 1
                    end
                end
            until not q:NextRow()

            if found == 0 then
                AP.RT.SendMessage(player,"|cff9966ff[Worldsoul]|r All attunable quests in this zone are complete!")
            else
                AP.RT.SendMessage(player,string.format(
                    "|cff9966ff[Worldsoul]|r Found %d quest(s). Use #apfind in other zones to track more.", found))
            end
        end, "AP apfind")
        return false
    end

    -- Tooltip request: #ap tip <entry> or ap tip <entry>
    local tipEntry = lower:match("^#?ap%s+tip%s+(%d+)$")
    if tipEntry then
        local guid = AP.RT.GetGUID(player)
        -- Key by guid+entry so hovering different items rapidly isn't blocked
        local key  = guid .. "_" .. tipEntry
        local now  = os.clock()  -- sub-second precision
        local last = AP._tipRateLimit[key] or 0
        if (now - last) >= TIP_RATE_LIMIT_SEC then
            AP._tipRateLimit[key] = now
            AP.Try(function()
                AP.SendTooltipPayload(player, tonumber(tipEntry))
            end, "AP tip handler")
        else
            AP.Debug("Tip rate limited for guid=" .. guid .. " entry=" .. tipEntry)
        end
        return false
    end

    return nil
end

-- Event 18: PLAYER_EVENT_ON_CHAT â€” SAY, YELL (includes GM chat)
AP.RT.RegisterEvent("player", 18, function(event, player, msg, type, lang, channel)
    return HandleChatLine(player, msg)
end)

-- Event 19: PLAYER_EVENT_ON_WHISPER â€” whisper received
-- This is what the client AddOn uses for tooltip requests.
AP.RT.RegisterEvent("player", 19, function(event, player, msg, lang, receiver)
    return HandleChatLine(player, msg)
end)

-- ============================================================
-- RETURNING PLAYER NOTIFICATION
-- Fires on login if the player has been away for 3+ days.
-- ============================================================
local function CheckReturningPlayer(player)
    local ok, err = pcall(function()
        local guid = AP.RT.GetGUID(player)

        -- Check last logout time from characters table
        -- Column 'online' stores 0/1; 'logout_time' stores the timestamp.
        -- (E2j5g: removed a 'last_login' fallback query — that column does
        -- not exist on this server's characters table; referencing it would
        -- trigger AzerothCore's fatal unexpected-column abort, not a
        -- catchable Lua error.)
        local lastLogout = 0
        local q = AP.DB.Query(string.format(
            "SELECT `logout_time` FROM `characters` WHERE `guid` = %d", guid))
        if q then
            lastLogout = tonumber(tostring(q:GetUInt32(0))) or 0
        end
        if lastLogout == 0 then return end  -- first login (never logged out yet)

        local now = os.time()
        local daysSince = (now - lastLogout) / 86400
        if daysSince < 3 then return end

        -- Get stats for the message
        local aether = 0
        local attuned = 0
        local qa = AP.DB.Query(string.format(
            "SELECT `aether` FROM `ap_mastery` WHERE `guid` = %d", guid))
        if qa then aether = tonumber(tostring(qa:GetUInt32(0))) or 0 end

        local qat = AP.DB.Query(string.format(
            "SELECT COUNT(*) FROM `ap_item_attune` WHERE `guid` = %d AND `attuned` = 1", guid))
        if qat then attuned = tonumber(tostring(qat:GetUInt32(0))) or 0 end

        local msg = string.format(
            "|cff9966ff[Worldsoul]|r Welcome back. Your echoes endured. "..
            "|cffffff00%d|r Essence. |cffffff00%d|r echoes claimed.",
            aether, attuned)

        local playerGuid = guid
        AP.RT.CreateTimer(function()
            local livePlayer = AP.RT.GetPlayerByGUID(playerGuid)
            if not livePlayer then return end
            AP.RT.SendMessage(livePlayer,msg)
        end, 5000, 1)
    end)
    if not ok then
        print("[EotW] ERROR in CheckReturningPlayer: " .. tostring(err))
    end
end

-- ============================================================
-- LOGIN / LOGOUT
-- ============================================================
AP.RT.RegisterEvent("player", 3, function(event, player)
    AP.Try(function()
        -- Capability probe: fires once per server session via AP.Probe._ran guard.
        -- Must run before any AP.Cap.Check() call lower in the login path.
        if AP.Probe and AP.Probe.RunLogin then AP.Probe.RunLogin(player) end

        local guid    = AP.RT.GetGUID(player)
        local session = GetSession(guid)
        LoadThreatFromDB(guid, session)
        AP.Log("Player logged in: guid=" .. guid .. " threat=" .. session.threat)

        -- Retroactive attunement migration: mark items as attuned if their
        -- stored progress already meets or exceeds the current scaled cap.
        -- Handles items stored under old cap values or config changes.
        AP.Try(function()
            local q = AP.DB.Query(string.format(
                "SELECT `item_entry`, `progress` FROM `ap_item_attune` WHERE `guid` = %d AND `attuned` = 0;",
                guid))
            if not q then return end
            local toAttune = {}
            repeat
                local itemEntry = tonumber(q:GetUInt32(0)) or 0
                local progress  = tonumber(q:GetUInt32(1)) or 0
                if itemEntry > 0 then
                    local cap = AP.GetScaledCap(itemEntry)
                    if progress >= cap then
                        toAttune[#toAttune + 1] = itemEntry
                    end
                end
            until not q:NextRow()

            for _, entry in ipairs(toAttune) do
                AP.DB.ExecuteCritical(string.format(
                    "UPDATE `ap_item_attune` SET `attuned` = 1 WHERE `guid` = %d AND `item_entry` = %d;",
                    guid, entry), "ap_events.login_attune_migration")
                AP.Log(string.format("Migration: attuned entry=%d", entry))
            end
            if #toAttune > 0 then
                AP.DB.Execute("COMMIT;")
            end
        end, "AP login migration")

        -- Snapshot migration: capture stats for any attuned item that has
        -- no snapshot yet. This handles items attuned before the snapshot
        -- system existed, or items attuned on old code paths.
        AP.Try(function()
            local accountId   = AP.GetAccountId(guid)

            -- Find all attuned items for this character with no snapshot
            local q = AP.DB.Query(string.format([[
                SELECT a.`item_entry`
                FROM `ap_item_attune` a
                LEFT JOIN `ap_item_snapshot` s
                    ON s.`guid` = %d AND s.`item_entry` = a.`item_entry`
                WHERE a.`guid` = %d AND a.`attuned` = 1
                AND s.`item_entry` IS NULL;
            ]], accountId, guid))

            if not q then return end

            local snapped = 0
            repeat
                local itemEntry = tonumber(q:GetUInt32(0)) or 0
                if itemEntry > 0 then
                    -- Snapshot ALL attuned items regardless of armor class
                    -- E2j5a: armor/weapon_dps restoration - shared helper (ap_core.lua).
                    local stats, quality = AP.ComputeSnapshotStatsFromItemTemplate(itemEntry)
                    if stats then
                        AP.SaveSnapshotAccountWide(guid, itemEntry, quality, stats)
                        snapped = snapped + 1
                        AP.Debug(string.format("Snapshot migration: entry=%d str=%.0f agi=%.0f sta=%.0f armor=%.0f wdps=%.1f",
                            itemEntry, stats.str, stats.agi, stats.sta, stats.armor, stats.weapon_dps))
                    end
                end
            until not q:NextRow()

            if snapped > 0 then
                AP.DB.Execute("COMMIT;")
                AP.Log(string.format("Snapshot migration: captured %d snapshots for guid=%d", snapped, guid))
            end
        end, "AP snapshot migration")
        CheckReturningPlayer(player)
    end, "AP login")
end)

AP.RT.RegisterEvent("player", 4, function(event, player)
    AP.Try(function()
        local guid = AP.RT.GetGUID(player)
        local session = AP._session[guid]
        if session then
            pcall(function()
                AP.DB.ExecuteAsync(string.format(
                    "INSERT INTO `ap_session_state` (`guid`,`clean_exit`,`threat_level`,`threat_momentum`,"..
                    "`threat_debt_kills`,`threat_debt_mult`) "..
                    "VALUES (%d, 1, %d, %.4f, %d, %.4f) "..
                    "ON DUPLICATE KEY UPDATE `clean_exit`=1, `threat_level`=%d, `threat_momentum`=%.4f, "..
                    "`threat_debt_kills`=%d, `threat_debt_mult`=%.4f",
                    guid, session.threat or 0, session.momentum or 0,
                    session.debtKills or 0, session.debtMult or 1.0,
                    session.threat or 0, session.momentum or 0,
                    session.debtKills or 0, session.debtMult or 1.0))
                AP.DB.ExecuteAsync("COMMIT;")
            end)
        else
            pcall(function()
                AP.DB.ExecuteAsync(string.format(
                    "INSERT INTO `ap_session_state` (`guid`,`clean_exit`) VALUES (%d, 1) "..
                    "ON DUPLICATE KEY UPDATE `clean_exit` = 1",
                    guid))
                AP.DB.ExecuteAsync("COMMIT;")
            end)
        end
        AP._session[guid] = nil
        AP.Debug("Session cleared + clean_exit=1: guid=" .. guid)
    end, "AP logout")
end)

-- ============================================================
-- COOLDOWN REDUCTION
-- Event 5 = PLAYER_EVENT_ON_SPELL_CAST (event, player, spell, skipCheck)
--
-- AddSpellCooldown is not exposed in this Eluna build's Lua API.
-- Without it we cannot set a partial cooldown, so we implement
-- Fallback A: a proc chance to fully reset the cooldown on cast.
-- At ceiling 20% (500k invested) this is a 20% chance per cast to
-- skip the cooldown entirely -- equivalent to ~25% faster cast rate
-- on that ability, approximating genuine CDR at max investment.
-- Only fires for spells with > 1500ms cooldown (skips GCD-only).
-- ============================================================
AP.RT.RegisterEvent("player", 5, function(event, player, spell, skipCheck)
    AP.Try(function()
        local accountId = AP.RT.GetAccountId(player)
        local invested  = AP.Sinks and AP.Sinks.GetInvested(accountId, "cooldown_reduction") or 0
        if invested <= 0 then return end

        local cdrFrac = AP.Sinks.GetEffect("cooldown_reduction", invested)
        if cdrFrac <= 0 then return end

        local spellId = AP.RT.GetSpellEntry(spell)
        if not spellId or spellId <= 0 then return end

        -- Capture plain GUID now; player userdata is invalid after this event returns
        local playerGuid = AP.RT.GetGUID(player)

        -- Check cooldown 100ms after cast (let the engine set it first)
        AP.RT.CreateTimer(function()
            local livPlayer = AP.RT.GetPlayerByGUID(playerGuid)
            if not livPlayer then return end
            if not AP.RT.IsInWorld(livPlayer) then return end
            if not AP.RT.HasSpellCooldown(livPlayer, spellId) then return end

            local remaining = AP.RT.GetCooldownDelay(livPlayer, spellId)
            if remaining <= 1500 then return end  -- GCD only, skip

            -- Roll for reset proc
            local roll = math.random()
            if roll < cdrFrac then
                AP.RT.ResetCooldown(livPlayer, spellId)
            end
        end, 100, 1)
    end, "AP cooldown_reduction")
end)

-- ============================================================
-- RES RESILIENCE -- Restore fraction of durability lost on death
-- Event 8  = PLAYER_EVENT_ON_KILLED_BY_CREATURE (killer, killed)
-- Event 36 = PLAYER_EVENT_ON_RESURRECT (player)
--
-- Durability loss happens inside the engine before event 8 fires,
-- so we can't snapshot pre-death values. Instead we flag the death
-- and on resurrect restore (resiFrac * deathRate) of max durability
-- per item. deathRate = 0.10 matches AzerothCore's default
-- DurabilityLoss.OnDeath config (10% of max per item).
--
-- ITEM_FIELD_DURABILITY    = OBJECT_END(6) + 0x36 = 60
-- ITEM_FIELD_MAXDURABILITY = OBJECT_END(6) + 0x37 = 61
-- ============================================================
local AP_ITEM_FIELD_DURABILITY    = 60
local AP_ITEM_FIELD_MAXDURABILITY = 61
local AP_DEATH_DUR_RATE           = 0.10  -- matches DurabilityLoss.OnDeath default

local s_recentlyDied = {}  -- guid -> true

AP.RT.RegisterEvent("player", 8, function(event, killer, killed)
    AP.Try(function()
        local guid      = AP.RT.GetGUID(killed)
        local accountId = AP.RT.GetAccountId(killed)
        local session   = AP._session[guid]

        -- Threat death penalties
        if session and session.threat > 0 then
            local pen = AP.GetDeathPenalty(session.threat)
            local attuneLoss = pen[1]
            local essencePct = pen[2]
            local essenceCap = pen[3]
            local debtKills  = pen[4]
            local debtMult   = pen[5]

            local totalLost = 0
            local essenceLost = 0

            -- 1. Momentum reset
            session.momentum = 0.0
            session.momentumKills = 0
            AP.RT.SendMessage(killed,
                "|cff9966ff[Worldsoul]|r Death breaks your Threat Momentum.")

            -- 2. Attunement progress penalty on equipped unattuned items
            if attuneLoss > 0 then
                local attunSlots = {0,1,2,4,5,6,7,8,9,10,11,12,13,14,15,16,17}
                for _, slot in ipairs(attunSlots) do
                    pcall(function()
                        local item = AP.RT.GetEquippedItem(killed, slot)
                        if not item then return end
                        local itemEntry = AP.RT.GetItemEntry(item)
                        local rec = AP.LoadItemAttune(guid, itemEntry)
                        if not rec or rec.attuned or rec.progress <= 0 then return end
                        local loss = math.floor(rec.progress * attuneLoss)
                        if loss > 0 then
                            local newProg = math.max(0, rec.progress - loss)
                            AP.SaveItemAttune(guid, itemEntry, newProg, false)
                            totalLost = totalLost + loss
                        end
                    end)
                end
                if totalLost > 0 then
                    AP.RT.SendMessage(killed,string.format(
                        "|cff9966ff[Worldsoul]|r Unfinished attunement weakened: %d progress lost.", totalLost))
                else
                    AP.RT.SendMessage(killed,
                        "|cff9966ff[Worldsoul]|r No unfinished attunement to lose.")
                end
            end

            -- 3. Essence tax
            if essencePct > 0 then
                pcall(function()
                    local q = AP.DB.Query(string.format(
                        "SELECT `aether` FROM `ap_mastery` WHERE `guid` = %d", guid))
                    if q then
                        local cur = tonumber(tostring(q:GetUInt32(0))) or 0
                        essenceLost = math.min(math.floor(cur * essencePct), essenceCap)
                        if essenceLost > 0 then
                            AP.DB.Execute(string.format(
                                "UPDATE `ap_mastery` SET `aether` = GREATEST(0, `aether` - %d) WHERE `guid` = %d",
                                essenceLost, guid))
                            AP.DB.Execute("COMMIT;")
                        end
                    end
                end)
                if essenceLost > 0 then
                    AP.RT.SendMessage(killed,string.format(
                        "|cff9966ff[Worldsoul]|r Death's toll: %d Essence lost.", essenceLost))
                end
            end

            -- 4. XP debt
            if debtKills > 0 then
                session.debtKills = debtKills
                session.debtMult  = debtMult
                AP.RT.SendMessage(killed,string.format(
                    "|cff9966ff[Worldsoul]|r Worldsoul Debt: next %d kills at %.0f%% gains.",
                    debtKills, debtMult * 100))
            end

            SaveThreatToDB(guid, session)
            if AP.API and AP.API.DispatchHook then
                AP.API.DispatchHook("OnThreatDeathPenalty", {
                    guid=guid, threat=session.threat,
                    essenceLost=essenceLost or 0, attuneLost=totalLost or 0,
                    debtKills=debtKills })
            end
        end

        -- Res Resilience (separate from threat penalties)
        local invested  = AP.Sinks and AP.Sinks.GetInvested(accountId, "res_resilience") or 0
        if invested <= 0 then return end
        s_recentlyDied[guid] = true
    end, "AP death handler")
end)

AP.RT.RegisterEvent("player", 36, function(event, player)
    AP.Try(function()
        local guid = AP.RT.GetGUID(player)
        if not s_recentlyDied[guid] then return end
        s_recentlyDied[guid] = nil

        local accountId = AP.RT.GetAccountId(player)
        local invested  = AP.Sinks and AP.Sinks.GetInvested(accountId, "res_resilience") or 0
        if invested <= 0 then return end

        local resiFrac = AP.Sinks and AP.Sinks.GetEffect("res_resilience", invested) or 0
        if resiFrac <= 0 then return end

        local session = AP._session[guid]
        local threatLvl = session and session.threat or 0
        if threatLvl > 0 then
            resiFrac = resiFrac * AP.GetSafetyScalar(threatLvl)
        end

        local restored = 0
        for slot = 0, 18 do
            local item = AP.RT.GetEquippedItem(player, slot)
            if item then
                local maxDur = AP.RT.GetItemUInt32Value(item, AP_ITEM_FIELD_MAXDURABILITY)
                local curDur = AP.RT.GetItemUInt32Value(item, AP_ITEM_FIELD_DURABILITY)
                if maxDur and maxDur > 0 then
                    local deathLoss = math.floor(maxDur * AP_DEATH_DUR_RATE)
                    local gain      = math.floor(deathLoss * resiFrac)
                    if gain > 0 then
                        local newDur = math.min(curDur + gain, maxDur)
                        if AP.RT.SetItemUInt32Value(item, AP_ITEM_FIELD_DURABILITY, newDur) then
                            AP.RT.SaveItemToDB(item)
                            restored = restored + gain
                        end
                    end
                end
            end
        end

        if restored > 0 then
            AP.RT.SendMessage(player,string.format(
                "|cff9966ff[Worldsoul]|r Res Resilience: %.1f%% of durability loss restored.",
                resiFrac * 100.0))
        end
    end, "AP res_resilience resurrect")
end)

-- ============================================================
-- ACHIEVEMENT AETHER
-- Event 45 = PLAYER_EVENT_ON_ACHIEVEMENT_COMPLETE
-- (event, player, achievement)
-- AP.RT.GetAchievementId(achievement) confirmed; GetPoints() NOT available in this build.
-- Points looked up from achievement_dbc (sparse â€” custom entries only).
-- Falls back to flat 50 Aether; Loremaster IDs handled as special cases.
-- ============================================================
local function GetSurgeMult(player)
    local accountId = AP.RT.GetAccountId(player)
    if not AP.SinkCache or not AP.SinkCache[accountId] then
        if AP.Sinks and AP.Sinks.LoadForAccount then
            AP.Sinks.LoadForAccount(accountId)
        end
    end
    local surgeInvested = AP.Sinks and AP.Sinks.GetInvested(accountId, "aether_surge") or 0
    return 1.0 + (AP.Sinks and AP.Sinks.GetEffect("aether_surge", surgeInvested) or 0)
end

AP.RT.RegisterEvent("player", 45, function(event, player, achievement)
    AP.Try(function()
        local achId = AP.RT.GetAchievementId(achievement)
        if not achId or achId <= 0 then return end

        local amount
        local label = "Achievement completed"

        -- Loremaster major: grant zone quest bonus (Task 8)
        local loremasterEntry = AP_LOREMASTER_MAJOR[achId]
        if loremasterEntry then
            amount = loremasterEntry.aether
            label  = loremasterEntry.label
        elseif AP_LOREMASTER_NORTHREND_ZONES[achId] then
            amount = 2000
            label  = "Northrend zone completed"
        else
            -- Look up points from achievement_dbc (only custom entries present)
            local points = 0
            local q = AP.DB.WorldQuery(string.format(
                "SELECT `Points` FROM `achievement_dbc` WHERE `ID` = %d LIMIT 1;",
                achId))
            if q then points = tonumber(q:GetUInt32(0)) or 0 end

            if points >= 100 then amount = 400
            elseif points >= 50 then amount = 200
            elseif points >= 25 then amount = 100
            elseif points >= 10 then amount = 40
            else amount = 50  -- default for all standard achievements
            end
        end

        amount = math.floor(amount * GetSurgeMult(player))
        local achGranted = GrantMilestoneAether(player, "achievement", achId, amount, label)
        if achGranted and AP.Tutorial and AP.Tutorial.Trigger then
            AP.Tutorial.Trigger(player, "first_achievement_essence")
        end
    end, "AP achievement")
end)

-- ============================================================
-- DUNGEON MASTERY SPEED
-- Applies +8% run speed inside conquered dungeons; removed on exit.
-- ============================================================
EotW_MasterySpeedActive = EotW_MasterySpeedActive or {}

local function CheckDungeonMasterySpeed(player)
    local ok, err = pcall(function()
        local guid      = AP.RT.GetGUID(player)
        local accountId = AP.RT.GetAccountId(player)

        local inDungeon = false
        local mapId     = 0
        local map = AP.RT.GetMap(player)
        if map then
            local isInst = AP.RT.IsMapInstance(map) or false
            local isRaid = AP.RT.IsMapRaid(map) or false
            inDungeon = isInst and not isRaid
            mapId = AP.RT.GetMapId(player)
        end

        if not inDungeon then
            if EotW_MasterySpeedActive[guid] then
                EotW_MasterySpeedActive[guid] = nil
                local sinkInv    = AP.Sinks and AP.Sinks.GetInvested(accountId, "movement_speed") or 0
                local sinkBonus  = AP.Sinks and AP.Sinks.GetEffect("movement_speed", sinkInv) or 0
                AP.RT.SetSpeed(player, 1, 1.0 + sinkBonus, true)
            end
            return
        end

        if EotW_MasterySpeedActive[guid] then return end  -- already applied

        local qc = AP.DB.Query(string.format(
            "SELECT 1 FROM `ap_aether_milestones` "..
            "WHERE `account_id` = %d AND `milestone_type` = 'dungeon_conquest' AND `milestone_id` = %d LIMIT 1",
            accountId, mapId))
        if not qc then return end

        local sinkInv   = AP.Sinks and AP.Sinks.GetInvested(accountId, "movement_speed") or 0
        local sinkBonus = AP.Sinks and AP.Sinks.GetEffect("movement_speed", sinkInv) or 0
        local isMounted = AP.RT.IsMounted(player)
        local isFlying  = AP.RT.IsInFlight(player)
        if not isMounted and not isFlying then
            AP.RT.SetSpeed(player, 1, 1.0 + sinkBonus + 0.08, true)
            EotW_MasterySpeedActive[guid] = true
        end
    end)
    if not ok then
        print("[EotW] ERROR in CheckDungeonMasterySpeed: " .. tostring(err))
    end
end

-- ============================================================
-- ZONE DISCOVERY AETHER
-- Event 27 = PLAYER_EVENT_ON_UPDATE_ZONE (event, player, newZone, newArea)
-- No dedicated first-discovery event; milestone table enforces one-time grant.
-- ContinentID from areatable_dbc determines Aether tier.
-- ============================================================
local function GetZoneAether(zoneId)
    local q = AP.DB.WorldQuery(string.format(
        "SELECT `ContinentID` FROM `areatable_dbc` WHERE `ID` = %d LIMIT 1;",
        zoneId))
    if not q then return 25 end
    local continentId = tonumber(q:GetUInt32(0)) or 0
    if continentId == 571 then return 250     -- Northrend
    elseif continentId == 530 then return 150 -- Outland
    elseif continentId == 0 or continentId == 1 then return 50  -- Azeroth continents
    else return 75  -- instances/other maps
    end
end

AP.RT.RegisterEvent("player", 27, function(event, player, newZone, newArea)
    AP.Try(function()
        if not newZone or newZone <= 0 then return end
        local granted = GrantMilestoneAether(player, "area", newZone,
            math.floor(GetZoneAether(newZone) * GetSurgeMult(player)), "New zone discovered")
        if granted and AP.Tutorial and AP.Tutorial.Trigger then
            AP.Tutorial.Trigger(player, "first_discovery")
        end
        -- Refresh visage auras on zone change (keeps them alive through instance transitions)
        if AP.Visage and AP.Visage.ApplyAuras then
            AP.Visage.ApplyAuras(player)
        end
        -- Dungeon Mastery: apply or remove speed bonus based on dungeon conquest status
        CheckDungeonMasterySpeed(player)
    end, "AP zone discovery")
end)

-- ============================================================
-- REPUTATION MILESTONE AETHER
-- Event 15 = PLAYER_EVENT_ON_REPUTATION_CHANGE
-- (event, player, factionId, standing, incremental)
-- WotLK standing values: 4=Friendly, 5=Honored, 6=Revered, 7=Exalted
-- milestone_id = factionId * 10 + (standing - 4)
-- ============================================================
local AP_REP_STANDING_AETHER = {
    [5] = { aether = 75,  label = "Honored"  },
    [6] = { aether = 150, label = "Revered"  },
    [7] = { aether = 300, label = "Exalted"  },
}

AP.RT.RegisterEvent("player", 15, function(event, player, factionId, standing, incremental)
    AP.Try(function()
        if not factionId or factionId <= 0 then return end
        local rep = AP_REP_STANDING_AETHER[standing]
        if not rep then return end
        local milestoneId = factionId * 10 + (standing - 4)
        local amount = math.floor(rep.aether * GetSurgeMult(player))
        local repGranted = GrantMilestoneAether(player, "reputation", milestoneId, amount,
            string.format("%s with faction %d", rep.label, factionId))
        if repGranted and standing == 7 and AP.Tutorial and AP.Tutorial.Trigger then
            AP.Tutorial.Trigger(player, "first_exalted")
        end
    end, "AP reputation")
end)

-- ============================================================
-- PROFESSION SKILL MILESTONE AETHER
-- Event 62 = PLAYER_EVENT_ON_UPDATE_SKILL
-- (event, player, skill_id, value, max, step, new_value)
-- value = previous skill value, new_value = value after update
-- milestone_id = skillId * 10 + tier (1-6 for 75/150/225/300/375/450)
-- ============================================================
AP.RT.RegisterEvent("player", 62, function(event, player, skillId, value, max, step, newValue)
    AP.Try(function()
        if not skillId or skillId <= 0 then return end

        local isPrimary   = AP_PRIMARY_PROFESSIONS[skillId]
        local isSecondary = AP_SECONDARY_PROFESSIONS[skillId]
        if not isPrimary and not isSecondary then return end

        local surgeMult = GetSurgeMult(player)

        for _, tier in ipairs(AP_SKILL_TIERS) do
            -- Only grant for tier 6 (450) on secondary professions
            if isSecondary and tier.tier < 6 then goto continue end

            -- Detect threshold crossing: was below, now at or above
            if (value < tier.threshold) and (newValue >= tier.threshold) then
                local milestoneId = skillId * 10 + tier.tier
                local amount = math.floor(tier.aether * surgeMult)
                GrantMilestoneAether(player, "profession", milestoneId, amount,
                    string.format("%s (%d)", tier.label, skillId))
            end

            ::continue::
        end
    end, "AP profession skill")
end)

-- ============================================================
-- RESONANT DROP HANDLER
-- PLAYER_EVENT_ON_LOOT_ITEM = 32  (confirmed from Hooks.h)
-- Signature: (event, player, item, count)
-- If the looted item is already fully attuned for this character,
-- remove it and replace with a Worldsoul Echo Fragment.
-- ============================================================
local ECHO_FRAGMENT_ENTRY = 900010

-- Session storage keyed by guid; populated here, consumed in ap_items.lua
EotW_EchoFragmentQuality   = EotW_EchoFragmentQuality   or {}
EotW_EchoFragmentItemEntry = EotW_EchoFragmentItemEntry or {}

AP.RT.RegisterEvent("player", 32, function(event, player, item, count)
    local ok, err = pcall(function()
        local guid      = AP.RT.GetGUID(player)
        local accountId = AP.RT.GetAccountId(player)

        -- item parameter may be an Item object or a raw entry integer depending on Eluna build
        local itemEntry = 0
        if type(item) == "number" then
            itemEntry = item
        else
            itemEntry = AP.RT.GetItemEntry(item)
        end
        if not itemEntry or itemEntry <= 0 then return end
        if itemEntry == ECHO_FRAGMENT_ENTRY then return end

        -- Is this item fully attuned for this character?
        local qa = AP.DB.Query(string.format(
            "SELECT 1 FROM `ap_item_attune` WHERE `guid` = %d AND `item_entry` = %d AND `attuned` = 1 LIMIT 1",
            guid, itemEntry))
        if not qa then return end

        -- Get drop count for Legacy Surge detection
        local dropCount = 0
        local qd = AP.DB.Query(string.format(
            "SELECT `drop_count` FROM `ap_resonant_drops` WHERE `account_id` = %d AND `item_entry` = %d",
            accountId, itemEntry))
        if qd then dropCount = tonumber(tostring(qd:GetUInt32(0))) or 0 end
        dropCount = dropCount + 1

        AP.DB.Execute(string.format(
            "INSERT INTO `ap_resonant_drops` (`account_id`, `item_entry`, `drop_count`) "..
            "VALUES (%d, %d, 1) ON DUPLICATE KEY UPDATE `drop_count` = `drop_count` + 1",
            accountId, itemEntry))
        AP.DB.Execute("COMMIT")

        -- Remove the original item before giving the fragment
        -- For object form: AP.RT.RemoveItemObject(item). For integer form: RemoveItem by entry.
        local removed = false
        if type(item) ~= "number" then
            removed = AP.RT.RemoveItemObject(item)
        end
        if not removed then
            removed = AP.RT.RemoveItem(player, itemEntry, 1)
        end
        if not removed then
            print("[EotW] WARN: Could not remove resonant drop entry=" .. itemEntry)
            AP.DB.Execute(string.format(
                "UPDATE `ap_resonant_drops` SET `drop_count` = `drop_count` - 1 "..
                "WHERE `account_id` = %d AND `item_entry` = %d", accountId, itemEntry))
            AP.DB.Execute("COMMIT")
            return
        end

        -- Look up quality from DB (reliable regardless of whether item is object or integer)
        local quality = 1
        local iq = AP.DB.WorldQuery(string.format(
            "SELECT `Quality` FROM `item_template` WHERE `entry` = %d LIMIT 1", itemEntry))
        if iq then quality = tonumber(iq:GetUInt8(0)) or 1 end

        EotW_EchoFragmentQuality[guid]   = quality
        EotW_EchoFragmentItemEntry[guid] = itemEntry

        -- Give the Echo Fragment and immediately persist it to DB so a
        -- client crash before the autosave tick cannot lose the item.
        local fragGiven = AP.RT.AddItem(player, ECHO_FRAGMENT_ENTRY, 1)
        if fragGiven then
            AP.RT.SavePlayerToDB(player, false, false)
        end

        if fragGiven then
            local goldPrev
            if     quality >= 5 then goldPrev = "20g"
            elseif quality >= 4 then goldPrev = "8g"
            elseif quality >= 3 then goldPrev = "3g"
            elseif quality >= 2 then goldPrev = "1g"
            else                     goldPrev = "20s"
            end
            if dropCount >= 4 then
                AP.RT.SendMessage(player,string.format(
                    "|cffffd700[Worldsoul]|r |cffff8800Legacy Surge!|r Echo already claimed. "..
                    "A |cff9966ffWorldsoul Echo Fragment|r is in your bag. "..
                    "Right-click for |cffffff003x Essence + %s|r.", goldPrev))
            else
                AP.RT.SendMessage(player,string.format(
                    "|cffffd700[Worldsoul]|r Echo already claimed. "..
                    "A |cff9966ffWorldsoul Echo Fragment|r is in your bag. "..
                    "Right-click for |cffffff00Essence + %s|r, or disenchant/vendor.", goldPrev))
            end
        else
            print("[EotW] WARN: Could not give Echo Fragment to " .. AP.RT.GetName(player) .. " (bag full?)")
        end
    end)
    if not ok then
        print("[EotW] ERROR in OnLootItem: " .. tostring(err))
    end
end)

print("[AttunementPlus] LIVE ap_events.lua loaded from RelWithDebInfo lua_scripts")

-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- ap_ui.lua
-- Echoes of the Worldsoul — Player UI (Gossip-Based)
-- ============================================================
-- The UI is opened by the chat command "ap" (or #ap, !ap, .ap).
-- It uses PlayerGossip to simulate a panel without requiring an NPC.
-- Pages:
--   Main Menu â†' Mastery / Equipped Items / Slot Spec / Talents / Toggles
--   Mastery     â†' shows Aether, current mastery rank, buy button
--   Equipped    â†' lists up to 6 equipped items with attunement %
--   Slot Spec   â†' lists slot levels
--   Talents     â†' shows talent points (stub for now)
--   Toggles     â†' Threat++
-- ============================================================

AP = AP or {}

-- ============================================================
-- GOSSIP MENU SENDER
-- Wraps GossipMenuAddItem / GossipSendMenu safely.
-- ============================================================
local function GossipReset(player)
    AP.Try(function() player:GossipClearMenu() end, "GossipClearMenu")
end

local function GossipAdd(player, icon, text, sender, intid)
    AP.Try(function()
        player:GossipMenuAddItem(icon or 0, text, sender or 0, intid or 0)
    end, "GossipMenuAddItem")
end

local function GossipSend(player, text, sender)
    AP.Try(function()
        player:GossipSendMenu(1, player, sender or 99)
    end, "GossipSendMenu")
end

-- ============================================================
-- UI PAGES
-- Each page function: clears menu, adds items, sends.
-- ============================================================

-- Use intid=0 universally for the Back button across all pages.
-- This avoids collision with page-specific intids and lets us
-- handle it before the sender dispatch.
local INTID_BACK     = 0
local SENDER_MAIN    = 1
local SENDER_MASTERY = 2
local SENDER_EQUIP   = 3
local SENDER_SLOT    = 4
local SENDER_TALENT  = 5
local SENDER_TOGGLE  = 6
local SENDER_ATTUNES = 8  -- View Attuned Items page

-- ---- MAIN MENU ----
local function ShowMainMenu(player)
    GossipReset(player)
    GossipAdd(player, 7, "Progression Status",   SENDER_MAIN, 1)
    GossipAdd(player, 6, "Equipped Items",       SENDER_MAIN, 2)
    GossipAdd(player, 8, "Slot Specialization",  SENDER_MAIN, 3)
    GossipAdd(player, 1, "Talents",              SENDER_MAIN, 4)
    GossipAdd(player, 4, "World Threat",          SENDER_MAIN, 5)
    GossipAdd(player, 6, "View Attuned Items",   SENDER_MAIN, 6)
    GossipAdd(player, 0, "The Crucible",          102, 1)
    GossipAdd(player, 0, "Visage",               201, 0)
    GossipAdd(player, 8, "Worldsoul Codex",       220, 0)
    GossipAdd(player, 6, "Attunement Rack",       240, 0)
    GossipAdd(player, 7, "Legacy Forge",          250, 0)
    GossipSend(player, "Echoes of the Worldsoul", SENDER_MAIN)
end

-- ---- PROGRESSION STATUS PAGE ----
local function ShowProgressionPage(player)
    local guid      = player:GetGUIDLow()
    local accountId = AP.GetAccountId(guid)
    local rec       = AP.LoadMastery(guid)
    local aether    = rec and rec.aether  or 0
    local mastery   = rec and rec.mastery or 0
    local level     = player:GetLevel()

    local basePct      = AP.MasteryAbsorbPct(mastery)
    local levelScale   = AP.LevelAbsorbScalar(level)
    local effectivePct = basePct * levelScale
    local nextCost     = AP.MasteryCost(mastery)

    local residue = 0
    if AP.Forge and AP.Forge.GetResidue then
        residue = AP.Forge.GetResidue(accountId) or 0
    end

    local totalAttuned = 0
    AP.Try(function()
        local q = CharDBQuery(string.format(
            "SELECT COUNT(*) FROM `ap_item_attune` WHERE `guid` = %d AND `attuned` = 1", guid))
        if q then totalAttuned = tonumber(tostring(q:GetUInt32(0))) or 0 end
    end, "status attuned count")

    local rackUsed = 0
    local rackCap  = 3
    AP.Try(function()
        if AP.Rack then
            rackCap  = AP.Rack.GetCapacity(guid) or 3
            rackUsed = AP.Rack.CountSlots(guid) or 0
        end
    end, "status rack count")

    local priTheme = "worldsoul"
    local priTier  = 0
    local priSel   = 0
    local secTheme = "worldsoul"
    local secTier  = 0
    local secSel   = 0
    if AP.Visage then
        if not AP.Visage.Cache[guid] then AP.Visage.LoadForChar(guid) end
        local vc = AP.Visage.Cache[guid]
        if vc then
            priTheme = vc.primary_theme or "worldsoul"
            secTheme = vc.secondary_theme or "worldsoul"
            priSel   = vc.primary_tier_selected or 0
            secSel   = vc.secondary_tier_selected or 0
        end
        local attCount = AP.Visage.GetAttunedCount(guid) or 0
        priTier = AP.Visage.GetPrimaryTier(attCount)
        local invested = AP.Visage.GetTotalCrucibleInvested(accountId) or 0
        secTier = AP.Visage.GetSecondaryTier(invested)
    end

    local priEff = AP.Visage and AP.Visage.GetEffectiveTier(priSel, priTier) or priTier
    local secEff = AP.Visage and AP.Visage.GetEffectiveTier(secSel, secTier) or secTier
    local priLabel = (priSel == 0) and "Auto" or ("T" .. priEff)
    local secLabel = (secSel == 0) and "Auto" or ("T" .. secEff)
    local priThemeName = (AP.Visage and AP.Visage.ThemeNames[priTheme]) or priTheme
    local secThemeName = (AP.Visage and AP.Visage.ThemeNames[secTheme]) or secTheme

    AP.Debug(string.format("ProgressionPage: guid=%d aether=%d mastery=%d base=%.4f level=%d scale=%.4f eff=%.4f",
        guid, aether, mastery, basePct, level, levelScale, effectivePct))

    GossipReset(player)

    GossipAdd(player, 0, "Echoes of the Worldsoul -- Progression", SENDER_MASTERY, 0)
    GossipAdd(player, 0, string.format(
        "Level: %d  |  Mastery Rank: %d", level, mastery), SENDER_MASTERY, 0)
    GossipAdd(player, 0, string.format(
        "Effective Absorption: %.1f%%  (Base %.1f%% x Level Scalar %.1f%%)",
        effectivePct * 100, basePct * 100, levelScale * 100), SENDER_MASTERY, 0)
    GossipAdd(player, 0, string.format(
        "Essence: %d  |  Worldsoul Residue: %d", aether, residue), SENDER_MASTERY, 0)
    GossipAdd(player, 0, string.format(
        "Attuned Items: %d  |  Rack: %d / %d slots", totalAttuned, rackUsed, rackCap), SENDER_MASTERY, 0)
    GossipAdd(player, 0, string.format(
        "Visage Primary: %s %s  |  Secondary: %s %s",
        priThemeName, priLabel, secThemeName, secLabel), SENDER_MASTERY, 0)

    local sessionThreat = AP._session and AP._session[guid]
    local tLevel = sessionThreat and sessionThreat.threat or 0
    local tMomentum = sessionThreat and sessionThreat.momentum or 0
    local tEffective = (AP.GetThreatMult(tLevel, tMomentum) - 1.0) * 100
    GossipAdd(player, 0, string.format(
        "World Threat: %s (%d)  |  Momentum: %.0f%%  |  Bonus: +%.1f%%",
        AP.GetThreatName(tLevel), tLevel, tMomentum * 100, tEffective), SENDER_MASTERY, 0)

    -- Next goals
    GossipAdd(player, 0, "-- Next Goals --", SENDER_MASTERY, 0)

    -- Mastery goal
    local nextBasePct = AP.MasteryAbsorbPct(mastery + 1)
    GossipAdd(player, 0, string.format(
        "Mastery: Rank %d costs %d Essence (base absorb %.1f%%)",
        mastery + 1, nextCost, nextBasePct * 100), SENDER_MASTERY, 0)

    -- Echoes/theme unlock goal
    local nextThemeGoal = nil
    if AP.Visage then
        for _, theme in ipairs(AP.Visage.ThemeOrder) do
            local req = AP.Visage.ThemeUnlocks[theme]
            if req > 0 and totalAttuned < req then
                local name = AP.Visage.ThemeNames[theme] or theme
                nextThemeGoal = string.format("Echoes: %d attuned items unlocks %s theme", req, name)
                break
            end
        end
    end
    GossipAdd(player, 0, nextThemeGoal or "Echoes: all themes unlocked", SENDER_MASTERY, 0)

    -- Rack expansion goal
    local nextRackGoal = "Rack: maxed (20 slots)"
    if AP.Rack and AP.Rack.ExpandTiers then
        for _, tier in ipairs(AP.Rack.ExpandTiers) do
            if rackCap < tier[1] then
                local essenceCost = tier[2]
                local residueCost = tier[3]
                if essenceCost > 0 then
                    nextRackGoal = string.format("Rack: expand to %d slots — %d Essence", tier[1], essenceCost)
                else
                    nextRackGoal = string.format("Rack: expand to %d slots — %d Residue", tier[1], residueCost)
                end
                break
            end
        end
    end
    GossipAdd(player, 0, nextRackGoal, SENDER_MASTERY, 0)

    -- Visage primary tier goal
    local nextVisageGoal = "Visage: all primary tiers unlocked"
    if AP.Visage and priTier < 5 then
        local nextReq = AP.Visage.PrimaryTiers[priTier + 1]
        if nextReq then
            nextVisageGoal = string.format("Visage: Primary Tier %d at %d attuned items", priTier + 1, nextReq)
        end
    end
    GossipAdd(player, 0, nextVisageGoal, SENDER_MASTERY, 0)

    -- Buy mastery button
    GossipAdd(player, 0, " ", SENDER_MASTERY, 0)
    if aether >= nextCost then
        GossipAdd(player, 7,
            string.format("Buy Mastery Rank %d (%d Essence)", mastery + 1, nextCost),
            SENDER_MASTERY, 10)
    else
        GossipAdd(player, 0,
            string.format("Need %d more Essence for next rank", nextCost - aether),
            SENDER_MASTERY, 0)
    end

    GossipAdd(player, 1, "<< Back", SENDER_MAIN, INTID_BACK)
    GossipSend(player, "Progression Status", SENDER_MASTERY)
end

-- ---- EQUIPPED ITEMS PAGE ----
local function ShowEquippedPage(player)
    local guid  = player:GetGUIDLow()
    local slots = {0,4,5,6,7,8,9,14,15,16}

    GossipReset(player)

    local shown = 0
    for _, slot in ipairs(slots) do
        AP.Try(function()
            local item = player:GetEquippedItemBySlot(slot)
            if not item then return end

            local entry  = item:GetEntry()
            local rec    = AP.LoadItemAttune(guid, entry)
            local prog   = rec and rec.progress or 0
            local att    = rec and rec.attuned or false
            local cap    = AP.GetScaledCap(entry)
            local pct    = math.floor((prog / cap) * 100)
            local status = att and "ATTUNED" or (pct .. "%")

            -- Item name via WorldDB
            local name = "Item " .. entry
            AP.Try(function()
                local q = WorldDBQuery(string.format(
                    "SELECT `name` FROM `item_template` WHERE `entry` = %d LIMIT 1;", entry))
                if q then name = q:GetString(0) end
            end, "item name lookup")

            GossipAdd(player, 0,
                string.format("%s - %s (%d/%d)", name, status, prog, cap),
                SENDER_EQUIP, 0)
            shown = shown + 1
        end, "ShowEquippedPage slot " .. slot)

        if shown >= 10 then break end
    end

    if shown == 0 then
        GossipAdd(player, 0, "No attunable items equipped.", SENDER_EQUIP, 0)
    end

    GossipAdd(player, 1, "<< Back", SENDER_MAIN, INTID_BACK)
    GossipSend(player, "Equipped Items", SENDER_EQUIP)
end

-- ---- SLOT SPECIALIZATION PAGE ----
local function ShowSlotPage(player)
    local guid = player:GetGUIDLow()

    -- Ordered slot list so display is consistent every time
    local slotOrder = {0,1,2,4,5,6,7,8,9,10,11,12,13,14,15,16,17}
    local slotNames = {
        [0]="Head",      [1]="Neck",      [2]="Shoulder",
        [4]="Chest",     [5]="Belt",      [6]="Legs",
        [7]="Boots",     [8]="Bracers",   [9]="Gloves",
        [10]="Ring 1",   [11]="Ring 2",
        [12]="Trinket 1",[13]="Trinket 2",
        [14]="Cloak",    [15]="Main Hand",[16]="Off Hand",[17]="Ranged",
    }

    GossipReset(player)

    -- Explanatory header
    GossipAdd(player, 0,
        "Each slot gains XP as you kill mobs while wearing items.",
        SENDER_SLOT, 0)
    GossipAdd(player, 0,
        "Higher slot level = bonus absorption % for items in that slot.",
        SENDER_SLOT, 0)
    GossipAdd(player, 0, " ", SENDER_SLOT, 0)

    local hasAny = false
    local totalBonus = 0

    for _, slot in ipairs(slotOrder) do
        AP.Try(function()
            local xp        = AP.LoadSlotXP(guid, slot)
            if xp <= 0 then return end  -- skip completely empty slots

            local name      = slotNames[slot] or ("Slot " .. slot)
            local slotLevel = math.floor(math.sqrt(xp / AP.Config.SlotXpDivisor))
            local mult      = AP.SlotMultiplier(xp)
            local bonusPct  = (mult - 1) * 100

            -- XP needed for next level
            local nextLevel = math.max(1, slotLevel + 1)
            local xpForNext = (nextLevel * nextLevel) * AP.Config.SlotXpDivisor
            local xpNeeded  = xpForNext - xp

            -- Show progress even at level 0 if has XP
            local levelStr
            if slotLevel == 0 then
                levelStr = string.format("%s  Lv0  (%.0f/%d xp to Lv1)",
                    name, xp, xpForNext)
            else
                levelStr = string.format("%s  Lv%d  +%.1f%%  (%d xp to Lv%d)",
                    name, slotLevel, bonusPct, xpNeeded, nextLevel)
            end

            totalBonus = totalBonus + bonusPct
            hasAny = true
            GossipAdd(player, 0, levelStr, SENDER_SLOT, 0)
        end, "ShowSlotPage slot " .. slot)
    end

    if not hasAny then
        GossipAdd(player, 0,
            "No slot specialization yet. Kill mobs while wearing items to build slot XP.",
            SENDER_SLOT, 0)
    else
        GossipAdd(player, 0,
            string.format("Total slot bonus across all slots: +%.1f%%", totalBonus),
            SENDER_SLOT, 0)
    end

    GossipAdd(player, 1, "<< Back", SENDER_MAIN, INTID_BACK)
    GossipSend(player, "Slot Specialization", SENDER_SLOT)
end

-- ---- TALENTS PAGE ----
-- Shows all 5 stats with current rank and cost to upgrade.
-- intid 10-14 = buy rank for stat 0-4
local SENDER_TALENT_STAT = 7  -- sub-page for stat detail

local function ShowTalentPage(player)
    local guid    = player:GetGUIDLow()
    local rec     = AP.LoadMastery(guid)
    local aether  = rec and rec.aether or 0
    local talents = AP.LoadTalents(guid)

    GossipReset(player)

    GossipAdd(player, 0,
        string.format("Essence: %d  |  Spend on a stat to boost absorption.", aether),
        SENDER_TALENT, 0)

    for statIdx = 0, 4 do
        local name    = AP.StatNames[statIdx]
        local rank    = talents[statIdx] or 0
        local maxRank = (rank < AP.Config.TalentPrimaryRanks) and
                        AP.Config.TalentPrimaryRanks or AP.Config.TalentSecondaryRanks
        -- Determine if primary (highest rank among all stats, or only invested)
        local isPrimary = true
        for idx, r in pairs(talents) do
            if idx ~= statIdx and r > rank then isPrimary = false; break end
        end
        local actualMax = isPrimary and AP.Config.TalentPrimaryRanks or AP.Config.TalentSecondaryRanks
        local cost    = (rank < actualMax) and AP.TalentCost(rank, isPrimary) or 0
        local bonus   = rank * (isPrimary and AP.Config.TalentPrimaryBonus or AP.Config.TalentSecondaryBonus)

        local label
        if rank >= actualMax then
            label = string.format("%s  [Rank %d/%d -- MAXED  +%.0f%% absorb]",
                name, rank, actualMax, bonus * 100)
        else
            label = string.format("%s  [Rank %d/%d -- Next: %d Essence  +%.0f%% -> +%.0f%%]",
                name, rank, actualMax, cost,
                bonus * 100,
                (bonus + (isPrimary and AP.Config.TalentPrimaryBonus or AP.Config.TalentSecondaryBonus)) * 100)
        end

        GossipAdd(player, 6, label, SENDER_TALENT, 10 + statIdx)
    end

    GossipAdd(player, 1, "<< Back", SENDER_MAIN, INTID_BACK)
    GossipSend(player, "Talents", SENDER_TALENT)
end

local function BuyTalentRank(player, statIndex)
    local guid    = player:GetGUIDLow()
    local rec     = AP.LoadMastery(guid)
    local aether  = rec and rec.aether or 0
    local talents = AP.LoadTalents(guid)
    local rank    = talents[statIndex] or 0
    local name    = AP.StatNames[statIndex]

    -- Determine if primary
    local isPrimary = true
    for idx, r in pairs(talents) do
        if idx ~= statIndex and r > rank then isPrimary = false; break end
    end
    local maxRank = isPrimary and AP.Config.TalentPrimaryRanks or AP.Config.TalentSecondaryRanks

    if rank >= maxRank then
        AP.Try(function()
            player:SendBroadcastMessage(string.format(
                "|cff9966ff[Worldsoul]|r %s is already at max rank.", name))
        end, "talent max broadcast")
        ShowTalentPage(player)
        return
    end

    local cost = AP.TalentCost(rank, isPrimary)
    if aether < cost then
        AP.Try(function()
            player:SendBroadcastMessage(string.format(
                "|cffff4444[Worldsoul]|r Not enough Essence. Need %d, have %d.", cost, aether))
        end, "talent cost broadcast")
        ShowTalentPage(player)
        return
    end

    -- Deduct Aether and save new rank
    local newAether = aether - cost
    local newRank   = rank + 1
    CharDBQuery(string.format([[
        INSERT INTO `ap_mastery` (`guid`, `aether`, `mastery`)
        VALUES (%d, %d, 0)
        ON DUPLICATE KEY UPDATE `aether` = %d;
    ]], guid, newAether, newAether))
    AP.SaveTalent(guid, statIndex, newRank)
    CharDBQuery("COMMIT;")

    local bonus = newRank * (isPrimary and AP.Config.TalentPrimaryBonus or AP.Config.TalentSecondaryBonus)
    AP.Try(function()
        player:SendBroadcastMessage(string.format(
            "|cff9966ff[Worldsoul]|r %s Rank %d unlocked! Absorption cap +%.0f%%.",
            name, newRank, bonus * 100))
    end, "talent buy broadcast")
    AP.Log(string.format("Talent: guid=%d stat=%d rank=%d", guid, statIndex, newRank))

    ShowTalentPage(player)
end

-- ---- VIEW ATTUNED ITEMS PAGE ----
-- Shows total absorbed stats across all attuned items account-wide,
-- filtered by armor class. Mirrors Synastria's "View Attuned Items" panel.
local function ShowAttunesPage(player)
    local guid        = player:GetGUIDLow()
    local accountId   = AP.GetAccountId(guid)
    local playerClass = player:GetClass()
    local level       = player:GetLevel()
    local rec         = AP.LoadMastery(guid)
    local masteryRank = rec and rec.mastery or 0

    local dbgAbsorb = AP.MasteryAbsorbPct(masteryRank)
    local dbgLevel  = AP.LevelAbsorbScalar(level)
    AP.Debug(string.format("AttunesPage: guid=%d mastery=%d absorbPct=%.4f level=%d levelScale=%.4f",
        guid, masteryRank, dbgAbsorb, level, dbgLevel))

    GossipReset(player)

    -- Count total attuned items account-wide
    local totalAttuned = 0
    AP.Try(function()
        local q = CharDBQuery(string.format(
            "SELECT COUNT(*) FROM `ap_item_attune` WHERE `guid` = %d AND `attuned` = 1;",
            guid))
        if q then totalAttuned = tonumber(q:GetUInt32(0)) or 0 end
    end, "attuned count")

    -- Count account-wide snapshots matching this class
    local accountSnapshots = 0
    AP.Try(function()
        local q = CharDBQuery(string.format(
            "SELECT COUNT(*) FROM `ap_item_snapshot` WHERE `guid` = %d;",
            accountId))
        if q then accountSnapshots = tonumber(q:GetUInt32(0)) or 0 end
    end, "snapshot count")

    GossipAdd(player, 0,
        string.format("Attuned items this character: %d", totalAttuned),
        SENDER_ATTUNES, 0)
    GossipAdd(player, 0,
        string.format("Account-wide snapshots (class-filtered): %d", accountSnapshots),
        SENDER_ATTUNES, 0)

    -- Calculate absorbed stats
    local absorb = AP.CalculateAbsorptionAccountWide(guid, playerClass, level, masteryRank)

    GossipAdd(player, 0, " ", SENDER_ATTUNES, 0)
    GossipAdd(player, 0, "-- Absorbed Stats (current) --", SENDER_ATTUNES, 0)
    GossipAdd(player, 0,
        string.format("STR  +%.1f    AGI  +%.1f    STA  +%.1f",
            absorb.str, absorb.agi, absorb.sta),
        SENDER_ATTUNES, 0)
    GossipAdd(player, 0,
        string.format("INT  +%.1f    SPI  +%.1f",
            absorb["int"], absorb.spi),
        SENDER_ATTUNES, 0)

    -- Show mastery absorption percentage
    local masteryPct = AP.MasteryAbsorbPct(masteryRank)
    local levelScale = AP.LevelAbsorbScalar(level)
    GossipAdd(player, 0, " ", SENDER_ATTUNES, 0)
    GossipAdd(player, 0,
        string.format("Mastery Rank: %d  (Base %.0f%% x Level Scalar %.0f%% = Effective %.1f%%)",
            masteryRank,
            masteryPct * 100,
            levelScale * 100,
            masteryPct * levelScale * 100),
        SENDER_ATTUNES, 0)

    GossipAdd(player, 1, "<< Back", SENDER_MAIN, INTID_BACK)
    GossipSend(player, "Attuned Items", SENDER_ATTUNES)
end
local function ShowThreatPage(player)
    local guid    = player:GetGUIDLow()
    local session = AP._session and AP._session[guid] or { threat = 0, momentum = 0 }
    local threat  = session.threat or 0
    local momentum = session.momentum or 0
    local maxT    = AP.Config.ThreatMax
    local name    = AP.GetThreatName(threat)
    local ceiling = AP.GetThreatCeiling(threat) * 100
    local effective = (AP.GetThreatMult(threat, momentum) - 1.0) * 100
    local safety  = AP.GetSafetyScalar(threat) * 100

    GossipReset(player)
    GossipAdd(player, 0, "World Threat -- Shape your challenge.", SENDER_TOGGLE, 0)
    GossipAdd(player, 0,
        string.format("Threat Level: |cffffff00%s (%d)|r", name, threat),
        SENDER_TOGGLE, 0)
    GossipAdd(player, 0,
        string.format("Reward Ceiling: +%.0f%%  |  Momentum: %.0f%%  |  Effective: +%.1f%%",
            ceiling, momentum * 100, effective),
        SENDER_TOGGLE, 0)

    if threat > 0 then
        local pen = AP.GetDeathPenalty(threat)
        GossipAdd(player, 0, "-- Death Penalty --", SENDER_TOGGLE, 0)
        GossipAdd(player, 0, string.format(
            "Momentum resets | Attunement progress -%d%% | Essence -%d%% (cap %d)",
            pen[1] * 100, pen[2] * 100, pen[3]), SENDER_TOGGLE, 0)
        GossipAdd(player, 0, string.format(
            "XP Debt: next %d kills at %.0f%% gains",
            pen[4], pen[5] * 100), SENDER_TOGGLE, 0)
        GossipAdd(player, 0, string.format(
            "Safety: Life Leech at %.0f%% | Res Resilience at %.0f%%", safety, safety),
            SENDER_TOGGLE, 0)
        GossipAdd(player, 0, "Trivial dampener tightened", SENDER_TOGGLE, 0)
    end

    -- Active debt display
    local debtKills = session.debtKills or 0
    local debtMult  = session.debtMult or 1.0
    if debtKills > 0 then
        GossipAdd(player, 0, string.format(
            "|cffff8800Worldsoul Debt:|r %d kills remaining at %.0f%% gains",
            debtKills, debtMult * 100), SENDER_TOGGLE, 0)
    end

    GossipAdd(player, 0,
        "Affected: Essence, Attunement XP, Slot XP, Rack XP, Fragments",
        SENDER_TOGGLE, 0)
    if threat > 0 then
        local caps = AP.Config.ThreatContentCaps
        GossipAdd(player, 0, string.format(
            "Content Cap: normal +%.0f%% | elite +%.0f%% | boss +%.0f%% | raid +%.0f%%",
            caps.same_normal * 100, caps.elite * 100, caps.dungeon_boss * 100, caps.raid_boss * 100),
            SENDER_TOGGLE, 0)
        GossipAdd(player, 0, "Full bonus requires elite, dungeon, or raid content.", SENDER_TOGGLE, 0)
    end

    GossipAdd(player, 0, "-- Adjust Threat --", SENDER_TOGGLE, 0)
    if threat < maxT then
        local nextName = AP.GetThreatName(threat + 1)
        local nextCeil = AP.GetThreatCeiling(threat + 1) * 100
        GossipAdd(player, 7,
            string.format("Increase to %s (%d)  [ceiling +%.0f%%]", nextName, threat + 1, nextCeil),
            SENDER_TOGGLE, 20)
    end
    if threat > 0 then
        local prevName = AP.GetThreatName(threat - 1)
        local prevCeil = AP.GetThreatCeiling(threat - 1) * 100
        GossipAdd(player, 1,
            string.format("Decrease to %s (%d)  [ceiling +%.0f%%, resets momentum]", prevName, threat - 1, prevCeil),
            SENDER_TOGGLE, 21)
        GossipAdd(player, 1, "Reset to Peaceful (0)  [resets momentum]", SENDER_TOGGLE, 22)
    end

    GossipAdd(player, 1, "<< Back", SENDER_MAIN, INTID_BACK)
    GossipSend(player, "World Threat", SENDER_TOGGLE)
end

-- ============================================================
-- DISPATCH: AP.OpenUI
-- Called from ap_events.lua chat parser and from GM tools.
-- ============================================================
function AP.OpenUI(player)
    AP.Try(function()
        ShowMainMenu(player)
        AP.Log("UI open via Chat for guid=" .. tostring(player:GetGUIDLow()))
    end, "AP.OpenUI")
end

-- ============================================================
-- GOSSIP EVENT HANDLER
-- Confirmed signature from live probe:
--   RegisterPlayerGossipEvent(menu_id, 2, callback)
--   menu_id must match the sender passed to GossipSendMenu
--   callback args: (event, player, sender, intid)
--
-- Since we use different sender IDs per page, we register one
-- handler per sender value.
-- ============================================================

local function HandleGossipSelect(player, sender, intid)
    AP.Try(function()
        AP.Log(string.format("[AttunementPlus] GossipSelect: sender=%d intid=%d", sender, intid))

        -- Back button: only fires from the explicit "<< Back" item (sender=SENDER_MAIN, intid=0).
        -- Display-only items on sub-pages also use intid=0 but with their own sender,
        -- so we require sender == SENDER_MAIN to distinguish.
        if intid == INTID_BACK and sender == SENDER_MAIN then
            ShowMainMenu(player)
            return
        end

        -- ---- MAIN MENU CLICKS ----
        if sender == SENDER_MAIN then
            if intid == 1 then ShowProgressionPage(player)
            elseif intid == 2 then ShowEquippedPage(player)
            elseif intid == 3 then ShowSlotPage(player)
            elseif intid == 4 then ShowTalentPage(player)
            elseif intid == 5 then ShowThreatPage(player)
            elseif intid == 6 then ShowAttunesPage(player)
            end

        -- ---- PROGRESSION / MASTERY CLICKS ----
        elseif sender == SENDER_MASTERY then
            if intid == 0 then
                ShowProgressionPage(player)
            elseif intid == 10 then
                -- Buy mastery rank
                local guid    = player:GetGUIDLow()
                local rec     = AP.LoadMastery(guid)
                local aether  = rec and rec.aether or 0
                local mastery = rec and rec.mastery or 0
                local cost    = AP.MasteryCost(mastery)

                if aether >= cost then
                    local newAether  = aether - cost
                    local newMastery = mastery + 1
                    CharDBQuery(string.format([[
                        INSERT INTO `ap_mastery` (`guid`, `aether`, `mastery`)
                        VALUES (%d, %d, %d)
                        ON DUPLICATE KEY UPDATE `aether` = %d, `mastery` = %d;
                    ]], guid, newAether, newMastery, newAether, newMastery))
                    CharDBQuery(string.format(
                        "INSERT INTO `ap_mastery_spend` (`guid`, `amount`) VALUES (%d, %d);",
                        guid, cost))
                    AP.Try(function()
                        player:SendBroadcastMessage(string.format(
                            "|cff9966ff[Worldsoul]|r Mastery Rank %d purchased!", newMastery))
                    end, "SendBroadcastMessage mastery buy")
                    AP.Log("Mastery purchased: guid=" .. guid .. " rank=" .. newMastery)
                else
                    AP.Try(function()
                        player:SendBroadcastMessage("|cffff4444[Worldsoul]|r Not enough Essence.")
                    end, "SendBroadcastMessage mastery fail")
                end
                ShowProgressionPage(player)
            end

        -- ---- EQUIP PAGE CLICKS ----
        elseif sender == SENDER_EQUIP then
            ShowEquippedPage(player)

        -- ---- SLOT PAGE CLICKS ----
        elseif sender == SENDER_SLOT then
            ShowSlotPage(player)

        -- ---- TALENT PAGE CLICKS ----
        elseif sender == SENDER_TALENT then
            -- intid 10-14 = buy rank for stat 0-4
            if intid >= 10 and intid <= 14 then
                BuyTalentRank(player, intid - 10)
            else
                ShowTalentPage(player)
            end

        -- ---- WORLD THREAT PAGE CLICKS ----
        elseif sender == SENDER_TOGGLE then
            local guid    = player:GetGUIDLow()
            local session = AP._session and AP._session[guid]
            if not session then
                AP._session[guid] = { threat = 0, momentum = 0.0, momentumKills = 0, kills = {} }
                session = AP._session[guid]
            end
            if intid == 0 then
                ShowThreatPage(player)
            elseif intid == 20 then
                if session.threat < AP.Config.ThreatMax then
                    local old = session.threat
                    session.threat = session.threat + 1
                    if AP.SaveThreatToDB then AP.SaveThreatToDB(guid, session) end
                    if AP.API and AP.API.DispatchHook then
                        AP.API.DispatchHook("OnThreatChanged", { guid=guid, oldLevel=old, newLevel=session.threat, momentum=session.momentum })
                    end
                    player:SendBroadcastMessage(string.format(
                        "|cff9966ff[Worldsoul]|r World Threat raised to %s (%d).",
                        AP.GetThreatName(session.threat), session.threat))
                end
                ShowThreatPage(player)
            elseif intid == 21 then
                if session.threat > 0 then
                    local old = session.threat
                    session.threat = session.threat - 1
                    session.momentum = 0.0
                    session.momentumKills = 0
                    if AP.SaveThreatToDB then AP.SaveThreatToDB(guid, session) end
                    if AP.API and AP.API.DispatchHook then
                        AP.API.DispatchHook("OnThreatChanged", { guid=guid, oldLevel=old, newLevel=session.threat, momentum=0 })
                    end
                    player:SendBroadcastMessage(string.format(
                        "|cff888888[Worldsoul]|r World Threat lowered to %s (%d). Momentum reset.",
                        AP.GetThreatName(session.threat), session.threat))
                end
                ShowThreatPage(player)
            elseif intid == 22 then
                local old = session.threat
                session.threat = 0
                session.momentum = 0.0
                session.momentumKills = 0
                if AP.SaveThreatToDB then AP.SaveThreatToDB(guid, session) end
                if AP.API and AP.API.DispatchHook then
                    AP.API.DispatchHook("OnThreatChanged", { guid=guid, oldLevel=old, newLevel=0, momentum=0 })
                end
                player:SendBroadcastMessage(
                    "|cff888888[Worldsoul]|r World Threat reset to Peaceful. Momentum cleared.")
                ShowThreatPage(player)
            end

        -- ---- ATTUNES PAGE CLICKS ----
        elseif sender == SENDER_ATTUNES then
            ShowAttunesPage(player)

        -- ---- AETHER SINKS (sender range 100-110) ----
        elseif sender >= 100 and sender <= 110 then
            if AP.Sinks and AP.Sinks.OnSelect then
                AP.Sinks.OnSelect(player, player, sender - 100, intid, nil)
            end

        -- ---- AURA LAB (sender range 210-216) ----
        elseif sender >= 210 and sender <= 216 then
            if AP.AuraLab and AP.AuraLab.OnSelect then
                local rOk, rErr = pcall(AP.AuraLab.OnSelect, player, player, sender, intid)
                if not rOk then
                    print("[Echoes] ERROR in AuraLab.OnSelect: " .. tostring(rErr))
                end
            end

        -- ---- VISAGE (sender range 200-209, 217-219) ----
        elseif (sender >= 200 and sender <= 209) or (sender >= 217 and sender <= 219) then
            if AP.Visage and AP.Visage.OnSelect then
                AP.Visage.OnSelect(player, player, sender, intid)
            end

        -- ---- WORLDSOUL CODEX (sender range 220-232) ----
        elseif sender >= 220 and sender <= 232 then
            if AP.Codex and AP.Codex.OnSelect then
                AP.Codex.OnSelect(player, player, sender, intid)
            end

        -- ---- ATTUNEMENT RACK (sender range 240-247) ----
        elseif sender >= 240 and sender <= 247 then
            if AP.Rack and AP.Rack.OnSelect then
                local rOk, rErr = pcall(AP.Rack.OnSelect, player, player, sender, intid)
                if not rOk then
                    print("[AttunementPlus] ERROR in Rack.OnSelect: " .. tostring(rErr))
                end
            else
                print("[AttunementPlus] AP.Rack.OnSelect is nil!")
            end

        -- ---- LEGACY FORGE (sender range 248-255) ----
        elseif sender >= 248 and sender <= 255 then
            if AP.Forge and AP.Forge.OnSelect then
                AP.Forge.OnSelect(player, player, sender, intid)
            end

        else
            AP.Try(function() player:GossipComplete() end, "GossipComplete fallback")
        end

    end, "AP gossip select")
end

-- Register one handler per sender value -- menu_id must match the
-- sender passed to GossipSendMenu for the event to fire.
-- Confirmed callback signature from live probe:
--   (event, player, player, sender, intid)
-- The player object appears twice -- skip the duplicate with _.
for _, sid in ipairs({SENDER_MAIN, SENDER_MASTERY, SENDER_EQUIP, SENDER_SLOT, SENDER_TALENT, SENDER_TOGGLE, SENDER_ATTUNES, 102, 201, 210, 211, 212, 213, 214, 215, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 240, 241, 242, 243, 244, 245, 250, 251, 252, 253, 254, 255}) do
    local s = sid
    RegisterPlayerGossipEvent(s, 2, function(event, player, _, sender, intid)
        HandleGossipSelect(player, sender, intid)
    end)
end

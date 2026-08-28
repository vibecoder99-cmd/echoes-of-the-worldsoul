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
    AP.Try(function() AP.UI.ClearMenu(player) end, "GossipClearMenu")
end

local function GossipAdd(player, icon, text, sender, intid)
    AP.Try(function()
        AP.UI.AddItem(player,icon or 0, text, sender or 0, intid or 0)
    end, "GossipMenuAddItem")
end

local function GossipSend(player, text, sender)
    AP.Try(function()
        AP.UI.SendMenu(player,1, player, sender or 99)
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
    local guid      = AP.RT.GetGUID(player)
    local accountId = AP.GetAccountId(guid)
    local rec       = AP.LoadMastery(guid)
    local aether    = rec and rec.aether  or 0
    local mastery   = rec and rec.mastery or 0
    local level     = AP.RT.GetLevel(player)

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
        local q = AP.DB.Query(string.format(
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

    -- Layer 1: explain -> Layer 2: current state -> Layer 3: link to advanced details.
    -- Replaces the old dense "Effective Absorption: %.1f%% (Base %.1f%% x Level Scalar %.1f%%)"
    -- line, which led with an unframed three-number formula (E2j12 UX audit finding).
    GossipAdd(player, 0, "Echoes of the Worldsoul -- Progression", SENDER_MASTERY, 0)
    GossipAdd(player, 0,
        "Mastery determines how much of your attuned gear's stats stay with you permanently, "..
        "even after you unequip the item or Dissolve it at the Legacy Forge.",
        SENDER_MASTERY, 0)
    GossipAdd(player, 0, string.format(
        "Level: %d  |  Mastery Rank: %d  |  Absorption: %.1f%%",
        level, mastery, effectivePct * 100), SENDER_MASTERY, 0)
    GossipAdd(player, 0, string.format(
        "Essence: %d  |  Worldsoul Residue: %d", aether, residue), SENDER_MASTERY, 0)
    GossipAdd(player, 0, string.format(
        "Attuned Items: %d  |  Rack: %d / %d slots", totalAttuned, rackUsed, rackCap), SENDER_MASTERY, 0)
    GossipAdd(player, 0, string.format(
        "Visage Primary: %s %s  |  Secondary: %s %s",
        priThemeName, priLabel, secThemeName, secLabel), SENDER_MASTERY, 0)
    GossipAdd(player, 0, "View exact formula / advanced details", SENDER_MASTERY, 20)

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

-- ---- PROGRESSION ADVANCED DETAILS PAGE ----
-- Layer 3 of the three-layer model: the exact formula breakdown and
-- session-scoped World Threat readout that used to lead the main
-- Progression page (E2j12 UX audit -- moved here, not deleted).
local function ShowProgressionDetailPage(player)
    local guid    = AP.RT.GetGUID(player)
    local rec     = AP.LoadMastery(guid)
    local mastery = rec and rec.mastery or 0
    local level   = AP.RT.GetLevel(player)

    local basePct      = AP.MasteryAbsorbPct(mastery)
    local levelScale   = AP.LevelAbsorbScalar(level)
    local effectivePct = basePct * levelScale

    GossipReset(player)

    GossipAdd(player, 0, "Progression -- Advanced Details", SENDER_MASTERY, 0)
    GossipAdd(player, 0, string.format(
        "Effective Absorption: %.1f%%  (Base %.1f%% x Level Scalar %.1f%%)",
        effectivePct * 100, basePct * 100, levelScale * 100), SENDER_MASTERY, 0)
    GossipAdd(player, 0,
        "Base Absorption starts at 5%% and grows toward ~85%% as you invest Essence into Mastery Ranks. "..
        "Level Scalar phases this in gradually from level 9 to level 80.",
        SENDER_MASTERY, 0)
    GossipAdd(player, 0,
        "Talents multiply this per-stat (see the Talents page for their exact formula). "..
        "Armor and Weapon-DPS absorption use this same percentage but are not affected by Talents.",
        SENDER_MASTERY, 0)

    local sessionThreat = AP._session and AP._session[guid]
    local tLevel = sessionThreat and sessionThreat.threat or 0
    local tMomentum = sessionThreat and sessionThreat.momentum or 0
    local tEffective = (AP.GetThreatMult(tLevel, tMomentum) - 1.0) * 100
    GossipAdd(player, 0, string.format(
        "World Threat (session-scoped, not permanent): %s (%d)  |  Momentum: %.0f%%  |  Bonus: +%.1f%%",
        AP.GetThreatName(tLevel), tLevel, tMomentum * 100, tEffective), SENDER_MASTERY, 0)

    GossipAdd(player, 1, "<< Back to Progression Status", SENDER_MASTERY, 0)
    GossipSend(player, "Progression Details", SENDER_MASTERY)
end

-- ---- EQUIPPED ITEMS PAGE ----
local function ShowEquippedPage(player)
    local guid  = AP.RT.GetGUID(player)
    local slots = {0,4,5,6,7,8,9,14,15,16}

    GossipReset(player)

    local shown = 0
    for _, slot in ipairs(slots) do
        AP.Try(function()
            local item = AP.RT.GetEquippedItem(player,slot)
            if not item then return end

            local entry  = AP.RT.GetItemEntry(item)
            local rec    = AP.LoadItemAttune(guid, entry)
            local prog   = rec and rec.progress or 0
            local att    = rec and rec.attuned or false
            local cap    = AP.GetScaledCap(entry)
            local pct    = math.floor((prog / cap) * 100)
            local status = att and "ATTUNED" or (pct .. "%")

            -- Item name via WorldDB
            local name = "Item " .. entry
            AP.Try(function()
                local q = AP.DB.WorldQuery(string.format(
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
    local guid = AP.RT.GetGUID(player)

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
    local guid    = AP.RT.GetGUID(player)
    local rec     = AP.LoadMastery(guid)
    local aether  = rec and rec.aether or 0
    local talents = AP.LoadTalents(guid)
    local snapshot = AP.BuildTalentSnapshot(talents)

    GossipReset(player)

    GossipAdd(player, 0,
        "Talents specialize your Mastery absorption into one or two stats you choose. "..
        "Primary stats allow up to 3 ranks, Secondary stats up to 2. This bonus has no "..
        "separate ceiling of its own -- but spreading investment across more stats reduces "..
        "how strongly each one is emphasized.",
        SENDER_TALENT, 0)
    GossipAdd(player, 0,
        string.format("Essence: %d", aether),
        SENDER_TALENT, 0)
    GossipAdd(player, 0, "View exact formula / advanced details", SENDER_TALENT, 20)

    for statIdx = 0, 4 do
        local stat = snapshot.stats[statIdx]
        local name, rank, actualMax = stat.name, stat.rank, stat.maxRank
        local cost, bonus = stat.nextCost, stat.bonusPct / 100

        local label
        if rank >= actualMax then
            label = string.format("%s  [Rank %d/%d -- MAXED  +%.0f%% absorb]",
                name, rank, actualMax, bonus * 100)
        else
            label = string.format("%s  [Rank %d/%d -- Next: %d Essence  +%.0f%% -> +%.0f%%]",
                name, rank, actualMax, cost,
                bonus * 100,
                stat.nextBonusPct)
        end

        GossipAdd(player, 6, label, SENDER_TALENT, 10 + statIdx)
    end

    GossipAdd(player, 1, "<< Back", SENDER_MAIN, INTID_BACK)
    GossipSend(player, "Talents", SENDER_TALENT)
end

local function BuyTalentRank(player, statIndex)
    local name = AP.StatNames[statIndex]
    local result = AP.API and AP.API.ExecuteTalentPurchase
        and AP.API.ExecuteTalentPurchase(player, statIndex)
        or { ok=false, status="SERVICE_UNAVAILABLE" }
    if result.status == "MAX_RANK" then
        AP.Try(function()
            AP.RT.SendMessage(player,string.format(
                "|cff9966ff[Worldsoul]|r %s is already at max rank.", name))
        end, "talent max broadcast")
        ShowTalentPage(player)
        return
    end
    if result.status == "INSUFFICIENT_ESSENCE" then
        AP.Try(function()
            AP.RT.SendMessage(player,string.format(
                "|cffff4444[Worldsoul]|r Not enough Essence. Need %d, have %d.",
                result.cost or 0, result.oldBalance or 0))
        end, "talent cost broadcast")
        ShowTalentPage(player)
        return
    end
    if not result.ok then
        AP.Try(function()
            AP.RT.SendMessage(player,"|cffff4444[Worldsoul]|r Talent investment is currently unavailable.")
        end, "talent unavailable broadcast")
        ShowTalentPage(player)
        return
    end
    AP.Try(function()
        AP.RT.SendMessage(player,string.format(
            "|cff9966ff[Worldsoul]|r %s Rank %d unlocked! Talent amplifier is now +%.0f%% "..
            "(no separate cap on this bonus -- spreading investment across more stats reduces each one's amplifier).",
            name, result.newRank or 0, result.newBonusPct or 0))
    end, "talent buy broadcast")

    ShowTalentPage(player)
end

-- ---- TALENT ADVANCED DETAILS PAGE ----
-- Layer 3: the exact formula. No "cap" language anywhere here -- talentMult is an
-- uncapped per-stat multiplier layered on top of Mastery's own separately-capped
-- (soft ~85% asymptote) absorption percentage. See E2j12 Permanent Stat Registry (§4).
local function ShowTalentDetailPage(player)
    GossipReset(player)

    GossipAdd(player, 0, "Talents -- Advanced Details", SENDER_TALENT, 0)
    GossipAdd(player, 0, string.format(
        "Primary stat: +%.0f%% per rank, up to %d ranks (max +%.0f%%).",
        AP.Config.TalentPrimaryBonus * 100, AP.Config.TalentPrimaryRanks,
        AP.Config.TalentPrimaryBonus * AP.Config.TalentPrimaryRanks * 100), SENDER_TALENT, 0)
    GossipAdd(player, 0, string.format(
        "Secondary stat: +%.0f%% per rank, up to %d ranks (max +%.0f%%).",
        AP.Config.TalentSecondaryBonus * 100, AP.Config.TalentSecondaryRanks,
        AP.Config.TalentSecondaryBonus * AP.Config.TalentSecondaryRanks * 100), SENDER_TALENT, 0)
    GossipAdd(player, 0,
        "This bonus is a multiplier applied on top of your Mastery Absorption percentage for "..
        "that one stat -- it has no independent ceiling of its own. The number of ranks you can "..
        "buy is capped, but the resulting bonus is not.",
        SENDER_TALENT, 0)
    GossipAdd(player, 0,
        "Investing in more than one distinct stat reduces the bonus on each (a diminishing-returns "..
        "penalty for spreading investment thinner). Armor and Weapon-DPS absorption are not affected "..
        "by Talents at all.",
        SENDER_TALENT, 0)

    GossipAdd(player, 1, "<< Back to Talents", SENDER_TALENT, 0)
    GossipSend(player, "Talent Details", SENDER_TALENT)
end

-- ---- VIEW ATTUNED ITEMS PAGE ----
-- Shows total absorbed stats across all attuned items account-wide,
-- filtered by armor class. Mirrors Synastria's "View Attuned Items" panel.
local function ShowAttunesPage(player)
    local guid        = AP.RT.GetGUID(player)
    local accountId   = AP.GetAccountId(guid)
    local playerClass = AP.RT.GetClass(player)
    local level       = AP.RT.GetLevel(player)
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
        local q = AP.DB.Query(string.format(
            "SELECT COUNT(*) FROM `ap_item_attune` WHERE `guid` = %d AND `attuned` = 1;",
            guid))
        if q then totalAttuned = tonumber(q:GetUInt32(0)) or 0 end
    end, "attuned count")

    -- Count account-wide snapshots matching this class
    local accountSnapshots = 0
    AP.Try(function()
        local q = AP.DB.Query(string.format(
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
    local guid    = AP.RT.GetGUID(player)
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
        AP.Log("UI open via Chat for guid=" .. tostring(AP.RT.GetGUID(player)))
    end, "AP.OpenUI")
end

-- ============================================================
-- GOSSIP EVENT HANDLER
-- Confirmed signature from live probe:
--   AP.RT.RegisterPlayerGossipEvent(menu_id, 2, callback)
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
                -- Buy mastery rank - delegates to the shared AP.Mastery.Purchase service
                -- (E2j5) so the human menu and the bot bridge use exactly one implementation.
                local result = AP.Mastery.Purchase(player)
                if result.status == "SUCCESS" then
                    AP.Try(function()
                        AP.RT.SendMessage(player,string.format(
                            "|cff9966ff[Worldsoul]|r Mastery Rank %d purchased!", result.newRank))
                    end, "SendBroadcastMessage mastery buy")
                elseif result.status == "DATABASE_FAILURE" then
                    AP.Try(function()
                        AP.RT.SendMessage(player,"|cffff4444[Worldsoul]|r Purchase failed - try again.")
                    end, "SendBroadcastMessage mastery fail")
                else
                    AP.Try(function()
                        AP.RT.SendMessage(player,"|cffff4444[Worldsoul]|r Not enough Essence.")
                    end, "SendBroadcastMessage mastery fail")
                end
                ShowProgressionPage(player)
            elseif intid == 20 then
                ShowProgressionDetailPage(player)
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
            elseif intid == 20 then
                ShowTalentDetailPage(player)
            else
                ShowTalentPage(player)
            end

        -- ---- WORLD THREAT PAGE CLICKS ----
        elseif sender == SENDER_TOGGLE then
            if intid == 0 then
                ShowThreatPage(player)
            elseif intid == 20 then
                local result = AP.API and AP.API.ExecuteWorldThreatAction
                    and AP.API.ExecuteWorldThreatAction(player, "increase")
                if result and result.ok then
                    AP.RT.SendMessage(player,string.format(
                        "|cff9966ff[Worldsoul]|r World Threat raised to %s (%d).",
                        result.name, result.newLevel))
                end
                ShowThreatPage(player)
            elseif intid == 21 then
                local result = AP.API and AP.API.ExecuteWorldThreatAction
                    and AP.API.ExecuteWorldThreatAction(player, "decrease")
                if result and result.ok then
                    AP.RT.SendMessage(player,string.format(
                        "|cff888888[Worldsoul]|r World Threat lowered to %s (%d). Momentum reset.",
                        result.name, result.newLevel))
                end
                ShowThreatPage(player)
            elseif intid == 22 then
                local result = AP.API and AP.API.ExecuteWorldThreatAction
                    and AP.API.ExecuteWorldThreatAction(player, "reset")
                if result and result.ok then
                    AP.RT.SendMessage(player,
                        "|cff888888[Worldsoul]|r World Threat reset to Peaceful. Momentum cleared.")
                end
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
            AP.Try(function() AP.UI.CloseMenu(player) end, "GossipComplete fallback")
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
    AP.RT.RegisterPlayerGossipEvent(s, 2, function(event, player, _, sender, intid)
        HandleGossipSelect(player, sender, intid)
    end)
end

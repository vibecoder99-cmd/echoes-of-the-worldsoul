-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- ap_core.lua
-- Echoes of the Worldsoul — Core Configuration, DB Bootstrap, Math
-- ============================================================
-- Responsibilities:
--   * AP global namespace and config
--   * Database table creation (non-destructive)
--   * Core math: mastery curve, absorption, slot multiplier
--   * Stat snapshot helpers
--   * Aether grant/read helpers
--   * Capability flags (set by zz_eluna_probe.lua on login)
-- ============================================================

AP = AP or {}

-- ============================================================
-- VERSION
-- Single source of truth. Bump on every release:
--   PATCH: bug fixes, balance, text changes (no schema changes)
--   MINOR: new features, new tables, backward-compatible additions
--   MAJOR: breaking schema changes or removed features
-- The server package version is independent of the client AddOn version.
-- ============================================================
AP.VERSION = "2.1.1"

-- ============================================================
-- CAPABILITY FLAGS
-- These are populated by zz_eluna_probe.lua at login.
-- Default to false until confirmed.
-- ============================================================
AP.Cap = AP.Cap or {
    SetStat        = false,  -- Player:SetStat — currently NO on this build
    IsQuestRewarded = false, -- Player:IsQuestRewarded — currently NO on this build
    RegisterCommand = false, -- RegisterCommand — currently NO on this build
}

-- ============================================================
-- CONFIGURATION
-- All tuning lives here. Edit these values to adjust difficulty.
-- ============================================================
AP.Config = {

    -- Staged DML/ALE production target identity (non-gameplay setting).
    DMLMode = true,

    -- XP-based attunement (Synastria design)
    -- Progress per item = (XP earned / equippedCount) * XpToAttune * rarityMult
    --
    -- XpToAttune = 0.1 — reduces the XP-to-progress conversion so attunement
    -- feels like a meaningful grind rather than something that happens in one run.
    --
    -- Cap scaling uses a QUADRATIC formula: cap = CapPerItem * (reqLevel/80)^2
    -- This makes high-level gear MUCH harder to attune than low-level gear:
    --   reqLevel  1: cap ~100    (gray starter gear — ~170 kills)
    --   reqLevel 20: cap ~625    (early greens — ~1 zone)
    --   reqLevel 40: cap ~2500   (mid-game blues — a few dungeon runs)
    --   reqLevel 60: cap ~5625   (MC/classic epics — ~8 MC clears)
    --   reqLevel 70: cap ~7656   (TBC blues — ~5 Utgarde runs)
    --   reqLevel 80: cap ~10000  (ICC epics — ~13 ICC clears)
    --
    -- This prevents the Brewfest exploit loop problem — content naturally
    -- appropriate to your gear level attunes it at a fun pace.
    CapPerItem     = 10000,
    XpToAttune     = 0.1,   -- down from 1.0
    BonusBoss      = 1500,

    -- Rarity multipliers — gray/white attune faster (low stats anyway)
    -- epics/legendaries attune slower (powerful absorbed stats)
    RarityMult = {
        [0] = 2.00,   -- Poor/Gray:      ~100 kills at level 5
        [1] = 1.50,   -- Common/White:   ~133 kills
        [2] = 1.00,   -- Uncommon/Green: ~200 kills
        [3] = 0.60,   -- Rare/Blue:      ~333 kills
        [4] = 0.30,   -- Epic/Purple:    ~667 kills
        [5] = 0.15,   -- Legendary:      ~1333 kills
        [6] = 0.15,   -- Artifact:       ~1333 kills
    },

    -- Aether rewards
    -- Normal kills: small steady flow, feels meaningful but not farmable.
    -- Boss Aether scales with creature level so low-level dungeon farming
    -- is not an efficient Aether printer at high levels.
    -- Formula: floor(AetherBossBase * (creatureLevel/80)^BossLevelExp * raidMult)
    -- Level 15 boss (RFC):  ~4 Aether
    -- Level 30 boss (BFD):  ~17 Aether
    -- Level 45 boss (ZF):   ~38 Aether
    -- Level 60 boss (MC):   ~68 Aether
    -- Level 73 boss (Norm): ~100 Aether
    -- Level 80 boss (ICC):  ~160 Aether
    -- Level 80 raid boss:   ~400 Aether (2.5x)
    AetherKillNormal   = 25,   -- up from 3
    AetherKillElite    = 75,   -- up from 10
    -- Boss formula: floor(AetherBossBase * (level/80)^BossLevelExp * raidMult)
    -- Level 80 dungeon boss: 750 * 1.0^2 * 1.0 = 750
    -- Level 80 raid boss:    750 * 1.0^2 * 6.67 ≈ 5000
    -- Level 60 dungeon boss: 750 * (60/80)^2 = 750 * 0.5625 ≈ 422
    AetherBossBase     = 750,  -- up from 160
    AetherBossLevelExp = 2.0,
    AetherBossRaidMult = 6.67, -- up from 2.5

    -- Quest Aether: ~8x increase proportional to kill reward scaling
    AetherQuestShort  = 60,   -- up from 8
    AetherQuestNormal = 150,  -- up from 18
    AetherQuestLong   = 250,  -- up from 30

    -- Mastery cost: cost(n) = MasteryCostBase * n^MasteryCostExp
    -- Tuned for dungeon-efficient Aether (~675/hr) so mastery feels like
    -- a long arc across the full 1-80 journey, not something spammable.
    -- Rank 1:   400  (~0.6h)    Rank 5:  4472  (~16h cumulative)
    -- Rank 10: 12649  (~90h cumulative) — a true endgame investment.
    MasteryCostBase   = 400,
    MasteryCostExp    = 1.5,

    -- Talent costs use a tripling curve: each rank costs 3x the previous.
    -- Primary stat (3 ranks max):
    --   Rank 1:  2000  — mid-teens, after first dungeon solos
    --   Rank 2:  6000  — level 30-40 territory
    --   Rank 3: 18000  — endgame, post-60 investment
    -- Secondary stat (2 ranks max):
    --   Rank 1:  1000  — level 20s
    --   Rank 2:  3000  — level 40s
    TalentCostPrimary   = 2000,
    TalentCostSecondary = 1000,

    -- Mastery absorption curve: 5% + 80% * (1 - e^(-0.038 * mastery))
    MasteryBaseAbsorb  = 0.05,
    MasteryMaxAbsorb   = 0.80,
    MasteryDecayK      = 0.038,

    -- Talent ranks
    TalentPrimaryRanks   = 3,
    TalentPrimaryBonus   = 0.12,   -- +12% amplifier per rank
    TalentSecondaryRanks = 2,
    TalentSecondaryBonus = 0.08,   -- +8% amplifier per rank
    TalentDistinctPenalty = 0.85,  -- per additional distinct stat beyond first

    -- Slot specialization
    SlotXpPerKill    = 1,
    SlotXpPerElite   = 3,
    SlotXpPerBoss    = 8,
    -- slotLevel = floor(sqrt(xp / 20))
    -- multiplier = 1 + 0.018 * sqrt(slotLevel)
    SlotXpDivisor    = 20,
    SlotMultCoeff    = 0.018,

    -- Group bonus (party size -> bonus multiplier add)
    GroupBonus = {
        [1]  = 0.00,
        [2]  = 0.15,
        [3]  = 0.25,
        [4]  = 0.30,
        [5]  = 0.30,
    },
    GroupBonusSmallRaid = 0.35,  -- 6-10
    GroupBonusLargeRaid = 0.40,  -- 11-25

    -- World Threat (momentum-based challenge system)
    ThreatBonusPerStep    = 0.10,
    ThreatMax             = 10,
    ThreatMomentumNormal  = 0.01,
    ThreatMomentumElite   = 0.03,
    ThreatMomentumBoss    = 0.10,
    ThreatSafetyPerStep   = 0.05,
    ThreatSafetyFloor     = 0.50,
    ThreatSaveInterval    = 10,

    -- Death penalties by threat band: {attune_loss_pct, essence_pct, essence_cap, debt_kills, debt_mult}
    ThreatDeathPenalties = {
        [0]  = { 0,    0,    0,     0,  1.00 },
        [1]  = { 0.05, 0.01, 250,   10, 0.80 },
        [2]  = { 0.05, 0.01, 250,   10, 0.80 },
        [3]  = { 0.05, 0.01, 250,   10, 0.80 },
        [4]  = { 0.10, 0.03, 1000,  15, 0.65 },
        [5]  = { 0.10, 0.03, 1000,  15, 0.65 },
        [6]  = { 0.10, 0.03, 1000,  15, 0.65 },
        [7]  = { 0.15, 0.05, 5000,  20, 0.50 },
        [8]  = { 0.15, 0.05, 5000,  20, 0.50 },
        [9]  = { 0.15, 0.05, 5000,  20, 0.50 },
        [10] = { 0.20, 0.08, 10000, 25, 0.40 },
    },

    -- Anti-cheese dampener (world-only, entry-based, 4-min window)
    DampenerWindowSec = 240,
    DampenerThresholds = {
        {limit=40,  mult=1.00},
        {limit=80,  mult=0.98},
        {limit=150, mult=0.95},
        {limit=300, mult=0.90},
        {limit=math.huge, mult=0.80},
    },

    -- Direct stat application (requires Player:SetStat — currently unavailable)
    DirectStatMode = false,

    -- Debug logging (set true for verbose worldserver output)
    Debug = false,
}

-- ============================================================
-- STAT INDEX CONSTANTS
-- These must match the absorption and snapshot logic throughout.
-- ============================================================
AP.STAT_STR = 0
AP.STAT_AGI = 1
AP.STAT_STA = 2
AP.STAT_INT = 3
AP.STAT_SPI = 4
AP.STAT_NAMES = {"str","agi","sta","int","spi"}

-- ============================================================
-- MODULE TOGGLES
-- Future expansion modules. All off by default until stable.
-- ============================================================
AP.Modules = AP.Modules or {
    FusionForge        = { Enabled = false },
    EmpireSystem       = { Enabled = false },
    PrestigeSystem     = { Enabled = false },
    CompanionDelegation = { Enabled = false },
    RelicHunting       = { Enabled = false, CosmeticRewardsEnabled = true, AetherRewardsEnabled = true, PowerRewardsEnabled = false },
    DynamicWorldThreat = { Enabled = false },
    CosmeticAscension  = { Enabled = true,  PowerRewardsEnabled = false },
}

-- ============================================================
-- LOGGING HELPERS
-- ============================================================
function AP.Log(msg)
    print("[AP] INFO: " .. tostring(msg))
end

function AP.Warn(msg)
    print("[AP] WARN: " .. tostring(msg))
end

function AP.Debug(msg)
    if AP.Config.Debug then
        print("[AP] DEBUG: " .. tostring(msg))
    end
end

function AP.Err(msg)
    print("[AP] ERROR: " .. tostring(msg))
end

-- ============================================================
-- GM CHECK (compatibility-safe)
-- ============================================================
function AP.IsGM(player)
    return AP.RT.IsGM(player, 1)
end

-- ============================================================
-- WORLD THREAT NAMES & HELPERS
-- ============================================================
AP.ThreatNames = {
    [0]  = "Peaceful",
    [1]  = "Uneasy",
    [2]  = "Stirring",
    [3]  = "Dangerous",
    [4]  = "Menacing",
    [5]  = "Hostile",
    [6]  = "Dire",
    [7]  = "Cataclysmic",
    [8]  = "Apocalyptic",
    [9]  = "Worldbreaker",
    [10] = "Ascendant",
}

function AP.GetThreatName(level)
    return AP.ThreatNames[level] or ("Level " .. level)
end

function AP.GetThreatCeiling(level)
    return level * AP.Config.ThreatBonusPerStep
end

function AP.GetThreatMult(level, momentum)
    return 1.0 + (AP.GetThreatCeiling(level) * momentum)
end

function AP.GetSafetyScalar(level)
    return math.max(AP.Config.ThreatSafetyFloor, 1.0 - level * AP.Config.ThreatSafetyPerStep)
end

function AP.GetDeathPenalty(level)
    return AP.Config.ThreatDeathPenalties[level] or AP.Config.ThreatDeathPenalties[0]
end

function AP.GetDampenerFloor(level)
    return math.max(0.40, 0.80 - level * 0.04)
end

-- Content cap: limits how much of the threat bonus can be cashed out
-- based on enemy difficulty. Returns max bonus fraction (0.0 to 1.0).
AP.Config.ThreatContentCaps = {
    gray         = 0.00,
    easy_normal  = 0.20,
    same_normal  = 0.40,
    hard_normal  = 0.60,
    elite        = 0.70,
    dungeon_boss = 0.85,
    raid_boss    = 1.00,
}

function AP.GetThreatContentCap(playerLevel, creatureLevel, rank, isBoss, isRaid)
    local caps = AP.Config.ThreatContentCaps
    if isBoss then
        return isRaid and caps.raid_boss or caps.dungeon_boss
    end
    if rank >= 1 then return caps.elite end
    local diff = creatureLevel - playerLevel
    if diff >= 3 then return caps.hard_normal end
    if diff >= -2 then return caps.same_normal end
    return caps.easy_normal
end

function AP.GetThreatMultCapped(level, momentum, contentCap)
    if level <= 0 then return 1.0 end
    local ceiling = AP.GetThreatCeiling(level)
    local momentumBonus = ceiling * momentum
    local effectiveBonus = math.min(momentumBonus, contentCap)
    return 1.0 + effectiveBonus
end

-- ============================================================
-- SAFE CALL WRAPPER
-- Wraps any function in pcall and logs errors without crashing.
-- ============================================================
function AP.Try(fn, label)
    local ok, err = pcall(fn)
    if not ok then
        AP.Err((label or "unknown") .. " — " .. tostring(err))
    end
    return ok
end

-- ============================================================
-- DATABASE READINESS
-- Metadata-only validation. Schema installation and migration belong to the
-- separately authorized database package and never execute from runtime Lua.
-- ============================================================
function AP.InitDB()
    if AP.DB and AP.DB.ValidateSchema then
        return AP.DB.ValidateSchema()
    end
    AP.Warn("Schema readiness validation unavailable; Echoes gameplay remains disabled.")
    return false
end

-- ============================================================
-- MATH HELPERS
-- ============================================================

-- Mastery absorption percentage given current mastery rank
-- Returns a value between 0.0 and ~0.85
function AP.MasteryAbsorbPct(masteryRank)
    local k = AP.Config.MasteryDecayK
    return AP.Config.MasteryBaseAbsorb
        + AP.Config.MasteryMaxAbsorb * (1 - math.exp(-k * masteryRank))
end

-- Cost to buy the next mastery rank (0-indexed: cost of going from n to n+1)
function AP.MasteryCost(currentRank)
    local n = currentRank + 1  -- buying rank n+1
    return math.floor(AP.Config.MasteryCostBase * (n ^ AP.Config.MasteryCostExp))
end

-- ============================================================
-- CHAOS READING (viewer-side unit system; never mutates combat)
-- ============================================================
AP.Chaos = AP.Chaos or {}
AP.Chaos.RulesetVersion = 1

function AP.Chaos.MasteryBasis(rank)
    local total = 0
    rank = math.max(0, math.floor(tonumber(rank) or 0))
    for current = 0, rank - 1 do total = total + AP.MasteryCost(current) end
    return total
end

function AP.Chaos.BuildReading(enabled, attuned, mastery, crucible)
    attuned = math.max(0, math.floor(tonumber(attuned) or 0))
    mastery = math.max(0, math.floor(tonumber(mastery) or 0))
    crucible = math.max(0, math.floor(tonumber(crucible) or 0))
    local attunementContribution = attuned * 5000
    local masteryBasis = AP.Chaos.MasteryBasis(mastery)
    local masteryContribution = masteryBasis * 25
    local crucibleContribution = crucible * 10
    local power = 1000 + attunementContribution + masteryContribution + crucibleContribution
    local magnitude = 0
    local probe = power
    while probe >= 1000 do probe = probe / 1000; magnitude = magnitude + 1 end
    return {
        enabled = enabled == true,
        power = string.format("%.0f", power),
        magnitude = magnitude,
        -- Basis points applied after the accepted level-aware client taper.
        -- Progression changes the reading gently without rebuilding world balance.
        scale = 1000 + math.min(250, magnitude * 25),
        ruleset = AP.Chaos.RulesetVersion,
        base = 1000,
        attuned = attuned,
        attunementContribution = attunementContribution,
        masteryRank = mastery,
        masteryBasis = masteryBasis,
        masteryContribution = masteryContribution,
        crucibleBasis = crucible,
        crucibleContribution = crucibleContribution,
    }
end

-- Slot multiplier given XP total for that slot
function AP.SlotMultiplier(xp)
    local slotLevel = math.floor(math.sqrt(xp / AP.Config.SlotXpDivisor))
    return 1.0 + AP.Config.SlotMultCoeff * math.sqrt(slotLevel)
end

-- Group bonus multiplier given party size
function AP.GroupMultiplier(partySize)
    if partySize <= 5 then
        return 1.0 + (AP.Config.GroupBonus[partySize] or 0.0)
    elseif partySize <= 10 then
        return 1.0 + AP.Config.GroupBonusSmallRaid
    else
        return 1.0 + AP.Config.GroupBonusLargeRaid
    end
end

-- Rarity multiplier for a given item quality
function AP.RarityMultiplier(quality)
    return AP.Config.RarityMult[quality] or 1.0
end

-- Level-based absorption scalar
-- Low levels absorb less; level 80 can reach 100% when mastery is maxed.
-- Formula: clamp(0, (level - 9) / 71, 1)  → 0 at level 9, 1.0 at level 80
function AP.LevelAbsorbScalar(level)
    if level <= 9 then return 0.0 end
    return math.min(1.0, (level - 9) / 71.0)
end

-- ============================================================
-- AETHER DB HELPERS
-- ============================================================

-- Load or create an Aether record for a player GUID.
-- Returns { aether=N, mastery=N } or nil on error.
function AP.LoadMastery(guid)
    local result = nil
    AP.Try(function()
        local q = AP.DB.Query(string.format(
            "SELECT `aether`, `mastery` FROM `ap_mastery` WHERE `guid` = %d LIMIT 1;", guid))
        if q then
            result = {
                aether  = AP.DB.GetUInt64(q, 0),
                mastery = tonumber(q:GetUInt32(1)) or 0,
            }
        else
            result = { aether = 0, mastery = 0 }
        end
    end, "AP.LoadMastery")
    return result
end

AP.Mastery = AP.Mastery or {}

-- ============================================================
-- MASTERY PURCHASE SERVICE (E2j5)
-- Narrow, reusable Echoes-owned service for advancing Mastery rank by
-- exactly one. Callable by both the human gossip menu (ap_ui.lua) and an
-- authorized bot caller (AP.API.ExecuteMasteryPurchase in ap_botapi.lua) -
-- there is exactly one Mastery purchase implementation, not two divergent
-- copies. Reuses AP.LoadMastery/AP.MasteryCost exactly as-is - never a
-- second cost formula, never a rank ceiling (AP.MasteryCost is uncapped by
-- design; this service never clamps or rejects based on rank alone).
--
-- Returns a structured status table:
--   { status = "SUCCESS" | "INSUFFICIENT_ESSENCE" | "INVALID_PLAYER" | "DATABASE_FAILURE",
--     oldRank, newRank, cost, oldBalance, newBalance }
-- On INSUFFICIENT_ESSENCE/DATABASE_FAILURE, no mutation occurs - oldRank/cost/oldBalance
-- are still populated for caller diagnostics, newRank/newBalance are absent.
function AP.Mastery.Purchase(player)
    if not player or not AP.RT or not AP.RT.GetGUID then
        return { status = "INVALID_PLAYER" }
    end
    local guid = AP.RT.GetGUID(player)
    if not guid then
        return { status = "INVALID_PLAYER" }
    end

    local rec     = AP.LoadMastery(guid)
    local aether  = rec and rec.aether or 0
    local mastery = rec and rec.mastery or 0
    local cost    = AP.MasteryCost(mastery)

    if aether < cost then
        return { status = "INSUFFICIENT_ESSENCE", oldRank = mastery, cost = cost, oldBalance = aether }
    end

    local newAether  = aether - cost
    local newMastery = mastery + 1

    -- Single atomic UPSERT - identical shape to the pre-E2j5 inline human path in
    -- ap_ui.lua. AP.DB.ExecuteCritical never silently degrades to async (see ap04_db.lua) -
    -- if it returns false here, NOTHING was written, so returning DATABASE_FAILURE without
    -- any further mutation is always safe and never leaves a partial state.
    local writeOk = AP.DB.ExecuteCritical(string.format([[
        INSERT INTO `ap_mastery` (`guid`, `aether`, `mastery`)
        VALUES (%d, %d, %d)
        ON DUPLICATE KEY UPDATE `aether` = %d, `mastery` = %d;
    ]], guid, newAether, newMastery, newAether, newMastery), "AP.Mastery.Purchase")

    if not writeOk then
        return { status = "DATABASE_FAILURE", oldRank = mastery, cost = cost, oldBalance = aether }
    end

    -- Audit insert is best-effort: the purchase above already committed and remains
    -- committed regardless of whether this succeeds - never rolled back, never retried
    -- because of an audit failure.
    AP.DB.ExecuteCritical(string.format(
        "INSERT INTO `ap_mastery_spend` (`guid`, `amount`) VALUES (%d, %d);",
        guid, cost), "AP.Mastery.Purchase.audit")

    AP.Log("Mastery purchased: guid=" .. guid .. " rank=" .. newMastery)

    return {
        status = "SUCCESS",
        oldRank = mastery,
        newRank = newMastery,
        cost = cost,
        oldBalance = aether,
        newBalance = newAether,
    }
end

-- Grant Aether to a character GUID (integer amount).
-- Uses INSERT IGNORE (ensure row) then UPDATE (add amount) pattern.
-- This avoids doing a SELECT before the write, which would open
-- a repeatable-read snapshot on the sync connection and prevent
-- the subsequent SELECT in LoadMastery from seeing the new value.
-- NOTE: AP.DB.Execute prefers CharDBDirectExecute (sync) so both statements
-- commit before any subsequent SELECT (e.g. LoadMastery). On builds without
-- CharDBDirectExecute, falls back to CharDBExecute (async FIFO queue);
-- ordering is still preserved since INSERT is enqueued before UPDATE.
function AP.GrantAether(guid, amount)
    if not guid or amount <= 0 then return end
    local ok, err = pcall(function()
        -- Ensure row exists without reading it first
        AP.DB.Execute(string.format(
            "INSERT IGNORE INTO `ap_mastery` (`guid`, `aether`, `mastery`) VALUES (%d, 0, 0);",
            guid))
        -- Add the amount in a separate statement (no snapshot open)
        AP.DB.Execute(string.format(
            "UPDATE `ap_mastery` SET `aether` = `aether` + %d WHERE `guid` = %d;",
            amount, guid))
    end)
    if not ok then AP.Err("GrantAether failed: " .. tostring(err)) end
    AP.Debug(string.format("GrantAether: guid=%d amount=%d", guid, amount))
end

-- Returns the item-level-scaled attunement cap for a given item entry.
-- Low level items have a much lower cap so high-level players attune
-- them instantly (their absorbed stats are weak anyway).
function AP.GetScaledCap(itemEntry)
    local cap = AP.Config.CapPerItem
    AP.Try(function()
        local q = AP.DB.WorldQuery(string.format(
            "SELECT `RequiredLevel` FROM `item_template` WHERE `entry` = %d LIMIT 1;",
            itemEntry))
        if q then
            -- RequiredLevel=0 means no level requirement — treat as level 1.
            local reqLevel = tonumber(q:GetUInt8(0)) or 0
            if reqLevel <= 0 then reqLevel = 1 end
            -- Quadratic scaling: high-level gear is MUCH harder to attune.
            -- cap = CapPerItem * (reqLevel/80)^2
            -- This prevents trivial content from being an attunement exploit.
            local levelFraction = math.max(0.01, reqLevel / 80)
            cap = math.max(100, math.floor(AP.Config.CapPerItem * (levelFraction ^ 2)))
        end
    end, "AP.GetScaledCap")
    return cap
end

-- ============================================================
-- TALENT DB HELPERS
-- ap_talents: guid, stat_index (0-4), rank (1+)
-- Stat indices: 0=STR 1=AGI 2=STA 3=INT 4=SPI
-- ============================================================
AP.StatNames = { [0]="STR", [1]="AGI", [2]="STA", [3]="INT", [4]="SPI" }

function AP.LoadTalents(guid)
    local talents = {}
    AP.Try(function()
        local q = AP.DB.Query(string.format(
            "SELECT `stat_index`, `rank` FROM `ap_talents` WHERE `guid` = %d;", guid))
        if q then
            repeat
                local idx  = tonumber(q:GetUInt8(0)) or 0
                local rank = tonumber(q:GetUInt8(1)) or 0
                talents[idx] = rank
            until not q:NextRow()
        end
    end, "AP.LoadTalents")
    return talents
end

function AP.SaveTalent(guid, statIndex, rank)
    AP.Try(function()
        AP.DB.Execute(string.format([[
            INSERT INTO `ap_talents` (`guid`, `stat_index`, `rank`)
            VALUES (%d, %d, %d)
            ON DUPLICATE KEY UPDATE `rank` = %d;
        ]], guid, statIndex, rank, rank))
        AP.DB.Execute("COMMIT;")
    end, "AP.SaveTalent")
end

-- Cost to buy the next rank for a given stat.
-- Uses a tripling curve: rank N costs base * 3^(N-1)
-- Primary stat:   rank1=2000, rank2=6000, rank3=18000
-- Secondary stat: rank1=1000, rank2=3000
function AP.TalentCost(currentRank, isPrimary)
    local nextRank = currentRank + 1
    local base = isPrimary and AP.Config.TalentCostPrimary or AP.Config.TalentCostSecondary
    return math.floor(base * (3 ^ (nextRank - 1)))
end

-- Authoritative Talent role. The compiled mod-echoes-stats engine uses the
-- highest invested rank and resolves ties to the lowest stat index. Keep the
-- Lua state/purchase surface deterministic and aligned with that live engine.
function AP.GetTalentPrimaryStat(talents)
    local primary, highest = nil, 0
    for statIndex = 0, 4 do
        local rank = math.max(0, math.floor(tonumber(talents and talents[statIndex]) or 0))
        if rank > highest then
            primary, highest = statIndex, rank
        end
    end
    return primary
end

-- Complete server-owned UI snapshot. The client receives results, never the
-- rank/cost/role formula. With no investment there is no Primary, but the first
-- rank bought in any anchor uses Primary cost/cap semantics.
function AP.BuildTalentSnapshot(talents)
    talents = talents or {}
    local primary = AP.GetTalentPrimaryStat(talents)
    local distinct = 0
    for statIndex = 0, 4 do
        if (tonumber(talents[statIndex]) or 0) > 0 then distinct = distinct + 1 end
    end
    local penalty = distinct <= 1 and 1.0
        or (AP.Config.TalentDistinctPenalty ^ (distinct - 1))
    local snapshot = { primary = primary, distinct = distinct, penalty = penalty, stats = {} }
    for statIndex = 0, 4 do
        local rank = math.max(0, math.floor(tonumber(talents[statIndex]) or 0))
        local isPrimary = primary ~= nil and statIndex == primary
        local purchasesAsPrimary = primary == nil or isPrimary
        local maxRank = purchasesAsPrimary and AP.Config.TalentPrimaryRanks
            or AP.Config.TalentSecondaryRanks
        local perRank = isPrimary and AP.Config.TalentPrimaryBonus
            or AP.Config.TalentSecondaryBonus
        if primary == nil then perRank = AP.Config.TalentPrimaryBonus end
        local bonusPct = rank * perRank * 100
        snapshot.stats[statIndex] = {
            statIndex = statIndex, name = AP.StatNames[statIndex], rank = rank,
            role = primary == nil and "UNSET" or (isPrimary and "PRIMARY" or "SECONDARY"),
            isPrimary = isPrimary, maxRank = maxRank, bonusPct = bonusPct,
            nextCost = rank < maxRank and AP.TalentCost(rank, purchasesAsPrimary) or 0,
            nextBonusPct = rank < maxRank and ((rank + 1) * perRank * 100) or bonusPct,
        }
    end
    return snapshot
end

function AP.PreviewTalentSnapshot(talents, statIndex)
    statIndex = tonumber(statIndex)
    if not statIndex or statIndex ~= math.floor(statIndex) or statIndex < 0 or statIndex > 4 then
        return { ok = false, status = "INVALID_STAT" }
    end
    local current = AP.BuildTalentSnapshot(talents)
    local selected = current.stats[statIndex]
    if selected.rank >= selected.maxRank then
        return { ok = false, status = "MAX_RANK", statIndex = statIndex, current = current }
    end
    local projectedTalents = {}
    for idx = 0, 4 do projectedTalents[idx] = current.stats[idx].rank end
    projectedTalents[statIndex] = selected.rank + 1
    return {
        ok = true, status = "READY", statIndex = statIndex, cost = selected.nextCost,
        current = current, projected = AP.BuildTalentSnapshot(projectedTalents),
    }
end

-- Returns the role-derived max rank using the same deterministic snapshot.
function AP.TalentMaxRank(statIndex, talents)
    local stat = AP.BuildTalentSnapshot(talents).stats[statIndex]
    return stat and stat.maxRank or AP.Config.TalentSecondaryRanks
end

-- Load attunement progress for a specific item entry on a character.
-- Returns { progress=N, attuned=bool } or nil.
function AP.LoadItemAttune(guid, itemEntry)
    local result = nil
    AP.Try(function()
        local q = AP.DB.Query(string.format(
            "SELECT `progress`, `attuned` FROM `ap_item_attune` WHERE `guid` = %d AND `item_entry` = %d LIMIT 1;",
            guid, itemEntry))
        if q then
            result = {
                progress = tonumber(q:GetUInt32(0)) or 0,
                attuned  = (tonumber(q:GetUInt8(1)) or 0) == 1,
            }
        else
            result = { progress = 0, attuned = false }
        end
    end, "AP.LoadItemAttune")
    return result
end

-- Save/update attunement progress for an item.
function AP.SaveItemAttune(guid, itemEntry, progress, attuned)
    AP.Try(function()
        local attunedInt = attuned and 1 or 0
        AP.DB.Execute(string.format([[
            INSERT INTO `ap_item_attune` (`guid`, `item_entry`, `progress`, `attuned`)
            VALUES (%d, %d, %d, %d)
            ON DUPLICATE KEY UPDATE `progress` = %d, `attuned` = %d;
        ]], guid, itemEntry, progress, attunedInt, progress, attunedInt))
    end, "AP.SaveItemAttune")
end

-- Store or update a stat snapshot for a fully attuned item.
-- stats table: { str=N, agi=N, sta=N, int=N, spi=N }
function AP.SaveSnapshot(guid, itemEntry, quality, stats)
    AP.Try(function()
        AP.DB.ExecuteCritical(string.format([[
            INSERT INTO `ap_item_snapshot` (`guid`, `item_entry`, `quality`, `str`, `agi`, `sta`, `int`, `spi`)
            VALUES (%d, %d, %d, %.4f, %.4f, %.4f, %.4f, %.4f)
            ON DUPLICATE KEY UPDATE
                `quality` = %d,
                `str` = %.4f,
                `agi` = %.4f,
                `sta` = %.4f,
                `int` = %.4f,
                `spi` = %.4f;
        ]],
        guid, itemEntry, quality,
        stats.str or 0, stats.agi or 0, stats.sta or 0, stats.int or 0, stats.spi or 0,
        quality,
        stats.str or 0, stats.agi or 0, stats.sta or 0, stats.int or 0, stats.spi or 0),
        "AP.SaveSnapshot")
    end, "AP.SaveSnapshot")
end

-- Load a stat snapshot. Returns stats table or nil.
function AP.LoadSnapshot(guid, itemEntry)
    local result = nil
    AP.Try(function()
        local q = AP.DB.Query(string.format(
            "SELECT `quality`, `str`, `agi`, `sta`, `int`, `spi` FROM `ap_item_snapshot` WHERE `guid` = %d AND `item_entry` = %d LIMIT 1;",
            guid, itemEntry))
        if q then
            result = {
                quality = tonumber(q:GetUInt8(0))   or 0,
                str     = tonumber(q:GetString(1))  or 0,
                agi     = tonumber(q:GetString(2))  or 0,
                sta     = tonumber(q:GetString(3))  or 0,
                int     = tonumber(q:GetString(4))  or 0,
                spi     = tonumber(q:GetString(5))  or 0,
            }
        end
    end, "AP.LoadSnapshot")
    return result
end

-- ============================================================
-- SLOT SPECIALIZATION DB HELPERS
-- ============================================================

function AP.LoadSlotXP(guid, slot)
    local xp = 0
    AP.Try(function()
        local q = AP.DB.Query(string.format(
            "SELECT `xp` FROM `ap_slot_mastery` WHERE `guid` = %d AND `slot` = %d LIMIT 1;",
            guid, slot))
        if q then xp = AP.DB.GetUInt64(q, 0) end
    end, "AP.LoadSlotXP")
    return xp
end

function AP.AddSlotXP(guid, slot, amount)
    AP.Try(function()
        -- INSERT IGNORE ensures row exists without opening a read snapshot
        AP.DB.Execute(string.format(
            "INSERT IGNORE INTO `ap_slot_mastery` (`guid`, `slot`, `xp`) VALUES (%d, %d, 0);",
            guid, slot))
        -- UPDATE adds the amount separately (no prior SELECT = no snapshot)
        AP.DB.Execute(string.format(
            "UPDATE `ap_slot_mastery` SET `xp` = `xp` + %d WHERE `guid` = %d AND `slot` = %d;",
            amount, guid, slot))
    end, "AP.AddSlotXP")
end

-- ============================================================
-- SNAPSHOT CAPTURE FROM PLAYER ITEM
-- Call this when an item first reaches full attunement.
-- item is a Lua Item object (from Player:GetEquippedItemBySlot).
-- ============================================================
function AP.CaptureSnapshot(player, item)
    if not player or not item then return end
    AP.Try(function()
        local guid      = AP.RT.GetGUID(player)
        local itemEntry = AP.RT.GetItemEntry(item)

        -- Snapshot ALL equippable items regardless of armor class.
        -- Class restriction only applies at absorption time so alts of
        -- the right class benefit from snapshots captured by any character.

        -- Read stats and weapon damage from item_template
        local q = AP.DB.WorldQuery(string.format([[
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
                   `Quality`, `armor`,
                   `dmg_min1`, `dmg_max1`,
                   `dmg_min2`, `dmg_max2`,
                   `delay`, `class`
            FROM `item_template`
            WHERE `entry` = %d LIMIT 1;
        ]], itemEntry))

        if not q then
            AP.Debug("CaptureSnapshot: no item_template row for entry=" .. itemEntry)
            return
        end

        local stats = { str=0, agi=0, sta=0, ["int"]=0, spi=0, armor=0, weapon_dps=0 }
        for i = 0, 9 do
            local statType  = tonumber(q:GetUInt32(i * 2))     or 0
            local statValue = tonumber(q:GetUInt32(i * 2 + 1)) or 0
            if     statType == 4 then stats.str        = stats.str    + statValue
            elseif statType == 3 then stats.agi        = stats.agi    + statValue
            elseif statType == 7 then stats.sta        = stats.sta    + statValue
            elseif statType == 5 then stats["int"]     = stats["int"] + statValue
            elseif statType == 6 then stats.spi        = stats.spi    + statValue
            end
        end
        local quality   = tonumber(q:GetUInt8(20))   or 1
        stats.armor     = tonumber(q:GetUInt32(21))  or 0
        local dmin1     = tonumber(q:GetString(22))  or 0
        local dmax1     = tonumber(q:GetString(23))  or 0
        local dmin2     = tonumber(q:GetString(24))  or 0
        local dmax2     = tonumber(q:GetString(25))  or 0
        local delay     = tonumber(q:GetUInt32(26))  or 0
        local itemClass = tonumber(q:GetUInt8(27))   or 0

        -- Calculate weapon DPS for weapons (class=2) with a valid delay
        -- avgDPS = ((dmin1+dmax1)/2 + (dmin2+dmax2)/2) / (delay/1000)
        if itemClass == 2 and delay > 0 then
            local avgDmg = ((dmin1 + dmax1) / 2) + ((dmin2 + dmax2) / 2)
            stats.weapon_dps = avgDmg / (delay / 1000)
        end

        AP.SaveSnapshotAccountWide(guid, itemEntry, quality, stats)
        AP.Log(string.format("Snapshot: entry=%d str=%.0f agi=%.0f sta=%.0f int=%.0f spi=%.0f",
            itemEntry, stats.str, stats.agi, stats.sta, stats["int"], stats.spi))
    end, "AP.CaptureSnapshot")
end

-- ============================================================
-- ABSORPTION CALCULATION
-- Returns total absorbed stats across all fully-attuned items
-- for a player at their current level and mastery.
-- result: { str=N, agi=N, sta=N, int=N, spi=N }
-- Note: actual stat application is currently DISABLED
--       because Player:SetStat is not available on this build.
--       This function is used for display/tooltip purposes.
-- ============================================================
function AP.CalculateAbsorption(guid, level, masteryRank)
    local totals = { str=0, agi=0, sta=0, int=0, spi=0 }
    AP.Try(function()
        local q = AP.DB.Query(string.format(
            "SELECT `str`, `agi`, `sta`, `int`, `spi` FROM `ap_item_snapshot` WHERE `guid` = %d;",
            guid))
        if not q then return end

        local masteryPct = AP.MasteryAbsorbPct(masteryRank)
        local levelScale = AP.LevelAbsorbScalar(level)
        local absorbPct  = masteryPct * levelScale

        repeat
            totals.str = totals.str + (tonumber(q:GetString(0)) or 0) * absorbPct
            totals.agi = totals.agi + (tonumber(q:GetString(1)) or 0) * absorbPct
            totals.sta = totals.sta + (tonumber(q:GetString(2)) or 0) * absorbPct
            totals.int = totals.int + (tonumber(q:GetString(3)) or 0) * absorbPct
            totals.spi = totals.spi + (tonumber(q:GetString(4)) or 0) * absorbPct
        until not q:NextRow()
    end, "AP.CalculateAbsorption")
    return totals
end

-- ============================================================
-- ARMOR CLASS RESTRICTION
-- Absorbed stats only apply if the item matches the player's
-- armor class or is a weapon they can use — same rule as Synastria.
-- item_template.class: 2=Weapon, 4=Armor
-- item_template.subclass for Armor: 1=Cloth, 2=Leather, 3=Mail, 4=Plate
-- WoW class IDs: 1=Warrior, 2=Paladin, 3=Hunter, 4=Rogue, 5=Priest,
--                6=DK, 7=Shaman, 8=Mage, 9=Warlock, 11=Druid
-- ============================================================

-- Armor absorption rules: each class absorbs their primary armor type
-- AND the tier directly below (adjacent tier only, not cumulative).
-- Warriors absorb mail+plate but NOT leather or cloth.
-- This prevents plate wearers from being OP by absorbing all armor types.
-- Misc/jewelry (subClass=0) always applies to all classes.
-- Format: { min=N, max=N } where 1=Cloth, 2=Leather, 3=Mail, 4=Plate
AP.ClassArmorRange = {
    [1]  = { min=3, max=4 },  -- Warrior:      mail + plate
    [2]  = { min=3, max=4 },  -- Paladin:       mail + plate
    [3]  = { min=2, max=3 },  -- Hunter:        leather + mail
    [4]  = { min=1, max=2 },  -- Rogue:         cloth + leather
    [5]  = { min=1, max=1 },  -- Priest:        cloth only
    [6]  = { min=3, max=4 },  -- Death Knight:  mail + plate
    [7]  = { min=2, max=3 },  -- Shaman:        leather + mail
    [8]  = { min=1, max=1 },  -- Mage:          cloth only
    [9]  = { min=1, max=1 },  -- Warlock:       cloth only
    [11] = { min=1, max=2 },  -- Druid:         cloth + leather
}

-- Cache of item class/subclass to avoid repeated WorldDB lookups
AP._itemClassCache = AP._itemClassCache or {}

function AP.GetItemClass(itemEntry)
    if AP._itemClassCache[itemEntry] then
        return AP._itemClassCache[itemEntry]
    end
    local result = { itemClass = 4, subClass = 1 }  -- default: cloth armor
    AP.Try(function()
        local q = AP.DB.WorldQuery(string.format(
            "SELECT `class`, `subclass` FROM `item_template` WHERE `entry` = %d LIMIT 1;",
            itemEntry))
        if q then
            result.itemClass = tonumber(q:GetUInt8(0)) or 4
            result.subClass  = tonumber(q:GetUInt8(1)) or 1
        end
    end, "AP.GetItemClass")
    AP._itemClassCache[itemEntry] = result
    return result
end

-- Returns true if the player's class can absorb this item's stats.
-- Weapons: allow all for now (weapon restrictions are complex per-class).
-- Armor: check subclass against ClassArmorRange (adjacent tier only).
-- Misc/jewelry (subClass=0): always allowed for all classes.
function AP.ItemMatchesClass(playerClass, itemEntry)
    local ic = AP.GetItemClass(itemEntry)
    if ic.itemClass == 2 then
        return true  -- Weapon — allow all
    elseif ic.itemClass == 4 then
        if ic.subClass == 0 then return true end  -- Misc/jewelry always allowed
        local range = AP.ClassArmorRange[playerClass]
        if not range then return false end
        return ic.subClass >= range.min and ic.subClass <= range.max
    end
    return false
end

-- ============================================================
-- ACCOUNT-WIDE ATTUNEMENT
-- All characters on the same account share attunement progress.
-- We use the account ID as the shared key, stored in ap_mastery
-- and ap_item_snapshot with a special "account guid" derived from
-- the account ID. Character-level progress (ap_item_attune) remains
-- per-character since the player must wear the item to attune it.
-- Snapshots and absorption are account-wide.
-- ============================================================

-- Cache of guid -> accountId to avoid repeated DB lookups
AP._accountCache = AP._accountCache or {}

function AP.GetAccountId(guid)
    if AP._accountCache[guid] then return AP._accountCache[guid] end
    local accountId = guid  -- fallback: use guid if account lookup fails
    AP.Try(function()
        local q = AP.DB.Query(string.format(
            "SELECT `account` FROM `characters` WHERE `guid` = %d LIMIT 1;",
            guid))
        if q then
            accountId = tonumber(tostring(q:GetUInt32(0))) or guid
        end
    end, "AP.GetAccountId")
    AP._accountCache[guid] = accountId
    return accountId
end

-- ============================================================
-- E2j5a: SNAPSHOT STATS FROM ITEM_TEMPLATE (armor + weapon damage restoration)
--
-- Historical source: cpp_patch/mod_attunement_plus.patch (echoes-of-the-worldsoul repo,
-- never applied to any deployed tree) proves the intended, actually-working formula:
--   weapon_dps = ((dmin1+dmax1)/2 + (dmin2+dmax2)/2) / (delay/1000)   [class=2 weapons, delay>0]
-- computed ONCE at attunement time and frozen, exactly like the five primary stats.
--
-- `armor` is ALSO captured here (item_template.armor, frozen at attunement) so the
-- Lua-native AP.CalculateAbsorptionAccountWide (display/tooltip track, reads the stored
-- snapshot `armor` column) produces a correct total. This is a DELIBERATE, documented
-- divergence from mod-echoes-stats (the C++ engine-application track): the historical
-- patch's own actually-executed CalculateAbsorption function reads armor LIVE from
-- ItemTemplate at calculation time (not from the snapshot), specifically because "DB
-- column unreliable for WotLK items whose armor is calculated dynamically by
-- _ApplyItemBonuses, not stored in armor column" (patch's own comment) - the patch also
-- contains a separate PatchEquippedItemArmor self-heal function that writes an
-- ScalingStatValue-adjusted armor into the snapshot column, but that value is NEVER
-- READ by CalculateAbsorption's own SELECT (which omits the armor column entirely) -
-- i.e. even in the historical source, the stored/adjusted armor value was write-only,
-- never actually consumed by the real calculation path. mod-echoes-stats therefore
-- replicates the ACTUALLY-EXECUTED historical behavior (live raw item_template.armor,
-- via EchoesStatsHooks.cpp's own ItemTemplate lookup - see EchoesQuerySnapshots), not
-- the write-only self-heal path. This snapshot's own `armor` value is for the Lua
-- display track only.
--
-- Returns { str, agi, sta, int, spi, armor, weapon_dps }, quality - never nil (matches
-- AP.LoadMastery's own "never nil" convention); returns an all-zero stats table and
-- quality=1 if the item_template row cannot be found.
function AP.ComputeSnapshotStatsFromItemTemplate(itemEntry)
    local stats = { str=0, agi=0, sta=0, ["int"]=0, spi=0, armor=0, weapon_dps=0 }
    local quality = 1
    local q = AP.DB.WorldQuery(string.format([[
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
               `Quality`, `armor`,
               `dmg_min1`, `dmg_max1`,
               `dmg_min2`, `dmg_max2`,
               `delay`, `class`
        FROM `item_template`
        WHERE `entry` = %d LIMIT 1;
    ]], itemEntry))
    if not q then
        return stats, quality
    end

    for i = 0, 9 do
        local statType  = tonumber(q:GetUInt32(i * 2))     or 0
        local statValue = tonumber(q:GetUInt32(i * 2 + 1)) or 0
        if     statType == 4 then stats.str    = stats.str    + statValue
        elseif statType == 3 then stats.agi    = stats.agi    + statValue
        elseif statType == 7 then stats.sta    = stats.sta    + statValue
        elseif statType == 5 then stats["int"] = stats["int"] + statValue
        elseif statType == 6 then stats.spi    = stats.spi    + statValue
        end
    end
    quality        = tonumber(q:GetUInt8(20))  or 1
    stats.armor    = tonumber(q:GetUInt32(21)) or 0
    local dmin1    = tonumber(q:GetString(22)) or 0
    local dmax1    = tonumber(q:GetString(23)) or 0
    local dmin2    = tonumber(q:GetString(24)) or 0
    local dmax2    = tonumber(q:GetString(25)) or 0
    local delay    = tonumber(q:GetUInt32(26)) or 0
    local itemClass = tonumber(q:GetUInt8(27)) or 0

    -- weapon_dps: class=2 (Weapon) only, requires a valid (nonzero) attack delay.
    -- Gray/common weapons use the exact same formula as any other quality - no quality
    -- restriction, matching this phase's explicit instruction.
    if itemClass == 2 and delay > 0 then
        local avgDmg = ((dmin1 + dmax1) / 2) + ((dmin2 + dmax2) / 2)
        stats.weapon_dps = avgDmg / (delay / 1000)
    end

    return stats, quality
end

-- Account-wide snapshot: save using accountId as the key
function AP.SaveSnapshotAccountWide(guid, itemEntry, quality, stats)
    local accountId = AP.GetAccountId(guid)
    AP.Try(function()
        AP.DB.ExecuteCritical(string.format([[
            INSERT INTO `ap_item_snapshot`
                (`guid`, `item_entry`, `quality`, `str`, `agi`, `sta`, `int`, `spi`, `armor`, `weapon_dps`)
            VALUES (%d, %d, %d, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f)
            ON DUPLICATE KEY UPDATE
                `quality`    = %d,
                `str`        = %.4f, `agi`        = %.4f, `sta`    = %.4f,
                `int`        = %.4f, `spi`        = %.4f, `armor`  = %.4f,
                `weapon_dps` = %.4f;
        ]],
            accountId, itemEntry, quality,
            stats.str or 0, stats.agi or 0, stats.sta or 0,
            stats["int"] or 0, stats.spi or 0, stats.armor or 0,
            stats.weapon_dps or 0,
            quality,
            stats.str or 0, stats.agi or 0, stats.sta or 0,
            stats["int"] or 0, stats.spi or 0, stats.armor or 0,
            stats.weapon_dps or 0),
        "AP.SaveSnapshotAccountWide")
        AP.DB.Execute("COMMIT;")
    end, "AP.SaveSnapshotAccountWide")
end

-- Account-wide absorption: load snapshots using accountId
-- Filters by playerClass using adjacent-tier-only armor range
function AP.CalculateAbsorptionAccountWide(guid, playerClass, level, masteryRank)
    local accountId = AP.GetAccountId(guid)
    local totals = { str=0, agi=0, sta=0, ["int"]=0, spi=0, armor=0 }
    AP.Try(function()
        local q = AP.DB.Query(string.format([[
            SELECT `item_entry`, `str`, `agi`, `sta`, `int`, `spi`, `armor`
            FROM `ap_item_snapshot`
            WHERE `guid` = %d;
        ]], accountId))
        if not q then return end

        local masteryPct = AP.MasteryAbsorbPct(masteryRank)
        local levelScale = AP.LevelAbsorbScalar(level)
        local absorbPct  = masteryPct * levelScale

        repeat
            local itemEntry = tonumber(q:GetUInt32(0)) or 0
            if AP.ItemMatchesClass(playerClass, itemEntry) then
                totals.str      = totals.str     + (tonumber(q:GetString(1)) or 0) * absorbPct
                totals.agi      = totals.agi     + (tonumber(q:GetString(2)) or 0) * absorbPct
                totals.sta      = totals.sta     + (tonumber(q:GetString(3)) or 0) * absorbPct
                totals["int"]   = totals["int"]  + (tonumber(q:GetString(4)) or 0) * absorbPct
                totals.spi      = totals.spi     + (tonumber(q:GetString(5)) or 0) * absorbPct
                totals.armor    = totals.armor   + (tonumber(q:GetString(6)) or 0) * absorbPct
            end
        until not q:NextRow()
    end, "AP.CalculateAbsorptionAccountWide")
    return totals
end
AP.RT.RegisterEvent("server", 3, function()  -- EVENT_ON_SERVER_STARTUP
    AP.Try(function()
        AP.Log("Echoes of the Worldsoul core loading...")

        -- Force direct stat mode off if SetStat unavailable
        if not AP.Cap.SetStat then
            if AP.Config.DirectStatMode then
                AP.Warn("Direct stat mode requested but Player:SetStat is not available on this core. Forcing Direct mode OFF.")
                AP.Config.DirectStatMode = false
            end
        end

        AP.InitDB()
        -- Finalise profile detection now that AP.Config is available.
        -- ap00_compat.lua defined AP.Compat.Apply(); it must be called here,
        -- not at load-time, because AP.Config.DMLMode is not readable until
        -- after ap_core.lua's top-level code has executed.
        if AP.Compat and AP.Compat.Apply then AP.Compat.Apply() end
        AP.Log("Core initialized. Profile=" .. tostring(AP.Profile and AP.Profile.name or "?")
            .. "  DirectStatMode=" .. tostring(AP.Config.DirectStatMode))

        -- Print module states
        for name, mod in pairs(AP.Modules) do
            if mod.Enabled then
                AP.Log("Module " .. name .. ": ENABLED")
            else
                AP.Log("Module " .. name .. ": disabled")
            end
        end
    end, "AP startup")
end)

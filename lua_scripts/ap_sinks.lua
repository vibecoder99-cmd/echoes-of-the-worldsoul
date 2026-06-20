-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- ap_sinks.lua  -  Echoes of the Worldsoul: Aether Sink System
-- Phase 1: Life Leech (Lua), Fortitude, Melee Power,
--          Spell Power (C++ side  -  see C++ instruction sheet)
-- Full 18-category infrastructure built so Phase 2 additions
-- only require new rows in AP.SinkDefs and new C++ handlers.
-- ============================================================

AP = AP or {}
AP.Sinks = AP.Sinks or {}

-- ============================================================
-- CATEGORY DEFINITIONS
-- All 18 planned categories defined here.
-- active = true  -> effect is computed and applied this phase
-- active = false -> investment accepted, effect pending C++/Phase2
--
-- DR formula: effect = ceiling * (1 - e^(-k * invested))
-- Units:
--   leech, mitigation, fortitude, power bonuses are raw fractions
--   e.g. ceiling=0.08 means 8% max effect
-- ============================================================
AP.SinkDefs = {
    -- -- DAMAGE ----------------------------------------------
    melee_power = {
        label    = "Melee Power",
        desc     = "Increases your absorbed weapon DPS contribution.",
        ceiling  = 1.00,   -- up to +100% bonus multiplier on weapon DPS
        k        = 0.000004,
        active   = true,   -- C++ reads this; see C++ instruction sheet
        phase    = 1,
    },
    spell_power = {
        label    = "Spell Power",
        desc     = "Increases INT absorption contribution to spell damage.",
        ceiling  = 1.00,
        k        = 0.000004,
        active   = true,   -- C++ reads this
        phase    = 1,
    },
    crit_rating = {
        label    = "Crit Rating",
        desc     = "Adds flat critical strike chance to melee, ranged, and spells.",
        ceiling  = 0.15,   -- up to +15% crit
        k        = 0.000003,
        active   = true,   -- C++ periodic refresh
        phase    = 2,
    },
    haste_rating = {
        label    = "Haste Rating",
        desc     = "Reduces GCD and increases attack and cast speed.",
        ceiling  = 0.20,   -- up to +20% haste
        k        = 0.000003,
        active   = true,   -- C++ periodic refresh
        phase    = 2,
    },
    armor_pen = {
        label    = "Armor Penetration",
        desc     = "Partially bypasses target physical armor.",
        ceiling  = 0.30,   -- up to 30% armor pen
        k        = 0.000003,
        active   = true,   -- C++ OnDamage
        phase    = 2,
    },
    execute_power = {
        label    = "Execute Power",
        desc     = "Bonus damage dealt when target is below 20% HP.",
        ceiling  = 0.40,   -- up to +40% damage in execute range
        k        = 0.000003,
        active   = true,   -- C++ OnDamage
        phase    = 2,
    },
    -- -- SURVIVAL --------------------------------------------
    life_leech = {
        label    = "Life Leech",
        desc     = "Restores HP based on damage dealt to enemies.",
        ceiling  = 0.08,   -- up to 8% leech
        k        = 0.000005,
        active   = true,   -- C++ per-hit (OnDamage)
        phase    = 1,
    },
    spell_mitigation = {
        label    = "Spell Mitigation",
        desc     = "Reduces incoming magic damage. Handled in C++.",
        ceiling  = 0.25,   -- up to 25% magic damage reduction
        k        = 0.000004,
        active   = true,   -- C++ ModifySpellDamageTaken hook
        phase    = 1,
    },
    fortitude = {
        label    = "Fortitude",
        desc     = "Multiplies bonus HP from STA absorption.",
        ceiling  = 0.50,   -- up to +50% HP bonus on top of STA
        k        = 0.000003,
        active   = true,   -- C++ reads this; see C++ instruction sheet
        phase    = 1,
    },
    dodge_rating = {
        label    = "Dodge Rating",
        desc     = "Adds flat dodge percentage via combat rating.",
        ceiling  = 0.15,
        k        = 0.000003,
        active   = true,   -- C++ periodic refresh
        phase    = 2,
    },
    parry_rating = {
        label    = "Parry Rating",
        desc     = "Adds flat parry percentage via combat rating.",
        ceiling  = 0.10,
        k        = 0.000003,
        active   = true,   -- C++ periodic refresh
        phase    = 2,
    },
    reflect_chance = {
        label    = "Reflect Chance",
        desc     = "Chance to reflect incoming spells back at the attacker.",
        ceiling  = 0.05,   -- up to 5% reflect
        k        = 0.000002,
        active   = true,   -- C++ ModifySpellDamageTaken
        phase    = 2,
    },
    -- -- UTILITY ---------------------------------------------
    cooldown_reduction = {
        label    = "Cooldown Reduction",
        desc     = "Chance to reset spell cooldown after casting.",
        ceiling  = 0.20,   -- up to 20% reset chance per cast
        k        = 0.000002,
        -- Implemented as Fallback A: AddSpellCooldown not available in this Eluna build.
        -- Effect is a proc chance to fully reset (not reduce) the cooldown after casting.
        active   = true,   -- Lua PLAYER_EVENT_ON_SPELL_CAST (event 5)
        phase    = 3,
    },
    movement_speed = {
        label    = "Movement Speed",
        desc     = "Increases run speed. Does not affect mounts.",
        ceiling  = 0.15,   -- up to +15% run speed
        k        = 0.000003,
        active   = true,   -- C++ periodic refresh
        phase    = 2,
    },
    threat_reduction = {
        label    = "Threat Reduction",
        desc     = "Reduces generated threat.",
        ceiling  = 0.30,
        k        = 0.000003,
        -- Implemented via custom spell 900001 (AP Threat Reduction) in spell_dbc:
        -- SPELL_EFFECT_APPLY_AURA + SPELL_AURA_MOD_THREAT, EffectMiscValue=127 (all schools).
        -- C++ ApplyAttunementStats applies/updates the aura via AddAura + AuraEffect::ChangeAmount.
        active   = true,   -- C++ periodic refresh (ApplyAttunementStats)
        phase    = 2,
    },
    res_resilience = {
        label    = "Res Resilience",
        desc     = "Reduces durability loss on death.",
        ceiling  = 0.50,   -- up to 50% less durability loss
        k        = 0.000004,
        active   = true,   -- Lua death/respawn hooks
        phase    = 2,
    },
    aether_surge = {
        label    = "Aether Surge",
        desc     = "Bonus Aether from kills and quests.",
        ceiling  = 0.50,   -- up to +50% Aether from kills
        k        = 0.000004,
        active   = true,   -- Lua multiplier in ap_events.lua
        phase    = 2,
    },
    attunement_echo = {
        label    = "Attunement Echo",
        desc     = "Bonus attunement XP rate from kills.",
        ceiling  = 0.50,   -- up to +50% attunement XP
        k        = 0.000004,
        active   = true,   -- Lua multiplier in ap_events.lua
        phase    = 2,
    },
}

-- Ordered list for consistent gossip display
-- Phase 1 actives first, then damage, survival, utility grouping
AP.SinkOrder = {
    -- Phase 1 active
    "life_leech", "fortitude", "melee_power", "spell_power",
    -- Phase 2 damage
    "crit_rating", "haste_rating", "armor_pen", "execute_power",
    -- Phase 2 survival
    "spell_mitigation", "dodge_rating", "parry_rating", "reflect_chance",
    -- Phase 2/3 utility
    "cooldown_reduction", "movement_speed", "threat_reduction",
    "res_resilience", "aether_surge", "attunement_echo",
}

-- ============================================================
-- FLAVOR TEXT
-- One approved lore line per category, displayed in the Crucible
-- UI above each category's mechanical summary.
-- ============================================================
AP.SinkFlavor = {
    life_leech         = "You draw vitality from those you strike down, their fading strength becoming yours.",
    spell_mitigation   = "The Worldsoul's essence forms a shield around your spirit, dulling the bite of hostile magic.",
    fortitude          = "Your body remembers the resilience of titans long past. Death finds you harder to claim.",
    melee_power        = "Every blade and fist you've wielded leaves its memory in your strikes.",
    spell_power        = "The echoes of a thousand spells cast linger in your fingertips, waiting to be unleashed again.",
    dodge_rating       = "You move as though half a heartbeat ahead of the world, where harm cannot quite reach.",
    parry_rating       = "Your hands have learned the shape of every blow before it lands.",
    movement_speed     = "The wind itself seems to favor your passage through Azeroth.",
    aether_surge       = "Your bond with the Worldsoul deepens, and its essence flows to you more readily.",
    attunement_echo    = "Each echo you claim resonates a little louder than the last.",
    armor_pen          = "No ward, no plate, no ancient guard can fully turn your strikes aside.",
    execute_power      = "When your foe's strength wanes, yours rises to meet the end.",
    reflect_chance     = "What is sent against you may yet return to its sender.",
    crit_rating        = "You strike not where your foe stands, but where they will be too slow to avoid.",
    haste_rating       = "Time bends slightly in your favor, granting you moments others do not have.",
    res_resilience     = "Even in death, your legacy holds fast against decay.",
    cooldown_reduction = "Fate occasionally favors the impatient, granting you power before its time.",
    threat_reduction   = "You can walk among danger and, when you choose, go almost unnoticed.",
}

-- ============================================================
-- CACHE
-- AP.SinkCache[accountId][category] = invested (INT)
-- AP.SinkAlloc[guid][category]      = allocation (0.0-1.0)
-- Populated on login, kept in memory for the session.
-- ============================================================
AP.SinkCache = AP.SinkCache or {}
AP.SinkAlloc = AP.SinkAlloc or {}

-- ============================================================
-- MATH
-- ============================================================

-- Returns the raw effect value (0.0-ceiling) for a category
-- given how much Aether has been invested account-wide.
function AP.Sinks.GetEffect(category, invested)
    local def = AP.SinkDefs[category]
    if not def then return 0 end
    if invested <= 0 then return 0 end
    return def.ceiling * (1 - math.exp(-def.k * invested))
end

-- Convenience: returns effect as a percentage string for display
-- e.g. "3.15%"
function AP.Sinks.GetEffectDisplay(category, invested)
    local eff = AP.Sinks.GetEffect(category, invested)
    return string.format("%.2f%%", eff * 100)
end

-- Returns the Aether cost to invest the next `amount` Aether
-- into a category. Cost IS the amount  -  sinks are a direct
-- 1:1 Aether spend. There is no markup. The cost of the sink
-- is simply the Aether you permanently commit.
-- Returns amount as cost (no additional fee in Phase 1).
function AP.Sinks.InvestCost(amount)
    return amount
end

-- ============================================================
-- DB LOAD
-- ============================================================

function AP.Sinks.LoadForAccount(accountId)
    AP.SinkCache[accountId] = {}
    local q = CharDBQuery(string.format(
        "SELECT `category`, `invested` FROM `ap_aether_sinks` WHERE `account_id` = %d",
        accountId
    ))
    if q then
        repeat
            local cat = q:GetString(0)
            local inv = tonumber(tostring(q:GetUInt32(1))) or 0
            AP.SinkCache[accountId][cat] = inv
        until not q:NextRow()
    end
end

function AP.Sinks.LoadAllocForChar(guid)
    AP.SinkAlloc[guid] = {}
    local q = CharDBQuery(string.format(
        "SELECT `category`, `allocation` FROM `ap_sink_allocation` WHERE `guid` = %d",
        guid
    ))
    if q then
        repeat
            local cat = q:GetString(0)
            -- GetString is confirmed available; tonumber handles the float string safely
            local alloc = tonumber(q:GetString(1)) or 0
            AP.SinkAlloc[guid][cat] = alloc
        until not q:NextRow()
    end
end

-- Get cached invested amount, defaulting to 0
function AP.Sinks.GetInvested(accountId, category)
    if not AP.SinkCache[accountId] then return 0 end
    return AP.SinkCache[accountId][category] or 0
end

-- ============================================================
-- INVESTMENT ACTION
-- Deducts Aether from the character's mastery Aether pool
-- and adds it to the account's sink investment.
-- amount must be a positive integer.
-- Returns true on success, false + reason on failure.
-- ============================================================
function AP.Sinks.Invest(player, category, amount)
    if not AP.SinkDefs[category] then
        return false, "Unknown sink category."
    end
    if type(amount) ~= "number" or amount < 1 then
        return false, "Invalid investment amount."
    end
    amount = math.floor(amount)

    local guid      = player:GetGUIDLow()
    local accountId = player:GetAccountId()

    -- Read current Aether
    local q = CharDBQuery(string.format(
        "SELECT `aether` FROM `ap_mastery` WHERE `guid` = %d",
        guid
    ))
    if not q then
        return false, "No Aether record found. Kill something first!"
    end
    local currentAether = tonumber(tostring(q:GetUInt32(0))) or 0

    if currentAether < amount then
        return false, string.format(
            "Not enough Essence. You have %d, need %d.",
            currentAether, amount
        )
    end

    -- NOTE: Two separate commits, not a single transaction. BEGIN/COMMIT via
    -- CharDBExecute is NOT atomic on AzerothCore's async connection pool.
    -- Each CharDBExecute call enqueues a separate BasicStatementTask on a shared
    -- ProducerConsumerQueue consumed by async worker threads, each owning its own
    -- MySQL connection. With >1 async worker, BEGIN can land on connection A and
    -- COMMIT on connection B -- connection B has no open transaction and commits
    -- nothing; connection A's transaction hangs open until timeout.
    -- Even with WorkerThreads=1 (current config), the C++ core (character autosaves,
    -- loot, etc.) also pushes to the same shared queue, so C++ writes can interleave
    -- with an open transaction between BEGIN and COMMIT.
    -- True atomicity requires AzerothCore's BeginTransaction/CommitTransaction C++ API
    -- (which wraps all statements in one TransactionTask queue item and executes them
    -- on one connection). That API is not exposed to Eluna Lua.
    -- Known gap: a crash between these two commits can deduct Aether without the
    -- corresponding sink investment being recorded. Non-exploitable (player loses
    -- Aether, gains nothing). Acceptable until a synchronous transaction mechanism
    -- is confirmed available from Lua.
    CharDBExecute(string.format(
        "UPDATE `ap_mastery` SET `aether` = `aether` - %d WHERE `guid` = %d",
        amount, guid
    ))
    CharDBExecute("COMMIT")
    CharDBExecute(string.format(
        "INSERT INTO `ap_aether_sinks` (`account_id`, `category`, `invested`) "..
        "VALUES (%d, '%s', %d) "..
        "ON DUPLICATE KEY UPDATE `invested` = `invested` + %d",
        accountId, category, amount, amount
    ))
    CharDBExecute("COMMIT")

    -- Update cache
    if not AP.SinkCache[accountId] then AP.SinkCache[accountId] = {} end
    AP.SinkCache[accountId][category] = (AP.SinkCache[accountId][category] or 0) + amount

    local newInvested = AP.SinkCache[accountId][category]
    local newEffect   = AP.Sinks.GetEffectDisplay(category, newInvested)
    local def         = AP.SinkDefs[category]

    player:SendBroadcastMessage(string.format(
        "|cff9966ff[Worldsoul]|r Invested %d Essence in %s. "..
        "Total: %d | Effect: %s (cap: %.0f%%)",
        amount, def.label, newInvested, newEffect, def.ceiling * 100
    ))

    -- Tutorial: first Crucible investment
    if AP.Tutorial and AP.Tutorial.Trigger then
        AP.Tutorial.Trigger(player, "first_crucible")
    end

    -- Visage: check for Crucible milestone crossing
    if AP.Visage and AP.Visage.CheckCrucibleMilestone then
        local totalInvested = 0
        local tq = CharDBQuery(string.format(
            "SELECT SUM(`invested`) FROM `ap_aether_sinks` WHERE `account_id` = %d",
            accountId
        ))
        if tq then totalInvested = tonumber(tostring(tq:GetUInt32(0))) or 0 end
        AP.Visage.CheckCrucibleMilestone(player, totalInvested)
    end

    return true, nil
end

-- ============================================================
-- LIFE LEECH  -  Lua combat hook
-- On creature kill, heal the player for leech% of the
-- creature's max HP. This is a proxy for damage-dealt leech
-- since Eluna on this build may not expose per-hit damage hooks.
-- Only fires if life_leech invested > 0.
-- ============================================================
local function OnKillCreature_Leech(event, player, xp, creature, bonus)
    local ok, err = pcall(function()
        local accountId = player:GetAccountId()

        -- Reload cache if missing entirely, or if life_leech specifically is absent
        if not AP.SinkCache[accountId] or AP.SinkCache[accountId]["life_leech"] == nil then
            AP.Sinks.LoadForAccount(accountId)
        end

        local invested = AP.Sinks.GetInvested(accountId, "life_leech")
        AP.Debug(string.format("LifeLeech check: accountId=%d invested=%d", accountId, invested))
        if invested <= 0 then return end

        local leechFrac = AP.Sinks.GetEffect("life_leech", invested)
        if leechFrac <= 0 then return end

        -- Reduce Life Leech at higher Threat
        local session = AP._session and AP._session[player:GetGUIDLow()]
        local threatLvl = session and session.threat or 0
        if threatLvl > 0 then
            leechFrac = leechFrac * AP.GetSafetyScalar(threatLvl)
        end

        local creatureLevel = creature:GetLevel()
        local playerLevel   = player:GetLevel()
        if (playerLevel - creatureLevel) > 10 then return end

        local mobMaxHP = creature:GetMaxHealth()
        local healAmt  = math.max(1, math.floor(mobMaxHP * leechFrac))
        local curHP    = player:GetHealth()
        local maxHP    = player:GetMaxHealth()

        local heal = math.min(healAmt, maxHP - curHP)
        if heal <= 0 then return end

        -- Try SetHealth; fall back to ModifyHealth if available
        local healed = false
        local hok = pcall(function()
            player:SetHealth(curHP + heal)
            healed = true
        end)
        if not healed then
            pcall(function()
                player:ModifyHealth(heal)
                healed = true
            end)
        end

        if healed then
            player:SendBroadcastMessage(string.format(
                "|cff9966ff[Worldsoul]|r Life Leech: +%d HP (%.2f%% of mob HP)",
                heal, leechFrac * 100
            ))
        else
            print("[AP Sinks] WARN: Life Leech heal failed - SetHealth and ModifyHealth both unavailable on this build")
        end
    end)
    if not ok then
        print("[AP Sinks] ERROR in OnKillCreature_Leech: " .. tostring(err))
    end
end

-- RegisterPlayerEvent(12, OnKillCreature_Leech)  -- disabled: moved to C++ per-hit leech

-- ============================================================
-- LOGIN HOOK  -  load sink data into cache
-- ============================================================
local function OnLogin_Sinks(event, player)
    local ok, err = pcall(function()
        local accountId = player:GetAccountId()
        local guid      = player:GetGUIDLow()
        AP.Sinks.LoadForAccount(accountId)
        AP.Sinks.LoadAllocForChar(guid)
        -- Notify C++ refresh that sink data is ready
        -- (C++ reads directly from DB on its own timer; cache is Lua-side only)
    end)
    if not ok then
        print("[AP Sinks] ERROR in OnLogin_Sinks: " .. tostring(err))
    end
end

RegisterPlayerEvent(3, OnLogin_Sinks)  -- PLAYER_EVENT_ON_LOGIN

-- ============================================================
-- GOSSIP UI  -  Aether Sinks page
-- Called from ap_ui.lua when player selects "Aether Sinks"
-- from the main gossip menu.
-- ============================================================

-- Main sinks overview page
-- Shows all categories grouped by phase with current effect
function AP.Sinks.ShowPage(player, npc, page)
    page = page or 1
    local accountId = player:GetAccountId()
    local guid      = player:GetGUIDLow()

    -- Read current Aether from DB (fresh read for accurate display)
    local aetherNow = 0
    local aq = CharDBQuery(string.format(
        "SELECT `aether` FROM `ap_mastery` WHERE `guid` = %d", guid
    ))
    if aq then
        aetherNow = tonumber(tostring(aq:GetUInt32(0))) or 0
    end

    player:GossipClearMenu()

    -- Header
    local headerText = string.format(
        "The Crucible  -  Invest Essence for permanent effects.\n"..
        "Your Essence: |cffffd700%d|r\n"..
        "Effects marked (ACTIVE) are live this session.\n"..
        "Effects marked (Phase 2) are coming soon.",
        aetherNow
    )
    player:GossipMenuAddItem(0, headerText, 0, 0, false, "", 0)

    -- Build page of 8 categories (gossip menu has item limits)
    local pageSize  = 8
    local startIdx  = (page - 1) * pageSize + 1
    local endIdx    = math.min(startIdx + pageSize - 1, #AP.SinkOrder)
    local totalPages = math.ceil(#AP.SinkOrder / pageSize)

    for i = startIdx, endIdx do
        local cat    = AP.SinkOrder[i]
        local def    = AP.SinkDefs[cat]
        local inv    = AP.Sinks.GetInvested(accountId, cat)
        local effStr = AP.Sinks.GetEffectDisplay(cat, inv)
        local status = def.active and "|cff00ff00ACTIVE|r" or
                       string.format("|cff888888Phase %d|r", def.phase)

        local flavor = AP.SinkFlavor[cat] or ""
        local line
        if flavor ~= "" then
            line = string.format(
                "|cffaa99cc\"%s\"|r\n[%s] %s  -  %s | Invested: %d",
                flavor, status, def.label, effStr, inv
            )
        else
            line = string.format(
                "[%s] %s  -  %s | Invested: %d",
                status, def.label, effStr, inv
            )
        end
        -- sender=1 means "open detail page for this category"
        player:GossipMenuAddItem(0, line, 101, i, false, "", 0)
    end

    -- Navigation
    if page > 1 then
        player:GossipMenuAddItem(0, "<< Previous page", 102, page - 1, false, "", 0)
    end
    if page < totalPages then
        player:GossipMenuAddItem(0, "Next page >>", 102, page + 1, false, "", 0)
    end

    player:GossipMenuAddItem(0, "<< Back to Main Menu", 103, 0, false, "", 0)

    player:GossipSendMenu(1, npc, 102)
end

-- Detail page for a single sink category
function AP.Sinks.ShowDetail(player, npc, catIndex)
    local cat    = AP.SinkOrder[catIndex]
    if not cat then
        AP.Sinks.ShowPage(player, npc, 1)
        return
    end
    local def       = AP.SinkDefs[cat]
    local accountId = player:GetAccountId()
    local guid      = player:GetGUIDLow()
    local inv       = AP.Sinks.GetInvested(accountId, cat)
    local effStr    = AP.Sinks.GetEffectDisplay(cat, inv)

    -- Preview of next milestones
    local preview = ""
    local milestones = { 10000, 50000, 100000, 200000, 500000 }
    for _, m in ipairs(milestones) do
        if m > inv then
            local projEff = AP.Sinks.GetEffectDisplay(cat, m)
            preview = preview .. string.format("\n  At %d invested: %s", m, projEff)
            if #preview > 200 then break end  -- gossip text limit safety
        end
    end

    -- Current Aether
    local aetherNow = 0
    local aq = CharDBQuery(string.format(
        "SELECT `aether` FROM `ap_mastery` WHERE `guid` = %d", guid
    ))
    if aq then aetherNow = tonumber(tostring(aq:GetUInt32(0))) or 0 end

    player:GossipClearMenu()

    local phaseStr = def.active and "|cff00ff00ACTIVE - Phase 1|r" or
                     string.format("|cff888888Coming - Phase %d|r", def.phase)
    local flavor = AP.SinkFlavor[cat] or ""
    local flavorLine = flavor ~= "" and
        string.format("|cffaa99cc\"%s\"|r\n\n", flavor) or ""
    local header = string.format(
        "%s%s  -  %s\n%s\nCeiling: %.0f%%\nYour investment: %d Aether\nCurrent effect: %s\nYour Aether: %d\n\nProjected effects:%s",
        flavorLine, def.label, phaseStr, def.desc,
        def.ceiling * 100, inv, effStr, aetherNow, preview
    )
    player:GossipMenuAddItem(0, header, 0, 0, false, "", 0)

    if def.active then
        -- Invest buttons: fixed amounts
        local investments = { 1000, 5000, 10000, 50000, 100000 }
        for _, amt in ipairs(investments) do
            if aetherNow >= amt then
                local projInv    = inv + amt
                local projEff    = AP.Sinks.GetEffectDisplay(cat, projInv)
                local btnLabel   = string.format(
                    "Invest %d Aether -> effect becomes %s",
                    amt, projEff
                )
                -- sender=4 = invest action, code = catIndex * 1000000 + amt
                -- (pack category and amount into the gossip code integer)
                player:GossipMenuAddItem(0, btnLabel, 104, catIndex * 1000 + math.floor(amt / 1000), false, "", 0)
            end
        end
        if aetherNow < 1000 then
            player:GossipMenuAddItem(0, "|cffff4444Not enough Aether to invest (minimum 1,000)|r", 0, 0, false, "", 0)
        end
    else
        player:GossipMenuAddItem(0, "|cff888888This sink category is not yet active.|r", 0, 0, false, "", 0)
    end

    player:GossipMenuAddItem(0, "<< Back to The Crucible", 105, 1, false, "", 0)
    player:GossipMenuAddItem(0, "<< Back to Main Menu", 103, 0, false, "", 0)

    player:GossipSendMenu(1, npc, 102)
end

-- ============================================================
-- GOSSIP SELECT HANDLER
-- Call this from ap_ui.lua's existing OnGossipSelect.
-- Suggested: add to the main gossip select routing table
-- with a new sender range for sinks.
--
-- sender codes used here:
--   0 = display-only (no action)
--   1 = open sink detail page (code = index in SinkOrder)
--   2 = navigate sink list pages (code = page number)
--   3 = back to main menu (handled by ap_ui.lua)
--   4 = invest action (code = catIndex * 1000 + amtK)
--   5 = back to sink list page (code = page number)
-- ============================================================
function AP.Sinks.OnSelect(player, npc, sender, code, menu)
    if sender == 0 then
        -- display only, no action
        return
    elseif sender == 1 then
        AP.Sinks.ShowDetail(player, npc, code)
    elseif sender == 2 then
        AP.Sinks.ShowPage(player, npc, code)
    elseif sender == 3 then
        AP.OpenUI(player)
    elseif sender == 4 then
        -- Invest action: unpack catIndex and amtK from code
        local catIndex = math.floor(code / 1000)
        local amtK     = code % 1000
        local amount   = amtK * 1000
        local cat      = AP.SinkOrder[catIndex]

        if not cat then
            player:SendBroadcastMessage("|cffff4444[Worldsoul] Invalid category.|r")
            AP.Sinks.ShowPage(player, npc, 1)
            return
        end

        local success, reason = AP.Sinks.Invest(player, cat, amount)
        if success then
            -- Refresh detail page to show updated state
            AP.Sinks.ShowDetail(player, npc, catIndex)
        else
            player:SendBroadcastMessage("|cffff4444[Worldsoul] " .. (reason or "Error.") .. "|r")
            AP.Sinks.ShowDetail(player, npc, catIndex)
        end
    elseif sender == 5 then
        AP.Sinks.ShowPage(player, npc, code)
    end
end

-- ============================================================
-- UTILITY: Export effect values for C++ to read
-- C++ reads directly from ap_aether_sinks via CharDB.
-- These Lua functions are provided for reference and for
-- any future Lua-side consumers.
-- ============================================================

-- Get the current life leech fraction for a player
function AP.Sinks.GetLifeLeechForPlayer(player)
    local accountId = player:GetAccountId()
    local inv = AP.Sinks.GetInvested(accountId, "life_leech")
    return AP.Sinks.GetEffect("life_leech", inv)
end

-- Get the current fortitude bonus fraction for a player
function AP.Sinks.GetFortitudeForPlayer(player)
    local accountId = player:GetAccountId()
    local inv = AP.Sinks.GetInvested(accountId, "fortitude")
    return AP.Sinks.GetEffect("fortitude", inv)
end

-- Get the current melee power bonus fraction for a player
function AP.Sinks.GetMeleePowerForPlayer(player)
    local accountId = player:GetAccountId()
    local inv = AP.Sinks.GetInvested(accountId, "melee_power")
    return AP.Sinks.GetEffect("melee_power", inv)
end

-- Get the current spell power bonus fraction for a player
function AP.Sinks.GetSpellPowerForPlayer(player)
    local accountId = player:GetAccountId()
    local inv = AP.Sinks.GetInvested(accountId, "spell_power")
    return AP.Sinks.GetEffect("spell_power", inv)
end

print("[AP Sinks] Aether Sink system loaded. Phase 1: Life Leech (C++ per-hit), Fortitude/Melee Power/Spell Power (C++).")

-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- ap_commands.lua - Echoes of the Worldsoul Command Suite
-- Handles all #ap subcommands beyond the basic UI opener.
-- Drop into lua_scripts alongside other AP files.
--
-- GM COMMANDS (#ap gm ...):
--   #ap gm aether <amount>          -- grant Aether to self
--   #ap gm mastery <rank>           -- set mastery rank directly
--   #ap gm attuneequipped           -- force-attune all equipped items
--   #ap gm attuneall                -- force-attune all snapshots
--   #ap gm sinkset <category> <amt> -- set a sink investment directly
--   #ap gm talents reset            -- reset talents, refund Aether
--   #ap gm status                   -- full state dump
--   #ap gm refresh                  -- not implementable in Lua (C++ timer)
--   #ap gm anticheese <on/off>      -- toggle anti-cheese this session
--   #ap gm wipechar                 -- wipe this character's AP progress
--
-- PLAYER COMMANDS (#ap ...):
--   #ap rate xp <0.1-20>            -- set personal attunement XP rate
--   #ap rate aether <0.1-20>        -- set personal Aether gain rate
--   #ap rate boss <0.1-20>          -- set personal boss Aether rate
--   #ap attuneall                   -- instantly attune all equipped items
--   #ap attuneme                    -- gossip page: attune individual items
--   #ap check                       -- quick status text dump
--   #ap sinks                       -- quick sink investment dump
-- ============================================================

AP = AP or {}
AP.Commands = AP.Commands or {}

-- Session-level anti-cheese toggle per player guid
AP.AntiCheeseDisabled = AP.AntiCheeseDisabled or {}

-- ============================================================
-- RATE SYSTEM
-- Stored in ap_mastery table via ALTER TABLE (see schema note).
-- Falls back to 1.0 if columns don't exist yet.
-- ============================================================

-- Cache rates per guid for the session
AP.RateCache = AP.RateCache or {}

function AP.Commands.GetRates(guid)
    if AP.RateCache[guid] then
        return AP.RateCache[guid]
    end
    local rates = { xp = 1.0, aether = 1.0, boss = 1.0 }
    local ok = pcall(function()
        local q = CharDBQuery(string.format(
            "SELECT `rate_xp`, `rate_aether`, `rate_boss` FROM `ap_mastery` WHERE `guid` = %d",
            guid
        ))
        if q then
            rates.xp     = tonumber(q:GetString(0)) or 1.0
            rates.aether = tonumber(q:GetString(1)) or 1.0
            rates.boss   = tonumber(q:GetString(2)) or 1.0
        end
    end)
    if not ok then
        -- Columns don't exist yet - schema migration not run
        -- Return defaults silently
    end
    AP.RateCache[guid] = rates
    return rates
end

function AP.Commands.SetRate(player, rateType, value)
    local guid = player:GetGUIDLow()
    value = tonumber(value)
    if not value then
        player:SendBroadcastMessage("|cffff4444[Worldsoul] Rate must be a number.|r")
        return
    end
    value = math.max(0.1, math.min(20.0, value))

    local col
    if rateType == "xp"     then col = "rate_xp"
    elseif rateType == "aether" then col = "rate_aether"
    elseif rateType == "boss"   then col = "rate_boss"
    else
        player:SendBroadcastMessage("|cffff4444[Worldsoul] Unknown rate type. Use: xp, aether, boss|r")
        return
    end

    local ok, err = pcall(function()
        CharDBExecute(string.format(
            "UPDATE `ap_mastery` SET `%s` = %.2f WHERE `guid` = %d",
            col, value, guid
        ))
        CharDBExecute("COMMIT")
    end)
    if not ok then
        player:SendBroadcastMessage(
            "|cffff4444[Worldsoul] Rate columns not found. Run ap_rates_schema.sql first.|r"
        )
        return
    end

    -- Update cache
    if not AP.RateCache[guid] then AP.RateCache[guid] = { xp=1.0, aether=1.0, boss=1.0 } end
    AP.RateCache[guid][rateType] = value

    player:SendBroadcastMessage(string.format(
        "|cff9966ff[Worldsoul]|r %s rate set to |cffffff00%.2fx|r",
        rateType:upper(), value
    ))
    if AP.Tutorial and AP.Tutorial.Trigger then
        AP.Tutorial.Trigger(player, "first_rate")
    end
end

-- Called by ap_events.lua to get the current rates for a player
-- Returns the rates table; if not cached, loads from DB
function AP.GetPlayerRates(guid)
    return AP.Commands.GetRates(guid)
end

-- ============================================================
-- FORCE ATTUNE HELPERS
-- ============================================================

-- Mark an item entry as attuned for this account in ap_item_attune
-- and force-insert a snapshot if one exists or can be derived.
-- Uses account-wide guid (accountId) for snapshot table.
local function ForceAttuneEntry(player, itemEntry)
    local guid      = player:GetGUIDLow()
    local accountId = player:GetAccountId()

    -- Set progress to cap and mark attuned in ap_item_attune (char-level tracking)
    CharDBExecute(string.format(
        "INSERT INTO `ap_item_attune` (`guid`, `item_entry`, `progress`, `attuned`) "..
        "VALUES (%d, %d, 10000, 1) "..
        "ON DUPLICATE KEY UPDATE `progress` = 10000, `attuned` = 1",
        guid, itemEntry
    ))
    CharDBExecute("COMMIT")
end

-- Force-attune all currently equipped items
-- Takes a fresh snapshot of each equipped slot and marks attuned
function AP.Commands.AttuneEquipped(player)
    local guid      = player:GetGUIDLow()
    local accountId = player:GetAccountId()
    local count     = 0

    -- Equipment slots 0-18 (head through ranged/wand)
    for slot = 0, 18 do
        local item = player:GetEquippedItemBySlot(slot)
        if item then
            local entry = item:GetEntry()
            if entry and entry > 0 then
                ForceAttuneEntry(player, entry)
                count = count + 1
            end
        end
    end

    CharDBExecute("COMMIT")

    player:SendBroadcastMessage(string.format(
        "|cff00ccff[Worldsoul GM]|r Force-attuned %d equipped items. "..
        "Snapshots will be taken on next C++ refresh (within 10s).",
        count
    ))
end

-- Force-attune all items that already have a snapshot entry for this account
function AP.Commands.AttuneAll(player)
    local guid      = player:GetGUIDLow()
    local accountId = player:GetAccountId()

    -- Get all snapshot entries for this account
    local q = CharDBQuery(string.format(
        "SELECT `item_entry` FROM `ap_item_snapshot` WHERE `guid` = %d",
        accountId
    ))
    if not q then
        player:SendBroadcastMessage("|cffff4444[Worldsoul] No snapshots found for this account.|r")
        return
    end

    local count = 0
    repeat
        local entry = tonumber(tostring(q:GetUInt32(0))) or 0
        if entry > 0 then
            ForceAttuneEntry(player, entry)
            count = count + 1
        end
    until not q:NextRow()

    CharDBExecute("COMMIT")

    player:SendBroadcastMessage(string.format(
        "|cff9966ff[Worldsoul]|r Force-attuned %d items from your snapshot history.",
        count
    ))
end

-- ============================================================
-- STATUS DUMP
-- ============================================================

function AP.Commands.Status(player)
    local guid      = player:GetGUIDLow()
    local accountId = player:GetAccountId()

    -- Aether and mastery
    local aether  = 0
    local mastery = 0
    local q = CharDBQuery(string.format(
        "SELECT `aether`, `mastery` FROM `ap_mastery` WHERE `guid` = %d", guid
    ))
    if q then
        aether  = tonumber(tostring(q:GetUInt32(0))) or 0
        mastery = tonumber(tostring(q:GetUInt32(1))) or 0
    end

    -- Total attuned items
    local attuned = 0
    local qa = CharDBQuery(string.format(
        "SELECT COUNT(*) FROM `ap_item_attune` WHERE `guid` = %d AND `attuned` = 1", guid
    ))
    if qa then attuned = tonumber(tostring(qa:GetUInt32(0))) or 0 end

    -- Total snapshots
    local snaps = 0
    local qs = CharDBQuery(string.format(
        "SELECT COUNT(*) FROM `ap_item_snapshot` WHERE `guid` = %d", accountId
    ))
    if qs then snaps = tonumber(tostring(qs:GetUInt32(0))) or 0 end

    -- Absorption percent (from ap_core if available)
    local absorbPct = 0
    if AP.GetAbsorption then
        absorbPct = AP.GetAbsorption(mastery) * 100
    end

    -- Sink investments
    local sinkLines = ""
    local sq = CharDBQuery(string.format(
        "SELECT `category`, `invested` FROM `ap_aether_sinks` WHERE `account_id` = %d "..
        "ORDER BY `invested` DESC",
        accountId
    ))
    if sq then
        repeat
            local cat = sq:GetString(0)
            local inv = tonumber(tostring(sq:GetUInt32(1))) or 0
            if inv > 0 then
                local def = AP.SinkDefs and AP.SinkDefs[cat]
                local effStr = ""
                if def then
                    effStr = string.format(" (%.2f%%)", AP.Sinks.GetEffect(cat, inv) * 100)
                end
                sinkLines = sinkLines .. string.format("\n  %s: %d%s", cat, inv, effStr)
            end
        until not sq:NextRow()
    end
    if sinkLines == "" then sinkLines = "\n  None" end

    -- Rates
    local rates = AP.Commands.GetRates(guid)

    player:SendBroadcastMessage(string.format(
        "|cff00ccff[Worldsoul Status]|r\n"..
        "Essence: |cffffff00%d|r  Mastery Rank: |cffffff00%d|r  Effective Absorption: |cffffff00%.1f%%|r\n"..
        "Attuned Items: |cffffff00%d|r  Snapshots: |cffffff00%d|r\n"..
        "Rates: XP=|cffffff00%.1fx|r Essence=|cffffff00%.1fx|r Boss=|cffffff00%.1fx|r\n"..
        "Crucible investments:%s",
        aether, mastery, absorbPct,
        attuned, snaps,
        rates.xp, rates.aether, rates.boss,
        sinkLines
    ))
end

-- ============================================================
-- QUICK SINK DUMP
-- ============================================================

function AP.Commands.SinksDump(player)
    local accountId = player:GetAccountId()
    local lines = "|cff00ccff[AP Sinks]|r Current investments:\n"
    local hasAny = false

    for _, cat in ipairs(AP.SinkOrder or {}) do
        local inv = AP.Sinks and AP.Sinks.GetInvested(accountId, cat) or 0
        if inv > 0 then
            local def    = AP.SinkDefs and AP.SinkDefs[cat]
            local label  = def and def.label or cat
            local effStr = AP.Sinks and AP.Sinks.GetEffectDisplay(cat, inv) or "?"
            lines = lines .. string.format("  %s: %d invested -> %s\n", label, inv, effStr)
            hasAny = true
        end
    end

    if not hasAny then
        lines = lines .. "  No Aether invested in any sink yet."
    end

    player:SendBroadcastMessage(lines)
end

-- ============================================================
-- GM: SET MASTERY RANK
-- ============================================================

function AP.Commands.GM_SetMastery(player, args)
    local rank = math.floor(tonumber(args[1]) or 0)
    if rank < 0 then rank = 0 end

    local guid = player:GetGUIDLow()
    CharDBExecute(string.format(
        "INSERT INTO `ap_mastery` (`guid`, `aether`, `mastery`) VALUES (%d, 0, %d) "..
        "ON DUPLICATE KEY UPDATE `mastery` = %d",
        guid, rank, rank
    ))
    CharDBExecute("COMMIT")

    player:SendBroadcastMessage(string.format(
        "|cff00ccff[Worldsoul GM]|r Mastery rank set to |cffffff00%d|r. "..
        "Stat refresh will apply within 10s.",
        rank
    ))
end

-- ============================================================
-- GM: SET SINK INVESTMENT
-- ============================================================

function AP.Commands.GM_SinkSet(player, args)
    local cat    = args[1]
    local amount = math.floor(tonumber(args[2]) or 0)

    if not cat or not AP.SinkDefs or not AP.SinkDefs[cat] then
        player:SendBroadcastMessage(
            "|cffff4444[Worldsoul GM] Unknown category. Check AP.SinkDefs for valid names.|r"
        )
        return
    end
    if amount < 0 then amount = 0 end

    local accountId = player:GetAccountId()

    CharDBExecute(string.format(
        "INSERT INTO `ap_aether_sinks` (`account_id`, `category`, `invested`) "..
        "VALUES (%d, '%s', %d) "..
        "ON DUPLICATE KEY UPDATE `invested` = %d",
        accountId, cat, amount, amount
    ))
    CharDBExecute("COMMIT")

    -- Update Lua cache
    if not AP.SinkCache then AP.SinkCache = {} end
    if not AP.SinkCache[accountId] then AP.SinkCache[accountId] = {} end
    AP.SinkCache[accountId][cat] = amount

    local effStr = AP.Sinks and AP.Sinks.GetEffectDisplay(cat, amount) or "?"
    player:SendBroadcastMessage(string.format(
        "|cff00ccff[Worldsoul GM]|r %s investment set to |cffffff00%d|r -> effect: %s",
        cat, amount, effStr
    ))
end

-- ============================================================
-- GM: RESET TALENTS
-- ============================================================

function AP.Commands.GM_TalentsReset(player)
    local guid = player:GetGUIDLow()

    -- Sum up what was spent so we can refund it
    local refund = 0
    local q = CharDBQuery(string.format(
        "SELECT `stat_index`, `rank` FROM `ap_talents` WHERE `guid` = %d", guid
    ))
    if q then
        repeat
            local statIdx = tonumber(tostring(q:GetUInt32(0))) or 0
            local rank    = tonumber(tostring(q:GetUInt32(1))) or 0
            -- Tripling cost curve: primary (rank 1=2000, 2=6000, 3=18000)
            -- secondary (rank 1=1000, 2=3000)
            -- Refund based on rank count
            local base = (statIdx < 5) and AP.Config and AP.Config.TalentCostPrimary or
                         (AP.Config and AP.Config.TalentCostSecondary or 1000)
            for r = 1, rank do
                refund = refund + math.floor(base * (3 ^ (r - 1)))
            end
        until not q:NextRow()
    end

    -- Wipe talents
    CharDBExecute(string.format(
        "DELETE FROM `ap_talents` WHERE `guid` = %d", guid
    ))
    -- Refund Aether
    if refund > 0 then
        CharDBExecute(string.format(
            "UPDATE `ap_mastery` SET `aether` = `aether` + %d WHERE `guid` = %d",
            refund, guid
        ))
    end
    CharDBExecute("COMMIT")

    player:SendBroadcastMessage(string.format(
        "|cff00ccff[Worldsoul GM]|r Talents reset. Refunded |cffffff00%d|r Aether.",
        refund
    ))
end

-- ============================================================
-- GM: ANTI-CHEESE TOGGLE
-- ============================================================

function AP.Commands.GM_AntiCheese(player, state)
    local guid = player:GetGUIDLow()
    if state == "off" then
        AP.AntiCheeseDisabled[guid] = true
        player:SendBroadcastMessage("|cffff8800[Worldsoul GM]|r Anti-cheese DISABLED for this session.")
    else
        AP.AntiCheeseDisabled[guid] = nil
        player:SendBroadcastMessage("|cff00ccff[Worldsoul GM]|r Anti-cheese ENABLED.")
    end
end

-- ============================================================
-- GM: WIPE CHARACTER (with confirmation)
-- Two-step: first call sets a pending flag, second call executes.
-- ============================================================
AP.WipePending = AP.WipePending or {}

function AP.Commands.GM_WipeChar(player, confirmed)
    local guid = player:GetGUIDLow()

    if confirmed ~= "confirm" then
        AP.WipePending[guid] = true
        player:SendBroadcastMessage(
            "|cffff4444[Worldsoul GM] WARNING:|r This will wipe ALL attunement progress for "..
            player:GetName()..". Type:|r\n"..
            "|cffffff00#ap gm wipechar confirm|r to proceed."
        )
        return
    end

    if not AP.WipePending[guid] then
        player:SendBroadcastMessage(
            "|cffff4444[Worldsoul GM] Run #ap gm wipechar first, then confirm within the same session.|r"
        )
        return
    end

    AP.WipePending[guid] = nil

    CharDBExecute(string.format("DELETE FROM `ap_item_attune`   WHERE `guid` = %d", guid))
    CharDBExecute(string.format("DELETE FROM `ap_talents`       WHERE `guid` = %d", guid))
    CharDBExecute(string.format("DELETE FROM `ap_slot_mastery`  WHERE `guid` = %d", guid))
    CharDBExecute(string.format("DELETE FROM `ap_quest_rewarded` WHERE `guid` = %d", guid))
    CharDBExecute(string.format(
        "UPDATE `ap_mastery` SET `aether` = 0, `mastery` = 0 WHERE `guid` = %d", guid
    ))
    -- Note: does NOT wipe ap_item_snapshot (account-wide) or ap_aether_sinks (account-wide)
    CharDBExecute("COMMIT")

    player:SendBroadcastMessage(
        "|cffff4444[Worldsoul GM]|r Character progress wiped for "..player:GetName()..
        ". Snapshots and sink investments preserved (account-wide)."
    )
end

-- ============================================================
-- GM: TEST RESONANT DROP
-- Simulates a resonant loot event for any item entry.
-- Bypasses the loot event so the fragment system can be tested
-- without farming a specific mob drop.
-- Usage: #ap gm testresonant <itemEntry>
-- ============================================================

function AP.Commands.GM_TestResonant(player, args)
    local itemEntry = math.floor(tonumber(args[1]) or 0)
    if itemEntry <= 0 then
        player:SendBroadcastMessage("|cffff4444[Worldsoul GM] Usage: #ap gm testresonant <itemEntry>|r")
        return
    end

    local ECHO_FRAGMENT_ENTRY = 900010

    -- Look up quality from item_template
    local quality = 1
    local iq = WorldDBQuery(string.format(
        "SELECT `Quality`, `name` FROM `item_template` WHERE `entry` = %d LIMIT 1", itemEntry))
    if not iq then
        player:SendBroadcastMessage(string.format(
            "|cffff4444[Worldsoul GM] Item entry %d not found in item_template.|r", itemEntry))
        return
    end
    quality = tonumber(iq:GetUInt8(0)) or 1
    local itemName = iq:GetString(1) or ("Item " .. itemEntry)

    local guid      = player:GetGUIDLow()
    local accountId = player:GetAccountId()

    -- Store context for the fragment use handler
    EotW_EchoFragmentQuality   = EotW_EchoFragmentQuality   or {}
    EotW_EchoFragmentItemEntry = EotW_EchoFragmentItemEntry or {}
    EotW_EchoFragmentQuality[guid]   = quality
    EotW_EchoFragmentItemEntry[guid] = itemEntry

    -- Increment drop count so Legacy Surge works correctly in the test
    local dropCount = 0
    local qd = CharDBQuery(string.format(
        "SELECT `drop_count` FROM `ap_resonant_drops` WHERE `account_id` = %d AND `item_entry` = %d",
        accountId, itemEntry))
    if qd then dropCount = tonumber(tostring(qd:GetUInt32(0))) or 0 end
    dropCount = dropCount + 1
    CharDBExecute(string.format(
        "INSERT INTO `ap_resonant_drops` (`account_id`, `item_entry`, `drop_count`) "..
        "VALUES (%d, %d, 1) ON DUPLICATE KEY UPDATE `drop_count` = `drop_count` + 1",
        accountId, itemEntry))
    CharDBExecute("COMMIT")

    -- Give the fragment
    local fragGiven = false
    pcall(function() player:AddItem(ECHO_FRAGMENT_ENTRY, 1); fragGiven = true end)

    if fragGiven then
        local isSurge = (dropCount >= 4)
        local goldPrev
        if quality >= 5 then     goldPrev = "20g"
        elseif quality >= 4 then goldPrev = "8g"
        elseif quality >= 3 then goldPrev = "3g"
        elseif quality >= 2 then goldPrev = "1g"
        else                     goldPrev = "20s"
        end

        player:SendBroadcastMessage(string.format(
            "|cff00ccff[Worldsoul GM]|r Resonant drop simulated for |cffffff00%s|r (quality %d, drop #%d).",
            itemName, quality, dropCount))
        if isSurge then
            player:SendBroadcastMessage(string.format(
                "|cffffd700[Worldsoul]|r |cffff8800Legacy Surge!|r Echo already claimed. "..
                "A |cff9966ffWorldsoul Echo Fragment|r is in your bag. "..
                "Right-click for |cffffff003x Essence + %s|r.", goldPrev))
        else
            player:SendBroadcastMessage(string.format(
                "|cffffd700[Worldsoul]|r Echo already claimed. "..
                "A |cff9966ffWorldsoul Echo Fragment|r is in your bag. "..
                "Right-click for |cffffff00Essence + %s|r, or disenchant/vendor.", goldPrev))
        end
    else
        player:SendBroadcastMessage(
            "|cffff4444[Worldsoul GM] Could not give Echo Fragment â€” bag may be full.|r")
        -- Roll back drop count since we couldn't complete the test
        CharDBExecute(string.format(
            "UPDATE `ap_resonant_drops` SET `drop_count` = `drop_count` - 1 "..
            "WHERE `account_id` = %d AND `item_entry` = %d", accountId, itemEntry))
        CharDBExecute("COMMIT")
    end
end

-- ============================================================
-- MAIN CHAT COMMAND ROUTER
-- Registered on PLAYER_EVENT_ON_CHAT alongside existing #ap handler.
-- Only intercepts subcommands not already handled by ap_events.lua.
-- ============================================================

local function OnChat(event, player, msg, msgType, lang)
    local lower = string.lower(msg)

    -- Only handle #ap subcommands (not bare #ap which opens the UI)
    if not lower:find("^#ap%s") then
        return
    end

    -- Tokenize
    local tokens = {}
    for t in msg:gmatch("%S+") do
        tokens[#tokens + 1] = t
    end
    -- tokens[1]="#ap", tokens[2]=subcommand, tokens[3+]=args

    local sub = string.lower(tokens[2] or "")

    -- -- PLAYER COMMANDS ------------------------------------------

    if sub == "check" then
        AP.Commands.Status(player)
        return false

    elseif sub == "sinks" then
        AP.Commands.SinksDump(player)
        return false

    elseif sub == "attuneall" then
        AP.Commands.AttuneAll(player)
        return false

    elseif sub == "attuneme" then
        -- Open gossip-based per-item attune page
        -- Requires player to be near an NPC or using self-gossip
        -- For now: text list of equipped items with their progress
        AP.Commands.ShowAttuneMe(player)
        return false

    elseif sub == "rack" then
        local itemEntry = tonumber(tokens[3])
        if not itemEntry then
            player:SendBroadcastMessage(
                "|cffffd700[Worldsoul]|r Usage: #ap rack <itemEntry>\n"..
                "Find item entry IDs with: |cffffff00#apfind <name>|r\n"..
                "Example: #ap rack 49623"
            )
        else
            if AP.Rack and AP.Rack.AddItem then
                AP.Rack.AddItem(player, math.floor(itemEntry))
            else
                player:SendBroadcastMessage(
                    "|cffff4444[Worldsoul]|r Attunement Rack not loaded.|r"
                )
            end
        end
        return false

    elseif sub == "rate" then
        local rateType = string.lower(tokens[3] or "")
        local value    = tokens[4]
        AP.Commands.SetRate(player, rateType, value)
        return false

    -- -- GM COMMANDS -----------------------------------------------

    elseif sub == "gm" then
        if not AP.IsGM(player) then
            player:SendBroadcastMessage("|cffff4444[Worldsoul]|r GM access required.")
            return false
        end
        local gmSub = string.lower(tokens[3] or "")
        local args  = { table.unpack(tokens, 4) }

        if gmSub == "aether" then
            -- Handled by ap_gm_aether.lua; shouldn't reach here but safe to handle
            local amount     = tonumber(args[1]) or 0
            local targetName = args[2] or ""
            -- Delegate to existing handler if available
            if AP.GM and AP.GM.GrantAether then
                AP.GM.GrantAether(player, targetName, amount)
            else
                player:SendBroadcastMessage(
                    "|cffff4444[Worldsoul] Use #ap gmaether <amount> instead.|r"
                )
            end

        elseif gmSub == "mastery" then
            AP.Commands.GM_SetMastery(player, args)

        elseif gmSub == "attuneequipped" then
            AP.Commands.AttuneEquipped(player)

        elseif gmSub == "attuneall" then
            AP.Commands.AttuneAll(player)

        elseif gmSub == "sinkset" then
            AP.Commands.GM_SinkSet(player, args)

        elseif gmSub == "talents" then
            if string.lower(args[1] or "") == "reset" then
                AP.Commands.GM_TalentsReset(player)
            else
                player:SendBroadcastMessage(
                    "|cffff4444[Worldsoul GM] Usage: #ap gm talents reset|r"
                )
            end

        elseif gmSub == "status" then
            AP.Commands.Status(player)

        elseif gmSub == "anticheese" then
            AP.Commands.GM_AntiCheese(player, string.lower(args[1] or "on"))

        elseif gmSub == "wipechar" then
            AP.Commands.GM_WipeChar(player, string.lower(args[1] or ""))

        elseif gmSub == "testresonant" then
            AP.Commands.GM_TestResonant(player, args)

        else
            player:SendBroadcastMessage(
                "|cffff4444[Worldsoul GM] Unknown command: " .. gmSub .. "\n"..
                "Available: aether, mastery, attuneequipped, attuneall, "..
                "sinkset, talents reset, status, anticheese, wipechar, testresonant|r"
            )
        end
        return false

    elseif sub == "clientversion" then
        -- Sent automatically by the client AddOn on login.
        -- Compares reported client version against AP.VERSION and warns if mismatched.
        local reported = tokens[3] or "unknown"
        if AP.VERSION and reported ~= AP.VERSION then
            player:SendBroadcastMessage(
                "|cffff4444[Worldsoul]|r ================================================")
            player:SendBroadcastMessage(string.format(
                "|cffff4444[Worldsoul] ADDON OUT OF DATE|r" ..
                "  (you: |cffffff00v%s|r  server: |cff9966ffv%s|r)",
                reported, AP.VERSION))
            player:SendBroadcastMessage(
                "|cffff4444[Worldsoul]|r Update from: " ..
                "|cffffff00https://github.com/vibecoder99/echoes-of-the-worldsoul/releases|r")
            player:SendBroadcastMessage(
                "|cffff4444[Worldsoul]|r ================================================")
        end
        return false

    -- Not a command this file handles; let ap_events.lua handle it
    end
end

RegisterPlayerEvent(18, OnChat)  -- PLAYER_EVENT_ON_CHAT

-- ============================================================
-- ATTUNE ME: text-based equipped item status
-- Shows each equipped item, its current progress, and whether
-- it's attuned. GM players get a force-attune option via
-- followup command.
-- ============================================================

function AP.Commands.ShowAttuneMe(player)
    local guid      = player:GetGUIDLow()
    local accountId = player:GetAccountId()

    local slotNames = {
        [0]="Head",[1]="Neck",[2]="Shoulders",[3]="Shirt",[4]="Chest",
        [5]="Waist",[6]="Legs",[7]="Feet",[8]="Wrists",[9]="Hands",
        [10]="Finger1",[11]="Finger2",[12]="Trinket1",[13]="Trinket2",
        [14]="Back",[15]="MainHand",[16]="OffHand",[17]="Ranged",[18]="Tabard"
    }

    local lines = "|cff9966ff[Worldsoul]|r Equipped item attunement:\n"
    local cap = AP.Config and AP.Config.CapPerItem or 10000

    for slot = 0, 18 do
        local item = player:GetEquippedItemBySlot(slot)
        if item then
            local entry    = item:GetEntry()
            local slotName = slotNames[slot] or ("Slot"..slot)

            -- Look up progress
            local progress = 0
            local attuned  = false
            local pq = CharDBQuery(string.format(
                "SELECT `progress`, `attuned` FROM `ap_item_attune` "..
                "WHERE `guid` = %d AND `item_entry` = %d",
                guid, entry
            ))
            if pq then
                progress = tonumber(tostring(pq:GetUInt32(0))) or 0
                attuned  = (tonumber(tostring(pq:GetUInt32(1))) or 0) == 1
            end

            local pct    = math.floor(progress / cap * 100)
            local status = attuned and "|cff00ff00ATTUNED|r" or
                           string.format("|cffffff00%d/%d (%d%%)|r", progress, cap, pct)

            lines = lines .. string.format("  [%s] entry=%d %s\n", slotName, entry, status)
        end
    end

    lines = lines .. "\nGM tip: |cffffff00#ap gm attuneequipped|r to force-attune all."
    player:SendBroadcastMessage(lines)
end

-- ============================================================
-- RATE SCHEMA NOTE
-- Run this SQL before using #ap rate commands:
--
-- ALTER TABLE `ap_mastery`
--   ADD COLUMN IF NOT EXISTS `rate_xp`     FLOAT NOT NULL DEFAULT 1.0,
--   ADD COLUMN IF NOT EXISTS `rate_aether` FLOAT NOT NULL DEFAULT 1.0,
--   ADD COLUMN IF NOT EXISTS `rate_boss`   FLOAT NOT NULL DEFAULT 1.0;
--
-- ap_events.lua integration: wherever Aether or XP is calculated,
-- call AP.GetPlayerRates(guid) and multiply by the relevant rate.
-- Example:
--   local rates = AP.GetPlayerRates(guid)
--   local finalAether = baseAether * rates.aether
--   local finalXP     = baseXP     * rates.xp
-- ============================================================

print("[AP Commands] Command suite loaded.")
print("[AP Commands] GM: #ap gm aether/mastery/attuneequipped/attuneall/sinkset/talents/status/anticheese/wipechar")
print("[AP Commands] Player: #ap check/sinks/attuneall/attuneme/rate/rack")

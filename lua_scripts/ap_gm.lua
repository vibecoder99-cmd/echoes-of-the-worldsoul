-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- ap_gm.lua
-- Echoes of the Worldsoul — GM / Debug Tools
-- ============================================================
-- EVENT ID REFERENCE (confirmed from Hooks.h):
--   18 = PLAYER_EVENT_ON_CHAT    (SAY â€” includes GM chat)
--   19 = PLAYER_EVENT_ON_WHISPER (whisper)
--   42 = PLAYER_EVENT_ON_COMMAND (in-game /commands AND worldserver console)
--
-- GM COMMANDS â€” type in-game chat OR worldserver console:
--   #apgm aether <amount>      â€” grant Aether to self
--   #apgm setmastery <rank>    â€” set mastery rank
--   #apgm snapshot             â€” force snapshot all equipped items
--   #apgm wipeattune           â€” wipe this character's attune bars only
--   #apgm toggledebug          â€” toggle debug logging
--   #apgm togglecheese         â€” toggle anti-cheese bypass
--   #apgm threat <0-10>        â€” set threat level
--   #apgm info                 â€” show current state
--
-- WORLDSERVER CONSOLE:
--   Commands typed at the worldserver terminal fire event 42
--   with player = nil.  All #apgm commands require a player
--   object, so they must be used in-game.
-- ============================================================

AP = AP or {}
AP._gmCheeseBypassed = false

-- ============================================================
-- COMMAND HANDLER
-- ============================================================
function AP.HandleGMCommand(player, rawMsg)
    if not player then return false end

    local msg = rawMsg:lower():match("^%s*(.-)%s*$")
    if not msg:match("^#apgm") then return false end

    if not AP.IsGM(player) then
        player:SendBroadcastMessage("|cffff4444[Worldsoul]|r GM access required.")
        return true
    end

    local function Reply(text)
        AP.Try(function()
            player:SendBroadcastMessage("|cffff9900[Worldsoul GM]|r " .. text)
        end, "GM reply")
    end

    -- Grant Aether
    local aetherAmt = msg:match("^#apgm%s+aether%s+(%d+)$")
    if aetherAmt then
        local amount = tonumber(aetherAmt)
        if amount and amount > 0 then
            AP.GrantAether(player:GetGUIDLow(), amount)
            Reply("Granted " .. amount .. " Aether.")
        else
            Reply("Usage: #apgm aether <positive_number>")
        end
        return true
    end

    -- Set mastery
    local masteryRank = msg:match("^#apgm%s+setmastery%s+(%d+)$")
    if masteryRank then
        local rank = tonumber(masteryRank)
        if rank and rank >= 0 then
            local guid = player:GetGUIDLow()
            AP.Try(function()
                CharDBQuery(string.format([[
                    INSERT INTO `ap_mastery` (`guid`, `aether`, `mastery`)
                    VALUES (%d, 0, %d)
                    ON DUPLICATE KEY UPDATE `mastery` = %d;
                ]], guid, rank, rank))
            end, "GM setmastery")
            Reply("Mastery set to rank " .. rank .. ".")
        else
            Reply("Usage: #apgm setmastery <rank>")
        end
        return true
    end

    -- Force snapshot
    if msg == "#apgm snapshot" then
        local guid  = player:GetGUIDLow()
        local slots = {0,1,2,4,5,6,7,8,9,10,11,12,13,14,15,16,17}
        local count = 0
        for _, slot in ipairs(slots) do
            AP.Try(function()
                local item = player:GetEquippedItemBySlot(slot)
                if item then
                    AP.CaptureSnapshot(player, item)
                    AP.SaveItemAttune(guid, item:GetEntry(), AP.Config.CapPerItem, true)
                    count = count + 1
                end
            end, "GM snapshot slot " .. slot)
        end
        Reply("Snapshot taken for " .. count .. " items.")
        return true
    end

    -- Wipe attune bars (this character only â€” explicit GM action)
    if msg == "#apgm wipeattune" then
        local guid = player:GetGUIDLow()
        AP.Try(function()
            CharDBQuery(string.format(
                "DELETE FROM `ap_item_attune` WHERE `guid` = %d;", guid))
            CharDBQuery(string.format(
                "DELETE FROM `ap_item_snapshot` WHERE `guid` = %d;", guid))
        end, "GM wipeattune")
        Reply("Attunement bars and snapshots wiped for this character.")
        return true
    end

    -- Toggle debug
    if msg == "#apgm toggledebug" then
        AP.Config.Debug = not AP.Config.Debug
        Reply("Debug logging: " .. (AP.Config.Debug and "ON" or "OFF"))
        return true
    end

    -- Toggle anti-cheese bypass
    if msg == "#apgm togglecheese" then
        AP._gmCheeseBypassed = not AP._gmCheeseBypassed
        Reply("Anti-cheese: " .. (AP._gmCheeseBypassed and "BYPASSED" or "ACTIVE"))
        return true
    end

    -- Set threat
    local threatVal = msg:match("^#apgm%s+threat%s+(%d+)$")
    if threatVal then
        local t = tonumber(threatVal)
        if t and t >= 0 and t <= AP.Config.ThreatMax then
            local guid    = player:GetGUIDLow()
            local session = AP._session and AP._session[guid]
            if session then
                session.threat = t
                session.momentum = 0.0
                session.momentumKills = 0
                if AP.SaveThreatToDB then AP.SaveThreatToDB(guid, session) end
                Reply(string.format("Threat set to %s (%d). Momentum reset.", AP.GetThreatName(t), t))
            else
                Reply("No active session for this character.")
            end
        else
            Reply(string.format("Usage: #apgm threat <0-%d>", AP.Config.ThreatMax))
        end
        return true
    end

    -- Info
    if msg == "#apgm info" then
        local guid      = player:GetGUIDLow()
        local rec       = AP.LoadMastery(guid)
        local aether    = rec and rec.aether  or 0
        local mastery   = rec and rec.mastery or 0
        local level     = player:GetLevel()
        local absorbPct = AP.MasteryAbsorbPct(mastery) * AP.LevelAbsorbScalar(level)
        local session   = (AP._session and AP._session[guid]) or { threat = 0 }
        Reply(string.format(
            "GUID=%d Lvl=%d Aether=%d Mastery=%d Absorb=%.1f%% Threat=%d Debug=%s Cheese=%s",
            guid, level, aether, mastery, absorbPct * 100,
            session.threat or 0,
            tostring(AP.Config.Debug),
            AP._gmCheeseBypassed and "BYPASSED" or "ACTIVE"))
        return true
    end

    Reply("Commands: aether, setmastery, snapshot, wipeattune, toggledebug, togglecheese, threat, info")
    return true
end

-- ============================================================
-- EVENT HOOKS
-- Event 18: PLAYER_EVENT_ON_CHAT (SAY â€” all players incl. GM)
-- Event 19: PLAYER_EVENT_ON_WHISPER
-- Both delegate to HandleGMCommand which checks GM level.
-- ============================================================
local function TryGMCommand(player, msg)
    if not msg then return end
    local lower = msg:lower():match("^%s*(.-)%s*$")
    if lower:match("^#apgm") then
        local handled = AP.HandleGMCommand(player, lower)
        if handled then return false end
    end
end

RegisterPlayerEvent(18, function(event, player, msg, type, lang, channel)
    return TryGMCommand(player, msg)
end)

RegisterPlayerEvent(19, function(event, player, msg, lang, receiver)
    return TryGMCommand(player, msg)
end)

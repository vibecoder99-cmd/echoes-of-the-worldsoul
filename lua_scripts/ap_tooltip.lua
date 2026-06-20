-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- ap_tooltip.lua
-- Echoes of the Worldsoul — Tooltip Bridge (Server Side)
-- ============================================================
-- When the client AddOn hovers over an item it sends a hidden
-- chat message: "#ap tip <itemEntry>"
-- This file handles that message, fetches attunement data,
-- and sends back a single packed payload line in a format the
-- AddOn can parse.
--
-- Payload format (whispered back to the player):
--   [APTIP] id=<entry>|prog=<N>|cap=<N>|snap=<str>/<agi>/<sta>/<int>/<spi>|absorb=<str>/<agi>/<sta>/<int>/<spi>
--
-- The AddOn filters this whisper from appearing in chat,
-- parses the fields, caches by item entry, and injects lines
-- into the active tooltip.
--
-- Design rules:
--   - Payload is sent as a whisper from server to player.
--     (SendBroadcastMessage is visible in system chat; we use
--      a direct whisper-style message so the AddOn can filter it
--      without it appearing to other players.)
--   - The server sends the payload on every request.
--     The AddOn does its own caching.
--   - If an item has no attunement data, we send a "new" payload
--     with prog=0 so the AddOn can show "0%."
-- ============================================================

AP = AP or {}

-- ============================================================
-- PAYLOAD BUILDER
-- Returns the formatted payload string for a given item entry
-- and player GUID.
-- ============================================================
local function BuildTooltipPayload(guid, itemEntry, level, masteryRank)
    local rec     = AP.LoadItemAttune(guid, itemEntry)
    local prog    = rec and rec.progress or 0
    local attuned = rec and rec.attuned or false

    -- Compute the same level-scaled cap used by the attunement handler
    local cap = AP.GetScaledCap(itemEntry)

    -- If already attuned, force prog = cap so the client shows 100%.
    if attuned then
        prog = cap
    end
    local snap = AP.LoadSnapshot(guid, itemEntry)
    local snapStr = "0/0/0/0/0"
    if snap then
        snapStr = string.format("%.0f/%.0f/%.0f/%.0f/%.0f",
            snap.str, snap.agi, snap.sta, snap.int, snap.spi)
    end

    -- Absorbed stats (display only â€” SetStat not available)
    local absStr = "0/0/0/0/0"
    if snap then
        local masteryPct = AP.MasteryAbsorbPct(masteryRank)
        local levelScale = AP.LevelAbsorbScalar(level)
        local absorbPct  = masteryPct * levelScale
        absStr = string.format("%.1f/%.1f/%.1f/%.1f/%.1f",
            snap.str * absorbPct,
            snap.agi * absorbPct,
            snap.sta * absorbPct,
            snap.int * absorbPct,
            snap.spi * absorbPct)
    end

    return string.format("[APTIP] id=%d|prog=%d|cap=%d|snap=%s|absorb=%s",
        itemEntry, prog, cap, snapStr, absStr)
end

-- ============================================================
-- SEND TOOLTIP PAYLOAD
-- Public function called from ap_events.lua chat parser.
-- Sends the payload back to the requesting player.
-- ============================================================
function AP.SendTooltipPayload(player, itemEntry)
    if not player or not itemEntry or itemEntry <= 0 then return end

    AP.Try(function()
        local guid        = player:GetGUIDLow()
        local level       = player:GetLevel()
        local rec         = AP.LoadMastery(guid)
        local masteryRank = rec and rec.mastery or 0

        local payload = BuildTooltipPayload(guid, itemEntry, level, masteryRank)

        -- Send as a system broadcast visible only to this player.
        -- The client AddOn must filter/hide messages starting with "[APTIP]".
        -- We use SendBroadcastMessage since it is confirmed available.
        player:SendBroadcastMessage(payload)

        AP.Debug("Tooltip payload sent: " .. payload)
    end, "AP.SendTooltipPayload")
end

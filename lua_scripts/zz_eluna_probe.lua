-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- zz_eluna_probe.lua
-- Echoes of the Worldsoul — Eluna Capability Probe
-- ============================================================
-- RegisterServerEvent event IDs to try:
--   1  = SERVER_EVENT_ON_NETWORK_START
--   2  = SERVER_EVENT_ON_NETWORK_STOP  
--   3  = SERVER_EVENT_ON_CONFIG_LOAD (fires on startup AND reload)
--   4  = SERVER_EVENT_ON_SHUTDOWN_BEGIN
--   5  = SERVER_EVENT_ON_SHUTDOWN_COMPLETE
--   6  = SERVER_EVENT_ON_UPDATE  (fires every world update tick)
--   7  = SERVER_EVENT_ON_STARTUP (may fire AFTER scripts load)
--   14 = SERVER_EVENT_ON_GAME_EVENT_START
-- We try multiple event IDs to find which one works.
-- ============================================================

AP = AP or {}
AP.Cap = AP.Cap or {}
AP.CapInfo = AP.CapInfo or {}

-- Print immediately at script load time (no event required)
print("[Eluna] probe: zz_eluna_probe.lua loaded at script init time.")
print("[Eluna] probe: CharDBDirectExecute available: " .. tostring(type(_G["CharDBDirectExecute"]) == "function"))

-- Production probe records registration availability without synthetic delivery.
-- High-frequency ALE delivery tests are intentionally excluded from package load.
print("[Eluna] probe: server-event delivery probes: SKIPPED (production read-only probe)")

-- Also do the capability check immediately at load time
local function probeNow()
    print("[Eluna] probe: === Immediate capability check (load time) ===")

    local function probe(name)
        local fn = _G[name]
        local ok = (type(fn) == "function")
        print(string.format("[Eluna] probe: %s: %s", name, ok and "YES" or "NO"))
        AP.Cap[name] = ok
        AP.CapInfo[name] = ok and "global function available" or "global function unavailable"
        return ok, fn
    end

    probe("RegisterServerEvent")
    probe("RegisterPlayerEvent")
    probe("CharDBQuery")
    probe("CharDBQueryAsync")
    probe("CharDBExecute")
    probe("CharDBExecuteAsync")
    probe("CharDBDirectExecute")
    probe("WorldDBQuery")
    probe("WorldDBQueryAsync")
    probe("WorldDBExecute")
    probe("WorldDBExecuteAsync")
    probe("WorldDBDirectExecute")

    -- The legacy event-14 test inserted and deleted temporary ap_mastery rows.
    -- Inventory write-capable globals above, but never execute them here.
    print("[Eluna] probe: legacy database write test: SKIPPED (production read-only probe)")
    print("[Eluna] probe: === Load-time check complete ===")
end

-- Run immediately
probeNow()

-- Also wire player login for player-level checks
AP._probeRan = false
AP.RT.RegisterEvent("player", 3, function(event, player)
    if AP._probeRan then return end
    AP._probeRan = true
    print("[Eluna] probe: Player login hook fired.")

    local function pm(name)
        local ok = (type(player[name]) == "function")
        print("[Eluna] probe: Player:" .. name .. ": " .. (ok and "YES" or "NO"))
        return ok
    end

    local setStatOk = pm("SetStat")
    AP.Cap.SetStat = setStatOk
    AP.CapInfo.SetStat = setStatOk and "Player:SetStat available" or "Player:SetStat unavailable"
    if not setStatOk and AP.Config and AP.Config.DirectStatMode then
        AP.Config.DirectStatMode = false
        print("[AP] WARN: Player:SetStat not available. Forcing DirectStatMode OFF.")
    end

    pm("HasQuest")
    pm("GetQuestStatus")
    pm("IsQuestRewarded")
    pm("GetGroup")
    pm("GetMap")
    pm("GetEquippedItemBySlot")
    pm("SendBroadcastMessage")
    pm("GossipSendMenu")
    pm("GossipMenuAddItem")
    pm("GossipClearMenu")

    -- GetBagSize is NOT available on this Eluna build. Confirmed via direct
    -- probe across indices 0-4: every call returned ok=false. Do not use it.
    -- Use GetItemByPos across known-good coordinate ranges instead:
    --   backpack: bag=255, slots 23-38 (16 slots)
    --   equipped bags: bag=19-22, slots 0-35 (up to 36 slots each)
    -- Out-of-range/empty slots return nil safely; no size lookup needed.
    AP.Cap.GetBagSize = false
    AP.CapInfo.GetBagSize = "confirmed unsupported; use GetItemByPos"
    print("[Eluna] probe: Player:GetBagSize: NO (confirmed unsupported — use GetItemByPos)")

    print("[Eluna] probe: CharDBDirectExecute: " .. (AP.Cap.CharDBDirectExecute and "YES" or "NO"))
    print("[Eluna] probe: === Player probe complete. ===")
end)


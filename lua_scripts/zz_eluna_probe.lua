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

-- Print immediately at script load time (no event required)
print("[Eluna] probe: zz_eluna_probe.lua loaded at script init time.")
print("[Eluna] probe: CharDBDirectExecute available: " .. tostring(type(_G["CharDBDirectExecute"]) == "function"))

-- Try registering on every plausible server event
for _, evId in ipairs({1, 2, 3, 6, 7, 11, 14, 15, 16}) do
    pcall(function()
        RegisterServerEvent(evId, function()
            -- Only print once per event ID
            print("[Eluna] probe: ServerEvent " .. evId .. " fired!")
        end)
    end)
end

-- Also do the capability check immediately at load time
local function probeNow()
    print("[Eluna] probe: === Immediate capability check (load time) ===")

    local function probe(name)
        local fn = _G[name]
        local ok = (type(fn) == "function")
        print(string.format("[Eluna] probe: %s: %s", name, ok and "YES" or "NO"))
        AP.Cap[name] = ok
        return ok, fn
    end

    probe("RegisterServerEvent")
    probe("RegisterPlayerEvent")
    probe("CharDBQuery")
    probe("CharDBExecute")
    local dxOk, dxFn = probe("CharDBDirectExecute")

    if dxOk then
        -- Defer the write test until after world initialization completes.
        pcall(function()
            RegisterServerEvent(14, function()
                -- Test 1: CharDBDirectExecute (async on this build, expect FAIL)
                local ok1, err1 = pcall(function()
                    dxFn("INSERT IGNORE INTO `ap_mastery` (`guid`,`aether`,`mastery`) VALUES (7777777,1,0);")
                end)
                if ok1 then
                    local q1 = _G["CharDBQuery"] and _G["CharDBQuery"](
                        "SELECT `aether` FROM `ap_mastery` WHERE `guid` = 7777777 LIMIT 1;")
                    local val1 = q1 and (tonumber(tostring(q1:GetUInt64(0))) or 0) or 0
                    print("[Eluna] probe: CharDBDirectExecute write test (post-init): " ..
                        (val1 == 1 and "PASS (synchronous)" or "FAIL (got " .. val1 .. " â€” async)"))
                    dxFn("DELETE FROM `ap_mastery` WHERE `guid` = 7777777;")
                else
                    print("[Eluna] probe: CharDBDirectExecute post-init ERROR: " .. tostring(err1))
                end

                -- Test 2: CharDBQuery INSERT (sync connection â€” expect PASS if perms correct)
                local q2fn = _G["CharDBQuery"]
                if q2fn then
                    q2fn("DELETE FROM `ap_mastery` WHERE `guid` = 6666666;")
                    q2fn("INSERT IGNORE INTO `ap_mastery` (`guid`,`aether`,`mastery`) VALUES (6666666,42,0);")
                    local q2 = q2fn("SELECT `aether` FROM `ap_mastery` WHERE `guid` = 6666666 LIMIT 1;")
                    local val2 = q2 and (tonumber(tostring(q2:GetUInt64(0))) or 0) or 0
                    print("[Eluna] probe: CharDBQuery INSERT write test (post-init): " ..
                        (val2 == 42 and "PASS (writes visible)" or "FAIL (got " .. val2 .. ")"))
                    q2fn("DELETE FROM `ap_mastery` WHERE `guid` = 6666666;")
                end
            end)
        end)
        print("[Eluna] probe: CharDBDirectExecute + CharDBQuery write tests scheduled for event 14.")
    end

    print("[Eluna] probe: === Load-time check complete ===")
end

-- Run immediately
probeNow()

-- Also wire player login for player-level checks
AP._probeRan = false
RegisterPlayerEvent(3, function(event, player)
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
    print("[Eluna] probe: Player:GetBagSize: NO (confirmed unsupported — use GetItemByPos)")

    print("[Eluna] probe: CharDBDirectExecute: " .. (AP.Cap.CharDBDirectExecute and "YES" or "NO"))
    print("[Eluna] probe: === Player probe complete. ===")
end)


-- Copyright (C) 2025-2026 vibecoder99
-- Licensed under the GNU General Public License v3. See LICENSE.
-- ============================================================
-- ap03_runtime_probe.lua
-- Echoes of the Worldsoul — Capability Probe Framework
--
-- Declares AP.Cap default booleans (all false) and AP.CapInfo
-- reason strings. Provides AP.Cap.Check(name) as a
-- backwards-compatible accessor.
--
-- IMPORTANT: AP.Cap fields remain plain booleans. This is safe
-- because zz_eluna_probe.lua uses AP.Cap = AP.Cap or {} (which
-- preserves this table) and only sets individual fields via
-- AP.Cap[name] = true/false — it never replaces the table.
--
-- AP.Cap.Check() is a new field on the AP.Cap table. It is never
-- overwritten by zz_eluna_probe.lua because that file only sets
-- named capability keys, not "Check".
--
-- Compatibility rule:
--   Old code:  if AP.Cap.GetMap then ...            ← reads boolean; still correct
--   New code:  if AP.Cap.Check("GetMap") then ...   ← reads same boolean; also correct
--   NEVER:     AP.Cap.GetMap = { ok=false }         ← would invert old checks (prohibited)
--
-- zz_eluna_probe.lua sets these booleans at runtime:
--   Load-time: RegisterServerEvent, RegisterPlayerEvent, CharDBQuery,
--              CharDBExecute, CharDBDirectExecute
--   Login-time: SetStat (confirmed blocked), GetBagSize (hardcoded false)
--   NOT stored: GetMap, GetGroup, GetEquippedItemBySlot, SendBroadcastMessage,
--               all Gossip functions, HasQuest, GetQuestStatus — these remain
--               false until AP.Probe.RunLogin is wired in Phase C.
--
-- AP.Probe.RunLogin(player): defined here; wired in Phase C.
-- ============================================================

AP         = AP         or {}
AP.Cap     = AP.Cap     or {}
AP.CapInfo = AP.CapInfo or {}
AP.Probe   = AP.Probe   or {}

-- ── BACKWARD-COMPATIBLE BOOLEAN ACCESSOR ─────────────────────
-- Reads the boolean value at AP.Cap[name].
-- Returns false for any name not yet set or set to false.
-- Returns false if name happens to map to a non-boolean (safety net).
AP.Cap.Check = function(name)
    local v = AP.Cap[name]
    return type(v) == "boolean" and v == true
end

-- ── DEFAULT DECLARATIONS ─────────────────────────────────────
-- Sets a cap to false and CapInfo to a reason string only if
-- neither has been set yet. This ensures zz_eluna_probe.lua
-- values (set later at load-time) are not overwritten here if
-- scripts are reloaded out of order.

local function decl(name, reason)
    if AP.Cap[name] == nil then
        AP.Cap[name] = false
    end
    if AP.CapInfo[name] == nil then
        AP.CapInfo[name] = reason
    end
end

-- Load-time caps (zz_eluna_probe.lua probeNow() sets these to true/false)
decl("RegisterServerEvent",   "not yet probed — zz_eluna_probe.lua runs at load-time end")
decl("RegisterPlayerEvent",   "not yet probed — zz_eluna_probe.lua runs at load-time end")
decl("CharDBQuery",           "not yet probed — zz_eluna_probe.lua runs at load-time end")
decl("CharDBExecute",         "not yet probed — zz_eluna_probe.lua runs at load-time end")
decl("CharDBDirectExecute",   "not yet probed — zz_eluna_probe.lua runs at load-time end")

-- Login-time caps (set by AP.Probe.RunLogin on first player login)
decl("GetMap",                "not probed — AP.Probe.RunLogin not yet wired (Phase C)")
decl("GetGroup",              "not probed — AP.Probe.RunLogin not yet wired (Phase C)")
decl("GetEquippedItemBySlot", "not probed — AP.Probe.RunLogin not yet wired (Phase C)")
decl("HasQuest",              "not probed — AP.Probe.RunLogin not yet wired (Phase C)")
decl("GetQuestStatus",        "not probed — AP.Probe.RunLogin not yet wired (Phase C)")
decl("SendBroadcastMessage",  "not probed — AP.Probe.RunLogin not yet wired (Phase C)")
decl("GossipClearMenu",       "not probed — AP.Probe.RunLogin not yet wired (Phase C)")
decl("GossipMenuAddItem",     "not probed — AP.Probe.RunLogin not yet wired (Phase C)")
decl("GossipSendMenu",        "not probed — AP.Probe.RunLogin not yet wired (Phase C)")

-- Permanently blocked in this Eluna build (confirmed by historical probes).
-- zz_eluna_probe.lua also sets SetStat and GetBagSize at login time,
-- which will agree with these values.
decl("SetStat",
    "blocked — Player:SetStat not available in this Eluna build; " ..
    "C++ module (mod_attunement_plus) handles stat application instead")
decl("IsQuestRewarded",
    "blocked — Player:IsQuestRewarded not available; use HasQuest/GetQuestStatus workaround")
decl("GetBagSize",
    "confirmed unsupported in this build — use GetItemByPos across known slot ranges instead")

-- ── LOGIN-TIME PROBE ─────────────────────────────────────────
-- Wired to RegisterPlayerEvent(3) in Phase C (ap_events.lua migration).
-- In Phase A this function exists but is not called automatically.
--
-- Uses AP.Probe._ran (distinct from AP._probeRan used by zz_eluna_probe.lua)
-- to ensure this probe only fires once per server session.
--
-- Design note on GossipMenuAddItem / GossipSendMenu:
--   Calling GossipSendMenu during a login probe would open a stray menu.
--   We instead infer those caps from GossipClearMenu (if clear works, the
--   other gossip calls almost certainly work on the same Eluna build).

function AP.Probe.RunLogin(player)
    if not player then return end
    if AP.Probe._ran then return end
    AP.Probe._ran = true

    local function tryCall(name, fn)
        local ok, err = pcall(fn)
        AP.Cap[name]     = ok
        AP.CapInfo[name] = ok
            and "confirmed callable on first login"
            or  ("probe errored on first login: " .. tostring(err))
    end

    tryCall("GetMap",                function() player:GetMap() end)
    tryCall("GetGroup",              function() player:GetGroup() end)
    tryCall("GetEquippedItemBySlot", function() player:GetEquippedItemBySlot(0) end)
    tryCall("HasQuest",              function() player:HasQuest(1) end)
    tryCall("GetQuestStatus",        function() player:GetQuestStatus(1) end)
    tryCall("SendBroadcastMessage",  function() player:SendBroadcastMessage("") end)
    tryCall("GossipClearMenu",       function() player:GossipClearMenu() end)

    -- Infer GossipMenuAddItem and GossipSendMenu from GossipClearMenu
    -- to avoid opening a stray gossip menu mid-login.
    local gcOk = AP.Cap.Check("GossipClearMenu")
    AP.Cap.GossipMenuAddItem     = gcOk
    AP.Cap.GossipSendMenu        = gcOk
    AP.CapInfo.GossipMenuAddItem = gcOk
        and "inferred from GossipClearMenu (same Eluna gossip surface)"
        or  "inferred from GossipClearMenu failure"
    AP.CapInfo.GossipSendMenu    = AP.CapInfo.GossipMenuAddItem

    print("[Echoes] AP.Probe.RunLogin complete")
end

-- ── PROBE REPORT (for #ap doctor) ────────────────────────────
function AP.Probe.Report()
    local lines = {}
    for name, v in pairs(AP.Cap) do
        if name ~= "Check" and type(v) == "boolean" then
            local status = v and "OK" or "BLOCKED/UNPROBED"
            local reason = (AP.CapInfo and AP.CapInfo[name]) or ""
            table.insert(lines, string.format("  %-28s %s — %s", name, status, reason))
        end
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end

print("[Echoes] ap03_runtime_probe loaded (AP.Cap defaults set | AP.Cap.Check available)")

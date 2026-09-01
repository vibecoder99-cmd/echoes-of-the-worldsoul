-- Copyright (C) 2025-2026 vibecoder99
-- Licensed under the GNU General Public License v3. See LICENSE.
-- ============================================================
-- ap06_doctor.lua
-- Echoes of the Worldsoul — System Doctor
--
-- AP.Doctor.AddWarning(label, msg) is available immediately and
-- used by ap04_db.lua (ExecuteCritical) and ap02_runtime_eluna.lua
-- (IsGM fallback).
--
-- AP.Doctor.Report(player) outputs the full diagnostic report.
-- Phase D wires it to the "#ap doctor" chat command in ap_events.lua.
--
-- Access gate: AP.Doctor.Report calls AP.RT.IsGM(player, 3).
-- It never calls player:GetGMLevel() directly.
-- ============================================================

AP        = AP        or {}
AP.Doctor = AP.Doctor or {}

-- ── WARNING ACCUMULATOR ──────────────────────────────────────
-- Populated by AP.DB.ExecuteCritical, AP.RT.IsGM, and any other
-- module that detects a degraded condition. Reported in #ap doctor.

AP.Doctor._warnings = AP.Doctor._warnings or {}

function AP.Doctor.AddWarning(label, msg)
    if not label or not msg then return end
    table.insert(AP.Doctor._warnings, {
        label = tostring(label),
        msg   = tostring(msg),
    })
end

-- ── REPORT ───────────────────────────────────────────────────

local function rpad(s, width)
    s = tostring(s or "")
    while #s < width do s = s .. " " end
    return s
end

local function rline(label, status, note)
    return string.format("  %s %s %s", rpad(label, 28), rpad(status, 12), note or "")
end

-- Tables required by current production code.
local REQUIRED_TABLES = {
    "ap_mastery",
    "ap_item_attune",
    "ap_item_snapshot",
    "ap_session_state",
    "ap_slot_mastery",
    "ap_talents",
    "ap_quest_rewarded",
    "ap_aether_milestones",
    "ap_aether_sinks",
    "ap_resonant_drops",
    "ap_rack",
}
local function tableRowCount(tblName)
    if not AP.DB or not AP.DB.Query then return -1 end

    -- Missing-table queries are fatal on some native cores, so verify
    -- existence through metadata before querying the table itself.
    local exists = AP.DB.Query(
        "SELECT COUNT(*) FROM information_schema.tables " ..
        "WHERE table_schema = DATABASE() AND table_name = '" .. tblName .. "';")
    if not exists then return -1 end
    local existsOk, existsCount = pcall(function() return exists:GetUInt32(0) end)
    if not existsOk or type(existsCount) ~= "number" or existsCount == 0 then
        return -1
    end

    local q = AP.DB.Query(
        "SELECT COUNT(*) FROM `" .. tblName .. "` LIMIT 1;")
    if not q then return -1 end
    local ok, n = pcall(function() return q:GetUInt32(0) end)
    return (ok and type(n) == "number" and n) or -1
end

local function columnExists(tblName, colName)
    if not AP.DB or not AP.DB.Query then return false end
    local q = AP.DB.Query(
        "SELECT COUNT(*) FROM information_schema.columns " ..
        "WHERE table_schema = DATABASE() " ..
        "AND table_name = '" .. tblName .. "' " ..
        "AND column_name = '" .. colName .. "';")
    if not q then return false end
    local ok, n = pcall(function() return q:GetUInt32(0) end)
    return ok and type(n) == "number" and n > 0
end
function AP.Doctor.Report(player)
    -- Access gate: GM level 3 required.
    -- Uses AP.RT.IsGM — never player:GetGMLevel() directly.
    if not AP.RT.IsGM(player, 3) then
        if player then
            AP.RT.SendMessage(
                player,
                "[Echoes] #ap doctor requires GM level 3.")
        end
        return
    end

    local out     = {}
    local errors  = 0
    local blocked = 0

    local function emit(s) table.insert(out, s) end
    local function section(name)
        emit("")
        emit("[ " .. name .. " ]")
    end

    -- capLine: reports one AP.Cap entry.
    -- expectedBlock=true means the cap is known/permanently blocked —
    --   counted as "blocked (expected)", not as an error.
    local function capLine(name, expectedBlock)
        local ok   = AP.Cap and AP.Cap.Check(name) or false
        local info = (AP.CapInfo and AP.CapInfo[name]) or ""
        if expectedBlock then
            blocked = blocked + 1
            emit(rline(name, "BLOCKED", "(expected) — " .. info))
        else
            if not ok then errors = errors + 1 end
            emit(rline(name, ok and "OK" or "ERROR", info))
        end
    end

    -- ── HEADER ───────────────────────────────────────────────
    emit("============================================================")
    emit(string.format(" Echoes of the Worldsoul — System Doctor v%s",
        AP.VERSION or "?"))
    emit(string.format(" Profile: %s  |  startup event: %s",
        (AP.Profile and AP.Profile.name) or "unknown",
        tostring(AP.Profile and AP.Profile.startupEventId or "unresolved")))
    emit("============================================================")

    -- ── RUNTIME ──────────────────────────────────────────────
    section("RUNTIME")
    capLine("RegisterServerEvent")
    capLine("RegisterPlayerEvent")
    capLine("CharDBQuery")
    capLine("CharDBExecute")
    capLine("CharDBDirectExecute")

    -- ── PLAYER API ───────────────────────────────────────────
    section("PLAYER API")
    capLine("GetMap")
    capLine("GetGroup")
    capLine("GetEquippedItemBySlot")
    capLine("HasQuest")
    capLine("GetQuestStatus")
    capLine("SendBroadcastMessage")
    capLine("SetStat",         true)   -- permanently blocked; expected
    capLine("IsQuestRewarded", true)   -- permanently blocked; expected
    capLine("GetBagSize",      true)   -- permanently blocked; expected

    -- ── UI ───────────────────────────────────────────────────
    section("UI")
    capLine("GossipClearMenu")
    capLine("GossipMenuAddItem")
    capLine("GossipSendMenu")

    -- ── TABLES ───────────────────────────────────────────────
    section("TABLES")
    local function tableLine(tbl)
        local count = tableRowCount(tbl)
        local ok    = count >= 0
        if not ok then errors = errors + 1 end
        emit(rline(
            tbl,
            ok and "OK" or "ERROR",
            ok and ("(" .. count .. " rows)")
               or  "MISSING — required by current production code"))
    end

    for _, tbl in ipairs(REQUIRED_TABLES) do
        tableLine(tbl)
    end

    local conditionalTables = {
        { "ap_visage",
          AP.Visage ~= nil or
              (AP.Modules and AP.Modules.CosmeticAscension and
               AP.Modules.CosmeticAscension.Enabled == true),
          "CosmeticAscension/Visage subsystem not loaded" },
        { "ap_aura_test_results", AP.AuraLab ~= nil,
          "Aura Lab subsystem not loaded" },
        { "ap_dissolved_items", AP.Forge ~= nil,
          "Forge subsystem not loaded" },
        { "ap_residue", AP.Forge ~= nil,
          "Forge subsystem not loaded" },
        { "ap_sink_allocation",
          AP.Sinks ~= nil and AP.Sinks.LoadAllocForChar ~= nil,
          "sink-allocation subsystem not loaded" },
    }
    for _, spec in ipairs(conditionalTables) do
        if spec[2] then
            tableLine(spec[1])
        else
            emit(rline(spec[1], "DISABLED", spec[3]))
        end
    end

    local threatColumns = {
        "threat_level",
        "threat_momentum",
        "threat_debt_kills",
        "threat_debt_mult",
    }
    for _, col in ipairs(threatColumns) do
        local ok = columnExists("ap_session_state", col)
        if not ok then errors = errors + 1 end
        emit(rline("ap_session_state." .. col,
            ok and "OK" or "ERROR",
            ok and "required threat state column"
               or "MISSING — required by current threat persistence"))
    end

    section("SCHEMA ARCHITECTURE")
    emit(rline("ap_aether_ledger", "LEGACY",
        "no current production consumer"))
    emit(rline("ap_world_threat", "SUPERSEDED",
        "ap_session_state threat columns"))
    emit(rline("ap_relic_drops", "RENAMED",
        "ap_resonant_drops"))
    emit(rline("ap_visage_library", "SUPERSEDED",
        "ap_visage + static Lua definitions"))
    emit(rline("ap_slot_talents", "SUPERSEDED",
        "ap_slot_mastery + ap_talents"))

    section("C++ MODULE")
    emit(rline("mod_attunement_plus", "UNVERIFIED",
        "no Lua-visible runtime marker; verify startup/module activity in Server.log"))
    emit(rline("DirectStatMode", "DISABLED",
        "(expected) — Player:SetStat blocked; C++ module applies stats directly"))

    -- MODULES
    section("MODULES")
    if AP.Modules then
        local mods = {}
        for k, v in pairs(AP.Modules) do
            table.insert(mods, { k, v })
        end
        table.sort(mods, function(a, b) return a[1] < b[1] end)
        for _, m in ipairs(mods) do
            emit(string.format("  %-28s %s", m[1], m[2] and "ENABLED" or "disabled"))
        end
    else
        emit("  (AP.Modules not loaded — ap_core.lua may not have initialized yet)")
    end

    -- ── PROFILE ──────────────────────────────────────────────
    section("PROFILE")
    emit(string.format("  %-28s %s",
        "Active profile", (AP.Profile and AP.Profile.name) or "unknown"))
    emit(string.format("  %-28s %s",
        "ALE lifecycle signal", (AP.Profile and AP.Profile.ale) and "CONFIRMED" or "UNRESOLVED"))
    emit(string.format("  %-28s %s",
        "Startup event ID", tostring(AP.Profile and AP.Profile.startupEventId or "unresolved")))

    -- ── WARNINGS (from AP.Doctor.AddWarning calls) ───────────
    if #AP.Doctor._warnings > 0 then
        section("WARNINGS")
        for i, w in ipairs(AP.Doctor._warnings) do
            emit(string.format("  [%d] %s: %s", i, w.label, w.msg))
        end
    end

    -- ── RESULT ───────────────────────────────────────────────
    emit("")
    emit("============================================================")
    emit(string.format(
        " RESULT: %d error(s) | %d blocked (expected) | %d warning(s)",
        errors, blocked, #AP.Doctor._warnings))
    emit("============================================================")

    -- Output one SendBroadcastMessage per line.
    -- AP.RT.SendMessage checks AP.Cap.Check("SendBroadcastMessage") internally.
    for _, s in ipairs(out) do
        AP.RT.SendMessage(player, s)
    end
end

print("[Echoes] ap06_doctor loaded (AP.Doctor.AddWarning/Report available)")

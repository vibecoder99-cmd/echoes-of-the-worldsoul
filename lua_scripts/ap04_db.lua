-- Copyright (C) 2025-2026 vibecoder99
-- Licensed under the GNU General Public License v3. See LICENSE.
-- ============================================================
-- ap04_db.lua
-- Echoes of the Worldsoul — Database Abstraction Layer
--
-- ALL database I/O goes through AP.DB.* after migration.
-- Never call CharDBQuery / CharDBExecute / WorldDBQuery directly
-- outside this file once a file has been migrated.
--
-- Three write functions — choose deliberately:
--
--   AP.DB.ExecuteAsync(sql)           Always async (CharDBExecute).
--                                     Use for: logging, session state,
--                                     stat ticks, non-critical updates.
--
--   AP.DB.Execute(sql)                Prefers sync (CharDBDirectExecute).
--                                     Falls back to async silently.
--                                     Use for: standard writes where sync
--                                     is preferred but not critical.
--
--   AP.DB.ExecuteCritical(sql, label) Sync required for correctness.
--                                     NEVER falls back to async. If
--                                     CharDBDirectExecute is unavailable,
--                                     returns false, records a doctor
--                                     warning, and does not execute —
--                                     callers must not assume success.
--                                     Use for: attunement snapshot,
--                                     absorption calc, ledger entries.
--
-- BIGINT rule: NEVER call q:GetUInt64(col) directly. Always use
--   AP.DB.GetUInt64(q, col). The raw call returns Lua userdata.
-- ============================================================

AP    = AP    or {}
AP.DB = AP.DB or {}

-- Runtime schema readiness. E2e3 never installs or repairs schema.
AP.DB.SchemaReady = false
AP.DB.SchemaReason = "schema validation has not run"
AP.DB._schemaWarningShown = false

local REQUIRED_TABLES = {
    "ap_mastery", "ap_item_attune", "ap_item_snapshot", "ap_session_state",
    "ap_slot_mastery", "ap_talents", "ap_quest_rewarded",
    "ap_aether_milestones", "ap_aether_sinks", "ap_resonant_drops",
    "ap_rack", "ap_visage", "ap_dissolved_items", "ap_residue",
    "ap_sink_allocation", "ap_mastery_spend", "ap_aura_test_results",
    "ap_dissolution_pending",
}

local REQUIRED_COLUMNS = {
    { "ap_mastery", "guid" }, { "ap_mastery", "aether" },
    { "ap_mastery", "mastery" }, { "ap_mastery", "rate_xp" },
    { "ap_mastery", "rate_aether" }, { "ap_mastery", "rate_boss" },
    { "ap_mastery", "rack_slots" },
    { "ap_item_attune", "guid" }, { "ap_item_attune", "item_entry" },
    { "ap_item_attune", "progress" }, { "ap_item_attune", "attuned" },
    { "ap_item_snapshot", "guid" }, { "ap_item_snapshot", "item_entry" },
    { "ap_item_snapshot", "quality" }, { "ap_item_snapshot", "str" },
    { "ap_item_snapshot", "agi" }, { "ap_item_snapshot", "sta" },
    { "ap_item_snapshot", "int" }, { "ap_item_snapshot", "spi" },
    { "ap_item_snapshot", "armor" }, { "ap_item_snapshot", "weapon_dps" },
    { "ap_session_state", "guid" }, { "ap_session_state", "clean_exit" },
    { "ap_session_state", "last_update" }, { "ap_session_state", "threat_level" },
    { "ap_session_state", "threat_momentum" },
    { "ap_session_state", "threat_debt_kills" },
    { "ap_session_state", "threat_debt_mult" },
    { "ap_slot_mastery", "guid" }, { "ap_slot_mastery", "slot" },
    { "ap_slot_mastery", "xp" },
    { "ap_talents", "guid" }, { "ap_talents", "stat_index" },
    { "ap_talents", "rank" },
    { "ap_quest_rewarded", "guid" }, { "ap_quest_rewarded", "quest_id" },
    { "ap_aether_milestones", "account_id" },
    { "ap_aether_milestones", "milestone_type" },
    { "ap_aether_milestones", "milestone_id" },
    { "ap_aether_sinks", "account_id" }, { "ap_aether_sinks", "category" },
    { "ap_aether_sinks", "invested" },
    { "ap_resonant_drops", "account_id" },
    { "ap_resonant_drops", "item_entry" }, { "ap_resonant_drops", "drop_count" },
    { "ap_rack", "guid" }, { "ap_rack", "slot_index" },
    { "ap_rack", "item_entry" }, { "ap_rack", "item_name" },
    { "ap_rack", "item_quality" },
    { "ap_visage", "guid" }, { "ap_visage", "primary_theme" },
    { "ap_visage", "primary_enabled" }, { "ap_visage", "secondary_theme" },
    { "ap_visage", "secondary_enabled" }, { "ap_visage", "flash_enabled" },
    { "ap_visage", "chat_flavor_enabled" },
    { "ap_visage", "primary_tier_selected" },
    { "ap_visage", "secondary_tier_selected" },
    { "ap_dissolved_items", "account_id" }, { "ap_dissolved_items", "item_entry" },
    { "ap_residue", "account_id" }, { "ap_residue", "amount" },
    { "ap_sink_allocation", "guid" }, { "ap_sink_allocation", "category" },
    { "ap_sink_allocation", "allocation" },
    { "ap_mastery_spend", "id" }, { "ap_mastery_spend", "guid" },
    { "ap_mastery_spend", "amount" }, { "ap_mastery_spend", "ts" },
    { "ap_aura_test_results", "guid" }, { "ap_aura_test_results", "spell_id" },
    { "ap_aura_test_results", "theme" }, { "ap_aura_test_results", "tier" },
    { "ap_aura_test_results", "result" }, { "ap_aura_test_results", "notes" },
    { "ap_aura_test_results", "tested_at" },
    { "ap_dissolution_pending", "guid" }, { "ap_dissolution_pending", "account_id" },
    { "ap_dissolution_pending", "item_entry" }, { "ap_dissolution_pending", "item_instance_guid" },
    { "ap_dissolution_pending", "quality" }, { "ap_dissolution_pending", "essence_reward" },
    { "ap_dissolution_pending", "gold_reward" }, { "ap_dissolution_pending", "residue_reward" },
    { "ap_dissolution_pending", "status" },
}

local function isMetadataSQL(sql)
    return type(sql) == "string" and string.find(string.lower(sql), "information_schema", 1, true) ~= nil
end

local function isEchoesSQL(sql)
    return type(sql) == "string" and string.find(string.lower(sql), "ap_", 1, true) ~= nil
end

local function warnSchemaOnce()
    if AP.DB._schemaWarningShown then return end
    AP.DB._schemaWarningShown = true
    print("[Echoes] WARN database schema is not ready; Echoes database operations are disabled until the separately installed schema passes validation.")
end

local function allowOperationalSQL(sql)
    if isMetadataSQL(sql) or not isEchoesSQL(sql) then return true end
    if AP.DB.SchemaReady then return true end
    warnSchemaOnce()
    return false
end

function AP.DB.IsReady()
    return AP.DB.SchemaReady == true
end

local function metadataCount(sql)
    if type(CharDBQuery) ~= "function" then return nil end
    local ok, q = pcall(CharDBQuery, sql)
    if not ok or not q then return nil end
    local okValue, value = pcall(function() return q:GetUInt32(0) end)
    if not okValue then return nil end
    return tonumber(value)
end

function AP.DB.ValidateSchema()
    AP.DB.SchemaReady = false
    AP.DB.SchemaReason = "schema metadata unavailable"
    local missing = {}
    for _, tableName in ipairs(REQUIRED_TABLES) do
        local count = metadataCount(string.format("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = '%s'", tableName))
        if count == nil then warnSchemaOnce(); return false
        elseif count ~= 1 then table.insert(missing, tableName) end
    end
    for _, required in ipairs(REQUIRED_COLUMNS) do
        local count = metadataCount(string.format("SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = '%s' AND column_name = '%s'", required[1], required[2]))
        if count == nil then warnSchemaOnce(); return false
        elseif count ~= 1 then table.insert(missing, required[1] .. "." .. required[2]) end
    end
    if #missing > 0 then
        AP.DB.SchemaReason = "missing required database objects: " .. table.concat(missing, ", ")
        warnSchemaOnce()
        return false
    end
    AP.DB.SchemaReady = true
    AP.DB.SchemaReason = "all required package tables and migrated columns are present"
    print("[Echoes] database schema readiness check passed")
    return true
end


-- ── READ ─────────────────────────────────────────────────────

function AP.DB.Query(sql)
    if not allowOperationalSQL(sql) then return nil end
    if not AP.Cap.Check("CharDBQuery") then return nil end
    local ok, result = pcall(CharDBQuery, sql)
    return (ok and result) or nil
end

function AP.DB.WorldQuery(sql)
    -- WorldDBQuery is always available when Eluna is loaded;
    -- no AP.Cap gate required (no probe tracks it separately).
    local ok, result = pcall(WorldDBQuery, sql)
    return (ok and result) or nil
end

-- ── WRITE: ASYNC ─────────────────────────────────────────────

-- Fire-and-forget. Always uses CharDBExecute.
-- Success cannot be confirmed. Do not use for critical data.
function AP.DB.ExecuteAsync(sql)
    if not allowOperationalSQL(sql) then return false end
    if not AP.Cap.Check("CharDBExecute") then return false end
    pcall(CharDBExecute, sql)
end

-- ── WRITE: STANDARD ──────────────────────────────────────────

-- Prefers CharDBDirectExecute (synchronous); degrades to async
-- silently without recording a warning.
-- Use when sync is preferred but data loss on crash is acceptable.
function AP.DB.Execute(sql)
    if not allowOperationalSQL(sql) then return false end
    if AP.Cap.Check("CharDBDirectExecute") then
        local ok = pcall(CharDBDirectExecute, sql)
        return ok
    end
    AP.DB.ExecuteAsync(sql)
    return true  -- async: success unconfirmable; caller assumes ok
end

-- ── WRITE: CRITICAL ──────────────────────────────────────────

-- Sync write required for data correctness. Requires a proven
-- synchronous direct-execute backend (CharDBDirectExecute). This
-- must NEVER silently degrade to async: a caller that depends on
-- read-after-write visibility (attunement grant, snapshot save,
-- session/visage/PvP/quest/forge persistence) would otherwise
-- read stale or cross-test-contaminated data, exactly as observed
-- under E2g1-R1 when this API was absent on stock ALE.
--
-- label: short identifier shown in the doctor warning,
--        e.g. "AP.SaveSnapshot", "AP.GrantAether"
function AP.DB.ExecuteCritical(sql, label)
    if not allowOperationalSQL(sql) then return false end
    if AP.Cap.Check("CharDBDirectExecute") then
        local ok = pcall(CharDBDirectExecute, sql)
        return ok
    end

    -- Synchronous backend unavailable: do NOT execute asynchronously
    -- and do NOT report success. A caller must treat this as a
    -- failed write and must not perform a dependent read assuming
    -- the write completed.
    if AP.Doctor and AP.Doctor.AddWarning then
        AP.Doctor.AddWarning(
            label or "AP.DB.ExecuteCritical",
            "CharDBDirectExecute unavailable on this Eluna/ALE build — critical write " ..
            "was NOT executed. (Previously this silently degraded to async CharDBExecute, " ..
            "which broke read-after-write consistency; that behavior has been removed.) " ..
            "Fix: use an Eluna/ALE build that exposes CharDBDirectExecute.")
    end
    return false
end

-- ── BIGINT FIX ───────────────────────────────────────────────
-- QueryResult:GetUInt64() returns Lua 5.1 userdata on this build.
-- Wrapping in tostring() converts userdata to its decimal string
-- representation; tonumber() parses that back to a Lua number.
-- This is the ONLY permitted location for q:GetUInt64 calls.

function AP.DB.GetUInt64(q, col)
    if not q then return 0 end
    local ok, v = pcall(function() return q:GetUInt64(col) end)
    if not ok or v == nil then return 0 end
    return tonumber(tostring(v)) or 0
end

-- ── ROW / SCHEMA HELPERS ─────────────────────────────────────
-- schema: array of { col=<0-based int>, name=<string>, type=<string> }
-- Supported types: "uint32", "uint64", "float", "string"

function AP.DB.Row(q, schema)
    if not q or not schema then return nil end
    local row = {}
    for _, field in ipairs(schema) do
        local t = field.type
        local c = field.col
        if t == "uint64" then
            row[field.name] = AP.DB.GetUInt64(q, c)
        elseif t == "uint32" then
            local ok, v = pcall(function() return q:GetUInt32(c) end)
            row[field.name] = (ok and v) or 0
        elseif t == "float" then
            local ok, v = pcall(function() return q:GetFloat(c) end)
            row[field.name] = (ok and v) or 0.0
        elseif t == "string" then
            local ok, v = pcall(function() return q:GetString(c) end)
            row[field.name] = (ok and v) or ""
        else
            row[field.name] = nil
        end
    end
    return row
end

-- Returns all rows as an array of row tables. Empty array on failure.
function AP.DB.FetchAll(sql, schema)
    local q = AP.DB.Query(sql)
    if not q then return {} end
    local rows = {}
    repeat
        table.insert(rows, AP.DB.Row(q, schema))
    until not q:NextRow()
    return rows
end

-- Returns the first row as a table, or nil on no result.
function AP.DB.FetchOne(sql, schema)
    local q = AP.DB.Query(sql)
    if not q then return nil end
    return AP.DB.Row(q, schema)
end

print("[Echoes] ap04_db loaded (AP.DB.* available)")

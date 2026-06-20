-- ============================================================
-- ap_api.lua -- Echoes of the Worldsoul: Public API & Extensions
-- Stable dependency surface for future modules.
-- ============================================================

AP = AP or {}
AP.API = AP.API or {}
AP.Extensions = AP.Extensions or {}
AP.Hooks = AP.Hooks or {}

-- ============================================================
-- VERSION & READINESS
-- ============================================================

function AP.API.GetVersion()
    return AP.VERSION or "0.0.0"
end

function AP.API.IsReady()
    return AP.Config ~= nil and AP.InitDB ~= nil
end

-- ============================================================
-- PLAYER DATA API
-- All functions accept a player object, return safe defaults.
-- ============================================================

function AP.API.GetPlayerSession(player)
    if not player then return nil end
    local ok, guid = pcall(function() return player:GetGUIDLow() end)
    if not ok or not guid then return nil end
    return AP._session and AP._session[guid] or nil
end

function AP.API.GetThreatLevel(player)
    local s = AP.API.GetPlayerSession(player)
    return s and s.threat or 0
end

function AP.API.GetThreatMomentum(player)
    local s = AP.API.GetPlayerSession(player)
    return s and s.momentum or 0.0
end

function AP.API.GetThreatMultiplier(player)
    local s = AP.API.GetPlayerSession(player)
    if not s then return 1.0 end
    return AP.GetThreatMult(s.threat or 0, s.momentum or 0)
end

function AP.API.GetThreatDebt(player)
    local s = AP.API.GetPlayerSession(player)
    if not s then return { kills = 0, mult = 1.0 } end
    return { kills = s.debtKills or 0, mult = s.debtMult or 1.0 }
end

function AP.API.GetTotalAttunedCount(player)
    if not player then return 0 end
    local ok, guid = pcall(function() return player:GetGUIDLow() end)
    if not ok or not guid then return 0 end
    if AP.Visage and AP.Visage.GetAttunedCount then
        return AP.Visage.GetAttunedCount(guid)
    end
    local q = CharDBQuery(string.format(
        "SELECT COUNT(*) FROM `ap_item_attune` WHERE `guid` = %d AND `attuned` = 1", guid))
    if q then return tonumber(tostring(q:GetUInt32(0))) or 0 end
    return 0
end

function AP.API.GetRackCount(player)
    if not player then return 0, 3 end
    local ok, guid = pcall(function() return player:GetGUIDLow() end)
    if not ok or not guid then return 0, 3 end
    local used = AP.Rack and AP.Rack.CountSlots(guid) or 0
    local cap  = AP.Rack and AP.Rack.GetCapacity(guid) or 3
    return used, cap
end

function AP.API.GetEssence(player)
    if not player then return 0 end
    local ok, guid = pcall(function() return player:GetGUIDLow() end)
    if not ok or not guid then return 0 end
    local rec = AP.LoadMastery(guid)
    return rec and rec.aether or 0
end

function AP.API.GetWorldsoulResidue(player)
    if not player then return 0 end
    local ok, accountId = pcall(function() return player:GetAccountId() end)
    if not ok or not accountId then return 0 end
    if AP.Forge and AP.Forge.GetResidue then
        return AP.Forge.GetResidue(accountId) or 0
    end
    return 0
end

function AP.API.GetMasteryRank(player)
    if not player then return 0 end
    local ok, guid = pcall(function() return player:GetGUIDLow() end)
    if not ok or not guid then return 0 end
    local rec = AP.LoadMastery(guid)
    return rec and rec.mastery or 0
end

function AP.API.GetBaseAbsorption(player)
    local rank = AP.API.GetMasteryRank(player)
    return AP.MasteryAbsorbPct(rank)
end

function AP.API.GetLevelScalar(player)
    if not player then return 0 end
    local ok, level = pcall(function() return player:GetLevel() end)
    if not ok or not level then return 0 end
    return AP.LevelAbsorbScalar(level)
end

function AP.API.GetEffectiveAbsorption(player)
    return AP.API.GetBaseAbsorption(player) * AP.API.GetLevelScalar(player)
end

function AP.API.GetVisageState(player)
    if not player then return {} end
    local ok, guid = pcall(function() return player:GetGUIDLow() end)
    if not ok or not guid then return {} end
    if AP.Visage then
        if not AP.Visage.Cache[guid] then AP.Visage.LoadForChar(guid) end
        local vc = AP.Visage.Cache[guid]
        if vc then
            return {
                primary_theme    = vc.primary_theme,
                primary_enabled  = vc.primary_enabled,
                primary_tier     = vc.primary_tier_selected,
                secondary_theme  = vc.secondary_theme,
                secondary_enabled = vc.secondary_enabled,
                secondary_tier   = vc.secondary_tier_selected,
            }
        end
    end
    return {}
end

function AP.API.GetProgressionSummary(player)
    return {
        version     = AP.API.GetVersion(),
        essence     = AP.API.GetEssence(player),
        residue     = AP.API.GetWorldsoulResidue(player),
        mastery     = AP.API.GetMasteryRank(player),
        base_absorb = AP.API.GetBaseAbsorption(player),
        level_scalar = AP.API.GetLevelScalar(player),
        effective_absorb = AP.API.GetEffectiveAbsorption(player),
        attuned     = AP.API.GetTotalAttunedCount(player),
        threat      = AP.API.GetThreatLevel(player),
        momentum    = AP.API.GetThreatMomentum(player),
        visage      = AP.API.GetVisageState(player),
    }
end

-- ============================================================
-- EXTENSION REGISTRY
-- ============================================================

function AP.API.RegisterExtension(id, data)
    if type(id) ~= "string" or id == "" then
        AP.Err("RegisterExtension: invalid id")
        return false
    end
    if type(data) ~= "table" then
        AP.Err("RegisterExtension: data must be a table")
        return false
    end
    AP.Extensions[id] = {
        name        = data.name or id,
        version     = data.version or "0.0.0",
        requires    = data.requires or {},
        description = data.description or "",
    }
    AP.Log("Extension registered: " .. id .. " v" .. (data.version or "0.0.0"))
    return true
end

function AP.API.GetExtensions()
    local list = {}
    for id, ext in pairs(AP.Extensions) do
        list[#list+1] = {
            id          = id,
            name        = ext.name,
            version     = ext.version,
            requires    = ext.requires,
            description = ext.description,
        }
    end
    return list
end

function AP.API.GetExtension(id)
    return AP.Extensions[id] or nil
end

-- ============================================================
-- HOOK SYSTEM
-- ============================================================

function AP.API.RegisterHook(hookName, extensionId, fn)
    if type(hookName) ~= "string" or hookName == "" then
        AP.Err("RegisterHook: invalid hookName")
        return false
    end
    if type(extensionId) ~= "string" or extensionId == "" then
        AP.Err("RegisterHook: invalid extensionId")
        return false
    end
    if type(fn) ~= "function" then
        AP.Err("RegisterHook: fn must be a function")
        return false
    end
    if not AP.Hooks[hookName] then
        AP.Hooks[hookName] = {}
    end
    AP.Hooks[hookName][extensionId] = fn
    AP.Debug("Hook registered: " .. hookName .. " by " .. extensionId)
    return true
end

function AP.API.DispatchHook(hookName, payload)
    local hooks = AP.Hooks[hookName]
    if not hooks then return end
    for extId, fn in pairs(hooks) do
        local ok, err = pcall(fn, payload)
        if not ok then
            AP.Debug(string.format("Hook error [%s/%s]: %s", hookName, extId, tostring(err)))
        end
    end
end

-- ============================================================
-- DEFINED HOOK POINTS
-- ============================================================
-- OnItemAttuned        { guid, itemEntry, progress }
-- OnAttunementProgress { guid, itemEntry, oldProgress, newProgress, cap }
-- OnThreatChanged      { guid, oldLevel, newLevel, momentum }
-- OnThreatDeathPenalty { guid, threat, essenceLost, attuneLost, debtKills }
-- OnEssenceChanged     { guid, oldAmount, newAmount, reason }
-- OnForgeDissolve      { guid, itemEntry, essenceReward, residueReward }
-- OnRackProgress       { guid, itemEntry, oldProgress, newProgress }
-- OnVisageChanged      { guid, field, oldValue, newValue }

print("[EotW] Public API & Extension system loaded. v" .. AP.API.GetVersion())

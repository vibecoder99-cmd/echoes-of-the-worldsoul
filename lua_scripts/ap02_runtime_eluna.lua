-- Copyright (C) 2025-2026 vibecoder99
-- Licensed under the GNU General Public License v3. See LICENSE.
-- ============================================================
-- ap02_runtime_eluna.lua
-- Echoes of the Worldsoul â€” Eluna Runtime Implementations
--
-- Overwrites every AP.RT stub (from ap01_runtime.lua) with a
-- real Eluna API call. Each implementation is wrapped in pcall
-- so a blocked or missing API returns nil/false rather than
-- crashing the caller.
--
-- AP.Cap.Check guards are present where the capability probe
-- has confirmed an API may be unavailable on some builds.
-- ============================================================

AP    = AP    or {}
AP.RT = AP.RT or {}

-- Mutating Eluna methods are commonly void, but some builds/mocks return a
-- Boolean. Preserve void-success compatibility while propagating an explicit
-- false and any thrown error as operation failure.
local function operationSucceeded(fn)
    local ok, result = pcall(fn)
    if not ok or result == false then return false end
    return true
end

-- â”€â”€ PLAYER IDENTITY â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

AP.RT.GetGUID = function(player)
    if not player then return nil end
    local ok, v = pcall(function() return player:GetGUIDLow() end)
    return (ok and v) or nil
end

AP.RT.GetAccountId = function(player)
    if not player then return nil end
    -- Prefer the direct API to avoid an extra DB round-trip.
    local ok, v = pcall(function() return player:GetAccountId() end)
    if ok and type(v) == "number" and v > 0 then return v end
    -- Fallback: cache lookup (AP.GetAccountId defined in ap_core.lua).
    local guid = AP.RT.GetGUID(player)
    if guid and AP.GetAccountId then
        return AP.GetAccountId(guid)
    end
    return nil
end

AP.RT.GetLevel = function(player)
    if not player then return 0 end
    local ok, v = pcall(function() return player:GetLevel() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.GetName = function(player)
    if not player then return "" end
    local ok, v = pcall(function() return player:GetName() end)
    return (ok and type(v) == "string" and v) or ""
end

AP.RT.GetClass = function(player)
    if not player then return 0 end
    local ok, v = pcall(function() return player:GetClass() end)
    return (ok and type(v) == "number" and v) or 0
end

-- â”€â”€ PLAYER WORLD STATE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

AP.RT.GetMap = function(player)
    if not player then return nil end
    if AP.Cap and not AP.Cap.Check("GetMap") then return nil end
    local ok, v = pcall(function() return player:GetMap() end)
    return (ok and v) or nil
end

AP.RT.GetMapId = function(player)
    if not player then return 0 end
    local ok, v = pcall(function() return player:GetMapId() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.GetZoneId = function(player)
    if not player then return 0 end
    local ok, v = pcall(function() return player:GetZoneId() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.GetGroup = function(player)
    if not player then return nil end
    if AP.Cap and not AP.Cap.Check("GetGroup") then return nil end
    local ok, v = pcall(function() return player:GetGroup() end)
    return (ok and v) or nil
end

AP.RT.IsInWorld = function(player)
    if not player then return false end
    local ok, v = pcall(function() return player:IsInWorld() end)
    return ok and v == true
end

AP.RT.GetGroupMembersCount = function(group)
    if not group then return 0 end
    local ok, v = pcall(function() return group:GetMembersCount() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.IsMapInstance = function(map)
    if not map then return nil end
    local ok, v = pcall(function() return map:IsInstance() end)
    if ok and type(v) == "boolean" then return v end
    return nil
end

AP.RT.IsMapRaid = function(map)
    if not map then return nil end
    local ok, v = pcall(function() return map:IsRaid() end)
    if ok and type(v) == "boolean" then return v end
    return nil
end

-- â”€â”€ EVENT OBJECT ACCESS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

AP.RT.GetQuestId = function(quest)
    if not quest then return 0 end
    local ok, v = pcall(function() return quest:GetId() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.GetSpellEntry = function(spell)
    if not spell then return 0 end
    local ok, v = pcall(function() return spell:GetEntry() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.GetCreatureEntry = function(creature)
    if not creature then return 0 end
    local ok, v = pcall(function() return creature:GetEntry() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.GetCreatureLevel = function(creature)
    if not creature then return 0 end
    local ok, v = pcall(function() return creature:GetLevel() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.GetAchievementId = function(achievement)
    if not achievement then return 0 end
    local ok, v = pcall(function() return achievement:GetId() end)
    return (ok and type(v) == "number" and v) or 0
end

-- â”€â”€ PLAYER ITEM ACCESS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

AP.RT.GetEquippedItem = function(player, slot)
    if not player then return nil end
    if AP.Cap and not AP.Cap.Check("GetEquippedItemBySlot") then return nil end
    local ok, v = pcall(function() return player:GetEquippedItemBySlot(slot) end)
    return (ok and v) or nil
end

-- â”€â”€ GM CHECK (three-stage fallback) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
--
-- Stage 1: player:GetGMLevel()   â€” preferred; returns numeric level
-- Stage 2: player:IsGM()         â€” boolean only; cannot confirm level > 1
-- Stage 3: AuthDBQuery + account_access â€” only if AuthDBQuery is present
--          (account_access lives in acore_auth, not acore_characters;
--           CharDBQuery must NOT be used for this lookup)
-- Failure: returns false, records a doctor warning once.
--
-- #ap doctor calls AP.RT.IsGM(player, 3) â€” never player:GetGMLevel() directly.

AP.RT.GetItemEntry = function(item)
    if not item then return 0 end
    local ok, v = pcall(function() return item:GetEntry() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.GetItemLevel = function(item)
    if not item then return 0 end
    local ok, v = pcall(function() return item:GetItemLevel() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.GetItemGUIDLow = function(item)
    if not item then return 0 end
    local ok, v = pcall(function() return item:GetGUIDLow() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.GetItemGUID = function(item)
    if not item then return nil end
    local ok, v = pcall(function() return item:GetGUID() end)
    return (ok and v) or nil
end

AP.RT.GetItemQuality = function(item)
    if not item then return 0 end
    local ok, v = pcall(function() return item:GetQuality() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.GetItemByEntry = function(player, entry)
    if not player or not entry then return nil end
    local ok, v = pcall(function() return player:GetItemByEntry(entry) end)
    return (ok and v) or nil
end

AP.RT.GetItemCount = function(player, entry, checkBank)
    if not player or not entry then return 0 end
    local ok, v = pcall(function() return player:GetItemCount(entry, checkBank == true) end)
    return (ok and type(v) == "number" and v) or 0
end

-- Verified variant for correctness-critical representation reconciliation.
-- Unlike GetItemCount's compatibility-safe zero fallback, this preserves the
-- distinction between a real empty inventory and an unavailable/raw API error.
AP.RT.TryGetItemCount = function(player, entry, checkBank)
    if not player or not entry then return false, nil end
    local ok, v = pcall(function() return player:GetItemCount(entry, checkBank == true) end)
    if not ok or type(v) ~= "number" or v < 0 then return false, nil end
    return true, v
end

AP.RT.GetItemByPos = function(player, bag, slot)
    if not player then return nil end
    local ok, v = pcall(function() return player:GetItemByPos(bag, slot) end)
    return (ok and v) or nil
end

AP.RT.GetItemUInt32Value = function(item, field)
    if not item or field == nil then return 0 end
    local ok, v = pcall(function() return item:GetUInt32Value(field) end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.SetItemUInt32Value = function(item, field, value)
    if not item or field == nil or value == nil then return false end
    return pcall(function() item:SetUInt32Value(field, value) end)
end

AP.RT.SaveItemToDB = function(item)
    if not item then return false end
    return pcall(function() item:SaveToDB() end)
end

AP.RT.RemoveItemObject = function(item)
    if not item then return false end
    return pcall(function() item:Remove() end)
end

-- â”€â”€ PLAYER ACTIONS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

AP.RT.SetSpeed = function(player, moveType, rate, forced)
    if not player then return false end
    return pcall(function() player:SetSpeed(moveType, rate, forced) end)
end

AP.RT.IsMounted = function(player)
    if not player then return false end
    local ok, v = pcall(function() return player:IsMounted() end)
    return ok and v == true
end

AP.RT.IsInFlight = function(player)
    if not player then return false end
    local ok, v = pcall(function() return player:IsInFlight() end)
    return ok and v == true
end

AP.RT.RemoveItem = function(player, entry, count)
    if not player or not entry then return false end
    return operationSucceeded(function() return player:RemoveItem(entry, count or 1) end)
end

AP.RT.AddItem = function(player, entry, count)
    if not player or not entry then return false end
    return operationSucceeded(function() return player:AddItem(entry, count or 1) end)
end

AP.RT.SavePlayerToDB = function(player, logout, saveImmediately)
    if not player then return false end
    return operationSucceeded(function() return player:SaveToDB(logout, saveImmediately) end)
end

AP.RT.GetCoinage = function(player)
    if not player then return 0 end
    local ok, v = pcall(function() return player:GetCoinage() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.SetCoinage = function(player, amount)
    if not player or type(amount) ~= "number" then return false end
    return operationSucceeded(function() return player:SetCoinage(amount) end)
end

AP.RT.ModifyMoney = function(player, amount)
    if not player or type(amount) ~= "number" then return false end
    return pcall(function() player:ModifyMoney(amount) end)
end

AP.RT.GetHealth = function(unit)
    if not unit then return 0 end
    local ok, v = pcall(function() return unit:GetHealth() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.GetMaxHealth = function(unit)
    if not unit then return 0 end
    local ok, v = pcall(function() return unit:GetMaxHealth() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.SetHealth = function(unit, amount)
    if not unit or type(amount) ~= "number" then return false end
    return pcall(function() unit:SetHealth(amount) end)
end

AP.RT.ModifyHealth = function(unit, amount)
    if not unit or type(amount) ~= "number" then return false end
    return pcall(function() unit:ModifyHealth(amount) end)
end

AP.RT.InBattleground = function(player)
    if not player then return false end
    local ok, v = pcall(function() return player:InBattleground() end)
    return ok and v == true
end

AP.RT.GetBattlegroundId = function(player)
    if not player then return 0 end
    local ok, v = pcall(function() return player:GetBattlegroundId() end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.GetTeam = function(player)
    if not player then return 0 end
    local ok, v = pcall(function() return player:GetTeam() end)
    return (ok and type(v) == "number" and v) or 0
end
AP.RT._isGmWarnedOnce = false

AP.RT.IsGM = function(player, minLevel)
    minLevel = minLevel or 3
    if not player then return false end

    -- Stage 1: GetGMLevel()
    local ok1, gmlevel = pcall(function() return player:GetGMLevel() end)
    if ok1 and type(gmlevel) == "number" then
        return gmlevel >= minLevel
    end

    -- Stage 2: IsGM() â€” only tells us the player is A GM, not the level
    local ok2, isgm = pcall(function() return player:IsGM() end)
    if ok2 and type(isgm) == "boolean" then
        if not isgm then return false end       -- definitively not a GM
        if minLevel <= 1 then return true end   -- boolean sufficient for level 1
        -- Player IS a GM but exact level is unknown; fall through to Stage 3
    end

    -- Stage 3: AuthDBQuery against account_access (acore_auth database)
    if type(AuthDBQuery) == "function" then
        local ok3, acctId = pcall(function() return player:GetAccountId() end)
        if ok3 and type(acctId) == "number" and acctId > 0 then
            local q
            local ok4 = pcall(function()
                q = AuthDBQuery(string.format(
                    "SELECT `gmlevel` FROM `account_access` WHERE `id` = %d LIMIT 1;",
                    acctId))
            end)
            if ok4 and q then
                local ok5, lvl = pcall(function() return q:GetUInt32(0) end)
                if ok5 and type(lvl) == "number" then
                    return lvl >= minLevel
                end
            end
        end
    end

    -- All stages failed â€” record a doctor warning (once, to avoid spam)
    if not AP.RT._isGmWarnedOnce then
        AP.RT._isGmWarnedOnce = true
        if AP.Doctor and AP.Doctor.AddWarning then
            AP.Doctor.AddWarning(
                "AP.RT.IsGM",
                "GM level check unavailable: GetGMLevel, IsGM, and AuthDBQuery all " ..
                "failed or returned unusable values. #ap doctor and all GM-only commands " ..
                "are inaccessible until this is resolved. Check Eluna build for GetGMLevel support.")
        end
        print("[Echoes] WARN ap02_runtime_eluna: AP.RT.IsGM: all fallback stages failed.")
    end
    return false
end

-- â”€â”€ COMMUNICATION â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

AP.RT.SendMessage = function(player, msg)
    if not player or not msg then return end
    if AP.Cap and not AP.Cap.Check("SendBroadcastMessage") then return end
    pcall(function() player:SendBroadcastMessage(msg) end)
end

-- â”€â”€ AURAS / COOLDOWNS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

AP.RT.AddAura = function(player, spellId)
    if not player or not spellId then return false end
    return pcall(function() player:AddAura(spellId, player) end)
end

AP.RT.RemoveAura = function(player, spellId)
    if not player or not spellId then return false end
    return pcall(function() player:RemoveAura(spellId) end)
end

AP.RT.HasSpellCooldown = function(player, spellId)
    if not player then return false end
    local ok, v = pcall(function() return player:HasSpellCooldown(spellId) end)
    return ok and v == true
end

AP.RT.HasCooldown = AP.RT.HasSpellCooldown

AP.RT.GetCooldownDelay = function(player, spellId)
    if not player then return 0 end
    local ok, v = pcall(function() return player:GetSpellCooldownDelay(spellId) end)
    return (ok and type(v) == "number" and v) or 0
end

AP.RT.ResetCooldown = function(player, spellId)
    if not player then return end
    pcall(function() player:ResetSpellCooldown(spellId, true) end)
end

-- â”€â”€ GLOBAL PLAYER LOOKUPS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

AP.RT.GetPlayerByGUID = function(guid)
    if not guid then return nil end
    local ok, v = pcall(function() return GetPlayerByGUID(guid) end)
    return (ok and v) or nil
end

AP.RT.GetPlayerByName = function(name)
    if not name then return nil end
    local ok, v = pcall(function() return GetPlayerByName(name) end)
    return (ok and v) or nil
end

AP.RT.GetPlayersInWorld = function()
    if type(GetPlayersInWorld) ~= "function" then return {} end
    local ok, v = pcall(GetPlayersInWorld)
    return (ok and type(v) == "table" and v) or {}
end

-- â”€â”€ TIMER / EVENT REGISTRATION â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

AP.RT._registrations = AP.RT._registrations or {}

local function recordCapability(name, available, reason)
    AP.Cap = AP.Cap or {}
    AP.CapInfo = AP.CapInfo or {}
    AP.Cap[name] = available == true
    AP.CapInfo[name] = reason or (available and "available" or "unavailable")
end

local function registrationKey(family, owner, eventId, fn)
    return table.concat({ family, tostring(owner or ""), tostring(eventId), tostring(fn) }, ":")
end

local function safeHandler(fn)
    return function(...)
        local ok, result = pcall(fn, ...)
        if not ok then
            print("[Echoes] WARN runtime handler failed: " .. tostring(result))
            return
        end
        return result
    end
end

local function guardedHandler(fn)
    local safe = safeHandler(fn)
    return function(...)
        if AP.DB and AP.DB.IsReady and not AP.DB.IsReady() then return end
        return safe(...)
    end
end

local function safeRegister(capability, globalName, key, call)
    if AP.RT._registrations[key] then return true end
    if type(_G[globalName]) ~= "function" then
        recordCapability(capability, false, globalName .. " is unavailable")
        return false
    end
    local ok, result = pcall(call)
    if not ok then
        recordCapability(capability, false, globalName .. " failed: " .. tostring(result))
        return false
    end
    AP.RT._registrations[key] = true
    recordCapability(capability, true, globalName .. " registration succeeded")
    return true
end

AP.RT.CreateTimer = function(fn, delayMs, repeats)
    if type(fn) ~= "function" or type(CreateLuaEvent) ~= "function" then return false end
    local ok = pcall(CreateLuaEvent, guardedHandler(fn), delayMs, repeats or 1)
    return ok
end

AP.RT.RegisterEvent = function(etype, eventId, fn)
    if type(fn) ~= "function" then return false end
    local mappedId = eventId
    local globalName
    local callback = fn
    if etype == "server" then
        globalName = "RegisterServerEvent"
        callback = safeHandler(fn)
        if AP.Config and AP.Config.DMLMode == true and eventId == 3 then
            mappedId = 13
            local delivered = false
            local safe = callback
            callback = function(...)
                if delivered then return end
                delivered = true
                return safe(...)
            end
        end
    elseif etype == "player" then
        globalName = "RegisterPlayerEvent"
        callback = guardedHandler(fn)
    else
        return false
    end
    local key = registrationKey(etype, "", mappedId, fn)
    return safeRegister(globalName, globalName, key, function()
        return _G[globalName](mappedId, callback)
    end)
end

AP.RT.RegisterItemEvent = function(entry, eventId, fn)
    if type(fn) ~= "function" then return false end
    local key = registrationKey("item", entry, eventId, fn)
    return safeRegister("RegisterItemEvent", "RegisterItemEvent", key, function()
        return RegisterItemEvent(entry, eventId, guardedHandler(fn))
    end)
end

AP.RT.RegisterBGEvent = function(eventId, fn)
    if type(fn) ~= "function" then return false end
    local key = registrationKey("battleground", "", eventId, fn)
    return safeRegister("RegisterBGEvent", "RegisterBGEvent", key, function()
        return RegisterBGEvent(eventId, guardedHandler(fn))
    end)
end

AP.RT.RegisterPlayerGossipEvent = function(menuId, eventId, fn)
    if type(fn) ~= "function" then return false end
    local key = registrationKey("player-gossip", menuId, eventId, fn)
    return safeRegister("RegisterPlayerGossipEvent", "RegisterPlayerGossipEvent", key, function()
        return RegisterPlayerGossipEvent(menuId, eventId, guardedHandler(fn))
    end)
end

print("[Echoes] ap02_runtime_eluna loaded (AP.RT wired to Eluna APIs)")

-- ============================================================
-- ap_botapi.lua -- Echoes of the Worldsoul: Bot Action Bridge Service (E2i6/E2i8)
--
-- Narrow, Echoes-owned service surface for the optional mod-echoes-playerbots C++
-- module to request Rack/Dissolution actions on behalf of a bot, WITHOUT any
-- gameplay rule (cost/reward/eligibility formula) being duplicated in C++.
--
-- This file is loaded only in the isolated E2i8 evidence tree. It follows the
-- existing AP.API convention established in ap_zzapi.lua (pcall-wrapped, returns
-- plain-value tables, safe defaults on failure) and calls only already-existing,
-- already-audited Echoes functions (AP.Rack.*, AP.Forge.*) -- it never reimplements
-- their logic.
--
-- Human gameplay paths (the existing gossip-menu Rack/Legacy Forge UI) are
-- completely unchanged by this file -- it adds new AP.API.* entry points, it
-- does not modify any existing function.
--
-- E2i8 naming correction: "Legacy Forge" IS Echoes' Dissolution system (see
-- ap_forge.lua's own header comment and ap_ui.lua's own "LEGACY FORGE" UI
-- section label). There is no separate upgrade/crafting Forge mechanic
-- anywhere in this codebase. The canonical wire actionType string is now
-- "DISSOLUTION" (matches EchoesBotAction::ActionTypeToString(ActionType::
-- DISSOLVE) on the C++ side); "LEGACY_FORGE" and the old E2i6/E2i7 "DISSOLVE"
-- string are both still accepted (see IsDissolutionAction below).
-- ============================================================

AP = AP or {}
AP.API = AP.API or {}
AP.API.BotAction = AP.API.BotAction or {}

-- Bounded, in-memory-only result ledger for QueryBotActionResult. Never persisted --
-- cleared on Lua reload/shutdown by construction (it is just a plain Lua table).
-- Bounded size: only ever holds recently-completed tokens, pruned on insert.
AP.API.BotAction.Results = AP.API.BotAction.Results or {}
AP.API.BotAction.ResultOrder = AP.API.BotAction.ResultOrder or {}
AP.API.BotAction.MAX_RESULTS = 200

local function PruneResults()
    while #AP.API.BotAction.ResultOrder > AP.API.BotAction.MAX_RESULTS do
        local oldest = table.remove(AP.API.BotAction.ResultOrder, 1)
        AP.API.BotAction.Results[oldest] = nil
    end
end

-- E2i8: the canonical wire string for the Dissolution action is "DISSOLUTION"
-- (matches EchoesBotAction::ActionTypeToString(ActionType::DISSOLVE) on the
-- C++ side, which changed from the E2i6/E2i7 "DISSOLVE" string as part of the
-- Legacy-Forge-is-Dissolution naming correction). "LEGACY_FORGE" and the old
-- "DISSOLVE" are both accepted as aliases, mirroring the C++ side's own
-- permissive ActionTypeFromString - this file must never require callers to
-- have upgraded in lockstep with the exact wire string.
local function IsDissolutionAction(actionType)
    return actionType == "DISSOLUTION" or actionType == "LEGACY_FORGE" or actionType == "DISSOLVE"
end

local function StoreResult(token, result)
    if not token or token == "" then return end
    if not AP.API.BotAction.Results[token] then
        AP.API.BotAction.ResultOrder[#AP.API.BotAction.ResultOrder + 1] = token
    end
    AP.API.BotAction.Results[token] = result
    PruneResults()
end

-- ============================================================
-- GetCapabilities() -- what this Echoes runtime can currently service.
-- Mirrors the existing presence-handshake pattern (version/readiness only, no
-- per-bot state).
--
-- E2i8 naming correction: reports the corrected, unambiguous
-- canDissolutionDryRun/canDissolutionExecute/legacyForgeAlias fields. There
-- is still no separate upgrade/crafting Forge capability to report --
-- canForgeUpgrade is not sent at all (the C++ side treats it as permanently
-- false regardless), which is the accurate reflection of the real capability
-- surface, not an omission bug.
-- ============================================================

function AP.API.GetCapabilities()
    local ok, result = pcall(function()
        local forgePresent = (AP.Forge ~= nil and AP.Forge.Rewards ~= nil and AP.Forge.Dissolve ~= nil)
        local forgeDirectPresent = (AP.Forge ~= nil and AP.Forge.DissolveDirect ~= nil)
        return {
            version = AP.API.GetVersion(),
            ready = AP.API.IsReady(),
            canRackStore = (AP.Rack ~= nil and AP.Rack.AddItem ~= nil),
            canRackRetrieve = (AP.Rack ~= nil and AP.Rack.RemoveItem ~= nil),
            canDissolutionDryRun = forgePresent,
            -- Whether execution actually mutates is gated independently on the
            -- C++ side (EchoesConfig::dissolutionExecuteEnabled) - Lua reports
            -- only whether the real (non-UI) mutation entry point exists to
            -- call at all.
            canDissolutionExecute = forgeDirectPresent,
            legacyForgeAlias = forgePresent,
        }
    end)
    if not ok then
        return { version = "0.0.0", ready = false, canRackStore = false, canRackRetrieve = false,
                 canDissolutionDryRun = false, canDissolutionExecute = false, legacyForgeAlias = false }
    end
    return result
end

-- ============================================================
-- E2i8-R1: GetAttunementCap(itemEntry) -- narrow, read-only delegation to
-- Echoes' own AP.GetScaledCap(itemEntry) (ap_core.lua), which computes the
-- real level-scaled quadratic attunement cap
-- (cap = max(100, floor(CapPerItem * (RequiredLevel/80)^2))). This exists
-- solely so EchoesBotCache (C++) never has to guess or hardcode this
-- formula - Echoes' own cap logic is the single source of truth, and this
-- function only ever calls it, never reimplements it. Returns
-- { ok = true, cap = <integer> } on success, { ok = false } if
-- AP.GetScaledCap is unavailable (Echoes absent) or itemEntry is invalid -
-- the caller (EchoesActionBridge::GetAttunementCap) must treat ok=false as
-- "cap unavailable," not as "cap is zero."
-- ============================================================

function AP.API.GetAttunementCap(itemEntry)
    local ok, result = pcall(function()
        if type(itemEntry) ~= "number" or itemEntry <= 0 then
            return { ok = false }
        end
        if not AP.GetScaledCap then
            return { ok = false }
        end
        local cap = AP.GetScaledCap(itemEntry)
        if type(cap) ~= "number" or cap <= 0 then
            return { ok = false }
        end
        return { ok = true, cap = math.floor(cap) }
    end)
    if not ok then
        return { ok = false }
    end
    return result
end

-- ============================================================
-- Internal, per-action validation helpers. Each reuses Echoes' own existing
-- guard-clause logic (attunement checks, possession checks, capacity checks,
-- already-dissolved checks) -- read-only, never mutating.
-- ============================================================

local function ValidateRackStore(request)
    local player = request._playerObj
    if not player then return { resultCode = "ITEM_NOT_FOUND", reasonCode = "no_player" } end
    if not AP.Rack then return { resultCode = "CAPABILITY_UNAVAILABLE", reasonCode = "rack_module_absent" } end

    local guid = AP.RT.GetGUID(player)
    local itemEntry = request.itemEntry

    local hasItem = false
    pcall(function() hasItem = AP.RT.GetItemCount(player, itemEntry, true) > 0 end)
    if not hasItem then
        return { resultCode = "NOT_OWNER", reasonCode = "item_not_possessed" }
    end

    if not AP.Rack.Cache[guid] then AP.Rack.Load(guid) end
    local cache = AP.Rack.Cache[guid]
    for _, slot in pairs(cache) do
        if slot.item_entry == itemEntry then
            return { resultCode = "ALREADY_APPLIED", reasonCode = "already_on_rack" }
        end
    end

    local used, capacity = AP.API.GetRackCount(player)
    if used >= capacity then
        return { resultCode = "BAG_SPACE_REQUIRED", reasonCode = "rack_full", authoritativeCost = 0, authoritativeReward = 0 }
    end

    return { resultCode = "SUCCESS", reasonCode = "eligible", authoritativeCost = 0, authoritativeReward = 0,
             destinationRef = string.format("rack_slot_pending"), stateVersionAfter = tostring(used) }
end

local function ValidateRackRetrieve(request)
    local player = request._playerObj
    if not player then return { resultCode = "ITEM_NOT_FOUND", reasonCode = "no_player" } end
    if not AP.Rack then return { resultCode = "CAPABILITY_UNAVAILABLE", reasonCode = "rack_module_absent" } end

    local guid = AP.RT.GetGUID(player)
    if not AP.Rack.Cache[guid] then AP.Rack.Load(guid) end
    local cache = AP.Rack.Cache[guid]
    local foundSlot = nil
    for i, slot in pairs(cache) do
        if slot.item_entry == request.itemEntry then
            foundSlot = i
            break
        end
    end
    if not foundSlot then
        return { resultCode = "ITEM_NOT_FOUND", reasonCode = "not_on_rack" }
    end
    return { resultCode = "SUCCESS", reasonCode = "eligible", destinationRef = tostring(foundSlot) }
end

-- Read-only preview of what AP.Forge.Dissolve would do, WITHOUT calling it and
-- WITHOUT priming AP.Forge.Pending (so no server-side state is touched at all
-- by a dry-run). Mirrors Dissolve()'s own guard clauses exactly, stopping
-- before the mutating steps (physical removal, ledger insert, reward grant).
-- stateVersionAfter carries the item's quality tier (1-5) forward so
-- ExecuteBotAction's DISSOLVE branch doesn't have to re-derive it.
local function ValidateDissolve(request)
    local player = request._playerObj
    if not player then return { resultCode = "ITEM_NOT_FOUND", reasonCode = "no_player" } end
    if not AP.Forge or not AP.Forge.Rewards or not AP.Forge.Dissolve then
        return { resultCode = "CAPABILITY_UNAVAILABLE", reasonCode = "forge_module_absent" }
    end

    local guid = AP.RT.GetGUID(player)
    local accountId = AP.RT.GetAccountId(player)
    local itemEntry = request.itemEntry

    local alreadyDissolved = AP.DB.Query(string.format(
        "SELECT 1 FROM `ap_dissolved_items` WHERE `account_id` = %d AND `item_entry` = %d",
        accountId, itemEntry))
    if alreadyDissolved then
        return { resultCode = "ALREADY_APPLIED", reasonCode = "already_dissolved" }
    end

    -- Fully attuned only (attuned = 1) - the same authoritative threshold
    -- ShowPage itself queries on. This is Echoes' own gameplay rule, not a
    -- bot-policy invention; the bot decision policy (EchoesDissolutionPolicy,
    -- C++ side) may reject additional cases beyond this, but never loosens it.
    local attuneRow = AP.DB.Query(string.format(
        "SELECT 1 FROM `ap_item_attune` WHERE `guid` = %d AND `item_entry` = %d AND `attuned` = 1",
        guid, itemEntry))
    if not attuneRow then
        return { resultCode = "REJECTED", reasonCode = "not_attuned" }
    end

    local hasItem = false
    pcall(function() hasItem = AP.RT.GetItemCount(player, itemEntry, true) > 0 end)
    if not hasItem then
        return { resultCode = "NOT_OWNER", reasonCode = "item_not_possessed" }
    end

    local isEquipped = false
    pcall(function()
        for slot = 0, 18 do
            local eq = AP.RT.GetEquippedItem(player, slot)
            if eq and AP.RT.GetItemEntry(eq) == itemEntry then
                isEquipped = true
                break
            end
        end
    end)
    if isEquipped then
        return { resultCode = "REJECTED", reasonCode = "item_equipped" }
    end

    local quality = 1
    local wq = AP.DB.WorldQuery(string.format(
        "SELECT `Quality` FROM `item_template` WHERE `entry` = %d", itemEntry))
    if wq then quality = tonumber(tostring(wq:GetUInt32(0))) or 1 end

    local rewards = AP.Forge.Rewards[quality] or AP.Forge.Rewards[1]

    return {
        resultCode = "SUCCESS",
        reasonCode = "eligible",
        authoritativeCost = 0,
        authoritativeReward = rewards.essence + rewards.residue,
        destinationRef = "worldsoul",
        stateVersionAfter = tostring(quality),
    }
end

-- ============================================================
-- ValidateBotAction(request) -- read-only dry-run evaluation for any action type.
-- Never mutates. Safe to call as often as the caller's own rate limiting allows.
-- ============================================================

function AP.API.ValidateBotAction(request)
    local ok, result = pcall(function()
        if type(request) ~= "table" then
            return { resultCode = "INTERNAL_ERROR", reasonCode = "malformed_request" }
        end
        if request.actionType == "RACK_STORE" then
            return ValidateRackStore(request)
        elseif request.actionType == "RACK_RETRIEVE" then
            return ValidateRackRetrieve(request)
        elseif IsDissolutionAction(request.actionType) then
            return ValidateDissolve(request)
        elseif request.actionType == "FORGE" then
            return { resultCode = "CAPABILITY_UNAVAILABLE", reasonCode = "no_separate_upgrade_crafting_forge_exists" }
        end
        return { resultCode = "INTERNAL_ERROR", reasonCode = "unknown_action_type" }
    end)
    if not ok then
        return { resultCode = "INTERNAL_ERROR", reasonCode = "lua_exception" }
    end
    return result
end

-- ============================================================
-- ExecuteBotAction(request) -- mutates for RACK_STORE/RACK_RETRIEVE (E2i7) and,
-- as of E2i8, DISSOLVE -- but only ever when the caller has already set
-- request.dryRun = false, which the C++ side (EchoesDissolutionAdapter::Execute)
-- only ever does after its own independent execution gate has passed
-- (EchoesConfig::dissolutionExecuteEnabled explicitly true, fresh local policy
-- revalidation, idempotency token present, request not stale). This function's
-- own contribution to safety is calling the REAL AP.Forge.Dissolve() mutation,
-- which performs its own complete guard-clause re-verification (pending state,
-- already-dissolved, attunement, possession, equipped) immediately before
-- ever removing the item -- this file never reimplements any of that check or
-- the reward calculation.
--
-- FORGE always returns CAPABILITY_UNAVAILABLE without mutating -- there is no
-- separate upgrade/crafting mutation to call, and never will be.
-- ============================================================

-- E2i8 (post-audit revision): calls AP.Forge.DissolveDirect, a proper
-- non-UI, non-gossip service entry point added to ap_forge.lua itself for
-- this purpose, instead of priming AP.Forge.Pending and calling the
-- gossip-oriented AP.Forge.Dissolve(player, nil, itemEntry). An independent
-- architecture audit found that priming Pending directly (though it worked
-- and never crashed - AP.UI.SendMenu's own nil-npc fallback was confirmed
-- safe) reached into an undocumented, file-private implementation detail
-- rather than a real interface. DissolveDirect performs the identical
-- guard-clause sequence and mutation ordering and returns a real, structured
-- result instead of requiring an ap_dissolved_items post-check to infer the
-- outcome. The human gossip flow (ShowConfirm/Dissolve/OnSelect) and
-- AP.Forge.Pending are completely untouched by this function.
local function ExecuteDissolve(request)
    local pre = ValidateDissolve(request)
    if pre.resultCode ~= "SUCCESS" then return pre end

    local player = request._playerObj
    local itemEntry = request.itemEntry

    if not AP.Forge.DissolveDirect then
        return { resultCode = "CAPABILITY_UNAVAILABLE", reasonCode = "dissolve_direct_absent" }
    end

    local ok, result = pcall(function() return AP.Forge.DissolveDirect(player, itemEntry) end)
    if not ok or type(result) ~= "table" then
        return { resultCode = "INTERNAL_ERROR", reasonCode = "dissolve_lua_exception" }
    end

    if not result.success then
        -- DissolveDirect ran one of its own guard clauses and declined
        -- (already-dissolved race, no-longer-attuned, item no longer
        -- possessed, found equipped, or removal failed) -- item was never
        -- removed. This is a clean rejection, not an internal error.
        return { resultCode = "REJECTED", reasonCode = result.reasonCode or "dissolve_declined_by_echoes_validator" }
    end

    return { resultCode = "SUCCESS", reasonCode = "dissolved",
             authoritativeReward = (result.essence or 0) + (result.residue or 0),
             destinationRef = "worldsoul" }
end

function AP.API.ExecuteBotAction(request)
    local ok, result = pcall(function()
        if type(request) ~= "table" then
            return { resultCode = "INTERNAL_ERROR", reasonCode = "malformed_request" }
        end

        if request.dryRun then
            return AP.API.ValidateBotAction(request)
        end

        if request.actionType == "RACK_STORE" then
            local pre = ValidateRackStore(request)
            if pre.resultCode ~= "SUCCESS" then return pre end
            local player = request._playerObj
            local applied = AP.Rack.AddItem(player, request.itemEntry)
            if not applied then
                return { resultCode = "REJECTED", reasonCode = "rack_add_failed" }
            end
            local used, cap = AP.API.GetRackCount(player)
            return { resultCode = "SUCCESS", reasonCode = "stored", stateVersionAfter = tostring(used) }
        elseif request.actionType == "RACK_RETRIEVE" then
            local pre = ValidateRackRetrieve(request)
            if pre.resultCode ~= "SUCCESS" then return pre end
            local player = request._playerObj
            local slotIndex = tonumber(pre.destinationRef)
            local applied = AP.Rack.RemoveItem(player, slotIndex)
            if not applied then
                return { resultCode = "REJECTED", reasonCode = "rack_remove_failed" }
            end
            return { resultCode = "SUCCESS", reasonCode = "retrieved" }
        elseif IsDissolutionAction(request.actionType) then
            return ExecuteDissolve(request)
        elseif request.actionType == "FORGE" then
            return { resultCode = "CAPABILITY_UNAVAILABLE", reasonCode = "no_separate_upgrade_crafting_forge_exists" }
        end
        return { resultCode = "INTERNAL_ERROR", reasonCode = "unknown_action_type" }
    end)
    if not ok then
        result = { resultCode = "INTERNAL_ERROR", reasonCode = "lua_exception" }
    end
    if request and request.idempotencyToken then
        StoreResult(request.idempotencyToken, result)
    end
    return result
end

-- ============================================================
-- QueryBotActionResult(token) -- bounded in-memory lookup only. Never a DB
-- table, never persisted, never polled per-tick by design -- the caller uses
-- this only to re-check a specific token it already holds.
-- ============================================================

function AP.API.QueryBotActionResult(token)
    if not token then return { resultCode = "INTERNAL_ERROR", reasonCode = "no_token" } end
    return AP.API.BotAction.Results[token] or { resultCode = "RETRYABLE", reasonCode = "not_found_or_expired" }
end

-- ============================================================
-- E2j1: bounded progression-economy read/spend surface. Every function here
-- is a thin, narrow delegation to Echoes' own already-existing mutation
-- functions (AP.Sinks.Invest, AP.Rack.Expand) - never a reimplementation of
-- their cost/effect formulas. Mastery and Talent purchases are intentionally
-- NOT wrapped here: Mastery's mutation is inline unnamed gossip-handler code
-- and Talent's mutation function is `local`-scoped and unexported, so
-- wrapping either would require restructuring already-live human-facing
-- Lua code - out of this phase's authorized scope. Both remain DEFERRED.
-- ============================================================

-- Read-only snapshot of a bot's current progression-economy state. Never
-- mutates. Returns ok=false (never a guessed/zero value) if the underlying
-- systems are unavailable.
function AP.API.GetProgressionSnapshot(player)
    local ok, result = pcall(function()
        if not player or not AP.RT or not AP.RT.GetGUID then
            return { ok = false }
        end
        local guid = AP.RT.GetGUID(player)
        local accountId = AP.RT.GetAccountId and AP.RT.GetAccountId(player)
        if not guid or not accountId then
            return { ok = false }
        end

        local essence = 0
        if AP.DB and AP.DB.Query then
            local q = AP.DB.Query(string.format(
                "SELECT `aether` FROM `ap_mastery` WHERE `guid` = %d", guid))
            if q then essence = tonumber(tostring(q:GetUInt32(0))) or 0 end
        end

        local rackSlots = (AP.Rack and AP.Rack.GetCapacity) and AP.Rack.GetCapacity(guid) or nil
        if rackSlots == nil then
            return { ok = false }
        end

        local residue = (AP.Forge and AP.Forge.GetResidue) and AP.Forge.GetResidue(accountId) or 0

        return { ok = true, essence = essence, rackSlots = rackSlots, residue = residue }
    end)
    if not ok then return { ok = false } end
    return result
end

-- Complete authoritative Talent state for player-facing UI. This deliberately
-- stays outside bot decision policy: it exposes the same human system state and
-- does not authorize autonomous Talent purchasing.
function AP.API.GetTalentSnapshot(player)
    local ok, result = pcall(function()
        if not player or not AP.LoadTalents or not AP.BuildTalentSnapshot then
            return { ok = false, status = "SERVICE_UNAVAILABLE" }
        end
        local guid = AP.RT.GetGUID(player)
        if not guid then return { ok = false, status = "INVALID_PLAYER" } end
        local mastery = AP.LoadMastery(guid)
        local snapshot = AP.BuildTalentSnapshot(AP.LoadTalents(guid))
        snapshot.ok = true
        snapshot.status = "READY"
        snapshot.guid = guid
        snapshot.essence = mastery and (tonumber(mastery.aether) or 0) or 0
        return snapshot
    end)
    if not ok then return { ok = false, status = "SERVICE_UNAVAILABLE" } end
    return result
end

-- Pure next-rank preview. Primary transition, per-stat amplifier, cost, and
-- diversification remain server-owned so the client never mirrors C++ rules.
function AP.API.PreviewTalentPurchase(player, statIndex)
    local ok, result = pcall(function()
        local current = AP.API.GetTalentSnapshot(player)
        if not current or not current.ok then
            return current or { ok = false, status = "SERVICE_UNAVAILABLE" }
        end
        local talents = {}
        for idx = 0, 4 do talents[idx] = current.stats[idx].rank end
        local preview = AP.PreviewTalentSnapshot(talents, statIndex)
        if not preview.ok then
            preview.essence = current.essence
            return preview
        end
        preview.essence = current.essence
        preview.affordable = current.essence >= preview.cost
        return preview
    end)
    if not ok then return { ok = false, status = "SERVICE_UNAVAILABLE" } end
    return result
end

-- Canonical human Talent mutation. Legacy gossip and E2J15 both delegate here,
-- preserving one validation/cost/persistence path.
function AP.API.ExecuteTalentPurchase(player, statIndex)
    local ok, result = pcall(function()
        local preview = AP.API.PreviewTalentPurchase(player, statIndex)
        if not preview or not preview.ok then
            return preview or { ok = false, status = "SERVICE_UNAVAILABLE" }
        end
        if not preview.affordable then
            return {
                ok = false, status = "INSUFFICIENT_ESSENCE", statIndex = preview.statIndex,
                cost = preview.cost, oldBalance = preview.essence, newBalance = preview.essence,
                current = preview.current, projected = preview.projected,
            }
        end
        local guid = AP.RT.GetGUID(player)
        local currentStat = preview.current.stats[preview.statIndex]
        local projectedStat = preview.projected.stats[preview.statIndex]
        local newBalance = preview.essence - preview.cost
        local writeOk = AP.DB.ExecuteCritical(string.format([[
            INSERT INTO `ap_mastery` (`guid`, `aether`, `mastery`)
            VALUES (%d, %d, 0)
            ON DUPLICATE KEY UPDATE `aether` = %d;
        ]], guid, newBalance, newBalance), "AP.API.ExecuteTalentPurchase")
        if not writeOk then
            return {
                ok = false, status = "DATABASE_FAILURE", statIndex = preview.statIndex,
                cost = preview.cost, oldBalance = preview.essence, newBalance = preview.essence,
            }
        end
        AP.SaveTalent(guid, preview.statIndex, projectedStat.rank)
        AP.DB.Execute("COMMIT;")
        AP.Log(string.format("Talent: guid=%d stat=%d rank=%d", guid, preview.statIndex, projectedStat.rank))
        return {
            ok = true, status = "SUCCESS", statIndex = preview.statIndex,
            oldRank = currentStat.rank, newRank = projectedStat.rank, cost = preview.cost,
            oldBalance = preview.essence, newBalance = newBalance,
            oldPrimary = preview.current.primary, newPrimary = preview.projected.primary,
            oldPenalty = preview.current.penalty, newPenalty = preview.projected.penalty,
            oldBonusPct = currentStat.bonusPct, newBonusPct = projectedStat.bonusPct,
        }
    end)
    if not ok then return { ok = false, status = "SERVICE_UNAVAILABLE" } end
    return result
end

-- Pure preview: computes cost/projected-effect of a hypothetical Crucible
-- sink investment WITHOUT mutating anything. Reuses AP.Sinks.GetEffect and
-- AP.Sinks.InvestCost exactly as the human gossip UI does - never a new
-- formula.
function AP.API.PreviewSinkInvest(category, amount, currentInvested)
    local ok, result = pcall(function()
        if not AP.Sinks or not AP.SinkDefs then
            return { ok = false }
        end
        local def = AP.SinkDefs[category]
        if not def or type(amount) ~= "number" or amount < 1 then
            return { ok = false }
        end
        amount = math.floor(amount)
        currentInvested = math.max(0, math.floor(tonumber(currentInvested) or 0))
        local cost = AP.Sinks.InvestCost(amount)
        local projectedInvested = currentInvested + amount
        local currentEffect = AP.Sinks.GetEffect(category, currentInvested)
        local projectedEffect = AP.Sinks.GetEffect(category, projectedInvested)
        return { ok = true, category = category, cost = cost,
                 currentInvested = currentInvested, currentEffect = currentEffect,
                 projectedInvested = projectedInvested,
                 projectedEffectAtAmount = projectedEffect,
                 ceiling = def.ceiling, label = def.label }
    end)
    if not ok then return { ok = false } end
    return result
end

-- Real, gated mutation: delegates to AP.Sinks.Invest exactly as the human
-- Crucible gossip menu does. Never reimplements the (explicitly documented
-- non-atomic-by-design) spend logic.
function AP.API.ExecuteSinkInvest(player, category, amount)
    local ok, result = pcall(function()
        if not player or not AP.Sinks or not AP.Sinks.Invest then
            return { ok = false, reason = "unavailable" }
        end
        local success, reason = AP.Sinks.Invest(player, category, amount)
        return { ok = success == true, reason = reason }
    end)
    if not ok then return { ok = false, reason = "exception" } end
    return result
end

-- Pure preview: read-only lookup of the next Rack expansion tier's cost,
-- without mutating. Mirrors AP.Rack.Expand's own tier-selection logic
-- exactly (same AP.Rack.ExpandTiers table), never a duplicate formula.
function AP.API.PreviewRackExpand(player)
    local ok, result = pcall(function()
        if not player or not AP.Rack or not AP.Rack.PreviewExpand then
            return { ok = false }
        end
        return AP.Rack.PreviewExpand(player)
    end)
    if not ok then return { ok = false } end
    return result
end

-- Real, gated mutation: delegates to AP.Rack.Expand exactly as the human
-- Attunement Rack gossip menu does.
function AP.API.ExecuteRackExpand(player, expectedCurrent, expectedNext, expectedResidue)
    local ok, result = pcall(function()
        if not player or not AP.Rack or not AP.Rack.Expand then
            return { ok = false, status = "SERVICE_UNAVAILABLE" }
        end
        if type(expectedResidue) == "number" then
            return AP.Rack.PurchaseExpand(player, expectedCurrent, expectedNext, expectedResidue)
        end
        local success = AP.Rack.Expand(player)
        return { ok = success == true, status = success and "SUCCESS" or "INELIGIBLE" }
    end)
    if not ok then return { ok = false, status = "SERVICE_UNAVAILABLE" } end
    return result
end

function AP.API.PreviewCatalyst(player)
    local ok, result = pcall(function()
        if not player or not AP.Forge or not AP.Forge.PreviewCatalyst then
            return { ok = false, status = "SERVICE_UNAVAILABLE" }
        end
        return AP.Forge.PreviewCatalyst(player)
    end)
    if not ok then return { ok = false, status = "SERVICE_UNAVAILABLE" } end
    return result
end

function AP.API.ExecuteCatalyst(player, expectedResidue, expectedEssence)
    local ok, result = pcall(function()
        if not player or not AP.Forge or not AP.Forge.PurchaseCatalyst then
            return { ok = false, status = "SERVICE_UNAVAILABLE" }
        end
        return AP.Forge.PurchaseCatalyst(player, expectedResidue, expectedEssence)
    end)
    if not ok then return { ok = false, status = "SERVICE_UNAVAILABLE" } end
    return result
end

-- E2j5: Mastery is now a bridgeable target - AP.Mastery.Purchase (ap_core.lua) was
-- extracted from the previously-inline human gossip handler into a real, reusable
-- service. Pure preview: read-only lookup of current rank/balance/next cost, mirroring
-- AP.MasteryCost/AP.LoadMastery exactly, never a duplicate formula, never a rank ceiling.
function AP.API.PreviewMasteryPurchase(player)
    local ok, result = pcall(function()
        if not player or not AP.RT or not AP.RT.GetGUID or not AP.LoadMastery or not AP.MasteryCost then
            return { ok = false }
        end
        local guid = AP.RT.GetGUID(player)
        if not guid then return { ok = false } end
        local rec     = AP.LoadMastery(guid)
        local aether  = rec and rec.aether or 0
        local mastery = rec and rec.mastery or 0
        local cost    = AP.MasteryCost(mastery)
        return { ok = true, currentRank = mastery, currentBalance = aether, cost = cost }
    end)
    if not ok then return { ok = false } end
    return result
end

-- Real, gated mutation: delegates to AP.Mastery.Purchase exactly as the human
-- Progression gossip menu does (E2j5) - never a second implementation.
function AP.API.ExecuteMasteryPurchase(player)
    local ok, result = pcall(function()
        if not player or not AP.Mastery or not AP.Mastery.Purchase then
            return { ok = false, status = "SERVICE_UNAVAILABLE" }
        end
        local purchaseResult = AP.Mastery.Purchase(player)
        purchaseResult.ok = (purchaseResult.status == "SUCCESS")
        return purchaseResult
    end)
    if not ok then return { ok = false, status = "SERVICE_UNAVAILABLE" } end
    return result
end

-- World Threat read surface. Every derived value comes from the same helpers
-- and live session object used by ShowThreatPage; the client never owns threat
-- names, reward math, penalties, caps, or persistence semantics.
function AP.API.GetWorldThreatSnapshot(player)
    local ok, result = pcall(function()
        if not player or not AP.RT or not AP.RT.GetGUID or not AP.GetThreatName
            or not AP.GetThreatCeiling or not AP.GetThreatMult
            or not AP.GetSafetyScalar or not AP.GetDeathPenalty then
            return { ok = false, status = "SERVICE_UNAVAILABLE" }
        end
        local guid = AP.RT.GetGUID(player)
        if not guid then return { ok = false, status = "INVALID_PLAYER" } end
        AP._session = AP._session or {}
        AP._session[guid] = AP._session[guid] or {
            threat=0, momentum=0.0, momentumKills=0,
            debtKills=0, debtMult=1.0, kills={},
        }
        local session = AP._session[guid]
        local level = tonumber(session.threat) or 0
        local momentum = tonumber(session.momentum) or 0
        local penalty = AP.GetDeathPenalty(level)
        local caps = AP.Config.ThreatContentCaps
        return {
            ok=true,
            level=level,
            name=AP.GetThreatName(level),
            maximum=AP.Config.ThreatMax,
            ceilingPct=AP.GetThreatCeiling(level) * 100,
            momentumPct=momentum * 100,
            effectivePct=(AP.GetThreatMult(level, momentum) - 1.0) * 100,
            safetyPct=AP.GetSafetyScalar(level) * 100,
            debtKills=tonumber(session.debtKills) or 0,
            debtMultPct=(tonumber(session.debtMult) or 1.0) * 100,
            attuneLossPct=penalty[1] * 100,
            essenceLossPct=penalty[2] * 100,
            essenceCap=penalty[3],
            penaltyDebtKills=penalty[4],
            penaltyDebtMultPct=penalty[5] * 100,
            capNormalPct=caps.same_normal * 100,
            capElitePct=caps.elite * 100,
            capBossPct=caps.dungeon_boss * 100,
            capRaidPct=caps.raid_boss * 100,
        }
    end)
    if not ok then return { ok=false, status="SERVICE_UNAVAILABLE" } end
    return result
end

-- Canonical one-step World Threat mutation used by both gossip and E2J15.
-- Raising retains Momentum; lowering and reset clear it exactly as before.
function AP.API.ExecuteWorldThreatAction(player, action)
    local ok, result = pcall(function()
        local snapshot = AP.API.GetWorldThreatSnapshot(player)
        if not snapshot.ok then return snapshot end
        local guid = AP.RT.GetGUID(player)
        local session = AP._session[guid]
        local old = session.threat or 0
        if action == "increase" then
            if old >= AP.Config.ThreatMax then return {ok=false,status="MAXIMUM",oldLevel=old,newLevel=old} end
            session.threat = old + 1
        elseif action == "decrease" then
            if old <= 0 then return {ok=false,status="MINIMUM",oldLevel=old,newLevel=old} end
            session.threat = old - 1
            session.momentum = 0.0
            session.momentumKills = 0
        elseif action == "reset" then
            session.threat = 0
            session.momentum = 0.0
            session.momentumKills = 0
        else
            return {ok=false,status="INVALID_ACTION",oldLevel=old,newLevel=old}
        end
        if AP.SaveThreatToDB then AP.SaveThreatToDB(guid, session) end
        if AP.API.DispatchHook then
            AP.API.DispatchHook("OnThreatChanged", {
                guid=guid, oldLevel=old, newLevel=session.threat,
                momentum=session.momentum or 0,
            })
        end
        return {
            ok=true, status="SUCCESS", oldLevel=old, newLevel=session.threat,
            name=AP.GetThreatName(session.threat),
            momentumPct=(session.momentum or 0) * 100,
        }
    end)
    if not ok then return {ok=false,status="SERVICE_UNAVAILABLE"} end
    return result
end

print("[EotW] Bot Action Bridge service loaded (E2i8/E2j1/E2j5/E2J15) - Rack executable, Dissolution (Legacy Forge) dry-run + gated execution, bounded progression-economy spend surface (Crucible/Rack-expansion/Mastery/Talents), no separate upgrade/crafting Forge exists.")

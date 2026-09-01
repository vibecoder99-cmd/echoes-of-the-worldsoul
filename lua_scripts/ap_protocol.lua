-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- ap_protocol.lua — E2j15 Minimum Echoes Client Companion Protocol
--
-- Structured, versioned server<->client contract for the future
-- graphical Client Companion, layered on the SAME transport the
-- tooltip bridge and boss-flash already use (SAY-based control
-- messages in, SendBroadcastMessage/[TAG] responses out) — no new
-- transport, no new AddOn channel, no core changes.
--
-- Namespace: reuses the existing "#ap <verb> ..." chat-command
-- convention (event 18, PLAYER_EVENT_ON_CHAT) already used by the
-- tooltip bridge and #ap status commands — proven low-collision,
-- already the project convention. Structured request families are hello,
-- state, action, and codex. Responses use the distinct tag "[ECHOES]" so they
-- are never confused with "[APTIP]" (tooltip bridge) or "[EOTW_FLASH]"
-- (boss presentation) — see E2J15-CLIENT-COMPANION-PROTOCOL-SPEC.md.
--
-- Server owns all values returned here: every field is read from the
-- same tables/helpers the existing gossip/#ap status commands already
-- use (AP.Commands.Status in ap_commands.lua is the reference — this
-- file reuses its exact query/helper calls, not new formulas). The
-- client never sets state; it only asks.
-- ============================================================

AP = AP or {}
AP.Protocol = AP.Protocol or {}

-- Protocol version is independent of the product version (AP.VERSION,
-- from ap_core.lua / the repo-root VERSION file). Bump this only when
-- the wire grammar itself changes in an incompatible way.
AP.PROTOCOL_VERSION = 1

-- Capabilities this server currently supports via the structured state/
-- action API. Keep in sync with what AP.Protocol.BuildState/HandleAction
-- actually implement — never advertise a capability that isn't real.
AP.Protocol.ServerCapabilities = {
    "structured_state_v1",
    "mastery",
    "residue",
    "crucible",
    "rack",
    "talents",
    "attunement",
    "action_preview_catalyst",
    "progression_state_v1",
    "action_mastery_purchase",
    "world_threat_state_v1",
    "action_world_threat",
    "crucible_state_v1",
    "action_crucible_preview",
    "action_crucible_invest",
    "talents_state_v1",
    "action_talent_preview",
    "action_talent_purchase",
    "rack_state_v1",
    "action_rack_add",
    "action_rack_remove",
    "action_rack_expand",
    "forge_state_v1",
    "action_forge_dissolve",
    "action_forge_purchase_catalyst",
    "visage_state_v1",
    "visage_preview_v1",
    "action_visage_preview",
    "action_visage_apply",
    "action_visage_cancel",
    "action_visage_notifications",
    "codex_state_v1",
    "codex_search_v1",
    "chaos_state_v1",
    "action_chaos_toggle",
}

-- ============================================================
-- RATE LIMITING
-- Per-player, per-verb-class, in-memory sliding window. Mirrors the
-- established AP._tipRateLimit pattern (os.time()-based, already used
-- elsewhere in this codebase) rather than inventing a new mechanism.
-- This is a spam/abuse guard only — it is never the source of truth for
-- any gameplay validation, which always happens in the existing guarded
-- services (AP.Forge.*, etc.) regardless of what the client claims.
-- ============================================================
AP.Protocol._rateLimit = AP.Protocol._rateLimit or {}
AP.Protocol.RateLimitWindowSec = {
    hello  = 3,
    state  = 1,
    action = 2,
    preview = 1,
    visage_commit = 0,
    codex_manifest = 2,
    codex_page = 1,
    search = 1,
}

local function RateLimited(guid, verb)
    local window = AP.Protocol.RateLimitWindowSec[verb] or 2
    local now = os.time()
    AP.Protocol._rateLimit[guid] = AP.Protocol._rateLimit[guid] or {}
    local last = AP.Protocol._rateLimit[guid][verb]
    if last and (now - last) < window then
        return true
    end
    AP.Protocol._rateLimit[guid][verb] = now
    return false
end

-- ============================================================
-- WIRE GRAMMAR
-- "[ECHOES]<VERB>|k1=v1|k2=v2|..." — the same pipe-delimited key=value
-- shape already proven by [APTIP] (see EchoesOfTheWorldsoulBridge.lua's
-- ParsePayload). Values must not themselves contain "|" or "=".
-- Sub-lists (e.g. per-category crucible investment) use "," and ":" as
-- established by no prior payload in this codebase — documented in
-- E2J15-CLIENT-COMPANION-PROTOCOL-SPEC.md's grammar section, chosen
-- because neither character appears in any value produced here (all
-- numeric, or restricted-charset category/action identifiers).
-- ============================================================

local function EncodeFields(fields)
    local parts = {}
    for _, kv in ipairs(fields) do
        parts[#parts + 1] = kv[1] .. "=" .. tostring(kv[2])
    end
    return table.concat(parts, "|")
end

local function SendEchoes(player, verb, fields)
    local payload = "[ECHOES]" .. verb
    local body = EncodeFields(fields)
    if body ~= "" then
        payload = payload .. "|" .. body
    end
    AP.RT.SendMessage(player, payload)
end

local function SendError(player, code, message)
    SendEchoes(player, "ERROR", {
        { "code", code },
        { "message", message or "" },
    })
end

-- Text-bearing Codex fields use conservative percent escaping inside the
-- existing v1 key=value grammar. Gameplay fields remain byte-for-byte
-- unchanged; this is a compatible extension, not a protocol revision.
local function EncodeText(value)
    return (tostring(value or ""):gsub("([^%w%._%-])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function DecodeText(value)
    return (tostring(value or ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

AP.Protocol.EncodeText = EncodeText
AP.Protocol.DecodeText = DecodeText

-- Native Rack picker. This is the same authoritative bag scan used by the
-- gossip picker: carried weapon/armor entries only, excluding entries already
-- tracked or fully attuned. Names stay client-local (GetItemInfo) so the wire
-- grammar never has to escape localized punctuation.
function AP.Protocol.BuildRackCandidates(player, limit)
    local result, seen, onRack, attuned = {}, {}, {}, {}
    if not player or not AP.Rack then return result end
    local guid = AP.RT.GetGUID(player)
    if not AP.Rack.Cache[guid] then AP.Rack.Load(guid) end
    local cache = type(AP.Rack.Cache[guid]) == "table" and AP.Rack.Cache[guid] or {}
    for _, row in pairs(cache) do
        if row and row.item_entry and row.item_entry > 0 then onRack[row.item_entry] = true end
    end
    local aq = AP.DB.Query(string.format(
        "SELECT `item_entry` FROM `ap_item_attune` WHERE `guid` = %d AND `attuned` = 1", guid))
    if aq then repeat
        local entry = tonumber(tostring(aq:GetUInt32(0))) or 0
        if entry > 0 then attuned[entry] = true end
    until not aq:NextRow() end
    local function scan(bag, slot)
        local item
        pcall(function() item = AP.RT.GetItemByPos(player, bag, slot) end)
        if not item then return end
        local entry = 0
        pcall(function() entry = AP.RT.GetItemEntry(item) end)
        if entry <= 0 or seen[entry] or onRack[entry] or attuned[entry] then return end
        seen[entry] = true
        local q = AP.DB.WorldQuery(string.format(
            "SELECT `Quality`,`class`,`InventoryType` FROM `item_template` WHERE `entry` = %d LIMIT 1", entry))
        if not q then return end
        local quality = tonumber(tostring(q:GetUInt8(0))) or 1
        local class = tonumber(tostring(q:GetUInt8(1))) or 0
        local inventoryType = tonumber(tostring(q:GetUInt32(2))) or 0
        if (class == 2 or class == 4) and inventoryType > 0 then
            result[#result + 1] = { entry=entry, quality=quality }
        end
    end
    for slot=23,38 do scan(255,slot) end
    for bag=19,22 do for slot=0,35 do scan(bag,slot) end end
    table.sort(result,function(a,b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.entry < b.entry
    end)
    while #result > (limit or 10) do table.remove(result) end
    return result
end

function AP.Protocol.BuildForgeEligible(player,limit)
    local result,equipped={},{}
    if not player or not (AP.Forge and AP.Forge.Rewards) then return result end
    local guid,accountId=AP.RT.GetGUID(player),AP.RT.GetAccountId(player)
    pcall(function() for slot=0,18 do local item=AP.RT.GetEquippedItem(player,slot); if item then equipped[AP.RT.GetItemEntry(item)]=true end end end)
    local q=AP.DB.Query(string.format(
        "SELECT a.item_entry,s.quality FROM ap_item_attune a "..
        "JOIN ap_item_snapshot s ON s.guid = %d AND s.item_entry = a.item_entry "..
        "LEFT JOIN ap_dissolved_items d ON d.account_id = %d AND d.item_entry = a.item_entry "..
        "WHERE a.guid = %d AND a.attuned = 1 AND d.account_id IS NULL "..
        "ORDER BY s.quality DESC,a.item_entry ASC",accountId,accountId,guid))
    if q then repeat
        local entry=tonumber(tostring(q:GetUInt32(0))) or 0
        local quality=tonumber(tostring(q:GetUInt32(1))) or 1
        if entry>0 and not equipped[entry] then
            local item; pcall(function() item=AP.RT.GetItemByEntry(player,entry) end)
            local wq=item and AP.DB.WorldQuery(string.format(
                "SELECT `class`,`InventoryType` FROM `item_template` WHERE `entry` = %d",entry)) or nil
            if wq then
                local class=tonumber(tostring(wq:GetUInt8(0))) or 0
                local inventoryType=tonumber(tostring(wq:GetUInt32(1))) or 0
                if (class==2 or class==4) and inventoryType>0 then
                    local rewards=AP.Forge.Rewards[quality] or AP.Forge.Rewards[1]
                    result[#result+1]={entry=entry,quality=quality,essence=rewards.essence,gold=rewards.gold,residue=rewards.residue}
                end
            end
        end
    until not q:NextRow() or #result>=(limit or 8) end
    return result
end

AP.Protocol.VisagePreviews=AP.Protocol.VisagePreviews or {}
local VISAGE_THEMES={worldsoul=true,ethereal=true,verdant=true,void=true,infernal=true}
local function VisageSnapshot(player)
    if not player or not AP.Visage then return nil end
    local guid,accountId=AP.RT.GetGUID(player),AP.RT.GetAccountId(player)
    if not AP.Visage.Cache[guid] then AP.Visage.LoadForChar(guid) end
    local c=AP.Visage.Cache[guid]
    local attuned=AP.Visage.GetAttunedCount(guid); local invested=AP.Visage.GetTotalCrucibleInvested(accountId)
    local pmax=AP.Visage.GetPrimaryTier(attuned); local smax=AP.Visage.GetSecondaryTier(invested)
    local unlocked={}; for _,theme in ipairs(AP.Visage.ThemeOrder or {}) do if AP.Visage.IsThemeUnlocked(theme,attuned) then unlocked[#unlocked+1]=theme end end
    return {guid=guid,attuned=attuned,invested=invested,primaryMax=pmax,secondaryMax=smax,unlocked=unlocked,
        primaryTheme=c.primary_theme,primaryEnabled=c.primary_enabled,primarySelected=c.primary_tier_selected or 0,primaryEffective=AP.Visage.GetEffectiveTier(c.primary_tier_selected,pmax),
        secondaryTheme=c.secondary_theme,secondaryEnabled=c.secondary_enabled,secondarySelected=c.secondary_tier_selected or 0,secondaryEffective=AP.Visage.GetEffectiveTier(c.secondary_tier_selected,smax),
        flash=c.flash_enabled,lore=c.chat_flavor_enabled}
end
local function RestoreVisage(player,guid)
    AP.Protocol.VisagePreviews[guid]=nil
    if AP.Visage and AP.Visage.ApplyAuras then pcall(AP.Visage.ApplyAuras,player) end
end
local function ApplyVisagePreviewAuras(player,draft)
    for spellId in pairs(AP.Visage.AllSpellIds or {}) do pcall(function() AP.RT.RemoveAura(player,spellId) end) end
    local function add(layer)
        if layer.enabled~=1 or layer.effective<=0 then return end
        local spells=AP.Visage.ThemeSpells[layer.theme]; local spell=spells and spells[layer.effective]
        if spell then pcall(function() AP.RT.AddAura(player,spell,player) end) end
    end
    if draft.mode~="secondary" then add(draft.primary) end
    if draft.mode~="primary" then add(draft.secondary) end
end
local function VisagePreviewRequest(player,tokens)
    local state=VisageSnapshot(player); if not state then return nil,"UNAVAILABLE" end
    local mode=tokens[4]; if mode~="combined" and mode~="primary" and mode~="secondary" then return nil,"INVALID_MODE" end
    local pt,st=tokens[5],tokens[8]; local ps,pe=tonumber(tokens[6]),tonumber(tokens[7]); local ss,se=tonumber(tokens[9]),tonumber(tokens[10])
    if not VISAGE_THEMES[pt] or not VISAGE_THEMES[st] or not ps or not ss or (pe~=0 and pe~=1) or (se~=0 and se~=1) then return nil,"MALFORMED" end
    if not AP.Visage.IsThemeUnlocked(pt,state.attuned) or not AP.Visage.IsThemeUnlocked(st,state.attuned) then return nil,"THEME_LOCKED" end
    if ps<0 or ps>5 or ps~=math.floor(ps) or ss<0 or ss>5 or ss~=math.floor(ss) then return nil,"INVALID_TIER" end
    if (ps>0 and ps>state.primaryMax) or (ss>0 and ss>state.secondaryMax) then return nil,"TIER_LOCKED" end
    return {guid=state.guid,mode=mode,primary={theme=pt,selected=ps,enabled=pe,effective=AP.Visage.GetEffectiveTier(ps,state.primaryMax)},secondary={theme=st,selected=ss,enabled=se,effective=AP.Visage.GetEffectiveTier(ss,state.secondaryMax)}},nil
end

-- ============================================================
-- HELLO / WELCOME (handshake)
-- Client -> "#ap hello <clientProtocolVersion> <capsCSV>"
-- Server -> "[ECHOES]WELCOME|server_version=...|protocol_version=...|caps=..."
--        or "[ECHOES]ERROR|code=INCOMPATIBLE_VERSION|..." on a hard mismatch
-- Compatibility rule (kept simple per spec): the client's protocol
-- version must equal AP.PROTOCOL_VERSION exactly for structured_state
-- to be usable. A mismatch does not error out silently — it responds
-- with WELCOME's fields still populated (so the client can show an
-- accurate "server is at protocol N" message) but with compatible=0,
-- letting the client itself decide to fall back rather than the server
-- guessing what an unknown future client should do.
-- ============================================================
local function HandleHello(player, guid, tokens)
    if RateLimited(guid, "hello") then
        SendError(player, "RATE_LIMITED", "hello")
        return
    end

    local clientProtocolVersion = tonumber(tokens[3])
    local capsCSV = tokens[4] or ""
    if not clientProtocolVersion then
        SendError(player, "MALFORMED", "hello requires <protocol_version> <caps>")
        return
    end

    local compatible = (clientProtocolVersion == AP.PROTOCOL_VERSION) and 1 or 0

    local capsStr = table.concat(AP.Protocol.ServerCapabilities, ",")
    SendEchoes(player, "WELCOME", {
        { "server_version", AP.VERSION or "0.0.0" },
        { "protocol_version", AP.PROTOCOL_VERSION },
        { "compatible", compatible },
        { "caps", capsStr },
    })

    AP.Log("[Protocol] HELLO from guid=" .. guid ..
        " client_protocol=" .. tostring(clientProtocolVersion) ..
        " client_caps=" .. capsCSV .. " compatible=" .. compatible)
end

-- ============================================================
-- STATE
-- Client -> "#ap state"
-- Server -> "[ECHOES]STATE|essence=...|mastery_rank=...|absorb_pct=...|
--            attuned=...|snapshots=...|residue=...|rack_used=...|
--            rack_cap=...|mastery_next_cost=...|slots=<slot>:<xp>,...|
--            absorbed_stats=<str>/<agi>/<sta>/<int>/<spi>|
--            talents=<idx>:<rank>,...|crucible=<cat>:<inv>,..."
--
-- Every field below reuses the exact query/helper AP.Commands.Status
-- (ap_commands.lua) already uses for the equivalent gossip/chat
-- display — this function does not invent new formulas, it packages
-- the same authoritative reads into a structured payload instead of a
-- colored chat string.
-- ============================================================
function AP.Protocol.BuildState(player)
    local guid      = AP.RT.GetGUID(player)
    local accountId = AP.RT.GetAccountId(player)

    local aether, mastery, chaosEnabled = 0, 0, false
    local q = AP.DB.Query(string.format(
        "SELECT `aether`, `mastery`, `chaos_enabled` FROM `ap_mastery` WHERE `guid` = %d", guid
    ))
    if q then
        aether  = AP.DB.GetUInt64(q, 0)
        mastery = tonumber(tostring(q:GetUInt32(1))) or 0
        chaosEnabled = (tonumber(tostring(q:GetUInt32(2))) or 0) == 1
    end

    local masteryNextCost = 0
    if AP.MasteryCost then masteryNextCost = AP.MasteryCost(mastery) or 0 end

    local attuned = 0
    local qa = AP.DB.Query(string.format(
        "SELECT COUNT(*) FROM `ap_item_attune` WHERE `guid` = %d AND `attuned` = 1", guid
    ))
    if qa then attuned = tonumber(tostring(qa:GetUInt32(0))) or 0 end

    local snaps = 0
    local qs = AP.DB.Query(string.format(
        "SELECT COUNT(*) FROM `ap_item_snapshot` WHERE `guid` = %d", accountId
    ))
    if qs then snaps = tonumber(tostring(qs:GetUInt32(0))) or 0 end

    local absorbPct = 0
    if AP.GetAbsorption then
        absorbPct = AP.GetAbsorption(mastery) * 100
    end

    local absorbed = { str=0, agi=0, sta=0, ["int"]=0, spi=0 }
    if AP.CalculateAbsorptionAccountWide and AP.RT.GetClass and AP.RT.GetLevel then
        absorbed = AP.CalculateAbsorptionAccountWide(
            guid, AP.RT.GetClass(player), AP.RT.GetLevel(player), mastery) or absorbed
    end

    local slotParts = {}
    if AP.LoadSlotXP then
        for _, slot in ipairs({0,1,2,4,5,6,7,8,9,10,11,12,13,14,15,16,17}) do
            local xp = tonumber(AP.LoadSlotXP(guid, slot)) or 0
            if xp > 0 then slotParts[#slotParts + 1] = slot .. ":" .. math.floor(xp) end
        end
    end

    local residue = 0
    if AP.Forge and AP.Forge.GetVerifiedResidue then
        local residueOk, residueVal = AP.Forge.GetVerifiedResidue(accountId)
        if residueOk then residue = residueVal or 0 end
    end

    local rackUsed, rackCap = 0, 0
    local rackEntries, rackCandidates = {}, {}
    if AP.Rack and AP.Rack.GetCapacity then
        local cap = AP.Rack.GetCapacity(guid)
        rackCap = cap or 0
    end
    if AP.Rack and AP.Rack.GetEntries then
        -- GetEntries reads AP.Rack.Cache[guid], which is only populated by
        -- AP.Rack.Load — matching the established pre-condition used at
        -- every other GetEntries/cache call site in ap_rack.lua (e.g. the
        -- AddItem/RemoveItem paths), so a player who hasn't opened the Rack
        -- UI yet this session still gets an accurate count here.
        if not AP.Rack.Cache[guid] then AP.Rack.Load(guid) end
        local entries = AP.Rack.GetEntries(guid)
        if entries then rackUsed = #entries end
        local rackCache = type(AP.Rack.Cache[guid]) == "table" and AP.Rack.Cache[guid] or {}
        for slotIndex,row in pairs(rackCache) do
            if row and row.item_entry and row.item_entry > 0 then
                rackEntries[#rackEntries + 1] = {
                    slot=slotIndex, entry=row.item_entry, quality=row.item_quality or 1,
                }
            end
        end
        table.sort(rackEntries,function(a,b) return a.slot < b.slot end)
        rackCandidates = AP.Protocol.BuildRackCandidates(player,10)
    end

    local rackEntryParts, rackCandidateParts = {}, {}
    for _,row in ipairs(rackEntries) do
        rackEntryParts[#rackEntryParts + 1] = row.slot .. ":" .. row.entry .. ":" .. row.quality
    end
    for _,row in ipairs(rackCandidates) do
        rackCandidateParts[#rackCandidateParts + 1] = row.entry .. ":" .. row.quality
    end
    local rackNextSlots, rackNextEssenceCost, rackNextResidueCost, rackAtMax = 0,0,0,0
    if AP.API and AP.API.PreviewRackExpand then
        local ok, preview = pcall(AP.API.PreviewRackExpand,player)
        if ok and preview and preview.ok then
            rackAtMax = preview.atMaxCapacity and 1 or 0
            rackNextSlots = preview.nextSlots or preview.currentSlots or rackCap
            rackNextEssenceCost = preview.essenceCost or 0
            rackNextResidueCost = preview.residueCost or 0
        end
    end

    local forgeParts={}
    for _,row in ipairs(AP.Protocol.BuildForgeEligible(player,8)) do
        forgeParts[#forgeParts+1]=table.concat({row.entry,row.quality,row.essence,row.gold,row.residue},":")
    end
    local forgeCatalystStatus,forgeCatalystCost,forgeCatalystReward="UNAVAILABLE",0,0
    local forgeCatalystExpectedResidue,forgeCatalystExpectedEssence=0,0
    if AP.Forge and AP.Forge.PreviewCatalyst then
        local ok,preview=pcall(AP.Forge.PreviewCatalyst,player)
        if ok and preview and preview.ok then
            forgeCatalystStatus=preview.status or "UNAVAILABLE"; forgeCatalystCost=preview.cost or 0; forgeCatalystReward=preview.reward or 0
            forgeCatalystExpectedResidue=preview.expectedResidue or 0; forgeCatalystExpectedEssence=preview.expectedEssence or 0
        end
    end
    local visage=VisageSnapshot(player)

    local talentSnapshot = AP.BuildTalentSnapshot(AP.LoadTalents(guid))
    local talentParts, talentRoleParts, talentBonusParts = {}, {}, {}
    local talentCostParts, talentNextBonusParts, talentMaxParts = {}, {}, {}
    for statIndex = 0, 4 do
        local stat = talentSnapshot.stats[statIndex]
        talentParts[#talentParts + 1] = statIndex .. ":" .. stat.rank
        talentRoleParts[#talentRoleParts + 1] = statIndex .. ":" .. stat.role
        talentBonusParts[#talentBonusParts + 1] = statIndex .. ":" .. string.format("%.1f",stat.bonusPct)
        talentCostParts[#talentCostParts + 1] = statIndex .. ":" .. stat.nextCost
        talentNextBonusParts[#talentNextBonusParts + 1] = statIndex .. ":" .. string.format("%.1f",stat.nextBonusPct)
        talentMaxParts[#talentMaxParts + 1] = statIndex .. ":" .. stat.maxRank
    end

    local crucibleInvested = {}
    local sq = AP.DB.Query(string.format(
        "SELECT `category`, `invested` FROM `ap_aether_sinks` WHERE `account_id` = %d "..
        "ORDER BY `invested` DESC",
        accountId
    ))
    if sq then
        repeat
            local cat = sq:GetString(0)
            local inv = tonumber(tostring(sq:GetUInt32(1))) or 0
            crucibleInvested[cat] = inv
        until not sq:NextRow()
    end

    local crucibleParts, crucibleStatusParts = {}, {}
    local crucibleEffectParts, crucibleCeilingParts = {}, {}
    local crucibleTotal = 0
    for _, cat in ipairs(AP.SinkOrder or {}) do
        local def = AP.SinkDefs and AP.SinkDefs[cat]
        -- threat_reduction is intentionally absent: active=false means no
        -- visible node, tease, or purchasable socket in the native contract.
        if def and def.active ~= false then
            local inv = crucibleInvested[cat] or 0
            local effect = AP.Sinks and AP.Sinks.GetEffect and AP.Sinks.GetEffect(cat, inv) or 0
            local status = AP.Sinks and AP.Sinks.GetStatus and AP.Sinks.GetStatus(cat, inv) or "UNAVAILABLE"
            crucibleParts[#crucibleParts + 1] = cat .. ":" .. inv
            crucibleStatusParts[#crucibleStatusParts + 1] = cat .. ":" .. status
            crucibleEffectParts[#crucibleEffectParts + 1] = cat .. ":" .. string.format("%.4f", effect * 100)
            crucibleCeilingParts[#crucibleCeilingParts + 1] = cat .. ":" .. string.format("%.2f", (def.ceiling or 0) * 100)
            crucibleTotal = crucibleTotal + inv
        end
    end

    local threat = AP.API and AP.API.GetWorldThreatSnapshot
        and AP.API.GetWorldThreatSnapshot(player) or {ok=false}

    local fields = {
        { "essence", aether },
        { "mastery_rank", mastery },
        { "absorb_pct", string.format("%.1f", absorbPct) },
        { "mastery_next_cost", masteryNextCost },
        { "slots", table.concat(slotParts, ",") },
        { "absorbed_stats", string.format("%.1f/%.1f/%.1f/%.1f/%.1f",
            absorbed.str or 0, absorbed.agi or 0, absorbed.sta or 0,
            absorbed["int"] or 0, absorbed.spi or 0) },
        { "attuned", attuned },
        { "snapshots", snaps },
        { "residue", residue },
        { "rack_used", rackUsed },
        { "rack_cap", rackCap },
        { "rack_entries", table.concat(rackEntryParts, ",") },
        { "rack_candidates", table.concat(rackCandidateParts, ",") },
        { "rack_next_slots", rackNextSlots },
        { "rack_next_essence_cost", rackNextEssenceCost },
        { "rack_next_residue_cost", rackNextResidueCost },
        { "rack_at_max", rackAtMax },
        { "forge_eligible", table.concat(forgeParts,",") },
        { "forge_catalyst_status", forgeCatalystStatus },
        { "forge_catalyst_cost", forgeCatalystCost },
        { "forge_catalyst_reward", forgeCatalystReward },
        { "forge_catalyst_expected_residue", forgeCatalystExpectedResidue },
        { "forge_catalyst_expected_essence", forgeCatalystExpectedEssence },
        { "talents", table.concat(talentParts, ",") },
        { "talent_primary_stat", talentSnapshot.primary == nil and "none" or talentSnapshot.primary },
        { "talent_role", table.concat(talentRoleParts, ",") },
        { "talent_bonus_pct", table.concat(talentBonusParts, ",") },
        { "talent_next_rank_cost", table.concat(talentCostParts, ",") },
        { "talent_next_bonus_pct", table.concat(talentNextBonusParts, ",") },
        { "talent_max_rank", table.concat(talentMaxParts, ",") },
        { "talent_distinct_stats", talentSnapshot.distinct },
        { "talent_distinct_penalty_pct", string.format("%.1f",talentSnapshot.penalty * 100) },
        { "crucible", table.concat(crucibleParts, ",") },
        { "crucible_status", table.concat(crucibleStatusParts, ",") },
        { "crucible_effect_pct", table.concat(crucibleEffectParts, ",") },
        { "crucible_ceiling_pct", table.concat(crucibleCeilingParts, ",") },
        { "crucible_total_invested", crucibleTotal },
    }
    local chaos = AP.Chaos.BuildReading(chaosEnabled, attuned, mastery, crucibleTotal)
    local chaosFields = {
        {"chaos_enabled",chaos.enabled and 1 or 0},{"chaos_power",chaos.power},
        {"chaos_magnitude",chaos.magnitude},{"chaos_scale",chaos.scale},
        {"chaos_ruleset",chaos.ruleset},{"chaos_base",chaos.base},
        {"chaos_attunement_basis",chaos.attuned},{"chaos_attunement_contribution",chaos.attunementContribution},
        {"chaos_mastery_rank",chaos.masteryRank},{"chaos_mastery_basis",chaos.masteryBasis},
        {"chaos_mastery_contribution",chaos.masteryContribution},{"chaos_crucible_basis",chaos.crucibleBasis},
        {"chaos_crucible_contribution",chaos.crucibleContribution},
    }
    for _,pair in ipairs(chaosFields) do fields[#fields+1]=pair end
    if threat.ok then
        local threatFields = {
            {"threat_level",threat.level},{"threat_name",threat.name},{"threat_max",threat.maximum},
            {"threat_ceiling_pct",string.format("%.1f",threat.ceilingPct)},
            {"threat_momentum_pct",string.format("%.1f",threat.momentumPct)},
            {"threat_effective_pct",string.format("%.1f",threat.effectivePct)},
            {"threat_safety_pct",string.format("%.1f",threat.safetyPct)},
            {"threat_debt_kills",threat.debtKills},{"threat_debt_mult_pct",string.format("%.1f",threat.debtMultPct)},
            {"threat_attune_loss_pct",string.format("%.1f",threat.attuneLossPct)},
            {"threat_essence_loss_pct",string.format("%.1f",threat.essenceLossPct)},
            {"threat_essence_cap",threat.essenceCap},{"threat_penalty_debt_kills",threat.penaltyDebtKills},
            {"threat_penalty_debt_mult_pct",string.format("%.1f",threat.penaltyDebtMultPct)},
            {"threat_cap_normal_pct",string.format("%.1f",threat.capNormalPct)},
            {"threat_cap_elite_pct",string.format("%.1f",threat.capElitePct)},
            {"threat_cap_boss_pct",string.format("%.1f",threat.capBossPct)},
            {"threat_cap_raid_pct",string.format("%.1f",threat.capRaidPct)},
        }
        for _,pair in ipairs(threatFields) do fields[#fields+1] = pair end
    end
    if visage then
        local visageFields={{"visage_primary_theme",visage.primaryTheme},{"visage_primary_enabled",visage.primaryEnabled},{"visage_primary_tier_selected",visage.primarySelected},{"visage_primary_tier_effective",visage.primaryEffective},{"visage_primary_tier_max",visage.primaryMax},{"visage_secondary_theme",visage.secondaryTheme},{"visage_secondary_enabled",visage.secondaryEnabled},{"visage_secondary_tier_selected",visage.secondarySelected},{"visage_secondary_tier_effective",visage.secondaryEffective},{"visage_secondary_tier_max",visage.secondaryMax},{"visage_themes_unlocked",table.concat(visage.unlocked,",")},{"visage_flash_enabled",visage.flash},{"visage_chat_flavor_enabled",visage.lore},{"visage_attuned_count",visage.attuned},{"visage_crucible_invested",visage.invested},{"visage_preview_active",AP.Protocol.VisagePreviews[visage.guid] and 1 or 0}}
        for _,pair in ipairs(visageFields) do fields[#fields+1]=pair end
    end
    return fields
end

local function HandleState(player, guid, tokens)
    if RateLimited(guid, "state") then
        SendError(player, "RATE_LIMITED", "state")
        return
    end
    local fields = AP.Protocol.BuildState(player)
    SendEchoes(player, "STATE", fields)
end

-- ============================================================
-- ACTION (minimum write-contract proof)
-- Client -> "#ap action <name>"
-- Server -> "[ECHOES]ACTION_OK|action=...|<result fields>"
--        or "[ECHOES]ERROR|code=...|message=..."
--
-- The baseline preview_catalyst action plus additive native-screen actions route
-- through the EXISTING, already-guarded AP.Forge.PreviewCatalyst
-- service — this file does not duplicate any cost/eligibility logic,
-- it only packages that service's own return value. Chosen specifically
-- because it is read-only (a preview, not a purchase) per the
-- authorization's explicit "request current cost" example — this proves
-- the request -> validate -> existing guarded service -> authoritative
-- result contract without any real currency mutation risk.
-- ============================================================
local KNOWN_ACTIONS = {
    preview_catalyst = true,
    mastery_purchase = true,
    threat_increase = true,
    threat_decrease = true,
    threat_reset = true,
    crucible_preview = true,
    crucible_invest = true,
    talent_preview = true,
    talent_purchase = true,
    rack_add = true,
    rack_remove = true,
    rack_expand = true,
    forge_dissolve = true,
    forge_purchase_catalyst = true,
    visage_preview = true,
    visage_apply = true,
    visage_cancel = true,
    visage_notifications = true,
    chaos_toggle = true,
}

local CRUCIBLE_AMOUNTS = { [1000]=true, [5000]=true, [10000]=true, [50000]=true, [100000]=true }

local function CrucibleRequest(tokens)
    local category = tokens[4]
    local amount = tonumber(tokens[5])
    local def = category and AP.SinkDefs and AP.SinkDefs[category]
    if not def or def.active == false then return nil, nil, "INVALID_CATEGORY" end
    if not amount or amount ~= math.floor(amount) or not CRUCIBLE_AMOUNTS[amount] then
        return nil, nil, "INVALID_AMOUNT"
    end
    return category, amount, nil
end

local function CurrentSinkInvestment(accountId, category)
    local q = AP.DB.Query(string.format(
        "SELECT `invested` FROM `ap_aether_sinks` WHERE `account_id` = %d AND `category` = '%s'",
        accountId, category
    ))
    if not q then return 0 end
    return tonumber(tostring(q:GetUInt32(0))) or 0
end

local function TalentRequest(tokens)
    local statIndex = tonumber(tokens[4])
    if not statIndex or statIndex ~= math.floor(statIndex) or statIndex < 0 or statIndex > 4 then
        return nil, "INVALID_STAT"
    end
    return statIndex, nil
end

local function PositiveInteger(value)
    value=tonumber(value)
    if not value or value ~= math.floor(value) or value <= 0 then return nil end
    return value
end

local function HandleAction(player, guid, tokens)
    local name = tokens[3]
    if not name or not KNOWN_ACTIONS[name] then
        SendError(player, "UNKNOWN_ACTION", tostring(name))
        return
    end

    local rateClass = (name == "crucible_preview" or name == "talent_preview" or name == "visage_preview") and "preview"
        or ((name == "visage_apply" or name == "visage_cancel") and "visage_commit" or "action")
    if RateLimited(guid, rateClass) then
        SendError(player, "RATE_LIMITED", rateClass)
        return
    end

    if name == "visage_preview" then
        local draft,err=VisagePreviewRequest(player,tokens); if not draft then SendError(player,err,name); return end
        draft.token=(AP.Protocol.VisagePreviews[guid] and AP.Protocol.VisagePreviews[guid].token or 0)+1; AP.Protocol.VisagePreviews[guid]=draft; ApplyVisagePreviewAuras(player,draft)
        pcall(function() player:RegisterEvent(function(_,_,_,livePlayer) local current=AP.Protocol.VisagePreviews[guid]; if current and current.token==draft.token then RestoreVisage(livePlayer or player,guid); SendEchoes(livePlayer or player,"ACTION_OK",{{"action","visage_cancel"},{"status","EXPIRED"}}) end end,30000,1) end)
        SendEchoes(player,"ACTION_OK",{{"action",name},{"status","PREVIEWING"},{"mode",draft.mode},{"expires_ms",30000},{"primary_effective",draft.primary.effective},{"secondary_effective",draft.secondary.effective}})
    elseif name == "chaos_toggle" then
        local enabled = tonumber(tokens[4])
        if enabled ~= 0 and enabled ~= 1 then SendError(player,"MALFORMED",name); return end
        local ok = AP.DB.ExecuteCritical(string.format(
            "INSERT INTO `ap_mastery` (`guid`,`aether`,`mastery`,`chaos_enabled`) VALUES (%d,0,0,%d) "..
            "ON DUPLICATE KEY UPDATE `chaos_enabled`=%d", guid, enabled, enabled), "AP.Chaos.Toggle")
        if not ok then SendError(player,"DATABASE_FAILURE",name); return end
        SendEchoes(player,"ACTION_OK",{{"action",name},{"status","SUCCESS"},{"enabled",enabled}})
    elseif name == "visage_apply" then
        local draft=AP.Protocol.VisagePreviews[guid]; if not draft then SendError(player,"NO_PREVIEW",name); return end
        if not AP.Visage.Cache[guid] then AP.Visage.LoadForChar(guid) end; local c=AP.Visage.Cache[guid]
        c.primary_theme=draft.primary.theme; c.primary_tier_selected=draft.primary.selected; c.primary_enabled=draft.primary.enabled; c.secondary_theme=draft.secondary.theme; c.secondary_tier_selected=draft.secondary.selected; c.secondary_enabled=draft.secondary.enabled
        AP.Visage.SaveForChar(guid); AP.Protocol.VisagePreviews[guid]=nil; AP.Visage.ApplyAuras(player)
        SendEchoes(player,"ACTION_OK",{{"action",name},{"status","SUCCESS"}})
    elseif name == "visage_cancel" then
        RestoreVisage(player,guid); SendEchoes(player,"ACTION_OK",{{"action",name},{"status","CANCELLED"}})
    elseif name == "visage_notifications" then
        local flash,lore=tonumber(tokens[4]),tonumber(tokens[5]); if (flash~=0 and flash~=1) or (lore~=0 and lore~=1) then SendError(player,"MALFORMED",name); return end
        if not AP.Visage.Cache[guid] then AP.Visage.LoadForChar(guid) end; AP.Visage.Cache[guid].flash_enabled=flash; AP.Visage.Cache[guid].chat_flavor_enabled=lore; AP.Visage.SaveForChar(guid)
        SendEchoes(player,"ACTION_OK",{{"action",name},{"status","SUCCESS"},{"flash",flash},{"lore",lore}})
    elseif name == "forge_dissolve" then
        local entry=PositiveInteger(tokens[4])
        if not entry or not (AP.Forge and AP.Forge.DissolveDirect) then SendError(player,"UNAVAILABLE",name); return end
        local ok,result=pcall(AP.Forge.DissolveDirect,player,entry)
        if not ok or not result then SendError(player,"SERVER_ERROR",name); return end
        SendEchoes(player,"ACTION_OK",{{"action",name},{"status",result.success and "SUCCESS" or "REJECTED"},{"reason",result.reasonCode or ""},{"item_entry",entry},{"quality",result.quality or 0},{"essence_reward",result.essence or 0},{"gold_reward",result.gold or 0},{"residue_reward",result.residue or 0},{"recoverable",result.recoverable and 1 or 0}})
    elseif name == "forge_purchase_catalyst" then
        if not (AP.Forge and AP.Forge.PreviewCatalyst and AP.Forge.PurchaseCatalyst) then SendError(player,"UNAVAILABLE",name); return end
        local okPreview,preview=pcall(AP.Forge.PreviewCatalyst,player)
        if not okPreview or not preview or not preview.ok then SendError(player,"SERVER_ERROR",name); return end
        if preview.status~="READY" then SendEchoes(player,"ACTION_OK",{{"action",name},{"status",preview.status or "REJECTED"}}); return end
        local ok,result=pcall(AP.Forge.PurchaseCatalyst,player,preview.expectedResidue,preview.expectedEssence)
        if not ok or not result then SendError(player,"SERVER_ERROR",name); return end
        SendEchoes(player,"ACTION_OK",{{"action",name},{"status",result.status or (result.ok and "SUCCESS" or "REJECTED")},{"cost",result.cost or preview.cost or 0},{"reward",result.reward or preview.reward or 0},{"new_residue",result.newBalance or preview.expectedResidue},{"new_essence",result.newEssence or preview.expectedEssence}})
    elseif name == "rack_add" then
        local entry=PositiveInteger(tokens[4])
        if not entry or not (AP.Rack and AP.Rack.AddItem) then SendError(player,"UNAVAILABLE",name); return end
        local ok,result=pcall(AP.Rack.AddItem,player,entry)
        SendEchoes(player,"ACTION_OK",{{"action",name},{"status",ok and result and "SUCCESS" or "REJECTED"},{"item_entry",entry}})
    elseif name == "rack_remove" then
        local slot=PositiveInteger(tokens[4])
        if not slot or not (AP.Rack and AP.Rack.RemoveItem) then SendError(player,"UNAVAILABLE",name); return end
        if not AP.Rack.Cache[guid] then AP.Rack.Load(guid) end
        local row=AP.Rack.Cache[guid] and AP.Rack.Cache[guid][slot]
        local entry=row and row.item_entry or 0
        local ok,result=pcall(AP.Rack.RemoveItem,player,slot)
        SendEchoes(player,"ACTION_OK",{{"action",name},{"status",ok and result and "SUCCESS" or "REJECTED"},{"slot",slot},{"item_entry",entry}})
    elseif name == "rack_expand" then
        if not (AP.API and AP.API.PreviewRackExpand and AP.API.ExecuteRackExpand) then SendError(player,"UNAVAILABLE",name); return end
        local okPreview,preview=pcall(AP.API.PreviewRackExpand,player)
        if not okPreview or not preview or not preview.ok then SendError(player,"SERVER_ERROR",name); return end
        if preview.atMaxCapacity then SendEchoes(player,"ACTION_OK",{{"action",name},{"status","AT_MAX"}}); return end
        local residueArg=preview.residueCost and preview.residueCost>0 and preview.expectedResidue or nil
        local ok,result=pcall(AP.API.ExecuteRackExpand,player,preview.currentSlots,preview.nextSlots,residueArg,preview.expectedEssence)
        if not ok or not result then SendError(player,"SERVER_ERROR",name); return end
        SendEchoes(player,"ACTION_OK",{{"action",name},{"status",result.status or (result.ok and "SUCCESS" or "REJECTED")},{"old_slots",result.oldSlots or preview.currentSlots},{"new_slots",result.newSlots or preview.nextSlots},{"cost",result.cost or preview.essenceCost or preview.residueCost or 0}})
    elseif name == "talent_preview" then
        local statIndex, requestError = TalentRequest(tokens)
        if requestError then SendError(player,requestError,name); return end
        if not (AP.API and AP.API.PreviewTalentPurchase) then
            SendError(player,"UNAVAILABLE",name); return
        end
        local pcallOk, result = pcall(AP.API.PreviewTalentPurchase,player,statIndex)
        if not pcallOk or not result then SendError(player,"SERVER_ERROR",name); return end
        if result.status == "INVALID_STAT" then SendError(player,"INVALID_STAT",name); return end
        local current = result.current and result.current.stats[statIndex]
        local projected = result.projected and result.projected.stats[statIndex]
        if not current then SendError(player,"SERVER_ERROR",name); return end
        SendEchoes(player,"ACTION_OK",{
            {"action",name},{"status",result.status or "UNAVAILABLE"},{"stat_index",statIndex},
            {"cost",result.cost or current.nextCost or 0},{"affordable",result.affordable and 1 or 0},
            {"current_rank",current.rank},{"projected_rank",projected and projected.rank or current.rank},
            {"current_role",current.role},{"projected_role",projected and projected.role or current.role},
            {"current_bonus_pct",string.format("%.1f",current.bonusPct)},
            {"projected_bonus_pct",string.format("%.1f",projected and projected.bonusPct or current.bonusPct)},
            {"current_primary_stat",result.current.primary == nil and "none" or result.current.primary},
            {"projected_primary_stat",result.projected and (result.projected.primary == nil and "none" or result.projected.primary) or (result.current.primary == nil and "none" or result.current.primary)},
            {"current_penalty_pct",string.format("%.1f",result.current.penalty*100)},
            {"projected_penalty_pct",string.format("%.1f",result.projected and result.projected.penalty*100 or result.current.penalty*100)},
            {"current_distinct",result.current.distinct},{"projected_distinct",result.projected and result.projected.distinct or result.current.distinct},
        })
    elseif name == "talent_purchase" then
        local statIndex, requestError = TalentRequest(tokens)
        if requestError then SendError(player,requestError,name); return end
        if not (AP.API and AP.API.ExecuteTalentPurchase) then SendError(player,"UNAVAILABLE",name); return end
        local pcallOk, result = pcall(AP.API.ExecuteTalentPurchase,player,statIndex)
        if not pcallOk or not result then SendError(player,"SERVER_ERROR",name); return end
        SendEchoes(player,"ACTION_OK",{
            {"action",name},{"status",result.status or "SERVICE_UNAVAILABLE"},{"stat_index",statIndex},
            {"old_rank",result.oldRank or 0},{"new_rank",result.newRank or result.oldRank or 0},
            {"cost",result.cost or 0},{"old_balance",result.oldBalance or 0},{"new_balance",result.newBalance or result.oldBalance or 0},
            {"old_primary_stat",result.oldPrimary == nil and "none" or result.oldPrimary},
            {"new_primary_stat",result.newPrimary == nil and "none" or result.newPrimary},
            {"old_penalty_pct",string.format("%.1f",(result.oldPenalty or 1)*100)},
            {"new_penalty_pct",string.format("%.1f",(result.newPenalty or result.oldPenalty or 1)*100)},
            {"old_bonus_pct",string.format("%.1f",result.oldBonusPct or 0)},
            {"new_bonus_pct",string.format("%.1f",result.newBonusPct or result.oldBonusPct or 0)},
        })
    elseif name == "crucible_preview" then
        local category, amount, requestError = CrucibleRequest(tokens)
        if requestError then SendError(player, requestError, name); return end
        if not (AP.API and AP.API.PreviewSinkInvest) then
            SendError(player, "UNAVAILABLE", name); return
        end
        local current = CurrentSinkInvestment(AP.RT.GetAccountId(player), category)
        local pcallOk, result = pcall(AP.API.PreviewSinkInvest, category, amount, current)
        if not pcallOk or not result or not result.ok then
            SendError(player, "SERVER_ERROR", name); return
        end
        SendEchoes(player, "ACTION_OK", {
            {"action",name},{"status","READY"},{"category",category},{"amount",amount},
            {"cost",result.cost or amount},{"current_invested",result.currentInvested or current},
            {"projected_invested",result.projectedInvested or (current + amount)},
            {"current_effect_pct",string.format("%.4f",(result.currentEffect or 0)*100)},
            {"projected_effect_pct",string.format("%.4f",(result.projectedEffectAtAmount or 0)*100)},
            {"ceiling_pct",string.format("%.2f",(result.ceiling or 0)*100)},
        })
    elseif name == "crucible_invest" then
        local category, amount, requestError = CrucibleRequest(tokens)
        if requestError then SendError(player, requestError, name); return end
        if not (AP.API and AP.API.ExecuteSinkInvest) then
            SendError(player, "UNAVAILABLE", name); return
        end
        local pcallOk, result = pcall(AP.API.ExecuteSinkInvest, player, category, amount)
        if not pcallOk or not result then SendError(player,"SERVER_ERROR",name); return end
        SendEchoes(player, "ACTION_OK", {
            {"action",name},{"status",result.ok and "SUCCESS" or "REJECTED"},
            {"category",category},{"amount",amount},{"reason",result.reason or ""},
        })
    elseif name == "mastery_purchase" then
        if not (AP.API and AP.API.ExecuteMasteryPurchase) then
            SendError(player, "UNAVAILABLE", "mastery_purchase")
            return
        end
        local pcallOk, result = pcall(AP.API.ExecuteMasteryPurchase, player)
        if not pcallOk or not result then
            SendError(player, "SERVER_ERROR", "mastery_purchase")
            return
        end
        SendEchoes(player, "ACTION_OK", {
            { "action", "mastery_purchase" },
            { "status", result.status or "INVALID_PLAYER" },
            { "old_rank", result.oldRank or 0 },
            { "new_rank", result.newRank or result.oldRank or 0 },
            { "cost", result.cost or 0 },
            { "old_balance", result.oldBalance or 0 },
            { "new_balance", result.newBalance or result.oldBalance or 0 },
        })
    elseif name == "threat_increase" or name == "threat_decrease" or name == "threat_reset" then
        if not (AP.API and AP.API.ExecuteWorldThreatAction) then
            SendError(player, "UNAVAILABLE", name)
            return
        end
        local operation = name == "threat_increase" and "increase"
            or (name == "threat_decrease" and "decrease" or "reset")
        local pcallOk, result = pcall(AP.API.ExecuteWorldThreatAction, player, operation)
        if not pcallOk or not result then SendError(player,"SERVER_ERROR",name); return end
        SendEchoes(player, "ACTION_OK", {
            {"action",name},{"status",result.status or "SERVICE_UNAVAILABLE"},
            {"old_level",result.oldLevel or 0},{"new_level",result.newLevel or result.oldLevel or 0},
            {"threat_name",result.name or ""},{"momentum_pct",string.format("%.1f",result.momentumPct or 0)},
        })
    elseif name == "preview_catalyst" then
        if not (AP.Forge and AP.Forge.PreviewCatalyst) then
            SendError(player, "UNAVAILABLE", "preview_catalyst")
            return
        end
        local pcallOk, result = pcall(AP.Forge.PreviewCatalyst, player)
        if not pcallOk or not result then
            SendError(player, "SERVER_ERROR", "preview_catalyst")
            return
        end
        if not result.ok then
            SendError(player, "UNAVAILABLE", result.status or "preview_catalyst")
            return
        end
        -- Field names/values are exactly AP.Forge.PreviewCatalyst's own
        -- return shape (cost/reward/expectedResidue/expectedEssence/status)
        -- — not renamed or recomputed, per the no-duplicated-formulas rule.
        SendEchoes(player, "ACTION_OK", {
            { "action", "preview_catalyst" },
            { "status", result.status },
            { "cost", result.cost or 0 },
            { "reward", result.reward or 0 },
            { "expected_residue", result.expectedResidue or 0 },
            { "expected_essence", result.expectedEssence or 0 },
            { "eligible", (result.status == "READY") and 1 or 0 },
        })
    end
end

-- ============================================================
-- DISPATCH
-- Registered on PLAYER_EVENT_ON_CHAT alongside the existing #ap
-- handlers in ap_commands.lua/ap_events.lua. Intercepts the structured
-- verbs (hello/state/action/codex); every other "#ap ..." subcommand is
-- left to the handlers that already own it.
-- ============================================================
local function OnProtocolChat(event, player, msg, msgType, lang)
    local lower = string.lower(msg)
    if not lower:find("^#ap%s") then return end

    local tokens = {}
    for t in msg:gmatch("%S+") do
        tokens[#tokens + 1] = t
    end
    local sub = string.lower(tokens[2] or "")
    local guid = AP.RT.GetGUID(player)

    if sub == "hello" then
        AP.Try(function() HandleHello(player, guid, tokens) end, "AP.Protocol hello")
        return false
    elseif sub == "state" then
        AP.Try(function() HandleState(player, guid, tokens) end, "AP.Protocol state")
        return false
    elseif sub == "action" then
        AP.Try(function() HandleAction(player, guid, tokens) end, "AP.Protocol action")
        return false
    elseif sub == "codex" then
        AP.Try(function()
            local operation = string.lower(tokens[3] or "")
            local topics = AP.Codex and AP.Codex.Topics
            if type(topics) ~= "table" then
                SendError(player, "UNAVAILABLE", "codex")
                return
            end
            if operation == "manifest" then
                if RateLimited(guid, "codex_manifest") then SendError(player, "RATE_LIMITED", "codex_manifest"); return end
                for topicIndex, topic in ipairs(topics) do
                    SendEchoes(player, "CODEX_TOPIC", {
                        {"topic", topicIndex}, {"title", EncodeText(topic.title)},
                        {"icon", topic.icon or 0}, {"pages", #(topic.pages or {})},
                    })
                end
                SendEchoes(player, "CODEX_DONE", {{"kind", "manifest"}, {"count", #topics}})
            elseif operation == "page" then
                if RateLimited(guid, "codex_page") then SendError(player, "RATE_LIMITED", "codex_page"); return end
                local topicIndex, pageIndex = tonumber(tokens[4]), tonumber(tokens[5])
                local topic = topicIndex and topics[topicIndex]
                local body = topic and topic.pages and pageIndex and topic.pages[pageIndex]
                if not body then SendError(player, "NOT_FOUND", "codex_page"); return end
                SendEchoes(player, "CODEX_PAGE", {
                    {"topic", topicIndex}, {"page", pageIndex}, {"count", #topic.pages},
                    {"title", EncodeText(topic.title)}, {"body", EncodeText(body)},
                })
            elseif operation == "search" then
                if RateLimited(guid, "search") then SendError(player, "RATE_LIMITED", "search"); return end
                local query = DecodeText(tokens[4] or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
                if #query < 2 or #query > 80 then SendError(player, "MALFORMED", "search_query"); return end
                local count, limit = 0, 20
                for topicIndex, topic in ipairs(topics) do
                    for pageIndex, body in ipairs(topic.pages or {}) do
                        local plain = tostring(body):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                        if tostring(topic.title):lower():find(query, 1, true) or plain:lower():find(query, 1, true) then
                            count = count + 1
                            if count <= limit then
                                local excerpt = plain
                                if #excerpt > 150 then excerpt = excerpt:sub(1, 147) .. "..." end
                                SendEchoes(player, "CODEX_RESULT", {
                                    {"rank", count}, {"topic", topicIndex}, {"page", pageIndex},
                                    {"title", EncodeText(topic.title)}, {"excerpt", EncodeText(excerpt)},
                                })
                            end
                        end
                    end
                end
                SendEchoes(player, "CODEX_DONE", {{"kind", "search"}, {"count", math.min(count, limit)}, {"total", count}})
            else
                SendError(player, "MALFORMED", "codex_operation")
            end
        end, "AP.Protocol codex")
        return false
    end
    -- Not one of ours; let other #ap handlers see the message.
end

AP.RT.RegisterEvent("player", 18, OnProtocolChat)  -- PLAYER_EVENT_ON_CHAT
AP.RT.RegisterEvent("player",4,function(_,player)
    -- Logging out with an active Visage preview must not depend on an
    -- unverified assumption about whether the engine strips temporary
    -- auras on its own. Explicitly restore the saved appearance through
    -- the same RestoreVisage path Cancel/Apply/timeout already use --
    -- pcall-wrapped, so it cannot raise even if the player object is
    -- already tearing down. Redundant if the engine also clears auras on
    -- logout; closes the gap either way.
    local guid=player and AP.RT.GetGUID(player)
    if guid and AP.Protocol.VisagePreviews[guid] then RestoreVisage(player,guid) end
end)

AP.Log("[Protocol] Echoes Client Companion protocol v" .. AP.PROTOCOL_VERSION .. " loaded")

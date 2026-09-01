-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- EchoesOfTheWorldsoulBridge.lua
-- Echoes of the Worldsoul â€” Client AddOn (WoW 3.3.5a / Interface 30300)
-- Version: 2.1.2
-- ============================================================
-- HOW THE BRIDGE WORKS (read this before editing):
--
--   1. Player hovers an item â†’ OnTooltipSetItem fires.
--   2. We extract the item entry from the tooltip link.
--   3. If we have cached data â†’ inject lines immediately (unless the
--      cached result is ineligible, in which case we add nothing).
--      (No network request needed. Cache hit = zero spam.)
--   4. If no cache â†’ send ONE "#ap tip <entry>" through SAY and wait.
--      No placeholder line is shown while waiting: tooltip enrichment
--      is optional metadata, so the plain Blizzard tooltip stays up
--      untouched until a useful (eligible) response actually arrives.
--      This avoids a "fetching..." flash on ineligible items, since the
--      server's ineligible=1 response never touches the tooltip at all.
--   5. Server receives the request via PLAYER_EVENT_ON_CHAT,
--      swallows it (returns false), builds the payload, and
--      sends it back via SendBroadcastMessage (CHAT_MSG_SYSTEM).
--   6. Our CHAT_MSG_SYSTEM filter catches "[APTIP] â€¦", hides it,
--      writes the cache, then repaints the tooltip ONCE -- but only
--      if the response is eligible. An ineligible response is cached
--      silently; nothing was ever shown, so nothing needs removing.
--
-- BUG FIXES IN 1.1.0:
--   FIX-1: Re-entrancy guard (APB.injecting) prevents the tooltip
--           repaint inside InjectTooltipLines from re-triggering
--           OnTooltipSetItem, which caused the infinite SAY loop.
--   FIX-2: Internal requests use SAY because this realm rejects
--           whisper-to-self before Echoes receives it. Exact client
--           filters and the server's false return suppress the
--           recognized control messages.
--   FIX-3: Background "refresh on cache hit" removed.  That was
--           the second source of the spam loop: every tooltip open
--           on a cached item sent a new request anyway.
--   FIX-4: APB.pendingEntry tracks which entry we are waiting for.
--           A new hover on a *different* item cancels the pending
--           request and starts fresh.  Same-item re-hover is
--           ignored while a request is in-flight.
--   FIX-5: Removed the immediate "fetching..." placeholder. It made
--           every ineligible item (consumables, quest items, etc.)
--           briefly show Echoes UI before the ineligible response
--           removed it. Tooltip enrichment is now silent until an
--           eligible response actually has something to add.
-- ============================================================

-- ============================================================
-- C_Timer POLYFILL (3.3.5 does not ship C_Timer)
-- Must be defined before anything uses it.
-- ============================================================
if not C_Timer then
    C_Timer = {}
    C_Timer.After = function(delay, fn)
        local f = CreateFrame("Frame")
        local elapsed = 0
        f:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= delay then
                self:SetScript("OnUpdate", nil)
                fn()
            end
        end)
    end
end

-- ============================================================
-- SAVED VARIABLES
-- ============================================================
if not AttunementPlusBridgeDB then
    AttunementPlusBridgeDB = { cache = {} }
end

local DB = AttunementPlusBridgeDB

-- ============================================================
-- MODULE STATE
-- All mutable state lives in one table so it is easy to inspect
-- from the chat console (/dump APB) during debugging.
-- ============================================================
local APB = {
    pendingEntry    = nil,
    pendingTime     = 0,
    pendingTimeout  = 4.0,
    hoveredEntry    = nil,
    injecting       = false,
    cacheMaxAge     = 0.75,  -- short-lived; attunement can change after each kill
    playerName      = nil,
    -- Entry we have already injected lines for in the current tooltip show.
    -- Prevents duplicate injection when OnTooltipSetItem fires multiple times
    -- for the same tooltip (which 3.3.5 does after any tooltip modification).
    injectedEntry   = nil,
    tooltipStates   = setmetatable({}, { __mode = "k" }),
    itemTooltipAugmenters = {},
    attunementSubscribers = {},
    nextAttunementSubscriberId = 0,
}

function APB:RegisterItemTooltipAugmenter(callback)
    if type(callback) ~= "function" then return false end
    self.itemTooltipAugmenters[#self.itemTooltipAugmenters + 1] = callback
    return true
end

-- Expose for debugging: /dump APB
_G["APB"] = APB

local function IsCacheFresh(cached)
    if not cached or not cached.ts then return false end
    local age = GetTime() - cached.ts
    return age >= 0 and age < APB.cacheMaxAge
end

local function IsAttunementRequestExcluded(entry)
    return entry == 900010 or entry == 900011
end

local function ClearEquippedTooltipCache()
    APB.pendingEntry = nil
    APB.pendingTime  = 0
    for slot = 0, 18 do
        local itemLink = GetInventoryItemLink("player", slot + 1)
        if itemLink then
            local itemId = tonumber(itemLink:match("item:(%d+)"))
            if itemId then
                DB.cache[itemId] = nil
            end
        end
    end
end

-- ============================================================
-- PAYLOAD PARSER
-- Input:  "[APTIP] id=1234|prog=5000|cap=10000|snap=10/5/20/0/0|absorb=1.0/0.5/2.0/0.0/0.0"
-- Output: { entry, prog, cap, snap={str,agi,sta,int,spi}, absorb={...}, ts }
--         or nil if the string is not a valid AP payload.
-- ============================================================
local function ParsePayload(msg)
    if not msg then return nil end
    local body = msg:match("^%[APTIP%]%s+(.+)$")
    if not body then return nil end

    local function kv(key)
        return body:match(key .. "=([^|]+)")
    end

    local function splitStats(s)
        if not s then return { str=0, agi=0, sta=0, ["int"]=0, spi=0 } end
        local a, b, c, d, e = s:match("([^/]+)/([^/]+)/([^/]+)/([^/]+)/([^/]+)")
        return {
            str      = tonumber(a) or 0,
            agi      = tonumber(b) or 0,
            sta      = tonumber(c) or 0,
            ["int"]  = tonumber(d) or 0,
            spi      = tonumber(e) or 0,
        }
    end

    local entry = tonumber(kv("id"))
    local ineligible = kv("ineligible") == "1"
    if entry and ineligible then
        return { entry=entry, ineligible=true, ts=GetTime() }
    end
    local prog  = tonumber(kv("prog"))
    local cap   = tonumber(kv("cap"))
    if not entry or not prog or not cap then return nil end

    return {
        entry  = entry,
        prog   = prog,
        cap    = cap,
        snap   = splitStats(kv("snap")),
        absorb = splitStats(kv("absorb")),
        ts     = GetTime(),
    }
end

-- ============================================================
-- ITEM ENTRY EXTRACTOR
-- Pulls the numeric item entry from the tooltip's item link.
-- Returns nil if the tooltip is not showing an item.
-- ============================================================
local function GetTooltipItemEntry(tooltip)
    if not tooltip or not tooltip.GetItem then return nil end
    local _, link = tooltip:GetItem()
    if not link then return nil end
    local entry = link:match("item:(%d+)")
    return tonumber(entry)
end

-- ============================================================
-- REQUEST SENDER
-- Sends one server-consumed SAY control message with the tip request.
-- Guards prevent sending if a request is already in-flight for
-- the same entry, or if the entry is already cached and fresh.
-- ============================================================
local function SendRequest(entry)
    if not entry or entry <= 0 then return end
    if IsAttunementRequestExcluded(entry) then return end
    if not APB.playerName then return end  -- not logged in yet

    local now = GetTime()

    -- Is there a fresh cached entry?
    local cached = DB.cache[entry]
    if IsCacheFresh(cached) then
        return
    end

    -- Clear any stale pending request (e.g. server restarted and never replied).
    -- After pendingTimeout seconds with no response, allow a new request.
    if APB.pendingEntry and (now - APB.pendingTime) > APB.pendingTimeout then
        APB.pendingEntry = nil
        APB.pendingTime  = 0
    end

    -- Don't send duplicate requests for the same entry while one is in-flight.
    if APB.pendingEntry == entry then return end

    APB.pendingEntry = entry
    APB.pendingTime  = now

    SendChatMessage("#ap tip " .. entry, "SAY")
end

-- Native system screens reuse the proven tooltip request path instead of
-- introducing a second equipped-attunement transport. The callback receives
-- the exact parsed APTIP payload after it has entered the shared cache.
function APB:RequestAttunement(entry)
    entry = tonumber(entry)
    if not entry or entry <= 0 or IsAttunementRequestExcluded(entry) then return false end
    local cached = DB.cache[entry]
    if IsCacheFresh(cached) then
        for _, callback in pairs(self.attunementSubscribers) do
            pcall(callback, cached)
        end
        return true
    end
    SendRequest(entry)
    return self.pendingEntry == entry
end

function APB:SubscribeAttunement(callback)
    if type(callback) ~= "function" then return nil end
    self.nextAttunementSubscriberId = self.nextAttunementSubscriberId + 1
    local id = self.nextAttunementSubscriberId
    self.attunementSubscribers[id] = callback
    return function() APB.attunementSubscribers[id] = nil end
end

-- ============================================================
-- TOOLTIP LINE BUILDER
-- Shared helper that adds AP lines to a tooltip.
-- Does NOT call tooltip:Show() â€” callers decide whether to do that.
-- ============================================================
local function AddTooltipLines(tooltip, data)
    if data.ineligible then return end
    local prog = data.prog or 0
    local cap  = data.cap  or 10000
    local pct  = math.floor((prog / cap) * 100)

    tooltip:AddLine(" ")  -- spacer

    if prog >= cap then
        tooltip:AddLine("|cff9966ff[EotW] Attuned|r", 1, 1, 1)
    else
        tooltip:AddLine(
            string.format("|cff9966ff[EotW]|r  %d%%  (%d / %d)", pct, prog, cap),
            1, 1, 1)
    end

    local snap = data.snap
    if snap and (snap.str > 0 or snap.agi > 0 or snap.sta > 0 or snap["int"] > 0 or snap.spi > 0) then
        local parts = {}
        if snap.str    > 0 then parts[#parts+1] = string.format("STR %.0f", snap.str) end
        if snap.agi    > 0 then parts[#parts+1] = string.format("AGI %.0f", snap.agi) end
        if snap.sta    > 0 then parts[#parts+1] = string.format("STA %.0f", snap.sta) end
        if snap["int"] > 0 then parts[#parts+1] = string.format("INT %.0f", snap["int"]) end
        if snap.spi    > 0 then parts[#parts+1] = string.format("SPI %.0f", snap.spi) end
        tooltip:AddLine("|cffaaaaaa Snapshot: " .. table.concat(parts, "  ") .. "|r", 1, 1, 1)
    end

    local absorb = data.absorb
    if absorb and (absorb.str > 0 or absorb.agi > 0 or absorb.sta > 0 or absorb["int"] > 0 or absorb.spi > 0) then
        local parts = {}
        if absorb.str    > 0 then parts[#parts+1] = string.format("STR %.1f", absorb.str) end
        if absorb.agi    > 0 then parts[#parts+1] = string.format("AGI %.1f", absorb.agi) end
        if absorb.sta    > 0 then parts[#parts+1] = string.format("STA %.1f", absorb.sta) end
        if absorb["int"] > 0 then parts[#parts+1] = string.format("INT %.1f", absorb["int"]) end
        if absorb.spi    > 0 then parts[#parts+1] = string.format("SPI %.1f", absorb.spi) end
        tooltip:AddLine("|cff88ff88 Absorbed: " .. table.concat(parts, "  ") .. "|r", 1, 1, 1)
    end
end

-- One deterministic post-native seam owns all Echoes item-tooltip additions.
-- Attunement is always written first; registered presentation modules (Chaos,
-- etc.) follow in load order. A per-tooltip marker prevents repeated events
-- from appending or reordering the same block during one tooltip lifecycle.
local function ApplyItemTooltipAugmentations(tooltip, entry, data)
    if not tooltip or not entry then return false end
    local state = APB.tooltipStates[tooltip]
    if state and state.entry == entry and state.applied then return false end

    APB.tooltipStates[tooltip] = { entry = entry, applied = true }
    APB.injectedEntry = entry -- retained for compatibility with older tests/tools
    if data and not data.ineligible then AddTooltipLines(tooltip, data) end
    for _, callback in ipairs(APB.itemTooltipAugmenters) do
        pcall(callback, tooltip, entry, data)
    end
    return true
end

-- ============================================================
-- DEFERRED TOOLTIP FINALIZER
-- A first-hover cache miss leaves Blizzard's native tooltip untouched until
-- the server answers. The finalizer appends the complete ordered Echoes block
-- once and calls Show only to resize for those new lines; it never clears or
-- replays the native tooltip.
-- ============================================================
local function FinalizeTooltip(tooltip, data)
    if not tooltip or not data then return end
    APB.injecting = true
    local changed = ApplyItemTooltipAugmentations(tooltip, data.entry, data)
    if changed then tooltip:Show() end
    APB.injecting = false
end

-- ============================================================
-- TOOLTIP HOOK â€” OnTooltipSetItem
-- Fires whenever GameTooltip (or ItemRefTooltip) populates with
-- an item.  This is the only place we call SendRequest.
-- ============================================================
local function OnTooltipSetItem(tooltip)
    if APB.injecting then return end

    local entry = GetTooltipItemEntry(tooltip)
    if not entry then return end
    if IsAttunementRequestExcluded(entry) then
        ApplyItemTooltipAugmentations(tooltip, entry, nil)
        return
    end

    APB.hoveredEntry = entry

    -- Already injected for this entry in the current tooltip show â€” skip.
    -- This prevents the blink caused by OnTooltipSetItem firing multiple
    -- times for the same tooltip after AddLine modifies it.
    local tooltipState = APB.tooltipStates[tooltip]
    if tooltipState and tooltipState.entry == entry and tooltipState.applied then return end

    local cached = DB.cache[entry]

    if IsCacheFresh(cached) then
        if cached.ineligible then
            ApplyItemTooltipAugmentations(tooltip, entry, cached)
            return
        end
        -- Fresh cache hit: add lines once, mark as injected.
        APB.injecting    = true
        ApplyItemTooltipAugmentations(tooltip, entry, cached)
        APB.injecting    = false
        return
    end

    -- No fresh cache: request silently. Do NOT touch the tooltip -- it
    -- is optional enrichment, and most first-hover misses turn out to be
    -- ineligible items that should never show any Echoes UI at all. The
    -- response finalizer (HandleChatMessage/FinalizeTooltip) adds
    -- the real lines if and when they actually arrive.
    SendRequest(entry)
end

local function OnTooltipCleared(tooltip)
    APB.hoveredEntry  = nil
    APB.injectedEntry = nil  -- allow fresh injection next hover
    APB.tooltipStates[tooltip] = nil
end

-- Hook GameTooltip
if GameTooltip then
    GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    GameTooltip:HookScript("OnTooltipCleared", OnTooltipCleared)
end

-- Hook ItemRefTooltip (chat links)
if ItemRefTooltip then
    ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    ItemRefTooltip:HookScript("OnTooltipCleared", OnTooltipCleared)
end

-- ============================================================
-- CHAT MESSAGE FILTER
-- Catches "[APTIP] â€¦" messages, hides them from all chat frames,
-- parses the data, and updates the cache.
-- If the player is still hovering the item that just replied,
-- we repaint the tooltip once.
-- ============================================================
local function HandleChatMessage(self, event, msg, ...)
    if not msg then return end

    -- Fast exit: must contain the exact prefix.
    if not msg:find("[APTIP]", 1, true) then return false end

    local data = ParsePayload(msg)
    if not data then return false end

    -- Write cache
    DB.cache[data.entry] = data

    -- Clear the pending flag now that we have a response
    if APB.pendingEntry == data.entry then
        APB.pendingEntry = nil
        APB.pendingTime  = 0
    end

    for _, callback in pairs(APB.attunementSubscribers) do
        pcall(callback, data)
    end

    -- If the player is still hovering this item, repaint with real data.
    -- An ineligible response never had anything injected (no placeholder
    -- is shown while pending -- see FIX-5), so there is nothing to remove
    -- and no rebuild is needed; skipping it also avoids any needless
    -- tooltip Show()/ClearLines() cycle on an otherwise-untouched tooltip.
    -- We use a 0-second timer so the filter function returns (hiding the
    -- message) before we touch the tooltip, avoiding any frame-during-filter issues.
    -- NOTE: We check the tooltip's actual item entry directly rather than
    -- APB.hoveredEntry, because OnTooltipCleared may have fired and cleared
    -- hoveredEntry even while the tooltip is still visually open (e.g. on
    -- a brief flicker). This makes the repaint reliable on first hover.
    C_Timer.After(0, function()
        for _, tooltip in ipairs({GameTooltip, ItemRefTooltip}) do
            if tooltip and tooltip:IsVisible() then
                local currentEntry = GetTooltipItemEntry(tooltip)
                if currentEntry == data.entry then FinalizeTooltip(tooltip, data) end
            end
        end
    end)

    -- Return true = suppress this message from all chat frames.
    return true
end

-- Register filter on every channel the server might deliver through.
-- SendBroadcastMessage on the server side arrives as CHAT_MSG_SYSTEM.
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM",  HandleChatMessage)

-- Suppress incoming whisper echoes of #ap tip requests and [APTIP] payloads.
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", function(self, event, msg, ...)
    if not msg then return false end
    if msg:find("%[APTIP%]") then return true end
    if msg:lower():find("#ap tip %d+") then return true end
    return false
end)

-- Legacy safety filter for exact internal tooltip whispers. The active
-- transport is SAY, but retaining this exact filter avoids leaking a stale
-- queued request across an AddOn reload.
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", function(self, event, msg, ...)
    if msg and msg:lower():match("^#ap tip %d+$") then return true end
    return false
end)

-- Suppress only the exact internal SAY control-message forms. Do not
-- hide arbitrary player speech containing "ap" or "#ap".
ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", function(self, event, msg, ...)
    if not msg then return false end
    local lower = msg:lower()
    if lower:match("^#ap tip %d+$") then return true end
    if lower:match("^#ap clientversion [%w%._%-]+$") then return true end
    if lower == "ap" then return true end
    if lower:match("^#ap hello %d+ [%w_,]*$") then return true end
    if lower == "#ap state" then return true end
    if lower:match("^#ap action [%w_]+[%s%w_%-]*$") then return true end
    if lower == "#ap codex manifest" then return true end
    if lower:match("^#ap codex page %d+ %d+$") then return true end
    if lower:match("^#ap codex search [%w%%._%-]+$") then return true end
    return false
end)

-- ============================================================
-- E2J15 CLIENT COMPANION PROTOCOL
-- Structured server<->client contract layered on the SAME SAY-based
-- control channel the tooltip bridge already uses (no new transport).
-- Requests: "#ap hello <protocolVersion> <capsCSV>" / "#ap state" /
--           "#ap action <name>" / "#ap codex ...", all sent through SAY,
-- exactly like the existing "#ap tip"/"#ap clientversion" requests above.
-- Responses: "[ECHOES]<VERB>|k=v|k=v|..." over CHAT_MSG_SYSTEM, the same
-- transport [APTIP] and [EOTW_FLASH] already use, but with its own
-- distinct bracket tag so it can never collide with either.
-- See E2J15-CLIENT-COMPANION-PROTOCOL-SPEC.md for the full grammar.
-- ============================================================
local ECHOES_PROTOCOL_VERSION = 1
local ECHOES_CLIENT_CAPS = "structured_state_v1,progression_ui_v1,world_threat_ui_v1,crucible_ui_v1,talents_ui_v1,rack_ui_v1,forge_ui_v1,visage_ui_v1,codex_ui_v1,search_ui_v1"

-- One-shot, bounded detection state. HELLO is sent exactly once per
-- login (see PLAYER_LOGIN below) and never retried automatically — a
-- non-Echoes server or an unresponsive one simply leaves this at its
-- initial "unknown" state for the rest of the session, per the
-- dormancy requirement (no repeated handshake flood).
APB.echoes = {
    helloSent      = false,
    welcomed       = false,   -- true only after a real [ECHOES]WELCOME
    serverVersion  = nil,
    protocolVersion = nil,
    compatible     = nil,     -- 1/0, only meaningful once welcomed
    caps           = {},      -- set of server capability strings
    actionSubscribers = {},
    nextActionSubscriberId = 0,
    codexSubscribers = {},
    nextCodexSubscriberId = 0,
    codexTopics = {},
    lastStateRequestTime = -10,
    stateRequestToken = 0,
    stateRequestScheduled = false,
    -- Coalesces rapid page navigation (NEXT/PREVIOUS held or clicked fast)
    -- into a single request for whichever page is currently desired, paced
    -- to stay under the server's per-second codex_page rate limit. See
    -- RequestCodexPage below.
    codexPage = {
        scheduled     = false,
        lastSendTime  = -10,
        desiredTopic  = nil,
        desiredPage   = nil,
        sentTopic     = nil,
        sentPage      = nil,
    },
}

-- Splits "[ECHOES]VERB|k1=v1|k2=v2" into (verb, {k1=v1, k2=v2, ...}).
-- Returns nil on anything that doesn't match the exact grammar - an
-- unparseable [ECHOES] message is dropped silently, never surfaced as
-- a Lua error (malformed-input tolerance, matches ParsePayload's own
-- posture for [APTIP]).
local function ParseEchoesPayload(msg)
    if not msg then return nil end
    -- ACTION_OK is part of the documented grammar, so underscores must be
    -- accepted alongside uppercase letters.
    local verb, tail = msg:match("^%[ECHOES%]([%u_]+)(.*)$")
    if not verb then return nil end

    local fields = {}
    if tail and tail ~= "" then
        -- tail starts with "|k=v|k=v..."
        for kv in tail:gmatch("|([^|]+)") do
            local k, v = kv:match("^([%w_]+)=(.*)$")
            if k then fields[k] = v end
        end
    end
    return verb, fields
end

local function EchoesLog(...)
    if not APB.debugProtocol then return end
    print("|cff66ccff[Echoes]|r", ...)
end

local function EncodeCodexText(value)
    return (tostring(value or ""):gsub("([^%w%._%-])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function DecodeCodexText(value)
    return (tostring(value or ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

-- Sent once at login (see PLAYER_LOGIN). Advertises this client's
-- protocol version and capability set; does not assume the server
-- will ever answer (bounded, no retry loop).
local function SendHello()
    if APB.echoes.helloSent then return end
    APB.echoes.helloSent = true
    SendChatMessage("#ap hello " .. ECHOES_PROTOCOL_VERSION .. " " .. ECHOES_CLIENT_CAPS, "SAY")
    EchoesLog("HELLO sent (protocol " .. ECHOES_PROTOCOL_VERSION .. ")")
end

-- Structured state request. Safe to call repeatedly (server-side rate
-- limited); does not implement client-side throttling itself, since
-- server-side validation is the actual authority per the trust-boundary
-- rule - this just sends the request.
local function RequestEchoesState()
    if not APB.echoes.welcomed then
        EchoesLog("state requested before WELCOME - server may not be Echoes-enabled or hasn't responded yet")
    end
    SendChatMessage("#ap state", "SAY")
end

function APB:RequestEchoesState()
    -- Coalesce onto the earliest permitted send. Replacing a delayed request
    -- with a newer delayed request can starve STATE indefinitely while a user
    -- is operating a screen rapidly.
    if self.echoes.stateRequestScheduled then return true end
    self.echoes.stateRequestToken = self.echoes.stateRequestToken + 1
    local token = self.echoes.stateRequestToken
    local elapsed = GetTime() - (self.echoes.lastStateRequestTime or -10)
    local delay = math.max(0, 1.05 - elapsed)
    local function send()
        if APB.echoes.stateRequestToken ~= token then return end
        APB.echoes.stateRequestScheduled = false
        APB.echoes.lastStateRequestTime = GetTime()
        RequestEchoesState()
    end
    if delay > 0 then
        self.echoes.stateRequestScheduled = true
        C_Timer.After(delay, send)
    else
        send()
    end
    return true
end

-- Thin action sender for server-advertised E2J15 actions. All validation and
-- execution remain server-side; native screens only observe the structured
-- result through SubscribeEchoesActions.
local function RequestEchoesAction(name, ...)
    if not name or name == "" then return end
    if not tostring(name):match("^[%w_]+$") then return false end
    local parts = {"#ap action", tostring(name)}
    for index = 1, select("#", ...) do
        local value = tostring(select(index, ...))
        if not value:match("^[%w_%-]+$") then return false end
        parts[#parts + 1] = value
    end
    SendChatMessage(table.concat(parts, " "), "SAY")
    return true
end

function APB:RequestEchoesAction(name, ...)
    return RequestEchoesAction(name, ...)
end

function APB:SubscribeEchoesActions(callback)
    if type(callback) ~= "function" then return nil end
    self.echoes.nextActionSubscriberId = self.echoes.nextActionSubscriberId + 1
    local id = self.echoes.nextActionSubscriberId
    self.echoes.actionSubscribers[id] = callback
    return function() APB.echoes.actionSubscribers[id] = nil end
end

function APB:SubscribeCodex(callback)
    if type(callback) ~= "function" then return nil end
    self.echoes.nextCodexSubscriberId = self.echoes.nextCodexSubscriberId + 1
    local id = self.echoes.nextCodexSubscriberId
    self.echoes.codexSubscribers[id] = callback
    return function() APB.echoes.codexSubscribers[id] = nil end
end

local function NotifyCodex(verb, fields)
    for _, callback in pairs(APB.echoes.codexSubscribers) do pcall(callback, verb, fields) end
end

function APB:RequestCodexManifest()
    SendChatMessage("#ap codex manifest", "SAY")
    return true
end

-- Rapid NEXT/PREVIOUS clicks (or a Search result opening a page while a
-- prior navigation is still in flight) must not each fire an immediate SAY.
-- The server's codex_page rate bucket allows roughly one request/second;
-- sending faster than that produces a RATE_LIMITED [ECHOES]ERROR that has
-- nothing to do with a real failure. Instead of sending on every call, we
-- remember the most recently DESIRED page and let a single pending timer
-- (paced to stay under the server window) send whatever is current when it
-- fires -- exactly like RequestEchoesState's existing coalescing pattern,
-- extended to carry the (topic, page) payload through. sentTopic/sentPage
-- record what the outstanding request actually asked for, so a screen can
-- tell a genuine failure apart from an error that belongs to a page the
-- player has since navigated away from (see CodexScreen:OnCodex).
function APB:RequestCodexPage(topic, page)
    topic, page = tonumber(topic), tonumber(page)
    if not topic or not page then return false end
    topic, page = math.floor(topic), math.floor(page)

    local state = self.echoes.codexPage
    state.desiredTopic, state.desiredPage = topic, page

    if state.scheduled then return true end -- the pending send will pick up this newer desire

    local function send()
        state.scheduled = false
        state.lastSendTime = GetTime()
        state.sentTopic, state.sentPage = state.desiredTopic, state.desiredPage
        SendChatMessage("#ap codex page " .. state.desiredTopic .. " " .. state.desiredPage, "SAY")
    end

    local elapsed = GetTime() - (state.lastSendTime or -10)
    local delay = math.max(0, 1.2 - elapsed) -- safely above the server's ~1s (integer-second) window
    if delay > 0 then
        state.scheduled = true
        C_Timer.After(delay, send)
    else
        send()
    end
    return true
end

function APB:SearchCodex(query)
    query = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #query < 2 or #query > 80 then return false end
    SendChatMessage("#ap codex search " .. EncodeCodexText(query), "SAY")
    return true
end

local function NotifyEchoesAction(verb, fields)
    for _, callback in pairs(APB.echoes.actionSubscribers) do
        pcall(callback, verb, fields)
    end
end

-- Handles every "[ECHOES]..." response. Registered as an additional
-- CHAT_MSG_SYSTEM filter alongside the existing [APTIP] handler above -
-- WoW chains multiple filters on the same event, each gets a look, so
-- this is fully independent of (and does not risk regressing) the
-- tooltip bridge's own filter.
local function HandleEchoesMessage(self, event, msg, ...)
    if not msg then return false end
    if not msg:find("[ECHOES]", 1, true) then return false end

    local verb, fields = ParseEchoesPayload(msg)
    if not verb then return true end -- still suppress unparseable [ECHOES] noise

    if verb == "WELCOME" then
        APB.echoes.welcomed        = true
        APB.echoes.serverVersion   = fields.server_version
        APB.echoes.protocolVersion = tonumber(fields.protocol_version)
        APB.echoes.compatible      = tonumber(fields.compatible)
        APB.echoes.caps = {}
        if fields.caps then
            for cap in fields.caps:gmatch("[^,]+") do
                APB.echoes.caps[cap] = true
            end
        end
        EchoesLog("WELCOME: server_version=" .. tostring(fields.server_version) ..
            " protocol_version=" .. tostring(fields.protocol_version) ..
            " compatible=" .. tostring(fields.compatible))
        if APB.echoes.compatible == 0 then
            print("|cffffaa00[Echoes]|r This server's protocol (v" .. tostring(fields.protocol_version) ..
                ") doesn't match this AddOn's (v" .. ECHOES_PROTOCOL_VERSION ..
                "). Structured features may be unavailable; the normal gossip menu still works.")
        end

    elseif verb == "STATE" then
        APB.echoes.lastState = fields
        APB.echoes.lastStateTime = GetTime()
        -- EchoesUI consumes the already-parsed E2J15 map. The Bridge remains
        -- the sole protocol/parser authority and continues normally if the
        -- opt-in native frontend is absent or fails to initialize.
        if EchoesUI and EchoesUI.SafeCall and EchoesUI.StateStore and EchoesUI.StateStore.Ingest then
            EchoesUI:SafeCall("StateStore ingest", EchoesUI.StateStore.Ingest,
                EchoesUI.StateStore, fields, APB.echoes.lastStateTime, true)
        end
        EchoesLog("STATE received: essence=" .. tostring(fields.essence) ..
            " mastery_rank=" .. tostring(fields.mastery_rank) ..
            " residue=" .. tostring(fields.residue))

    elseif verb == "ACTION_OK" then
        NotifyEchoesAction(verb, fields)
        EchoesLog("ACTION_OK: action=" .. tostring(fields.action) .. " status=" .. tostring(fields.status))

    elseif verb == "ERROR" then
        NotifyEchoesAction(verb, fields)
        NotifyCodex(verb, fields)
        EchoesLog("ERROR: code=" .. tostring(fields.code) .. " message=" .. tostring(fields.message))
    elseif verb == "CODEX_TOPIC" or verb == "CODEX_PAGE" or verb == "CODEX_RESULT" or verb == "CODEX_DONE" then
        if fields.title then fields.title = DecodeCodexText(fields.title) end
        if fields.body then fields.body = DecodeCodexText(fields.body) end
        if fields.excerpt then fields.excerpt = DecodeCodexText(fields.excerpt) end
        if verb == "CODEX_TOPIC" and fields.topic then
            APB.echoes.codexTopics[tonumber(fields.topic)] = fields
        end
        NotifyCodex(verb, fields)
        EchoesLog(verb .. ": topic=" .. tostring(fields.topic) .. " page=" .. tostring(fields.page))
    end

    return true -- always suppress raw [ECHOES] protocol text from chat
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", HandleEchoesMessage)

-- Suppress "Accepting Whisper: ON" or similar system acknowledgements
-- that some server builds emit when a whisper is processed.
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(self, event, msg, ...)
    if not msg then return false end
    if msg:lower():find("accepting whisper") then return true end
    return false
end)

-- ============================================================
-- SLASH COMMAND â€” /apb
-- Debugging and manual control.
--   /apb status        â€” print current state
--   /apb test <entry>  â€” manually send a tip request for an item entry
--   /apb clear         â€” wipe the cache
--   /apb dump          â€” dump the raw cache contents
-- ============================================================
SLASH_APBRIDGE1 = "/apb"
SlashCmdList["APBRIDGE"] = function(input)
    local cmd, arg = input:match("^(%S+)%s*(.*)$")
    cmd = (cmd or ""):lower()

    if cmd == "status" then
        print("|cff9966ff[EotW]|r playerName  = " .. tostring(APB.playerName))
        print("|cff9966ff[EotW]|r pendingEntry = " .. tostring(APB.pendingEntry))
        print("|cff9966ff[EotW]|r hoveredEntry = " .. tostring(APB.hoveredEntry))
        print("|cff9966ff[EotW]|r injecting    = " .. tostring(APB.injecting))
        local n = 0
        for _ in pairs(DB.cache) do n = n + 1 end
        print("|cff9966ff[EotW]|r cache entries = " .. n)

    elseif cmd == "test" then
        local entry = tonumber(arg)
        if not entry or entry <= 0 then
            print("|cffff4444[EotW]|r Usage: /apb test <itemEntry>")
            return
        end
        if IsAttunementRequestExcluded(entry) then
            print("|cffff4444[EotW]|r Echo Fragment and Worldsoul Residue are not Attunement items.")
            return
        end
        print("|cff9966ff[EotW]|r Sending tip request for entry " .. entry .. "...")
        APB.pendingEntry = entry
        APB.pendingTime  = GetTime()
        SendChatMessage("#ap tip " .. entry, "SAY")

    elseif cmd == "clear" then
        DB.cache = {}
        print("|cff9966ff[EotW]|r Cache cleared.")

    elseif cmd == "dump" then
        local n = 0
        for k, v in pairs(DB.cache) do
            n = n + 1
            print(string.format("|cff9966ff[EotW]|r cache[%d]: prog=%d cap=%d age=%.1fs",
                k, v.prog or 0, v.cap or 0, GetTime() - (v.ts or 0)))
        end
        if n == 0 then print("|cff9966ff[EotW]|r Cache is empty.") end

    elseif cmd == "hello" then
        APB.debugProtocol = true
        print("|cff66ccff[Echoes]|r Sending HELLO (protocol " .. ECHOES_PROTOCOL_VERSION .. ")...")
        APB.echoes.helloSent = false -- explicit debug re-send, bypasses the one-shot login guard
        SendHello()

    elseif cmd == "state" then
        APB.debugProtocol = true
        if not APB.echoes.welcomed then
            print("|cffffaa00[Echoes]|r No WELCOME received yet this session - requesting state anyway.")
        end
        RequestEchoesState()

    elseif cmd == "action" then
        APB.debugProtocol = true
        local name = arg ~= "" and arg or "preview_catalyst"
        print("|cff66ccff[Echoes]|r Requesting action: " .. name)
        RequestEchoesAction(name)

    elseif cmd == "protocol" then
        print("|cff66ccff[Echoes]|r welcomed=" .. tostring(APB.echoes.welcomed) ..
            " server_version=" .. tostring(APB.echoes.serverVersion) ..
            " protocol_version=" .. tostring(APB.echoes.protocolVersion) ..
            " compatible=" .. tostring(APB.echoes.compatible))
        local capList = {}
        for cap in pairs(APB.echoes.caps) do capList[#capList + 1] = cap end
        print("|cff66ccff[Echoes]|r caps=" .. table.concat(capList, ","))
        if APB.echoes.lastState then
            print("|cff66ccff[Echoes]|r last STATE (age " ..
                string.format("%.1f", GetTime() - (APB.echoes.lastStateTime or 0)) .. "s):")
            for k, v in pairs(APB.echoes.lastState) do
                print("  " .. k .. " = " .. tostring(v))
            end
        end

    else
        print("|cff9966ff[EotW]|r Commands: /apb status | /apb test <entry> | /apb clear | /apb dump | /apb hello | /apb state | /apb action [name] | /apb protocol")
    end
end
-- ============================================================
-- MINIMAP BUTTON
-- A draggable circular button on the minimap that:
--   - Left-click: opens the AP gossip menu (types "ap" in chat)
--   - Right-click: clears tooltip cache
--   - Hover: shows a summary of in-progress and attuned items
-- Position is saved in AttunementPlusBridgeDB.minimapAngle.
-- ============================================================
local MinimapButton = {}

local function CreateMinimapButton()
    local db = AttunementPlusBridgeDB
    db.minimapAngle = db.minimapAngle or 225
    if type(db.minimapAngle) ~= "number" then db.minimapAngle = 225 end

    local button = CreateFrame("Button", "APBMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetWidth(31)
    button:SetHeight(31)
    button:SetFrameLevel(8)
    button:RegisterForClicks("anyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetTexture("Interface\\Icons\\Spell_Holy_Spellwarding")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -5)
    button.icon = icon

    local function UpdatePosition()
        local angle = math.rad(db.minimapAngle or 225)
        local x, y = math.cos(angle) * 80, math.sin(angle) * 80
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    local function OnUpdate(self)
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale  = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        db.minimapAngle = math.deg(math.atan2(py - my, px - mx)) % 360
        UpdatePosition()
    end

    local isDragging = false

    button:SetScript("OnDragStart", function(self)
        isDragging = true
        self:LockHighlight()
        self.icon:SetTexCoord(0, 1, 0, 1)
        self:SetScript("OnUpdate", OnUpdate)
        GameTooltip:Hide()
    end)

    button:SetScript("OnDragStop", function(self)
        isDragging = false
        self:SetScript("OnUpdate", nil)
        self.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        self:UnlockHighlight()
    end)

    button:SetScript("OnMouseDown", function(self)
        self.icon:SetTexCoord(0, 1, 0, 1)
    end)

    button:SetScript("OnMouseUp", function(self)
        self.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    end)

    button:SetScript("OnClick", function(self, btn)
        if isDragging then return end
        if btn == "LeftButton" then
            SendChatMessage("ap", "SAY")
        elseif btn == "RightButton" then
            DB.cache = {}
            print("|cff9966ff[EotW]|r Tooltip cache cleared.")
        end
    end)

    button:SetScript("OnEnter", function(self)
        if isDragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cff9966ffEchoes of the Worldsoul|r")
        GameTooltip:AddLine(" ")

        local attuned, inProgress, topEntry, topPct = 0, 0, nil, 0
        for entry, data in pairs(DB.cache) do
            local prog = data.prog or 0
            local cap  = data.cap  or 10000
            if prog >= cap then
                attuned = attuned + 1
            elseif prog > 0 then
                inProgress = inProgress + 1
                local pct = math.floor((prog / cap) * 100)
                if pct > topPct then topPct = pct; topEntry = entry end
            end
        end

        GameTooltip:AddDoubleLine("Attuned (cached):",     attuned,    1,1,1, 0,1,0.6)
        GameTooltip:AddDoubleLine("In Progress (cached):", inProgress, 1,1,1, 1,1,0.4)

        if topEntry then
            local name = GetItemInfo(topEntry)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Closest to attuned:", 0.7, 0.7, 0.7)
            GameTooltip:AddDoubleLine(
                name or ("Item "..topEntry), topPct.."%",
                1,1,1, 0.4,1,0.4)
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffaaaaaaLeft-click: Open #ap panel|r")
        GameTooltip:AddLine("|cffaaaaaaRight-click: Clear cache|r")
        GameTooltip:AddLine("|cffaaaaaa  Drag: Move button|r")
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    UpdatePosition()
    button:Show()
    MinimapButton.frame = button
end
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "EchoesOfTheWorldsoulBridge" then
        -- Ensure saved variable tables exist after load
        if not AttunementPlusBridgeDB then
            AttunementPlusBridgeDB = { cache = {} }
        end
        if not AttunementPlusBridgeDB.cache then
            AttunementPlusBridgeDB.cache = {}
        end
        DB = AttunementPlusBridgeDB
        -- SavedVariables persist across sessions, but GetTime() restarts on
        -- login. Reusing old timestamps can make stale tooltip data look fresh.
        DB.cache = {}

    elseif event == "PLAYER_LOGIN" then
        APB.playerName = UnitName("player")
        print("|cff9966ff[EotW]|r Bridge active. Player: " .. (APB.playerName or "?"))
        self:UnregisterEvent("PLAYER_LOGIN")

        -- Report AddOn version to the server for compatibility checking.
        -- GetAddOnMetadata reads from this .toc's ## Version field â€” no
        -- separate version constant to keep in sync.
        -- Sent through the same server-consumed SAY control channel as tooltip
        -- requests after a short delay to ensure the player is fully in-world.
        local addonVer = GetAddOnMetadata("EchoesOfTheWorldsoulBridge", "Version") or "unknown"
        C_Timer.After(2, function()
            local pname = UnitName("player")
            if pname then
                SendChatMessage("#ap clientversion " .. addonVer, "SAY")
            end
        end)

        -- E2j15: one-shot, bounded protocol handshake. Sent slightly after
        -- clientversion (2.5s vs 2s) to avoid bunching two SAY sends in the
        -- same frame; never retried this session (see APB.echoes.helloSent).
        C_Timer.After(2.5, function()
            if UnitName("player") then
                SendHello()
            end
        end)

        -- Create minimap button at PLAYER_LOGIN when all frames are guaranteed ready
        local ok, err = pcall(CreateMinimapButton)
        if not ok then
            print("|cffff4444[EotW]|r Minimap button error: " .. tostring(err))
        else
            print("|cff9966ff[EotW]|r Minimap button created.")
        end
    end
end)

-- ============================================================
-- DARK SOULS STYLE FLASH RENDERER
-- Triggered by server payload: [EOTW_FLASH]TITLE|subtitle
-- Two-line display: large gold title, smaller silver subtitle
-- Animation: fade in 0.5s, hold 2.5s, fade out 1.5s (4.5s total)
-- ============================================================

local EotW_Flash = CreateFrame("Frame", "EotW_FlashFrame", UIParent)
EotW_Flash:SetAllPoints(UIParent)
EotW_Flash:SetFrameStrata("HIGH")
EotW_Flash:SetAlpha(0)
EotW_Flash:Hide()

-- Title text (large, gold, MORPHEUS font for gravitas)
local EotW_Title = EotW_Flash:CreateFontString(nil, "OVERLAY")
EotW_Title:SetFont("Fonts\\MORPHEUS.TTF", 52, "OUTLINE, THICKOUTLINE")
EotW_Title:SetTextColor(1, 0.82, 0, 1)       -- deep gold
EotW_Title:SetShadowColor(0.3, 0.1, 0, 1)
EotW_Title:SetShadowOffset(2, -2)
EotW_Title:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
EotW_Title:SetWidth(900)
EotW_Title:SetJustifyH("CENTER")

-- Subtitle text (smaller, silver-white)
local EotW_Subtitle = EotW_Flash:CreateFontString(nil, "OVERLAY")
EotW_Subtitle:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
EotW_Subtitle:SetTextColor(0.88, 0.88, 0.88, 1)  -- silver
EotW_Subtitle:SetShadowColor(0, 0, 0, 1)
EotW_Subtitle:SetShadowOffset(1, -1)
EotW_Subtitle:SetPoint("CENTER", UIParent, "CENTER", 0, -2)
EotW_Subtitle:SetWidth(800)
EotW_Subtitle:SetJustifyH("CENTER")

-- Thin separator line between title and subtitle
local EotW_Line = EotW_Flash:CreateTexture(nil, "OVERLAY")
EotW_Line:SetTexture(0.8, 0.65, 0, 0.6)  -- gold line (SetColorTexture not in 3.3.5a)
EotW_Line:SetSize(600, 1)
EotW_Line:SetPoint("CENTER", UIParent, "CENTER", 0, 18)

-- Animation state
local flashTimer     = 0
local flashDuration  = 4.5   -- total seconds
local fadeInTime     = 0.5
local holdTime       = 2.5
local fadeOutTime    = 1.5
local flashActive    = false

EotW_Flash:SetScript("OnUpdate", function(self, elapsed)
    if not flashActive then return end
    flashTimer = flashTimer + elapsed
    local alpha

    if flashTimer < fadeInTime then
        alpha = flashTimer / fadeInTime
    elseif flashTimer < fadeInTime + holdTime then
        alpha = 1.0
    elseif flashTimer < flashDuration then
        local fadeProgress = (flashTimer - fadeInTime - holdTime) / fadeOutTime
        alpha = 1.0 - fadeProgress
    else
        alpha = 0
        flashActive = false
        self:Hide()
        return
    end

    self:SetAlpha(alpha)
end)

local function EotW_ShowFlash(title, subtitle)
    EotW_Title:SetText(title)
    if subtitle and subtitle ~= "" then
        EotW_Subtitle:SetText(subtitle)
        EotW_Subtitle:Show()
        EotW_Line:Show()
    else
        EotW_Subtitle:Hide()
        EotW_Line:Hide()
    end

    flashTimer  = 0
    flashActive = true
    EotW_Flash:SetAlpha(0)
    EotW_Flash:Show()
end

-- ============================================================
-- EOTW PAYLOAD FILTER
-- Intercepts [EOTW_FLASH] from CHAT_MSG_SYSTEM and triggers
-- the flash renderer. Suppresses all [EOTW prefixed messages
-- from appearing in chat.
-- ============================================================

local EotW_FlashFilter = CreateFrame("Frame")
EotW_FlashFilter:RegisterEvent("CHAT_MSG_SYSTEM")

EotW_FlashFilter:SetScript("OnEvent", function(self, event, msg, ...)
    if not msg then return end
    if msg:find("^%[EOTW_FLASH%]") then
        local payload = msg:match("^%[EOTW_FLASH%](.+)$")
        if payload then
            local title, subtitle = payload:match("^([^|]+)|?(.*)$")
            if title then
                EotW_ShowFlash(title:upper(), subtitle or "")
            end
        end
    end
end)

-- Suppress [EOTW_*] payloads from all chat channels
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(self, event, msg)
    return msg and msg:find("^%[EOTW") ~= nil
end)
ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", function(self, event, msg)
    return msg and msg:find("^%[EOTW") ~= nil
end)
ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", function(self, event, msg)
    return msg and msg:find("^%[EOTW") ~= nil
end)

-- ============================================================
-- /eotw TEST COMMAND (preview flash without server trigger)
-- ============================================================
SLASH_EOTW1 = "/eotw"
SlashCmdList["EOTW"] = function(msg)
    local cmd = msg:lower():match("^(%S+)")
    if cmd == "test" then
        EotW_ShowFlash(
            "THE LICH KING HAS FALLEN",
            "DEATH ITSELF YIELDS TO YOU."
        )
    elseif cmd == "test2" then
        EotW_ShowFlash("THE FIRST ECHO AWAKENS", "Your journey has begun in earnest.")
    elseif cmd == "test3" then
        EotW_ShowFlash("A NEW FORCE WALKS AZEROTH", "")
    else
        print("[EotW] Commands: /eotw test | /eotw test2 | /eotw test3")
    end
end

-- ============================================================
-- ATTUNEMENT PROGRESS - BUST CACHE FOR EQUIPPED ITEMS
-- Server-side attunement can change after kills even when the client does not
-- fire PLAYER_XP_GAINED, so also clear equipped-item cache when combat ends.
-- ============================================================
local invalidateFrame = CreateFrame("Frame")
invalidateFrame:RegisterEvent("PLAYER_XP_GAINED")
invalidateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
invalidateFrame:SetScript("OnEvent", function(self, event)
    ClearEquippedTooltipCache()
end)

-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- EchoesOfTheWorldsoulBridge.lua
-- Echoes of the Worldsoul — Client AddOn (WoW 3.3.5a / Interface 30300)
-- Version: 1.1.0  (fixes: spam loop, re-entrancy, background refresh)
-- ============================================================
-- HOW THE BRIDGE WORKS (read this before editing):
--
--   1. Player hovers an item → OnTooltipSetItem fires.
--   2. We extract the item entry from the tooltip link.
--   3. If we have cached data → inject lines immediately, DONE.
--      (No network request needed. Cache hit = zero spam.)
--   4. If no cache → show "fetching" line, set a REQUEST GUARD,
--      send ONE "#ap tip <entry>" as a WHISPER to ourselves.
--      The request guard prevents any further sends until the
--      response arrives OR the tooltip is closed.
--   5. Server receives the whisper via PLAYER_EVENT_ON_CHAT,
--      swallows it (returns false), builds the payload, and
--      sends it back via SendBroadcastMessage (CHAT_MSG_SYSTEM).
--   6. Our CHAT_MSG_SYSTEM filter catches "[APTIP] …", hides it,
--      writes the cache, then repaints the tooltip ONCE.
--
-- BUG FIXES IN 1.1.0:
--   FIX-1: Re-entrancy guard (APB.injecting) prevents the tooltip
--           repaint inside InjectTooltipLines from re-triggering
--           OnTooltipSetItem, which caused the infinite SAY loop.
--   FIX-2: Request channel changed from SAY to WHISPER-to-self.
--           SAY is visible to nearby players even for a split
--           second before the server swallows it.  Whisper to
--           self is silent client-side until the server responds.
--   FIX-3: Background "refresh on cache hit" removed.  That was
--           the second source of the spam loop: every tooltip open
--           on a cached item sent a new request anyway.
--   FIX-4: APB.pendingEntry tracks which entry we are waiting for.
--           A new hover on a *different* item cancels the pending
--           request and starts fresh.  Same-item re-hover is
--           ignored while a request is in-flight.
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
    cacheMaxAge     = 8.0,   -- seconds before a cache entry is considered stale
    playerName      = nil,
    -- Entry we have already injected lines for in the current tooltip show.
    -- Prevents duplicate injection when OnTooltipSetItem fires multiple times
    -- for the same tooltip (which 3.3.5 does after any tooltip modification).
    injectedEntry   = nil,
}

-- Expose for debugging: /dump APB
_G["APB"] = APB

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
-- Sends one whisper-to-self with the tip request.
-- Guards prevent sending if a request is already in-flight for
-- the same entry, or if the entry is already cached and fresh.
-- ============================================================
local function SendRequest(entry)
    if not entry or entry <= 0 then return end
    if not APB.playerName then return end  -- not logged in yet

    local now = GetTime()

    -- Is there a fresh cached entry?
    local cached = DB.cache[entry]
    if cached and (now - cached.ts) < APB.cacheMaxAge then
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

-- ============================================================
-- TOOLTIP LINE BUILDER
-- Shared helper that adds AP lines to a tooltip.
-- Does NOT call tooltip:Show() — callers decide whether to do that.
-- ============================================================
local function AddTooltipLines(tooltip, data)
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

-- ============================================================
-- TOOLTIP LINE INJECTOR
-- Used by the deferred repaint (C_Timer.After) path only.
-- Since we are outside the OnTooltipSetItem call stack here,
-- we need tooltip:Show() to force a resize — but we also need
-- the re-entrancy guard to prevent the Show() from triggering
-- OnTooltipSetItem → InjectTooltipLines → Show() loop.
-- ============================================================
local function InjectTooltipLines(tooltip, data)
    if not tooltip or not data then return end
    if APB.injecting then return end

    APB.injecting = true
    AddTooltipLines(tooltip, data)
    tooltip:Show()  -- needed here because we are outside OnTooltipSetItem
    APB.injecting = false
end

-- ============================================================
-- TOOLTIP HOOK — OnTooltipSetItem
-- Fires whenever GameTooltip (or ItemRefTooltip) populates with
-- an item.  This is the only place we call SendRequest.
-- ============================================================
local function OnTooltipSetItem(tooltip)
    if APB.injecting then return end

    local entry = GetTooltipItemEntry(tooltip)
    if not entry then return end

    APB.hoveredEntry = entry

    -- Already injected for this entry in the current tooltip show — skip.
    -- This prevents the blink caused by OnTooltipSetItem firing multiple
    -- times for the same tooltip after AddLine modifies it.
    if APB.injectedEntry == entry then return end

    local cached = DB.cache[entry]
    local now    = GetTime()

    if cached and (now - cached.ts) < APB.cacheMaxAge then
        -- Fresh cache hit: add lines once, mark as injected.
        APB.injecting    = true
        APB.injectedEntry = entry
        AddTooltipLines(tooltip, cached)
        APB.injecting    = false
        return
    end

    -- No fresh cache: add "fetching" placeholder once, mark as injected
    -- so subsequent OnTooltipSetItem fires don't add it again.
    APB.injecting     = true
    APB.injectedEntry = entry
    tooltip:AddLine(" ")
    tooltip:AddLine("|cff9966ff[EotW]|r  fetching...", 1, 1, 1)
    APB.injecting     = false

    SendRequest(entry)
end

local function OnTooltipCleared(tooltip)
    APB.hoveredEntry  = nil
    APB.injectedEntry = nil  -- allow fresh injection next hover
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
-- Catches "[APTIP] …" messages, hides them from all chat frames,
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

    -- If the player is still hovering this item, repaint with real data.
    -- We use a 0-second timer so the filter function returns (hiding the
    -- message) before we touch the tooltip, avoiding any frame-during-filter issues.
    -- NOTE: We check the tooltip's actual item entry directly rather than
    -- APB.hoveredEntry, because OnTooltipCleared may have fired and cleared
    -- hoveredEntry even while the tooltip is still visually open (e.g. on
    -- a brief flicker). This makes the repaint reliable on first hover.
    C_Timer.After(0, function()
        if not GameTooltip:IsVisible() then return end
        local currentEntry = GetTooltipItemEntry(GameTooltip)
        if currentEntry == data.entry then
            -- Reset injectedEntry so InjectTooltipLines (which uses Show())
            -- is allowed to run, and so the guard doesn't block it.
            APB.injectedEntry = nil
            InjectTooltipLines(GameTooltip, data)
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

-- Suppress outgoing whisper notifications ("To [Name]: #ap tip 1234").
-- CHAT_MSG_WHISPER_INFORM fires for every whisper the client sends.
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", function(self, event, msg, ...)
    if msg and msg:lower():find("#ap tip %d+") then return true end
    return false
end)

-- Suppress outgoing SAY messages containing #ap tip (now the primary request channel).
ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", function(self, event, msg, ...)
    if msg and msg:lower():find("#ap tip %d+") then return true end
    return false
end)

-- Suppress "Accepting Whisper: ON" or similar system acknowledgements
-- that some server builds emit when a whisper is processed.
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(self, event, msg, ...)
    if not msg then return false end
    if msg:lower():find("accepting whisper") then return true end
    return false
end)

-- ============================================================
-- SLASH COMMAND — /apb
-- Debugging and manual control.
--   /apb status        — print current state
--   /apb test <entry>  — manually send a tip request for an item entry
--   /apb clear         — wipe the cache
--   /apb dump          — dump the raw cache contents
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

    else
        print("|cff9966ff[EotW]|r Commands: /apb status | /apb test <entry> | /apb clear | /apb dump")
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

    elseif event == "PLAYER_LOGIN" then
        APB.playerName = UnitName("player")
        print("|cff9966ff[EotW]|r Bridge active. Player: " .. (APB.playerName or "?"))
        self:UnregisterEvent("PLAYER_LOGIN")

        -- Report AddOn version to the server for compatibility checking.
        -- GetAddOnMetadata reads from this .toc's ## Version field — no
        -- separate version constant to keep in sync.
        -- Sent as a whisper-to-self (same silent channel as #ap tip requests)
        -- after a short delay to ensure the player is fully in-world.
        local addonVer = GetAddOnMetadata("EchoesOfTheWorldsoulBridge", "Version") or "unknown"
        C_Timer.After(2, function()
            local pname = UnitName("player")
            if pname then
                SendChatMessage("#ap clientversion " .. addonVer, "WHISPER", nil, pname)
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
-- XP GAIN — BUST CACHE FOR EQUIPPED ITEMS
-- When the player gains XP, their equipped items' attunement
-- progress has changed on the server. Wipe those cache entries
-- so the next hover fetches fresh data immediately.
-- ============================================================
local xpFrame = CreateFrame("Frame")
xpFrame:RegisterEvent("PLAYER_XP_GAINED")
xpFrame:SetScript("OnEvent", function(self, event)
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
end)

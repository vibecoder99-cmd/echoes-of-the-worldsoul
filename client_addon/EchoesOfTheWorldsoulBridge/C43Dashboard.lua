-- Candidate 43 Dashboard shell
-- WoW 3.3.5a / Interface 30300
--
-- This module is deliberately presentation-only. The existing E2J15 Bridge
-- remains the protocol and gameplay authority. No submenu architecture or
-- client-owned economy state is introduced here.

local ADDON_NAME = "EchoesOfTheWorldsoulBridge"
local ART_WIDTH = 1672
local ART_HEIGHT = 941
local MIN_PHYSICAL_LABEL = 12
local VIEWPORT_FIT = 0.81
local MAX_DASHBOARD_SCALE = 0.81

if not APB then
    return
end

AttunementPlusBridgeDB = AttunementPlusBridgeDB or { cache = {} }
AttunementPlusBridgeDB.c43 = AttunementPlusBridgeDB.c43 or {}
local C43DB = AttunementPlusBridgeDB.c43

local C43 = {
    focusId = "core",
    keyboardFocusActive = false,
    motionState = "CLOSED",
    motionElapsed = 0,
    openingCoreBoost = 0,
    selectedId = nil,
    stateStamp = nil,
    stateRequestPending = false,
    stateRequestTime = 0,
    welcomedObserved = false,
    scale = 1,
    buttons = {},
    motionListeners = {},
    orderedIds = {
        "codex", "search", "talents", "rack", "visage", "core",
        "progression", "threat", "crucible", "forge",
        "accessibility", "settings", "close",
    },
}
APB.C43 = C43

local frame = CreateFrame("Frame", "EchoesC43Dashboard", UIParent)
frame:SetSize(ART_WIDTH, ART_HEIGHT)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:EnableKeyboard(true)
frame:Hide()
C43.frame = frame

table.insert(UISpecialFrames, "EchoesC43Dashboard")

local shade = frame:CreateTexture(nil, "BACKGROUND")
shade:SetAllPoints(frame)
shade:SetTexture(0, 0, 0, 0.72)

-- Candidate 43 is tiled into conservative 512x512 textures for the 3.3.5a
-- renderer. Edge tiles use texture coordinates so transparent padding never
-- alters the approved 1672x941 composition.
local tiles = {
    {0,    0,   512, 512, "C43_00"},
    {512,  0,   512, 512, "C43_10"},
    {1024, 0,   512, 512, "C43_20"},
    {1536, 0,   136, 512, "C43_30"},
    {0,    512, 512, 429, "C43_01"},
    {512,  512, 512, 429, "C43_11"},
    {1024, 512, 512, 429, "C43_21"},
    {1536, 512, 136, 429, "C43_31"},
}

for _, tile in ipairs(tiles) do
    local x, y, w, h, name = unpack(tile)
    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\" .. name)
    texture:SetSize(w, h)
    texture:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
    texture:SetTexCoord(0, w / 512, 0, h / 512)
end

local function SetTopLeft(region, x, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
end

local status = frame:CreateFontString(nil, "OVERLAY")
status:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
status:SetTextColor(0.82, 0.78, 0.68, 1)
status:SetShadowColor(0, 0, 0, 1)
status:SetShadowOffset(1, -1)
status:SetWidth(620)
status:SetJustifyH("CENTER")
status:SetPoint("TOP", frame, "TOP", 0, -660)
status:Hide()

local statusElapsed = 0
local function ShowStatus(text)
    status:SetText(text or "")
    statusElapsed = 0
    status:Show()
end

local essenceSeat = CreateFrame("Frame", nil, frame)
essenceSeat:SetSize(142, 34)
SetTopLeft(essenceSeat, 489, 669)

local essenceBacking = essenceSeat:CreateTexture(nil, "BACKGROUND")
essenceBacking:SetAllPoints(essenceSeat)
essenceBacking:SetTexture(0.015, 0.018, 0.022, 0.82)
essenceBacking:Hide()

local essenceRune = essenceSeat:CreateTexture(nil, "OVERLAY")
essenceRune:SetTexture(0.25, 0.72, 1, 1)
essenceRune:SetSize(8, 8)
essenceRune:SetPoint("LEFT", essenceSeat, "LEFT", 8, 0)
essenceRune:Hide()

local essenceText = essenceSeat:CreateFontString(nil, "OVERLAY")
essenceText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
essenceText:SetTextColor(0.88, 0.82, 0.66, 1)
essenceText:SetPoint("TOPLEFT", essenceSeat, "TOPLEFT", 25, -2)
essenceText:SetWidth(109)
essenceText:SetJustifyH("LEFT")
essenceText:SetText("ESSENCE")

local essenceValue = essenceSeat:CreateFontString(nil, "OVERLAY")
essenceValue:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
essenceValue:SetTextColor(0.92, 0.88, 0.76, 1)
essenceValue:SetPoint("BOTTOMRIGHT", essenceSeat, "BOTTOMRIGHT", -8, 1)
essenceValue:SetWidth(109)
essenceValue:SetJustifyH("RIGHT")
essenceValue:SetText("--")
C43.essenceSeat = essenceSeat
C43.essenceText = essenceText
C43.essenceRune = essenceRune
C43.essenceValue = essenceValue

local definitions = {
    progression = { text="PROGRESSION", x=735, y=84,  w=260, h=180, lx=790, ly=168, lw=150 },
    talents     = { text="TALENTS",     x=190, y=170, w=330, h=310, lx=218, ly=322, lw=130 },
    threat      = { text="WORLD THREAT",x=1085,y=42,  w=410, h=300, lx=1183,ly=218, lw=185 },
    crucible    = { text="THE CRUCIBLE",x=1245,y=304, w=355, h=365, lx=1370,ly=505, lw=180 },
    rack        = { text="ATTUNEMENT RACK",x=55,y=470,w=490,h=370,lx=235,ly=692,lw=220 },
    visage      = { text="VISAGE",      x=575, y=690, w=335, h=225, lx=690,ly=840, lw=120 },
    forge       = { text="LEGACY FORGE",x=1005,y=650,w=405,h=255,lx=1100,ly=792,lw=185 },
    core        = { text="WORLDSOUL CORE",x=575,y=255,w=555,h=430,lx=787,ly=571,lw=220, fontSize=16, labelHeight=28, focusHeight=22, home=true },
    codex       = { text="CODEX",       x=54,  y=45,  w=145, h=52,  lx=91, ly=54,  lw=95, focusOffset=-14, utility=true },
    search      = { text="SEARCH",      x=54,  y=95,  w=145, h=52,  lx=91, ly=105, lw=95, utility=true },
    accessibility={text="ACCESSIBILITY",x=1415,y=130,w=205,h=55,lx=1450,ly=145, lw=165, utility=true },
    settings    = { text="",            x=1493,y=64,  w=68,  h=64, lx=1514,ly=77,  lw=38, utility=true, icon=true },
    close       = { text="",            x=1570,y=18,  w=75,  h=72, lx=1591,ly=30,  lw=40, utility=true, icon=true },
}

local navigation = {
    core={UP="progression",DOWN="visage",LEFT="rack",RIGHT="crucible"},
    progression={UP="codex",DOWN="core",LEFT="talents",RIGHT="threat"},
    talents={UP="codex",DOWN="rack",LEFT="search",RIGHT="progression"},
    threat={UP="settings",DOWN="crucible",LEFT="progression",RIGHT="accessibility"},
    crucible={UP="threat",DOWN="forge",LEFT="core",RIGHT="close"},
    rack={UP="talents",DOWN="visage",LEFT="search",RIGHT="core"},
    visage={UP="core",DOWN="forge",LEFT="rack",RIGHT="forge"},
    forge={UP="crucible",DOWN="close",LEFT="visage",RIGHT="close"},
    codex={UP="close",DOWN="talents",LEFT="search",RIGHT="progression"},
    search={UP="codex",DOWN="rack",LEFT="codex",RIGHT="talents"},
    accessibility={UP="close",DOWN="threat",LEFT="threat",RIGHT="settings"},
    settings={UP="close",DOWN="accessibility",LEFT="threat",RIGHT="close"},
    close={UP="settings",DOWN="forge",LEFT="settings",RIGHT="codex"},
}

local function UpdateButtonState(button)
    if button.nativeSuppressed then
        button.focusMark:Hide()
        button.hoverBacking:Hide()
        button.label:Hide()
        if button.hoverVisualTextures then
            button.hoverVisualAlpha = 0
            button.hoverVisualTarget = 0
            button.hoverVisualRenderedAlpha = 0
            for _, texture in ipairs(button.hoverVisualTextures) do
                texture:SetAlpha(0)
            end
        end
        return
    end

    button.label:Show()
    local focused = C43.keyboardFocusActive and C43.focusId == button.id
    local selected = C43.selectedId == button.id
    local hovered = button.hovered

    if focused then button.focusMark:Show() else button.focusMark:Hide() end
    -- Candidate 43 already provides physical label seats in the artwork.
    -- Keep the generated backing permanently hidden so hover/focus cannot
    -- expose a rectangular UI panel over those architectural seats.
    button.hoverBacking:Hide()

    if button.hoverVisualTextures then
        local nextTarget = 0
        if selected then
            nextTarget = button.selectedAlpha
        elseif hovered then
            nextTarget = button.hoverAlpha
        elseif focused then
            nextTarget = button.focusAlpha
        end

        if nextTarget ~= button.hoverVisualTarget then
            button.hoverVisualFrom = button.hoverVisualAlpha or 0
            button.hoverVisualTarget = nextTarget
            button.hoverTransitionElapsed = 0
            button.hoverTransitionDuration = nextTarget > button.hoverVisualFrom and 0.14 or 0.18
        end
    end

    if focused then
        button.label:SetTextColor(1.00, 0.88, 0.48, 1)
    elseif hovered then
        button.label:SetTextColor(0.98, 0.82, 0.38, 1)
    elseif selected then
        button.label:SetTextColor(0.62, 0.87, 1.00, 1)
    else
        button.label:SetTextColor(0.86, 0.76, 0.55, 1)
    end
end

-- Tight source-art crops let the artifact itself wake under the cursor while
-- the larger rectangular hit regions remain completely invisible. Profiles
-- vary by landmark role; low alpha protects Candidate 43's resting hierarchy.
local hoverProfiles = {
    codex =         { color={1.00,0.76,0.34}, hover=0.30, focus=0.14, selected=0.38, crops={{54,45,44,42}} },
    search =        { color={1.00,0.74,0.34}, hover=0.24, focus=0.12, selected=0.32, crops={{57,96,34,40}} },
    accessibility = { color={1.00,0.76,0.34}, hover=0.28, focus=0.14, selected=0.36, crops={{1425,131,30,45}} },
    settings =      { color={1.00,0.72,0.28}, hover=0.38, focus=0.18, selected=0.46, crops={{1510,67,38,38}} },
    close =         { color={1.00,0.72,0.38}, hover=0.40, focus=0.18, selected=0.48, crops={{1590,28,42,42}} },
    progression =   { color={1.00,0.72,0.30}, hover=0.20, focus=0.10, selected=0.28, crops={{805,55,110,100}} },
    talents =       { color={0.72,0.38,1.00}, hover=0.15, focus=0.08, selected=0.23, crops={{350,170,135,145},{350,352,135,118}} },
    threat =        { color={0.48,0.80,1.00}, hover=0.17, focus=0.09, selected=0.25, crops={{1085,145,85,140},{1375,120,80,150}} },
    crucible =      { color={1.00,0.34,0.12}, hover=0.17, focus=0.09, selected=0.25, crops={{1370,330,180,160}} },
    rack =          { color={0.42,0.74,1.00}, hover=0.12, focus=0.07, selected=0.20, crops={{125,500,340,175}} },
    visage =        { color={0.58,0.48,1.00}, hover=0.18, focus=0.09, selected=0.26, crops={{630,705,130,125}} },
    forge =         { color={1.00,0.42,0.14}, hover=0.16, focus=0.08, selected=0.24, crops={{1100,710,230,70},{1100,830,230,70}} },
    core =          { color={0.42,0.78,1.00}, hover=0.09, focus=0.05, selected=0.15, crops={{725,275,300,290}} },
}

local function CreateHoverOverlay(button, id)
    local profile = hoverProfiles[id]
    if not profile then return end

    button.hoverVisualTextures = {}
    button.hoverVisualAlpha = 0
    button.hoverVisualRenderedAlpha = 0
    button.hoverVisualFrom = 0
    button.hoverVisualTarget = 0
    button.hoverTransitionElapsed = 0
    button.hoverTransitionDuration = 0.14
    button.hoverAlpha = profile.hover
    button.focusAlpha = profile.focus
    button.selectedAlpha = profile.selected

    for _, crop in ipairs(profile.crops) do
        local cropX, cropY, cropW, cropH = unpack(crop)
        local cropRight = math.min(cropX + cropW, ART_WIDTH)
        local cropBottom = math.min(cropY + cropH, ART_HEIGHT)
        local pieceY = cropY

        while pieceY < cropBottom do
            local tileRow = math.floor(pieceY / 512)
            local tileTop = tileRow * 512
            local pieceBottom = math.min(cropBottom, tileTop + 512)
            local pieceX = cropX

            while pieceX < cropRight do
                local tileColumn = math.floor(pieceX / 512)
                local tileLeft = tileColumn * 512
                local pieceRight = math.min(cropRight, tileLeft + 512)
                local pieceWidth = pieceRight - pieceX
                local pieceHeight = pieceBottom - pieceY
                local textureName = "C43_" .. tileColumn .. tileRow
                local texture = frame:CreateTexture(nil, "OVERLAY")

                texture:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Assets\\" .. textureName)
                texture:SetSize(pieceWidth, pieceHeight)
                texture:SetPoint("TOPLEFT", frame, "TOPLEFT", pieceX, -pieceY)
                texture:SetTexCoord(
                    (pieceX - tileLeft) / 512,
                    (pieceRight - tileLeft) / 512,
                    (pieceY - tileTop) / 512,
                    (pieceBottom - tileTop) / 512
                )
                texture:SetBlendMode("ADD")
                texture:SetVertexColor(profile.color[1], profile.color[2], profile.color[3])
                texture:SetAlpha(0)
                table.insert(button.hoverVisualTextures, texture)
                pieceX = pieceRight
            end

            pieceY = pieceBottom
        end
    end
end

local function RefreshButtonStates()
    for _, button in pairs(C43.buttons) do
        UpdateButtonState(button)
    end
end

local function SetKeyboardFocus(id)
    if not definitions[id] then return end
    C43.focusId = id
    C43.keyboardFocusActive = true
    RefreshButtonStates()
end

local function SetPointerSelection(id)
    if not definitions[id] then return end
    C43.focusId = id
    C43.keyboardFocusActive = false
    RefreshButtonStates()
end

local function RequestState()
    if APB.echoes and APB.echoes.welcomed then
        local now = GetTime()
        if C43.stateRequestPending and (now - C43.stateRequestTime) < 4 then
            return true
        end
        C43.stateRequestPending = true
        C43.stateRequestTime = now
        if APB.RequestEchoesState then APB:RequestEchoesState()
        else SendChatMessage("#ap state", "SAY") end
        return true
    else
        ShowStatus("Waiting for the Worldsoul connection.")
        return false
    end
end

-- Cold-load routing: a click that misses a native destination's
-- IsAvailable() check can mean two very different things -- the E2J15
-- handshake genuinely hasn't completed yet (a normal, brief window right
-- after login/Dashboard-open that resolves on its own within seconds), or
-- the destination is genuinely unsupported/incompatible once welcomed.
-- Only the second case should open the real gossip fallback; the first
-- should read as "still connecting," exactly like Core's own
-- RequestState() already distinguishes above. Not-ready-yet must never
-- look identical to unsupported. No timer: the existing architecture
-- already re-evaluates IsAvailable() fresh on every click, so the very
-- next click (whether or not the player reopens the Dashboard) recovers
-- automatically once the handshake actually completes.
local function NativeUnavailable(label)
    if not (APB.echoes and APB.echoes.welcomed) then
        ShowStatus("Waiting for the Worldsoul connection.")
        return
    end
    ShowStatus("Native " .. label .. " unavailable; opening the gossip fallback.")
    SendChatMessage("ap", "SAY")
end

local BeginOpen
local BeginClose

local function NotifyMotion(state)
    for _, callback in pairs(C43.motionListeners) do
        local ok, err = pcall(callback, state)
        if not ok then
            print("|cffff5555[Echoes]|r Dashboard motion listener failed: " .. tostring(err))
        end
    end
end

local function Activate(id)
    if id == "close" then
        BeginClose()
        return
    elseif id == "core" then
        if RequestState() then
            ShowStatus("Worldsoul state requested.")
        end
    elseif id == "accessibility" then
        local UI=EchoesUI; local screen=UI and UI.ScreenManager and UI.ScreenManager.registry.accessibility
        if screen and (not screen.IsAvailable or screen:IsAvailable()) and UI.ScreenManager:Show("accessibility") then return end
        ShowStatus("Accessibility is unavailable in this client build.")
    elseif id == "settings" then
        local UI=EchoesUI; local screen=UI and UI.ScreenManager and UI.ScreenManager.registry.settings
        if screen and (not screen.IsAvailable or screen:IsAvailable()) and UI.ScreenManager:Show("settings") then return end
        ShowStatus("Settings are unavailable in this client build.")
    elseif id == "codex" then
        local UI=EchoesUI; local screen=UI and UI.ScreenManager and UI.ScreenManager.registry.codex
        if screen and (not screen.IsAvailable or screen:IsAvailable()) and UI.ScreenManager:Show("codex") then return end
        NativeUnavailable("Codex")
    elseif id == "search" then
        local UI=EchoesUI; local screen=UI and UI.ScreenManager and UI.ScreenManager.registry.search
        if screen and (not screen.IsAvailable or screen:IsAvailable()) and UI.ScreenManager:Show("search") then return end
        NativeUnavailable("Search")
    elseif id == "progression" then
        local UI = EchoesUI
        if UI and UI.flags and UI.flags.nativeProgression ~= false
            and UI.ScreenManager and UI.ScreenManager.Show
            and UI.ScreenManager:Show("progression") then
            UI:Debug("landmark activated -> progression route entered")
            return
        end
        NativeUnavailable("Progression")
    elseif id == "threat" then
        local UI = EchoesUI
        if UI and UI.flags and UI.flags.nativeWorldThreat ~= false
            and UI.ScreenManager and UI.ScreenManager.Show
            and UI.ScreenManager:Show("threat") then
            UI:Debug("landmark activated -> World Threat route entered")
            return
        end
        NativeUnavailable("World Threat")
    elseif id == "crucible" then
        local UI = EchoesUI
        if UI and UI.flags and UI.flags.nativeCrucible ~= false
            and UI.ScreenManager and UI.ScreenManager.Show
            and UI.ScreenManager:Show("crucible") then
            UI:Debug("landmark activated -> Crucible route entered")
            return
        end
        NativeUnavailable("Crucible")
    elseif id == "talents" then
        local UI = EchoesUI
        local screen = UI and UI.ScreenManager and UI.ScreenManager.registry
            and UI.ScreenManager.registry.talents
        if UI and UI.flags and UI.flags.nativeTalents ~= false and screen
            and (not screen.IsAvailable or screen:IsAvailable())
            and UI.ScreenManager:Show("talents") then
            UI:Debug("landmark activated -> Talents route entered")
            return
        end
        NativeUnavailable("Talents")
    elseif id == "rack" then
        local UI = EchoesUI
        local screen = UI and UI.ScreenManager and UI.ScreenManager.registry
            and UI.ScreenManager.registry.rack
        if UI and UI.flags and UI.flags.nativeRack ~= false and screen
            and (not screen.IsAvailable or screen:IsAvailable())
            and UI.ScreenManager:Show("rack") then
            UI:Debug("landmark activated -> Attunement Rack route entered")
            return
        end
        NativeUnavailable("Attunement Rack")
    elseif id == "forge" then
        local UI = EchoesUI
        local screen = UI and UI.ScreenManager and UI.ScreenManager.registry
            and UI.ScreenManager.registry.forge
        if UI and UI.flags and UI.flags.nativeForge ~= false and screen
            and (not screen.IsAvailable or screen:IsAvailable())
            and UI.ScreenManager:Show("forge") then
            UI:Debug("landmark activated -> Legacy Forge route entered")
            return
        end
        NativeUnavailable("Legacy Forge")
    elseif id == "visage" then
        local UI = EchoesUI
        local screen = UI and UI.ScreenManager and UI.ScreenManager.registry
            and UI.ScreenManager.registry.visage
        if UI and UI.flags and UI.flags.nativeVisage ~= false and screen
            and (not screen.IsAvailable or screen:IsAvailable())
            and UI.ScreenManager:Show("visage") then
            UI:Debug("landmark activated -> Visage route entered")
            return
        end
        NativeUnavailable("Visage")
    else
        ShowStatus(definitions[id].text:gsub("\n", " ") .. " route ready; destination interface pending.")
    end

    C43.selectedId = id
    RefreshButtonStates()
    C_Timer.After(0.12, function()
        if C43.selectedId == id then
            C43.selectedId = nil
            RefreshButtonStates()
        end
    end)
end

local function CreateLandmarkButton(id, def)
    local button = CreateFrame("Button", "EchoesC43_" .. id, frame)
    button.id = id
    button.isUtility = def.utility or false
    button:SetSize(def.w, def.h)
    SetTopLeft(button, def.x, def.y)
    button:RegisterForClicks("LeftButtonUp")

    local labelBacking = button:CreateTexture(nil, "OVERLAY")
    labelBacking:SetTexture(0.01, 0.012, 0.015, 0.82)
    labelBacking:SetSize(def.lw + 18, def.home and 50 or 32)
    labelBacking:SetPoint("TOPLEFT", frame, "TOPLEFT", def.lx - 9, -(def.ly - 5))
    labelBacking:Hide()
    button.hoverBacking = labelBacking

    local label = button:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\MORPHEUS.TTF", def.fontSize or (def.icon and 25 or 18), "OUTLINE")
    label:SetText(def.text)
    label:SetWidth(def.lw)
    label:SetHeight(def.labelHeight or (def.home and 46 or 28))
    label:SetJustifyH("CENTER")
    label:SetJustifyV("MIDDLE")
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", def.lx, -def.ly)
    button.label = label
    button.baseFontSize = def.fontSize or (def.icon and 25 or 18)

    -- A small structural bracket at the label seat communicates keyboard
    -- focus without exposing the rectangular interaction region.
    local focusMark = button:CreateTexture(nil, "OVERLAY")
    focusMark:SetTexture(0.95, 0.70, 0.20, 1)
    focusMark:SetSize(3, def.focusHeight or (def.home and 38 or 22))
    focusMark:SetPoint("RIGHT", label, "LEFT", def.focusOffset or -5, 0)
    focusMark:Hide()
    button.focusMark = focusMark

    CreateHoverOverlay(button, id)

    button:SetScript("OnEnter", function(self)
        self.hovered = true
        UpdateButtonState(self)
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = false
        UpdateButtonState(self)
    end)
    button:SetScript("OnClick", function(self)
        SetPointerSelection(self.id)
        Activate(self.id)
    end)

    C43.buttons[id] = button
    UpdateButtonState(button)
end

for id, def in pairs(definitions) do
    CreateLandmarkButton(id, def)
end

local function UpdateScale()
    local sw = UIParent:GetWidth() or ART_WIDTH
    local sh = UIParent:GetHeight() or ART_HEIGHT
    local scale = math.min((sw * VIEWPORT_FIT) / ART_WIDTH, (sh * VIEWPORT_FIT) / ART_HEIGHT, MAX_DASHBOARD_SCALE)
    if scale <= 0 then scale = 1 end
    C43.scale = scale
    frame:SetScale(scale)

    for _, button in pairs(C43.buttons) do
        local physicalSize = button.baseFontSize * scale
        local localSize = button.baseFontSize
        if physicalSize < MIN_PHYSICAL_LABEL then
            localSize = MIN_PHYSICAL_LABEL / scale
        end
        button.label:SetFont("Fonts\\MORPHEUS.TTF", localSize, "OUTLINE")
    end
end

local function UpdateState(force)
    local echoes = APB.echoes
    if not echoes or not echoes.lastState then return end
    if not force and C43.stateStamp == echoes.lastStateTime then return end
    C43.stateStamp = echoes.lastStateTime
    C43.stateRequestPending = false

    local value = tonumber(echoes.lastState.essence)
    if value then
        local formatted = tostring(math.floor(value)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        essenceValue:SetText(formatted)
    else
        essenceValue:SetText("--")
    end
end

local OPEN_DURATION = 0.30
local CLOSE_DURATION = 0.18
local pollElapsed = 0

local function SmoothStep(value)
    local clamped = math.max(0, math.min(1, value))
    return clamped * clamped * (3 - 2 * clamped)
end

local function SetInteractionEnabled(enabled)
    frame:EnableKeyboard(enabled)
    for _, button in pairs(C43.buttons) do
        button:EnableMouse(enabled and not button.nativeSuppressed)
    end
end

local function SetOpeningTextAlpha(elapsed)
    for _, button in pairs(C43.buttons) do
        local delay = button.id == "core" and 0.03 or (button.isUtility and 0.07 or 0.05)
        local progress = SmoothStep((elapsed - delay) / 0.20)
        local startAlpha = button.motionLabelFrom or 0
        button.label:SetAlpha(startAlpha + (1 - startAlpha) * progress)
    end

    local essenceProgress = SmoothStep((elapsed - 0.05) / 0.20)
    local essenceStart = C43.motionEssenceFrom or 0
    essenceSeat:SetAlpha(essenceStart + (1 - essenceStart) * essenceProgress)
end

local function FinishOpen()
    C43.motionState = "OPEN"
    NotifyMotion("OPEN")
    C43.motionElapsed = 0
    C43.openingCoreBoost = 0
    frame:SetAlpha(1)
    for _, button in pairs(C43.buttons) do
        button.label:SetAlpha(1)
    end
    essenceSeat:SetAlpha(1)
    SetInteractionEnabled(true)
end

BeginOpen = function()
    local previousState = C43.motionState
    if previousState == "OPEN" or previousState == "OPENING" then return end
    local wasClosing = previousState == "CLOSING"

    C43.motionState = "OPENING"
    NotifyMotion("OPENING")
    C43.motionElapsed = 0
    C43.openingCoreBoost = 0

    if not frame:IsShown() then
        frame:Show()
    end

    UpdateScale()
    C43.focusId = C43.focusId or "core"
    C43.keyboardFocusActive = false
    RefreshButtonStates()
    UpdateState(true)
    C43.welcomedObserved = APB.echoes and APB.echoes.welcomed or false
    RequestState()

    if C43DB.reducedMotion then
        FinishOpen()
        return
    end

    C43.motionAlphaFrom = wasClosing and frame:GetAlpha() or 0.18
    frame:SetAlpha(C43.motionAlphaFrom)
    for _, button in pairs(C43.buttons) do
        button.motionLabelFrom = wasClosing and button.label:GetAlpha() or 0
        button.label:SetAlpha(button.motionLabelFrom)
    end
    C43.motionEssenceFrom = wasClosing and essenceSeat:GetAlpha() or 0
    essenceSeat:SetAlpha(C43.motionEssenceFrom)
    SetInteractionEnabled(true)
end

BeginClose = function()
    if C43.motionState == "CLOSED" or C43.motionState == "CLOSING" then return end

    if C43DB.reducedMotion then
        C43.motionState = "CLOSED"
        NotifyMotion("CLOSED")
        frame:Hide()
        return
    end

    C43.motionState = "CLOSING"
    NotifyMotion("CLOSING")
    C43.motionElapsed = 0
    C43.openingCoreBoost = 0
    C43.motionAlphaFrom = frame:GetAlpha()
    SetInteractionEnabled(false)
end

frame:SetScript("OnUpdate", function(self, elapsed)
    pollElapsed = pollElapsed + elapsed
    if pollElapsed >= 0.20 then
        pollElapsed = 0
        UpdateState()
        local echoes = APB.echoes
        if self:IsShown() and echoes and echoes.welcomed and not C43.welcomedObserved then
            C43.welcomedObserved = true
            if not echoes.lastState then
                RequestState()
            end
        end
    end

    if status:IsShown() then
        statusElapsed = statusElapsed + elapsed
        if statusElapsed >= 2.8 then status:Hide() end
    end

    if C43.motionState == "OPENING" then
        C43.motionElapsed = C43.motionElapsed + elapsed
        local progress = SmoothStep(C43.motionElapsed / OPEN_DURATION)
        self:SetAlpha(C43.motionAlphaFrom + (1 - C43.motionAlphaFrom) * progress)
        SetOpeningTextAlpha(C43.motionElapsed)

        local coreProgress = math.max(0, math.min(1, C43.motionElapsed / 0.24))
        C43.openingCoreBoost = 0.045 * math.sin(math.pi * coreProgress)
        if C43.motionElapsed >= OPEN_DURATION then
            FinishOpen()
        end
    elseif C43.motionState == "CLOSING" then
        C43.motionElapsed = C43.motionElapsed + elapsed
        local progress = SmoothStep(C43.motionElapsed / CLOSE_DURATION)
        self:SetAlpha(C43.motionAlphaFrom * (1 - progress))
        if C43.motionElapsed >= CLOSE_DURATION then
            C43.motionState = "CLOSED"
            self:Hide()
            return
        end
    end

    for _, button in pairs(C43.buttons) do
        if button.hoverVisualTextures then
            local target = button.hoverVisualTarget or 0
            local current = button.hoverVisualAlpha or 0
            if C43DB.reducedMotion then
                current = target
            elseif current ~= target then
                button.hoverTransitionElapsed = (button.hoverTransitionElapsed or 0) + elapsed
                local duration = button.hoverTransitionDuration or 0.14
                local progress = SmoothStep(button.hoverTransitionElapsed / duration)
                local from = button.hoverVisualFrom or current
                current = from + (target - from) * progress
                if button.hoverTransitionElapsed >= duration then
                    current = target
                end
            end
            button.hoverVisualAlpha = current
            local effectiveAlpha = current
            if button.id == "core" then
                effectiveAlpha = math.min(1, effectiveAlpha + C43.openingCoreBoost)
            end
            if math.abs(effectiveAlpha - (button.hoverVisualRenderedAlpha or 0)) > 0.0005 then
                button.hoverVisualRenderedAlpha = effectiveAlpha
                for _, texture in ipairs(button.hoverVisualTextures) do
                    texture:SetAlpha(effectiveAlpha)
                end
            end
        end
    end
end)

frame:SetScript("OnShow", function(self)
    if C43.motionState == "CLOSED" then
        BeginOpen()
    end
end)

frame:SetScript("OnHide", function(self)
    C43.motionState = "CLOSED"
    NotifyMotion("CLOSED")
    C43.motionElapsed = 0
    C43.openingCoreBoost = 0
    self:SetAlpha(1)
    SetInteractionEnabled(true)
    status:Hide()
    for _, button in pairs(C43.buttons) do
        button.hovered = false
        button.label:SetAlpha(1)
        button.motionLabelFrom = nil
        button.hoverVisualFrom = 0
        button.hoverVisualTarget = 0
        button.hoverVisualAlpha = 0
        button.hoverVisualRenderedAlpha = 0
        button.hoverTransitionElapsed = 0
        if button.hoverVisualTextures then
            for _, texture in ipairs(button.hoverVisualTextures) do
                texture:SetAlpha(0)
            end
        end
    end
    essenceSeat:SetAlpha(1)
end)

frame:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
        BeginClose()
        return
    elseif key == "ENTER" or key == "SPACE" then
        SetKeyboardFocus(C43.focusId)
        Activate(C43.focusId)
        return
    elseif key == "TAB" then
        local current = 1
        for index, id in ipairs(C43.orderedIds) do
            if id == C43.focusId then current = index break end
        end
        local delta = IsShiftKeyDown() and -1 or 1
        local nextIndex = current + delta
        if nextIndex < 1 then nextIndex = #C43.orderedIds end
        if nextIndex > #C43.orderedIds then nextIndex = 1 end
        SetKeyboardFocus(C43.orderedIds[nextIndex])
        return
    end

    local graph = navigation[C43.focusId]
    if graph and graph[key] then
        SetKeyboardFocus(graph[key])
    end
end)

function C43:Show()
    BeginOpen()
end

function C43:Hide()
    BeginClose()
end

function C43:Toggle()
    if C43.motionState == "CLOSED" or C43.motionState == "CLOSING" then
        BeginOpen()
    else
        BeginClose()
    end
end

function C43:SubscribeMotion(callback)
    if type(callback) ~= "function" then return nil end
    local token = {}
    self.motionListeners[token] = callback
    return function() self.motionListeners[token] = nil end
end

SLASH_ECHOESC43DASHBOARD1 = "/echoes"
SlashCmdList["ECHOESC43DASHBOARD"] = function(input)
    local cmd = (input or ""):lower():match("^%s*(%S*)")
    if cmd == "gossip" then
        SendChatMessage("ap", "SAY")
    elseif cmd == "scale" then
        print(string.format("|cff66ccff[Echoes]|r Candidate 43 scale: %.0f%%", C43.scale * 100))
    else
        C43:Toggle()
    end
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("DISPLAY_SIZE_CHANGED")
bootstrap:RegisterEvent("UI_SCALE_CHANGED")
bootstrap:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0, function()
            local minimap = _G["APBMinimapButton"]
            if not minimap then
                print("|cffffaa00[Echoes]|r Candidate 43 loaded; use /echoes to open the Dashboard.")
                return
            end

            minimap:SetScript("OnClick", function(button, mouseButton)
                if button.c43Dragging then return end
                if mouseButton == "LeftButton" then
                    C43:Toggle()
                elseif mouseButton == "RightButton" then
                    AttunementPlusBridgeDB.cache = {}
                    print("|cff9966ff[EotW]|r Tooltip cache cleared.")
                end
            end)

            minimap:HookScript("OnDragStart", function(button)
                button.c43Dragging = true
            end)
            minimap:HookScript("OnDragStop", function(button)
                C_Timer.After(0, function()
                    button.c43Dragging = false
                end)
            end)

            minimap:SetScript("OnEnter", function(button)
                GameTooltip:SetOwner(button, "ANCHOR_LEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine("|cff66ccffEchoes of the Worldsoul|r")
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffffffffLeft-click: Open Dashboard|r")
                GameTooltip:AddLine("|cffaaaaaaRight-click: Clear tooltip cache|r")
                GameTooltip:AddLine("|cffaaaaaaDrag: Move button|r")
                GameTooltip:Show()
            end)
        end)
        self:UnregisterEvent("PLAYER_LOGIN")
    else
        UpdateScale()
    end
end)

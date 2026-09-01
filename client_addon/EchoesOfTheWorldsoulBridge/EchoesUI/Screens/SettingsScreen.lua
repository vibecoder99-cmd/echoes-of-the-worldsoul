local UI = EchoesUI
if not UI or not UI.UtilityShell or not UI.ScreenManager then return end
local Theme = UI.Theme
local ASSET = "Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\"
local function Art(parent, layer, name, uMax, vMax)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(ASSET .. name)
    t:SetTexCoord(0, uMax, 0, vMax)
    return t
end
local function ArtMirrored(parent, layer, name, uMax, vMax)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(ASSET .. name)
    t:SetTexCoord(uMax, 0, 0, vMax)
    return t
end
local function NeutralizeRow(row)
    Theme:SetTextureColor(row.channel, {0, 0, 0, 0})
    Theme:SetTextureColor(row.selection, {0, 0, 0, 0})
    Theme:SetTextureColor(row.edge, {0, 0, 0, 0})
end
-- resting < hover/focus (shared nav keys)
local function WireTwoState(row, resting, focus)
    NeutralizeRow(row)
    row.onStateChange = function(self)
        if self.focused or self.hovered then resting:Hide(); focus:Show()
        else focus:Hide(); resting:Show() end
    end
    row.onStateChange(row)
end
-- resting < hover/focus < press (Settings route; ProgressionRow already
-- exposes a genuine self.pressed boolean, so no state is invented)
local function WireThreeStatePress(row, resting, focus, pressed)
    NeutralizeRow(row)
    row.onStateChange = function(self)
        if self.pressed then resting:Hide(); focus:Hide(); pressed:Show()
        elseif self.focused or self.hovered then resting:Hide(); pressed:Hide(); focus:Show()
        else focus:Hide(); pressed:Hide(); resting:Show() end
    end
    row.onStateChange(row)
end

local Screen = UI.UtilityShell:Create({
    id="settings", name="EchoesUISettingsScreen", title="SETTINGS",
    subtitle="A SMALL, HONEST CONFIGURATION LEDGER",
})

-- Settings-local shared-shell material pass. Each UtilityShell:Create() call
-- builds its own independent frame/texture set, so this only affects this
-- Settings instance -- Codex/Search/Accessibility keep their own. The native
-- 0.96 veil is intentionally left untouched: Settings/Accessibility must
-- retain their existing strong environmental suppression, unlike Codex/
-- Search's reduced, more atmospheric veil.
Screen.rimPanel:SetAlpha(0)
Screen.corePanel:SetAlpha(0)
Screen.headerPlate:SetAlpha(0)
Screen.headerLine:SetAlpha(0)

local headerCrown = Art(Screen.frame, "ARTWORK", "UtilityHeaderCrown", 0.63476562, 0.546875)
headerCrown:SetSize(650, 70); headerCrown:SetPoint("TOP", Screen.frame, "TOP", 0, -22); headerCrown:SetAlpha(0.78)

local shellTopRail = Art(Screen.frame, "ARTWORK", "UtilityShellTopRail", 0.609375, 0.75)
shellTopRail:SetSize(1248, 48); shellTopRail:SetPoint("TOP", Screen.frame, "TOP", 0, -20); shellTopRail:SetAlpha(0.62)

local shellSideSpineL = Art(Screen.frame, "ARTWORK", "UtilityShellSideSpine", 0.53125, 0.60546875)
shellSideSpineL:SetSize(34, 620); shellSideSpineL:SetPoint("TOPLEFT", Screen.frame, "TOPLEFT", 16, -82); shellSideSpineL:SetAlpha(0.56)
local shellSideSpineR = ArtMirrored(Screen.frame, "ARTWORK", "UtilityShellSideSpine", 0.53125, 0.60546875)
shellSideSpineR:SetSize(34, 620); shellSideSpineR:SetPoint("TOPRIGHT", Screen.frame, "TOPRIGHT", -16, -82); shellSideSpineR:SetAlpha(0.56)

local shellLower = Art(Screen.frame, "ARTWORK", "UtilityShellLowerTerminus", 0.609375, 0.59375)
shellLower:SetSize(1248, 38); shellLower:SetPoint("BOTTOM", Screen.frame, "BOTTOM", 0, 20); shellLower:SetAlpha(0.54)

-- Shared navigation keys (Back / Core-Home / Close) live on UtilityShell.lua's
-- shell.back/home/close fields, but each instance belongs to this Settings
-- frame alone -- art and neutralization are attached here, never in the
-- shared file.
for _, id in ipairs({"back", "home", "close"}) do
    local row = Screen[id]
    local resting = Art(row.root, "ARTWORK", "UtilityNavKeyResting", 0.5390625, 0.59375)
    resting:SetSize(138, 38); resting:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); resting:SetAlpha(0.74)
    local focus = Art(row.root, "ARTWORK", "UtilityNavKeyFocus", 0.5390625, 0.59375)
    focus:SetSize(138, 38); focus:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); focus:SetAlpha(0.9)
    WireTwoState(row, resting, focus)
end

-- UtilityCanvasAnchors.tga (2048x1024) is RETIRED -- NATIVE CLIENT SIZE
-- INCOMPATIBILITY (confirmed causal for ERROR #132 in isolated live testing
-- on 2026-08-27). Replaced by four non-overlapping 565x287 quadrants, each a
-- 1024x512 POT tile (2 MiB), reassembling the identical 1130x574 visible
-- composition. Do not load UtilityCanvasAnchors.tga.
local canvasAnchorTL = Art(Screen.content, "ARTWORK", "UtilityCanvasAnchorsTL", 0.5517578125, 0.560546875)
canvasAnchorTL:SetSize(565, 287); canvasAnchorTL:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 0, 0); canvasAnchorTL:SetAlpha(0.32)
local canvasAnchorTR = Art(Screen.content, "ARTWORK", "UtilityCanvasAnchorsTR", 0.5517578125, 0.560546875)
canvasAnchorTR:SetSize(565, 287); canvasAnchorTR:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 565, 0); canvasAnchorTR:SetAlpha(0.32)
local canvasAnchorBL = Art(Screen.content, "ARTWORK", "UtilityCanvasAnchorsBL", 0.5517578125, 0.560546875)
canvasAnchorBL:SetSize(565, 287); canvasAnchorBL:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 0, -287); canvasAnchorBL:SetAlpha(0.32)
local canvasAnchorBR = Art(Screen.content, "ARTWORK", "UtilityCanvasAnchorsBR", 0.5517578125, 0.560546875)
canvasAnchorBR:SetSize(565, 287); canvasAnchorBR:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 565, -287); canvasAnchorBR:SetAlpha(0.32)

local function Text(text, y, size, color)
    local fs=Screen.content:CreateFontString(nil,"OVERLAY")
    fs:SetFont(Theme.fonts.readable,size or 13); fs:SetText(text)
    fs:SetTextColor(unpack(color or Theme.colors.textMuted)); fs:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",40,-y)
    fs:SetWidth(1050); fs:SetHeight(46); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    return fs
end

-- UtilitySectionRail (2048x32, low-risk: smaller pixel count than every
-- other 2048-wide asset already proven safe in A-F/Codex/Search) rolled into
-- the control baseline without a separate human test, per independent audit.
local sectionRailTop = Art(Screen.content, "ARTWORK", "UtilitySectionRail", 0.51269531, 0.8125)
sectionRailTop:SetSize(1050, 26); sectionRailTop:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 40, -24); sectionRailTop:SetAlpha(0.62)
local copyAnchor = Art(Screen.content, "ARTWORK", "SettingsCopyAnchor", 0.51269531, 0.56640625)
copyAnchor:SetSize(1050, 145); copyAnchor:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 40, -24); copyAnchor:SetAlpha(0.48)

Text("CLIENT CONFIGURATION",24,11,Theme.colors.bronzeBright)
Text("No ordinary Worldsoul preferences currently require configuration.",55,18,Theme.colors.text)
Text("Keyboard navigation, visible focus, chat-safe input, and the native gameplay screens are always available when supported. Debug state and minimap position remain developer/self-managed and are not presented as player settings.",102,13)

local access=UI.ProgressionRow:Create(Screen.content,{
    id="openAccessibility",name="EchoesUISettingsAccessibility",width=650,height=76,icon=false,
    label="OPEN ACCESSIBILITY",meta="Reduced Motion is managed there",value="›",
    accentColor=Theme.colors.worldsoul,focusColor=Theme.colors.worldsoul,
    onActivate=function() Screen:Hide(); UI.ScreenManager:Show("accessibility",false) end,
})
access.root:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",40,-190)
Screen.accessibility=access; Screen:AddControl(access,"openAccessibility")
local routeResting = Art(access.root, "ARTWORK", "SettingsRouteResting", 0.63476562, 0.59375)
routeResting:SetSize(650, 76); routeResting:SetPoint("TOPLEFT", access.root, "TOPLEFT", 0, 0); routeResting:SetAlpha(0.78)
local routeFocus = Art(access.root, "ARTWORK", "SettingsRouteFocus", 0.63476562, 0.59375)
routeFocus:SetSize(650, 76); routeFocus:SetPoint("TOPLEFT", access.root, "TOPLEFT", 0, 0); routeFocus:SetAlpha(0.92)
local routePressed = Art(access.root, "ARTWORK", "SettingsRoutePressed", 0.63476562, 0.59375)
routePressed:SetSize(650, 76); routePressed:SetPoint("TOPLEFT", access.root, "TOPLEFT", 0, 0); routePressed:SetAlpha(0.96)
WireThreeStatePress(access, routeResting, routeFocus, routePressed)

-- Chaos occupies the source-audited unused right-hand region beside the
-- Accessibility route. Activation is authoritative character state.
local chaos=UI.ProgressionRow:Create(Screen.content,{
    id="toggleChaos",name="EchoesUISettingsChaos",width=380,height=76,icon=false,
    label="CHAOS NUMBERS",meta="Express combat in Chaos-scale units",value="OFF",valueWidth=56,
    tooltip="Expresses combat values at a larger logical scale.\nNative combat rules and relative power remain unchanged.",
    accentColor=Theme.colors.worldsoul,focusColor=Theme.colors.worldsoul,
    onActivate=function() UI.Chaos:Toggle() end,
})
chaos.root:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",710,-190)
Screen.chaos=chaos; Screen:AddControl(chaos,"toggleChaos")
UI.Chaos:Subscribe(function(state)
    chaos:SetData({label="CHAOS NUMBERS",meta="Express combat in Chaos-scale units",
        value=state.enabled and "ON" or "OFF",tooltip=chaos.tooltip})
end)

local sectionRailStorage = Art(Screen.content, "ARTWORK", "UtilitySectionRail", 0.51269531, 0.8125)
sectionRailStorage:SetSize(1050, 26); sectionRailStorage:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 40, -320); sectionRailStorage:SetAlpha(0.62)
local storageRail = Art(Screen.content, "ARTWORK", "SettingsStorageRail", 0.51269531, 0.671875)
storageRail:SetSize(1050, 86); storageRail:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 40, -320); storageRail:SetAlpha(0.48)

Text("STORAGE",320,11,Theme.colors.bronzeBright)
Text("Reduced Motion is stored account-wide in AttunementPlusBridgeDB and applies immediately. No server data is changed by this utility suite.",350,13)
Screen.input:SetNavigation({"openAccessibility","toggleChaos","back","home","close"},{
    openAccessibility={UP="back",DOWN="back",RIGHT="toggleChaos"},
    toggleChaos={UP="home",DOWN="home",LEFT="openAccessibility",RIGHT="home"},
    back={DOWN="openAccessibility"},
    home={DOWN="toggleChaos",RIGHT="close"},close={LEFT="home",DOWN="toggleChaos"},
})
Screen.defaultFocus="openAccessibility"
function Screen:IsAvailable() return UI.flags.nativeSettings ~= false end
function Screen:Show() UI.UtilityShell.Show(self,"openAccessibility") end
UI.SettingsScreen=Screen; UI.ScreenManager:Register("settings",Screen,false); UI.modules.SettingsScreen=true

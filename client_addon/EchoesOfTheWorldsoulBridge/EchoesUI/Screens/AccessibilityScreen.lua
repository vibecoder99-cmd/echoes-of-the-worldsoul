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
-- Reduced Motion: OFF/resting and ON/active are the persistent DB-driven base
-- (mutually exclusive); focus is transient and always wins over whichever
-- base is currently showing, so it stays visible regardless of ON/OFF -- no
-- state is ever stacked.
local function WireToggle(row, off, on, focus, isOn)
    NeutralizeRow(row)
    row.onStateChange = function(self)
        if self.focused or self.hovered then off:Hide(); on:Hide(); focus:Show()
        elseif isOn() then off:Hide(); focus:Hide(); on:Show()
        else on:Hide(); focus:Hide(); off:Show() end
    end
    row.onStateChange(row)
end

local Screen = UI.UtilityShell:Create({
    id="accessibility", name="EchoesUIAccessibilityScreen", title="ACCESSIBILITY",
    subtitle="MOTION AND INPUT BEHAVIOR", accentColor=Theme.colors.worldsoul,
})

-- Accessibility-local shared-shell material pass. Each UtilityShell:Create()
-- call builds its own independent frame/texture set, so this only affects
-- this Accessibility instance -- Codex/Search/Settings keep their own. The
-- native 0.96 veil is intentionally left untouched: Settings/Accessibility
-- must retain their existing strong environmental suppression.
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
-- shell.back/home/close fields, but each instance belongs to this
-- Accessibility frame alone -- art and neutralization are attached here,
-- never in the shared file.
for _, id in ipairs({"back", "home", "close"}) do
    local row = Screen[id]
    local resting = Art(row.root, "ARTWORK", "UtilityNavKeyResting", 0.5390625, 0.59375)
    resting:SetSize(138, 38); resting:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); resting:SetAlpha(0.74)
    local focus = Art(row.root, "ARTWORK", "UtilityNavKeyFocus", 0.5390625, 0.59375)
    focus:SetSize(138, 38); focus:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); focus:SetAlpha(0.9)
    WireTwoState(row, resting, focus)
end

-- UtilityCanvasAnchors.tga (2048x1024) is RETIRED -- NATIVE CLIENT SIZE
-- INCOMPATIBILITY (confirmed causal for ERROR #132 in isolated Settings live
-- testing). Replaced by the same four proven-safe 565x287/1024x512-POT
-- quadrants already live-tested in Settings, reused here with identical
-- geometry/UV/alpha -- no new seam compensation. Do not load
-- UtilityCanvasAnchors.tga.
local canvasAnchorTL = Art(Screen.content, "ARTWORK", "UtilityCanvasAnchorsTL", 0.5517578125, 0.560546875)
canvasAnchorTL:SetSize(565, 287); canvasAnchorTL:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 0, 0); canvasAnchorTL:SetAlpha(0.32)
local canvasAnchorTR = Art(Screen.content, "ARTWORK", "UtilityCanvasAnchorsTR", 0.5517578125, 0.560546875)
canvasAnchorTR:SetSize(565, 287); canvasAnchorTR:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 565, 0); canvasAnchorTR:SetAlpha(0.32)
local canvasAnchorBL = Art(Screen.content, "ARTWORK", "UtilityCanvasAnchorsBL", 0.5517578125, 0.560546875)
canvasAnchorBL:SetSize(565, 287); canvasAnchorBL:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 0, -287); canvasAnchorBL:SetAlpha(0.32)
local canvasAnchorBR = Art(Screen.content, "ARTWORK", "UtilityCanvasAnchorsBR", 0.5517578125, 0.560546875)
canvasAnchorBR:SetSize(565, 287); canvasAnchorBR:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 565, -287); canvasAnchorBR:SetAlpha(0.32)

local introRail = Art(Screen.content, "ARTWORK", "AccessibilityIntroRail", 0.5078125, 0.78125)
introRail:SetSize(1040, 50); introRail:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 40, -28); introRail:SetAlpha(0.44)
local intro=Screen.content:CreateFontString(nil,"OVERLAY")
intro:SetFont(Theme.fonts.readable,14); intro:SetText("One player-controlled accessibility preference is currently supported. Other input protections are always on.")
intro:SetTextColor(unpack(Theme.colors.textMuted)); intro:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",40,-28); intro:SetWidth(1040); intro:SetHeight(40); intro:SetJustifyH("LEFT")

local toggle=UI.ProgressionRow:Create(Screen.content,{
    id="reducedMotion",name="EchoesUIAccessibilityReducedMotion",width=760,height=86,icon=false,
    label="REDUCED MOTION",meta="Removes decorative transitions and response movement",value="OFF",
    accentColor=Theme.colors.worldsoul,focusColor=Theme.colors.worldsoul,
    onActivate=function()
        AttunementPlusBridgeDB.c43=AttunementPlusBridgeDB.c43 or {}
        AttunementPlusBridgeDB.c43.reducedMotion=not AttunementPlusBridgeDB.c43.reducedMotion
        Screen:Refresh()
    end,
})
toggle.root:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",40,-100)
Screen.toggle=toggle; Screen:AddControl(toggle,"reducedMotion")
local toggleOff = Art(toggle.root, "ARTWORK", "AccessibilityToggleOff", 0.7421875, 0.671875)
toggleOff:SetSize(760, 86); toggleOff:SetPoint("TOPLEFT", toggle.root, "TOPLEFT", 0, 0); toggleOff:SetAlpha(0.8)
local toggleOn = Art(toggle.root, "ARTWORK", "AccessibilityToggleOn", 0.7421875, 0.671875)
toggleOn:SetSize(760, 86); toggleOn:SetPoint("TOPLEFT", toggle.root, "TOPLEFT", 0, 0); toggleOn:SetAlpha(0.9)
local toggleFocus = Art(toggle.root, "ARTWORK", "AccessibilityToggleFocus", 0.7421875, 0.671875)
toggleFocus:SetSize(760, 86); toggleFocus:SetPoint("TOPLEFT", toggle.root, "TOPLEFT", 0, 0); toggleFocus:SetAlpha(0.94)
WireToggle(toggle, toggleOff, toggleOn, toggleFocus, function() return UI:IsReducedMotion() end)

local assuranceBed = Art(Screen.content, "ARTWORK", "AccessibilityAssuranceBed", 0.78125, 0.5859375)
assuranceBed:SetSize(800, 150); assuranceBed:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 40, -250); assuranceBed:SetAlpha(0.5)
local always=Screen.content:CreateFontString(nil,"OVERLAY")
always:SetFont(Theme.fonts.readable,13); always:SetText("ALWAYS ON\n\n• Keyboard navigation and visible focus\n• Chat-focus guard for Dashboard shortcuts\n• Escape / Back / Core / Close navigation")
always:SetTextColor(unpack(Theme.colors.text)); always:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",40,-250); always:SetWidth(800); always:SetHeight(150); always:SetJustifyH("LEFT"); always:SetJustifyV("TOP")
function Screen:Refresh()
    local reduced=UI:IsReducedMotion(); toggle.value:SetText(reduced and "ON" or "OFF")
    toggle.onStateChange(toggle)
    if reduced then UI.AnimationController:Stop(self.frame); self.frame:SetAlpha(1) end
end
Screen.input:SetNavigation({"reducedMotion","back","home","close"},{
    reducedMotion={UP="back",DOWN="back",RIGHT="home"},back={DOWN="reducedMotion"},
    home={DOWN="reducedMotion",RIGHT="close"},close={LEFT="home",DOWN="reducedMotion"},
})
Screen.defaultFocus="reducedMotion"
function Screen:IsAvailable() return UI.flags.nativeAccessibility ~= false end
function Screen:Show() self:Refresh(); UI.UtilityShell.Show(self,"reducedMotion") end
UI.AccessibilityScreen=Screen; UI.ScreenManager:Register("accessibility",Screen,false); UI.modules.AccessibilityScreen=true

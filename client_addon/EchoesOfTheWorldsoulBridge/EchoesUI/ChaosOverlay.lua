local UI = EchoesUI
if not UI or not UI.Chaos or not UI.Theme then return end

local Chaos = UI.Chaos
local Theme = UI.Theme
local Animation = UI.AnimationController
local anchor = TargetFrameHealthBar or TargetFrame or UIParent

local frame = CreateFrame("Frame", "EchoesUIChaosTargetOverlay", anchor)
frame:SetSize(132, 14)
frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
frame:SetFrameStrata("HIGH")
frame:EnableMouse(true)
frame:Hide()

local value = frame:CreateFontString(nil, "OVERLAY")
value:SetFont(Theme.fonts.readable, 10, "OUTLINE")
value:SetTextColor(1, 1, 1)
value:SetPoint("CENTER", frame, "CENTER", 0, 0)
value:SetWidth(132); value:SetJustifyH("CENTER")

local playerValue
if PlayerFrameHealthBar then
    playerValue = PlayerFrameHealthBar:CreateFontString("EchoesUIChaosPlayerHealthText", "OVERLAY")
    playerValue:SetFont(Theme.fonts.readable, 10, "OUTLINE")
    playerValue:SetTextColor(1, 1, 1)
    playerValue:SetPoint("CENTER", PlayerFrameHealthBar, "CENTER", 0, 0)
    playerValue:SetWidth(132); playerValue:SetJustifyH("CENTER"); playerValue:Hide()
end

frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Effective Health", 0.65, 0.88, 1)
    GameTooltip:AddLine("The target's health expressed through your current Chaos scale.", 0.88, 0.82, 0.68, true)
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

local transition = CreateFrame("Frame", "EchoesUIChaosMagnitudeNotice", UIParent)
transition:SetSize(220, 38)
transition:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 5)
transition:SetFrameStrata("HIGH")
transition:Hide()
local transitionBack = transition:CreateTexture(nil, "BACKGROUND")
transitionBack:SetAllPoints(transition)
Theme:SetTextureColor(transitionBack, {0.008, 0.011, 0.016, 0.92})
local transitionTitle = transition:CreateFontString(nil, "OVERLAY")
transitionTitle:SetFont(Theme.fonts.readable, 10)
transitionTitle:SetTextColor(unpack(Theme.colors.text))
transitionTitle:SetPoint("TOPLEFT", transition, "TOPLEFT", 9, -5)
local transitionValue = transition:CreateFontString(nil, "OVERLAY")
transitionValue:SetFont(Theme.fonts.readable, 10)
transitionValue:SetTextColor(unpack(Theme.colors.worldsoulPale))
transitionValue:SetPoint("BOTTOMLEFT", transition, "BOTTOMLEFT", 9, 5)

local Overlay = {frame=frame, value=value, playerValue=playerValue, transition=transition, noticeToken=0, nativeText={}, playerNativeText={}, auxiliary={}, hitIndicators={}}

local function RememberNativeText(list, fontString)
    if not fontString or type(fontString.SetAlpha) ~= "function" then return end
    for _, entry in ipairs(list) do
        if entry.object == fontString then return end
    end
    list[#list + 1] = {object=fontString, alpha=fontString:GetAlpha()}
end

RememberNativeText(Overlay.nativeText, _G.TargetFrameHealthBarText)
if TargetFrameHealthBar then
    RememberNativeText(Overlay.nativeText, TargetFrameHealthBar.TextString)
    RememberNativeText(Overlay.nativeText, TargetFrameHealthBar.LeftText)
    RememberNativeText(Overlay.nativeText, TargetFrameHealthBar.RightText)
end
RememberNativeText(Overlay.playerNativeText, _G.PlayerFrameHealthBarText)
if PlayerFrameHealthBar then
    RememberNativeText(Overlay.playerNativeText, PlayerFrameHealthBar.TextString)
    RememberNativeText(Overlay.playerNativeText, PlayerFrameHealthBar.LeftText)
    RememberNativeText(Overlay.playerNativeText, PlayerFrameHealthBar.RightText)
end

RememberNativeText(Overlay.hitIndicators, _G.PlayerHitIndicator)
RememberNativeText(Overlay.hitIndicators, _G.PetHitIndicator)

local function AddAuxiliaryHealth(unit, frameObject, healthBar, nativeText, width)
    if not frameObject or not healthBar or not nativeText then return end
    local text=healthBar:CreateFontString(nil,"OVERLAY")
    text:SetFont(Theme.fonts.readable,9,"OUTLINE"); text:SetTextColor(1,1,1)
    text:SetPoint("CENTER",healthBar,"CENTER",0,0); text:SetWidth(width or 90); text:SetJustifyH("CENTER"); text:Hide()
    local native={}; RememberNativeText(native,nativeText)
    Overlay.auxiliary[#Overlay.auxiliary+1]={unit=unit,frame=frameObject,text=text,native=native,nativeText=nativeText}
end

AddAuxiliaryHealth("focus",_G.FocusFrame,_G.FocusFrameHealthBar,_G.FocusFrameHealthBarText,90)
AddAuxiliaryHealth("pet",_G.PetFrame,_G.PetFrameHealthBar,_G.PetFrameHealthBarText,69)
for index=1,4 do
    AddAuxiliaryHealth("party"..index,_G["PartyMemberFrame"..index],_G["PartyMemberFrame"..index.."HealthBar"],_G["PartyMemberFrame"..index.."HealthBarText"],70)
end

local function SetNativeTextSuppressed(list, suppressed)
    for _, entry in ipairs(list) do
        entry.object:SetAlpha(suppressed and 0 or entry.alpha)
    end
end

function Overlay:SetTargetNativeTextSuppressed(suppressed) SetNativeTextSuppressed(self.nativeText, suppressed) end
function Overlay:SetPlayerNativeTextSuppressed(suppressed) SetNativeTextSuppressed(self.playerNativeText, suppressed) end

local function DisplayedUnit(frameObject,fallback)
    return frameObject and frameObject.unit or fallback
end

function Overlay:RefreshAuxiliary()
    for _,entry in ipairs(self.auxiliary) do
        local unit=DisplayedUnit(entry.frame,entry.unit)
        local exists=type(UnitExists)=="function" and UnitExists(unit)
        local nativeVisible=entry.nativeText:IsShown() and tostring(entry.nativeText:GetText() or "")~=""
        if Chaos.state.enabled and exists and nativeVisible then
            entry.text:SetText(Chaos:Format(Chaos:GetEffectiveHealth(UnitHealth(unit),unit)).." / "..Chaos:Format(Chaos:GetEffectiveHealth(UnitHealthMax(unit),unit)))
            SetNativeTextSuppressed(entry.native,true); entry.text:Show()
        else
            SetNativeTextSuppressed(entry.native,false); entry.text:Hide()
        end
    end
    SetNativeTextSuppressed(self.hitIndicators,Chaos.state.enabled)
end

function Overlay:HasTarget()
    return type(UnitExists) == "function" and not not UnitExists("target")
end

function Overlay:Refresh()
    if not Chaos.state.enabled or not self:HasTarget() then
        self.frame:Hide()
        self:SetTargetNativeTextSuppressed(false)
    else
        local unit=DisplayedUnit(_G.TargetFrame,"target")
        local current = type(UnitHealth) == "function" and UnitHealth(unit) or 0
        local maximum = type(UnitHealthMax) == "function" and UnitHealthMax(unit) or 0
        self.value:SetText(Chaos:Format(Chaos:GetEffectiveHealth(current, unit)) .. " / " .. Chaos:Format(Chaos:GetEffectiveHealth(maximum, unit)))
        self:SetTargetNativeTextSuppressed(true)
        self.frame:Show()
    end

    if Chaos.state.enabled and self.playerValue then
        local unit=DisplayedUnit(_G.PlayerFrame,"player")
        local current = type(UnitHealth) == "function" and UnitHealth(unit) or 0
        local maximum = type(UnitHealthMax) == "function" and UnitHealthMax(unit) or 0
        self.playerValue:SetText(Chaos:Format(Chaos:GetEffectiveHealth(current, unit)) .. " / " .. Chaos:Format(Chaos:GetEffectiveHealth(maximum, unit)))
        self:SetPlayerNativeTextSuppressed(true); self.playerValue:Show()
    else
        self:SetPlayerNativeTextSuppressed(false)
        if self.playerValue then self.playerValue:Hide() end
    end
    self:RefreshAuxiliary()
end

function Overlay:ShowMagnitudeTransition()
    self.noticeToken = self.noticeToken + 1
    local token = self.noticeToken
    transitionTitle:SetText("CHAOS " .. Chaos:GetMagnitudeText())
    transitionValue:SetText(Chaos:FormatParts(1, Chaos.state.magnitude) .. " scale reached")
    transition:SetAlpha(1); transition:Show()
    C_Timer.After(2.4, function()
        if token ~= Overlay.noticeToken then return end
        if UI:IsReducedMotion() then transition:Hide(); return end
        Animation:Alpha(transition, 0, 0.25, function()
            if token == Overlay.noticeToken then transition:Hide() end
        end)
    end)
end

local events = CreateFrame("Frame", nil, UIParent)
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UNIT_HEALTH")
events:RegisterEvent("UNIT_MAXHEALTH")
events:RegisterEvent("PLAYER_FOCUS_CHANGED")
events:RegisterEvent("UNIT_PET")
events:RegisterEvent("PARTY_MEMBERS_CHANGED")
events:RegisterEvent("UNIT_ENTERED_VEHICLE")
events:RegisterEvent("UNIT_EXITED_VEHICLE")
events:SetScript("OnEvent", function(_, event, unit)
    if (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") and unit ~= "target" and unit ~= "player" and unit ~= "focus" and unit ~= "pet" and unit ~= "vehicle" and not tostring(unit):match("^party[1-4]$") then return end
    Overlay:Refresh()
end)
events:SetScript("OnUpdate", function()
    if Chaos.state.enabled then
        if Overlay:HasTarget() then Overlay:SetTargetNativeTextSuppressed(true) end
        Overlay:SetPlayerNativeTextSuppressed(true)
        Overlay:RefreshAuxiliary()
    end
end)
Overlay.events = events

Chaos:Subscribe(function(state, reason)
    Overlay:Refresh()
    if state.enabled and reason == "enabled" then Overlay:ShowMagnitudeTransition() end
    if not state.enabled then
        Overlay.noticeToken = Overlay.noticeToken + 1
        transition:Hide()
    end
end)

UI.ChaosOverlay = Overlay
UI.modules.ChaosOverlay = true

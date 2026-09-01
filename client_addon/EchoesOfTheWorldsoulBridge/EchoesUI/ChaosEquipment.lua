local UI = EchoesUI
if not UI or not UI.Chaos then return end

local Chaos = UI.Chaos
local Equipment = {hookedTooltips={},paperDollHooked=false}
local ACCENT="|cff66ccff"
local MUTED="|cffaaa49a"
local CLOSE="|r"

function Equipment:GetReferenceRange(minimum,maximum)
    local scale=Chaos:GetPersonalScale()
    return (tonumber(minimum) or 0)*scale,(tonumber(maximum) or 0)*scale,scale
end

function Equipment:FormatReferenceRange(minimum,maximum)
    local low,high=self:GetReferenceRange(minimum,maximum)
    return Chaos:Format(low,4).." - "..Chaos:Format(high,4)
end

function Equipment:ParseWeaponLines(lines)
    local minimum,maximum,speed,dps
    for _,line in ipairs(lines or {}) do
        local low,high=tostring(line):match("(%d+%.?%d*)%s*%-%s*(%d+%.?%d*)%s+[Dd]amage")
        if low and high then minimum,maximum=tonumber(low),tonumber(high) end
        speed=speed or tonumber(tostring(line):match("[Ss]peed%s+(%d+%.?%d*)"))
        dps=dps or tonumber(tostring(line):match("(%d+%.?%d*)%s+[Dd]amage [Pp]er [Ss]econd"))
    end
    return minimum,maximum,speed,dps
end

function Equipment:AddWeaponReference(tooltip)
    if not Chaos.state.enabled or not tooltip or type(tooltip.AddLine)~="function" then return false end
    local name=type(tooltip.GetName)=="function" and tooltip:GetName() or nil
    if not name or type(tooltip.NumLines)~="function" then return false end
    local lines={}
    for index=1,tooltip:NumLines() do
        local region=_G[name.."TextLeft"..index]
        lines[#lines+1]=region and region:GetText() or ""
    end
    for _,line in ipairs(lines) do if tostring(line):find("Chaos Weapon Reference",1,true) then return true end end
    local minimum,maximum,speed,dps=self:ParseWeaponLines(lines)
    if not minimum or not maximum then return false end
    tooltip:AddLine(" ")
    tooltip:AddLine(ACCENT.."Chaos Weapon Reference"..CLOSE,0.40,0.82,1)
    tooltip:AddLine(self:FormatReferenceRange(minimum,maximum).." effective base damage",0.78,0.90,1)
    if dps then tooltip:AddLine(Chaos:Format(dps*Chaos:GetPersonalScale(),4).." effective DPS",0.78,0.90,1)
    elseif speed and speed>0 then tooltip:AddLine(Chaos:Format((((minimum+maximum)/2)/speed)*Chaos:GetPersonalScale(),4).." effective DPS",0.78,0.90,1) end
    tooltip:AddLine(MUTED.."Personal reference; final hits vary by target."..CLOSE,0.67,0.64,0.60,true)
    return true
end

function Equipment:HookTooltip(tooltip)
    if not tooltip or self.hookedTooltips[tooltip] or type(tooltip.HookScript)~="function" then return end
    tooltip:HookScript("OnTooltipSetItem",function(self) Equipment:AddWeaponReference(self) end)
    self.hookedTooltips[tooltip]=true
end

local function SetPaperDollReference(statFrame,unit,ranged)
    if not Chaos.state.enabled or unit=="pet" or not statFrame or type(statFrame.GetName)~="function" then return end
    unit=unit or "player"
    local minimum,maximum
    if ranged then
        local speed,low,high=UnitRangedDamage(unit)
        minimum,maximum=low,high
    else
        minimum,maximum=UnitDamage(unit)
    end
    if not minimum or not maximum then return end
    local text=_G[statFrame:GetName().."StatText"]
    if text then text:SetText(Equipment:FormatReferenceRange(math.max(math.floor(minimum),1),math.max(math.ceil(maximum),1))) end
    local native=math.max(math.floor(minimum),1).." - "..math.max(math.ceil(maximum),1)
    local note=ACCENT.."Chaos reference: "..Equipment:FormatReferenceRange(math.max(math.floor(minimum),1),math.max(math.ceil(maximum),1))..CLOSE..
        "\n"..MUTED.."Native range: "..native..". Final hits vary by target."..CLOSE
    statFrame.tooltip2=note
end

function Equipment:InstallPaperDollHooks()
    if self.paperDollHooked or type(hooksecurefunc)~="function" then return false end
    if type(PaperDollFrame_SetDamage)~="function" or type(PaperDollFrame_SetRangedDamage)~="function" then return false end
    hooksecurefunc("PaperDollFrame_SetDamage",function(frame,unit) SetPaperDollReference(frame,unit,false) end)
    hooksecurefunc("PaperDollFrame_SetRangedDamage",function(frame,unit) SetPaperDollReference(frame,unit,true) end)
    self.paperDollHooked=true
    return true
end

-- GameTooltip and ItemRefTooltip share the bridge's ordered augmentation seam:
-- native Blizzard lines -> Attunement -> Chaos. Shopping comparison tooltips
-- have no Attunement writer, so their local hook remains sufficient.
if APB and type(APB.RegisterItemTooltipAugmenter)=="function" then
    APB:RegisterItemTooltipAugmenter(function(tooltip) Equipment:AddWeaponReference(tooltip) end)
else
    Equipment:HookTooltip(GameTooltip)
    Equipment:HookTooltip(ItemRefTooltip)
end
Equipment:HookTooltip(ShoppingTooltip1)
Equipment:HookTooltip(ShoppingTooltip2)

local loader=CreateFrame("Frame",nil,UIParent)
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent",function() Equipment:InstallPaperDollHooks() end)
Equipment.loader=loader
Equipment:InstallPaperDollHooks()

Chaos:Subscribe(function()
    if type(PaperDollFrame_UpdateStats)=="function" and PaperDollFrame and PaperDollFrame:IsShown() then
        UI:SafeCall("Chaos paper doll refresh",PaperDollFrame_UpdateStats)
    end
end)

UI.ChaosEquipment=Equipment
UI.modules.ChaosEquipment=true

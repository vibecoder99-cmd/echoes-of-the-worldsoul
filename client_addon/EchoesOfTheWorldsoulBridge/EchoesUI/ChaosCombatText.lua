local UI = EchoesUI
if not UI or not UI.Chaos then return end

-- Wrath 3.3.5a supplies the CLEU payload directly to OnEvent. This module
-- changes presentation only: the destination health-pool scale is applied to
-- the native event amount, and no combat value is sent to or changed on server.
local Chaos = UI.Chaos
local Combat = {
    active = false,
    originalCVars = {},
    scaleByGUID = {},
    messages = {},
    failed = false,
}

local CVARS = {"CombatDamage", "CombatHealing", "PetMeleeDamage", "CombatLogPeriodicSpells", "enableCombatText"}
local UNIT_TOKENS = {"player", "target", "focus", "mouseover", "pet", "vehicle"}
for i=1,4 do UNIT_TOKENS[#UNIT_TOKENS+1] = "party"..i; UNIT_TOKENS[#UNIT_TOKENS+1] = "partypet"..i end
for i=1,40 do UNIT_TOKENS[#UNIT_TOKENS+1] = "raid"..i end

local function AvailableCVar(name)
    if type(GetCVar) ~= "function" then return nil end
    local ok, value = pcall(GetCVar, name)
    if not ok or value == nil or value == "" then return nil end
    return tostring(value)
end

function Combat:RefreshGUIDScales()
    if type(UnitGUID) ~= "function" then return end
    for _, unit in ipairs(UNIT_TOKENS) do
        local guid = UnitGUID(unit)
        if guid then self.scaleByGUID[guid] = Chaos:GetScale(unit) end
    end
end

function Combat:GetRecipientScale(guid)
    self:RefreshGUIDScales()
    return guid and self.scaleByGUID[guid] or nil
end

function Combat:Convert(amount, guid)
    local scale = self:GetRecipientScale(guid)
    if not scale then return nil end
    return math.max(0, tonumber(amount) or 0) * scale, scale
end

function Combat:Render(text, kind, critical, meta)
    self.messages[#self.messages+1] = {text=text, kind=kind, critical=critical==true, meta=meta}
    local r,g,b = 1,0.82,0
    if kind == "incoming" then r,g,b = 1,0.1,0.1
    elseif kind == "heal" then r,g,b = 0.1,1,0.1
    elseif kind == "prevented" then r,g,b = 0.65,0.88,1 end
    CombatText_AddMessage(text, COMBAT_TEXT_SCROLL_FUNCTION or CombatText_StandardScroll, r,g,b,
        critical and "crit" or nil, not critical)
end

local function DamagePayload(subevent, ...)
    if subevent == "SWING_DAMAGE" then
        local amount, overkill, school, resisted, blocked, absorbed, critical = ...
        return math.max(0,(tonumber(amount) or 0)-(tonumber(overkill) or 0)), critical, resisted, blocked, absorbed
    elseif subevent == "ENVIRONMENTAL_DAMAGE" then
        local _, amount, overkill, school, resisted, blocked, absorbed, critical = ...
        return math.max(0,(tonumber(amount) or 0)-(tonumber(overkill) or 0)), critical, resisted, blocked, absorbed
    elseif subevent == "RANGE_DAMAGE" or subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "DAMAGE_SHIELD" then
        local _,_,_,amount,overkill,school,resisted,blocked,absorbed,critical = ...
        return math.max(0,(tonumber(amount) or 0)-(tonumber(overkill) or 0)), critical, resisted, blocked, absorbed
    end
end

function Combat:HandleCLEU(...)
    local timestamp, subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags = ...
    if not subevent or not destGUID then return false end
    local tail = {select(9,...)}
    local amount, critical, resisted, blocked, absorbed = DamagePayload(subevent, unpack(tail))
    local playerGUID = type(UnitGUID)=="function" and UnitGUID("player") or nil
    if amount ~= nil then
        local converted, scale = self:Convert(amount, destGUID)
        if not converted then return false end
        local kind = destGUID == playerGUID and "incoming" or "damage"
        self:Render((kind=="incoming" and "-" or "")..Chaos:Format(converted), kind, critical,
            {subevent=subevent,native=amount,scale=scale,destination=destGUID})
        for _, entry in ipairs({{"RESIST",resisted},{"BLOCK",blocked},{"ABSORB",absorbed}}) do
            if tonumber(entry[2]) and tonumber(entry[2]) > 0 then
                self:Render(entry[1].." "..Chaos:Format(tonumber(entry[2])*scale), "prevented", false,
                    {subevent=subevent,native=entry[2],scale=scale,destination=destGUID})
            end
        end
        return true
    end
    if subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        local spellId, spellName, spellSchool, raw, overheal, healAbsorb, isCritical = unpack(tail)
        local effective = math.max(0, (tonumber(raw) or 0) - (tonumber(overheal) or 0))
        local converted, scale = self:Convert(effective, destGUID)
        if not converted then return false end
        if converted > 0 then self:Render("+"..Chaos:Format(converted), "heal", isCritical,
            {subevent=subevent,native=effective,scale=scale,destination=destGUID}) end
        if tonumber(healAbsorb) and tonumber(healAbsorb)>0 then
            self:Render("ABSORB "..Chaos:Format(tonumber(healAbsorb)*scale), "prevented", false,
                {subevent=subevent,native=healAbsorb,scale=scale,destination=destGUID})
        end
        return true
    end
    if subevent == "SWING_MISSED" or subevent == "RANGE_MISSED" or subevent == "SPELL_MISSED" or subevent == "SPELL_PERIODIC_MISSED" then
        local offset = subevent == "SWING_MISSED" and 0 or 3
        local missType, prevented = tail[1+offset], tail[2+offset]
        local scale = self:GetRecipientScale(destGUID)
        if not scale then return false end
        local label = tostring(missType or "MISS")
        if tonumber(prevented) and tonumber(prevented)>0 then label=label.." "..Chaos:Format(tonumber(prevented)*scale) end
        self:Render(label, "prevented", false, {subevent=subevent,native=prevented or 0,scale=scale,destination=destGUID})
        return true
    end
    return false
end

function Combat:RestoreNative()
    if type(SetCVar)=="function" then
        for name, value in pairs(self.originalCVars) do pcall(SetCVar, name, value) end
    end
    self.originalCVars = {}; self.active = false
end

function Combat:Enable()
    if self.active then return true end
    if type(CombatText_AddMessage)~="function" and type(LoadAddOn)=="function" then pcall(LoadAddOn,"Blizzard_CombatText") end
    if type(CombatText_AddMessage)~="function" or type(SetCVar)~="function" then
        self.failed=true; self:RestoreNative(); return false
    end
    for _, name in ipairs(CVARS) do
        local value=AvailableCVar(name)
        if value~=nil then self.originalCVars[name]=value; pcall(SetCVar,name,"0") end
    end
    self.active=true; self.failed=false; self:RefreshGUIDScales(); return true
end

function Combat:SetEnabled(enabled)
    if enabled then return self:Enable() end
    self:RestoreNative(); return true
end

local events=CreateFrame("Frame",nil,UIParent)
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("RAID_ROSTER_UPDATE")
events:RegisterEvent("PARTY_MEMBERS_CHANGED")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent",function(_,event,...)
    if event=="PLAYER_LOGOUT" then Combat:RestoreNative(); return end
    if event~="COMBAT_LOG_EVENT_UNFILTERED" then Combat:RefreshGUIDScales(); return end
    if not Combat.active then return end
    local ok=pcall(Combat.HandleCLEU,Combat,...)
    if not ok then
        Combat.failed=true; Combat:RestoreNative()
        print("|cffff4444[Echoes] Chaos combat text failed; native combat text restored.|r")
    end
end)
Combat.events=events

Chaos:Subscribe(function(state) Combat:SetEnabled(state.enabled==true) end)
UI.ChaosCombatText=Combat
UI.modules.ChaosCombatText=true

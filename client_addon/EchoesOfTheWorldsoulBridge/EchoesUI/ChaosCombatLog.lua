local UI = EchoesUI
if not UI or not UI.Chaos or not UI.ChaosCombatText then return end

-- Blizzard_CombatLog owns ChatFrame2 and formats COMBAT_LOG_EVENT itself;
-- ChatFrame message-event filters are not involved. Preserve that formatter
-- and its localization by substituting numeric sentinels into a presentation-
-- only copy of the CLEU payload, then replace only those sentinels afterward.
local Chaos, Combat = UI.Chaos, UI.ChaosCombatText
local Log = {installed=false, originalAddEvent=nil, evidence={}}
local SENTINEL_BASE = 9876543210100

local DAMAGE_LAYOUT = {
    SWING_DAMAGE={amount=9,overkill=10,resisted=12,blocked=13,absorbed=14},
    ENVIRONMENTAL_DAMAGE={amount=10,overkill=11,resisted=13,blocked=14,absorbed=15},
    RANGE_DAMAGE={amount=12,overkill=13,resisted=15,blocked=16,absorbed=17},
    SPELL_DAMAGE={amount=12,overkill=13,resisted=15,blocked=16,absorbed=17},
    SPELL_PERIODIC_DAMAGE={amount=12,overkill=13,resisted=15,blocked=16,absorbed=17},
    DAMAGE_SHIELD={amount=12,overkill=13,resisted=15,blocked=16,absorbed=17},
}
local HEAL_EVENTS={SPELL_HEAL=true,SPELL_PERIODIC_HEAL=true}
local MISS_LAYOUT={SWING_MISSED={kind=9,amount=10},RANGE_MISSED={kind=12,amount=13},SPELL_MISSED={kind=12,amount=13},SPELL_PERIODIC_MISSED={kind=12,amount=13}}

local function CopyArgs(...)
    local result={n=select("#",...)}
    for i=1,result.n do result[i]=select(i,...) end
    return result
end

local function AddReplacement(replacements, native, scale, label)
    native=tonumber(native)
    if not native or native<=0 then return nil end
    local sentinel=SENTINEL_BASE+#replacements+1
    replacements[#replacements+1]={sentinel=tostring(sentinel),text=Chaos:Format(native*scale),native=native,scale=scale,label=label}
    return sentinel
end

function Log:TransformEvent(...)
    local args=CopyArgs(...)
    local subevent,destGUID=args[2],args[6]
    local layout=DAMAGE_LAYOUT[subevent]
    local scale=Combat:GetRecipientScale(destGUID)
    if (layout or HEAL_EVENTS[subevent] or MISS_LAYOUT[subevent]) and not scale then return nil,"unresolved_destination" end
    local replacements={}
    if layout then
        local effective=math.max(0,(tonumber(args[layout.amount]) or 0)-(tonumber(args[layout.overkill]) or 0))
        args[layout.amount]=AddReplacement(replacements,effective,scale,"amount") or 0
        args[layout.overkill]=0
        for _,field in ipairs({"resisted","blocked","absorbed"}) do
            local index=layout[field]
            if index and tonumber(args[index]) and tonumber(args[index])>0 then args[index]=AddReplacement(replacements,args[index],scale,field) end
        end
    elseif HEAL_EVENTS[subevent] then
        local effective=math.max(0,(tonumber(args[12]) or 0)-(tonumber(args[13]) or 0))
        args[12]=AddReplacement(replacements,effective,scale,"amount") or 0
        args[13]=0
        if tonumber(args[14]) and tonumber(args[14])>0 then args[14]=AddReplacement(replacements,args[14],scale,"absorbed") end
    elseif MISS_LAYOUT[subevent] then
        local miss=MISS_LAYOUT[subevent]
        local kind=args[miss.kind]
        if (kind=="ABSORB" or kind=="BLOCK" or kind=="RESIST") and tonumber(args[miss.amount]) and tonumber(args[miss.amount])>0 then
            args[miss.amount]=AddReplacement(replacements,args[miss.amount],scale,string.lower(kind))
        else
            return args,replacements
        end
    else
        return args,replacements
    end
    return args,replacements
end

function Log:RewriteFormatted(formatter,settings,...)
    local args,replacements=self:TransformEvent(...)
    if not args then return nil,"suppress_unresolved" end
    local text,r,g,b=formatter(settings,unpack(args,1,args.n))
    if type(text)~="string" then return text,r,g,b end
    for _,entry in ipairs(replacements) do
        local count
        text,count=text:gsub(entry.sentinel,entry.text,1)
        if count~=1 then return nil,"suppress_unreplaced" end
    end
    self.evidence[#self.evidence+1]={event=args[2],text=text,replacements=replacements}
    if #self.evidence>40 then table.remove(self.evidence,1) end
    return text,r,g,b
end

function Log:Install()
    if self.installed then return true end
    if type(CombatLog_AddEvent)~="function" or type(CombatLog_OnEvent)~="function" or not COMBATLOG then return false end
    self.originalAddEvent=CombatLog_AddEvent
    local original=self.originalAddEvent
    CombatLog_AddEvent=function(...)
        if not Chaos.state.enabled then return original(...) end
        local ok,text,r,g,b=pcall(Log.RewriteFormatted,Log,CombatLog_OnEvent,Blizzard_CombatLog_CurrentSettings,...)
        if ok and text then return COMBATLOG:AddMessage(text,r,g,b) end
        if ok then return end -- one numeric line could not be made coherent
        return original(...) -- global failsafe: retain native logging on code failure
    end
    self.installed=true
    return true
end

local loader=CreateFrame("Frame",nil,UIParent)
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent",function(_,event,name)
    if event=="PLAYER_ENTERING_WORLD" or name=="Blizzard_CombatLog" then Log:Install() end
end)
Log.loader=loader
Log:Install()

UI.ChaosCombatLog=Log
UI.modules.ChaosCombatLog=true

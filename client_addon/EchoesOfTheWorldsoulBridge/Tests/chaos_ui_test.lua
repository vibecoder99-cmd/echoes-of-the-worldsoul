local ADDON_DIR=arg[1]; assert(ADDON_DIR,"addon path required"); dofile(arg[2])
local function fail(m) print("FAIL: "..m); os.exit(1) end
local function pass(m) print("PASS: "..m) end
AttunementPlusBridgeDB={cache={},c43={reducedMotion=false}}
local requestedActions, actionSubscribers = {}, {}
_G.APB={C43={frame=CreateFrame("Frame",nil,UIParent)},echoes={lastState={
    chaos_enabled="1",chaos_power="1000",chaos_magnitude="1",chaos_scale="1000",
},lastStateTime=0}}
function APB:RequestEchoesAction(...) requestedActions[#requestedActions+1]={...}; return true end
function APB:RequestEchoesState() self.stateRequested=true; return true end
function APB:SubscribeEchoesActions(callback) actionSubscribers[#actionSubscribers+1]=callback end
_G.TargetFrame=CreateFrame("Frame","TargetFrame",UIParent)
_G.TargetFrameHealthBar=CreateFrame("Frame","TargetFrameHealthBar",TargetFrame)
_G.TargetFrameHealthBarText=TargetFrameHealthBar:CreateFontString("TargetFrameHealthBarText","OVERLAY")
TargetFrameHealthBarText:SetAlpha(0.65)
_G.PlayerFrame=CreateFrame("Frame","PlayerFrame",UIParent)
_G.PlayerFrameHealthBar=CreateFrame("Frame","PlayerFrameHealthBar",PlayerFrame)
_G.PlayerFrameHealthBarText=PlayerFrameHealthBar:CreateFontString("PlayerFrameHealthBarText","OVERLAY")
PlayerFrameHealthBarText:SetAlpha(0.8)
_G.PlayerHitIndicator=PlayerFrame:CreateFontString("PlayerHitIndicator","OVERLAY"); PlayerHitIndicator:SetAlpha(0.9)
_G.PetFrame=CreateFrame("Frame","PetFrame",UIParent); PetFrame.unit="pet"
_G.PetFrameHealthBar=CreateFrame("Frame","PetFrameHealthBar",PetFrame)
_G.PetFrameHealthBarText=PetFrameHealthBar:CreateFontString("PetFrameHealthBarText","OVERLAY"); PetFrameHealthBarText:SetText("50 / 50"); PetFrameHealthBarText:Show()
_G.PetHitIndicator=PetFrame:CreateFontString("PetHitIndicator","OVERLAY"); PetHitIndicator:SetAlpha(0.7)
_G.FocusFrame=CreateFrame("Frame","FocusFrame",UIParent); FocusFrame.unit="focus"
_G.FocusFrameHealthBar=CreateFrame("Frame","FocusFrameHealthBar",FocusFrame)
_G.FocusFrameHealthBarText=FocusFrameHealthBar:CreateFontString("FocusFrameHealthBarText","OVERLAY"); FocusFrameHealthBarText:SetText("80 / 80"); FocusFrameHealthBarText:Show()
for i=1,4 do
    local frame=CreateFrame("Frame","PartyMemberFrame"..i,UIParent); frame.unit="party"..i
    local bar=CreateFrame("Frame","PartyMemberFrame"..i.."HealthBar",frame)
    local text=bar:CreateFontString("PartyMemberFrame"..i.."HealthBarText","OVERLAY"); _G["PartyMemberFrame"..i.."HealthBarText"]=text; text:SetText("70 / 70"); text:Show()
end
local units={
    target={exists=false,current=0,maximum=0,level=1,classification="normal",guid="Creature-target"},
    player={exists=true,current=117,maximum=117,level=4,classification="normal",guid="Player-self"},
    vehicle={exists=true,current=500,maximum=1000,level=4,classification="normal",guid="Vehicle-self"},
    pet={exists=true,current=50,maximum=50,level=4,classification="normal",guid="Pet-self"},
    focus={exists=true,current=80,maximum=80,level=2,classification="normal",guid="Focus-unit"},
    party1={exists=true,current=70,maximum=70,level=3,classification="normal",guid="Party-1"},
}
_G.UnitExists=function(unit) return units[unit] and units[unit].exists or false end
_G.UnitHealth=function(unit) return units[unit] and units[unit].current or 0 end
_G.UnitHealthMax=function(unit) return units[unit] and units[unit].maximum or 0 end
_G.UnitLevel=function(unit) return units[unit] and units[unit].level or 1 end
_G.UnitClassification=function(unit) return units[unit] and units[unit].classification or "normal" end
_G.UnitGUID=function(unit) return units[unit] and units[unit].exists and units[unit].guid or nil end
_G.UnitDamage=function() return 12,18,0,0,0,0,1 end
_G.UnitRangedDamage=function() return 2,16,24,0,0,1 end
_G.PaperDollFrame_SetDamage=function(frame) _G[frame:GetName().."StatText"]:SetText("12 - 18") end
_G.PaperDollFrame_SetRangedDamage=function(frame) _G[frame:GetName().."StatText"]:SetText("16 - 24") end
local function load(rel) local f,e=loadfile(ADDON_DIR.."/"..rel); if not f then fail(e) end; local ok,x=pcall(f); if not ok then fail(rel..": "..x) end end
for _,rel in ipairs({
    "EchoesUI/Bootstrap.lua","EchoesUI/Theme.lua","EchoesUI/StateStore.lua","EchoesUI/AnimationController.lua","EchoesUI/Chaos.lua","EchoesUI/ChaosCombatText.lua","EchoesUI/ChaosCombatLog.lua","EchoesUI/ChaosEquipment.lua","EchoesUI/ChaosTooltip.lua",
    "EchoesUI/ScreenManager.lua","EchoesUI/InputManager.lua","EchoesUI/Components/ProgressionRow.lua","EchoesUI/Components/UtilityShell.lua",
    "EchoesUI/Screens/SettingsScreen.lua","EchoesUI/ChaosOverlay.lua",
}) do load(rel) end

local C=EchoesUI.Chaos
local Combat=EchoesUI.ChaosCombatText
local Overlay=EchoesUI.ChaosOverlay
local Settings=EchoesUI.SettingsScreen
if not C.state.ready or not C.state.enabled or not Combat.active then fail("persisted ON snapshot did not reactivate Chaos during initial hydration") end
if Settings.chaos.value:GetText()~="ON" or not Overlay.playerValue:IsShown() or PlayerFrameHealthBarText:GetAlpha()~=0 then fail("persisted ON presentation surfaces did not initialize from authoritative state") end
EchoesUI.StateStore:Ingest({chaos_enabled="0",chaos_power="1000",chaos_magnitude="1",chaos_scale="1000"},0.5)
if C.state.enabled or Combat.active or Overlay.playerValue:IsShown() or PlayerFrameHealthBarText:GetAlpha()~=0.8 then fail("persisted OFF hydration did not restore native presentation") end
pass("persisted ON/OFF initial hydration converges through authoritative presentation state")
local cases={{999,"999"},{1000,"1.00K"},{12500,"12.5K"},{999000,"999K"},{1000000,"1.00M"},{12500000,"12.5M"},{842000000,"842M"},{1030000000,"1.03B"},{999000000000,"999B"},{1000000000000,"1.00T"}}
for _,case in ipairs(cases) do if C:Format(case[1])~=case[2] then fail(tostring(case[1]).." formatted as "..C:Format(case[1])) end end
if C:FormatParts(1,5)~="1.00Qa" or C:FormatParts(1,6)~="1.00Qi" or C:GetPowerText()~="1.00K" then fail("structured formatting contract failed") end
C:ApplyState({power="12345678901234567890",magnitude=6,scale=1000,ready=true},"test")
if C:GetPowerText()~="12.35Qi" or C.state.powerRaw~="12345678901234567890" then fail("lossless decimal power parsing failed: "..C:GetPowerText()) end
pass("Chaos formatter examples and structured future-safe seam")
if C:GetMagnitudeName(1)~="STIRRING" or C:GetMagnitudeName(2)~="RESONANT" or C:GetMagnitudeName(5)~="TRANSCENDENT" or C:GetMagnitudeName(6)~="UNBOUNDED" then fail("Magnitude rank-name ladder failed") end
pass("Magnitude bands use the restrained rank-name ladder")

Settings:Show(); Settings.chaos:Activate("keyboard")
if #requestedActions~=1 or requestedActions[1][1]~="chaos_toggle" or requestedActions[1][2]~=1 then fail("Settings toggle did not request authoritative Chaos activation") end
EchoesUI.StateStore:Ingest({chaos_enabled="1",chaos_power="1000",chaos_magnitude="1",chaos_scale="1000"},1)
if not C.state.enabled or Settings.chaos.value:GetText()~="ON" or C:GetPowerText()~="1.00K" then fail("authoritative Chaos state did not reach UI") end
pass("Settings toggle is textual and character-authoritative")

local target=units.target
if GetMockCVar("CombatDamage")~="0" or GetMockCVar("CombatHealing")~="0" or GetMockCVar("enableCombatText")~="0" then fail("native combat text CVars not suppressed") end
local function cleu(...) return Combat:HandleCLEU(...) end
target.exists=true; target.level=1
Combat:RefreshGUIDScales()
local targetScale, playerScale=C:GetScale("target"), C:GetScale("player")
cleu(1,"SWING_DAMAGE","Player-self","Brus",0,"Creature-target","Wolf",0,10,0,1,0,0,0,false,false,false)
local m=Combat.messages[#Combat.messages]
if m.text~=C:Format(10*targetScale) or m.meta.scale~=targetScale or m.critical then fail("direct recipient-scaled damage failed") end
cleu(2,"SPELL_DAMAGE","Creature-target","Wolf",0,"Player-self","Brus",0,1,"Bite",1,8,0,1,0,0,0,true,false,false)
m=Combat.messages[#Combat.messages]
if m.text~="-"..C:Format(8*playerScale) or not m.critical or m.kind~="incoming" then fail("incoming critical damage failed") end
cleu(3,"SPELL_PERIODIC_DAMAGE","Player-self","Brus",0,"Creature-target","Wolf",0,2,"Burn",4,3,0,4,0,0,0,false,false,false)
m=Combat.messages[#Combat.messages]
if m.text~=C:Format(3*targetScale) or m.meta.subevent~="SPELL_PERIODIC_DAMAGE" then fail("periodic damage failed") end
cleu(4,"SPELL_HEAL","Player-self","Brus",0,"Player-self","Brus",0,3,"Heal",2,20,5,0,true)
m=Combat.messages[#Combat.messages]
if m.text~="+"..C:Format(15*playerScale) or not m.critical then fail("effective critical healing failed") end
local convertedA=Combat:Convert(100,"Creature-target")
local convertedB=Combat:Convert(100,"Player-self")
if convertedA==convertedB or convertedA~=100*targetScale or convertedB~=100*playerScale then fail("same event recipient-scale independence failed") end
local before=117*playerScale; local damage=8*playerScale; local after=(117-8)*playerScale
if before-after~=damage then fail("health/damage full-precision reconciliation failed") end
if C:GetScale("target")==nil or target.classification~="normal" then fail("classification-independent scale fixture failed") end
pass("CLEU damage, incoming, periodic, healing, crit, recipient scale, and reconciliation")

local CombatLog=EchoesUI.ChaosCombatLog
local function StockFormatter(_,timestamp,event,srcGUID,srcName,srcFlags,dstGUID,dstName,dstFlags,...)
    local tail={...}
    if event=="SWING_DAMAGE" then
        local amount=tail[1]-tail[2]
        local result=""
        if tonumber(tail[6]) and tonumber(tail[6])>0 then result=" ("..tail[6].." Absorbed)" end
        if tail[7] then result=result.." (Critical)" end
        return srcName.."'s melee swing hits "..dstName.." for "..amount.." Physical."..result,0.8,0.8,0.8
    elseif event=="SPELL_HEAL" then
        return srcName.." heals "..dstName.." for "..(tail[4]-tail[5])..".",0.1,1,0.1
    elseif event=="SWING_MISSED" then
        return srcName.." misses "..dstName.." ("..tail[1]..").",1,1,1
    end
    return "ordinary nonnumeric combat state",1,1,1
end
local line=CombatLog:RewriteFormatted(StockFormatter,{},1,"SWING_DAMAGE","Player-self","Brus",0,"Creature-target","Diseased Young Wolf",0,15,0,1,0,0,0,true,false,false)
if line~="Brus's melee swing hits Diseased Young Wolf for "..C:Format(15*targetScale).." Physical. (Critical)" then fail("stock wolf line rewrite failed: "..tostring(line)) end
if line:find(" for 15 Physical",1,true) then fail("native wolf amount leaked") end
line=CombatLog:RewriteFormatted(StockFormatter,{},2,"SPELL_HEAL","Player-self","Brus",0,"Player-self","Brus",0,3,"Heal",2,20,5,0,false)
if line~="Brus heals Brus for "..C:Format(15*playerScale).."." then fail("stock effective-heal rewrite failed: "..tostring(line)) end
line=CombatLog:RewriteFormatted(StockFormatter,{},3,"SWING_MISSED","Player-self","Brus",0,"Creature-target","Diseased Young Wolf",0,"DODGE",0)
if line~="Brus misses Diseased Young Wolf (DODGE)." then fail("text-only miss changed") end
local unresolved,why=CombatLog:RewriteFormatted(StockFormatter,{},4,"SWING_DAMAGE","Player-self","Brus",0,"Unknown-guid","Unknown",0,15,0,1,0,0,0,false,false,false)
if unresolved~=nil or why~="suppress_unresolved" then fail("unresolved numeric line was not narrowly suppressed") end
local nativeCalls,stockLines=0,{}
_G.COMBATLOG={AddMessage=function(_,text,r,g,b) stockLines[#stockLines+1]=text end}
_G.Blizzard_CombatLog_CurrentSettings={}
_G.CombatLog_OnEvent=StockFormatter
_G.CombatLog_AddEvent=function(...) nativeCalls=nativeCalls+1 end
if not CombatLog:Install() then fail("stock CombatLog_AddEvent seam did not install") end
CombatLog_AddEvent(5,"SWING_DAMAGE","Player-self","Brus",0,"Creature-target","Diseased Young Wolf",0,15,0,1,0,0,0,false,false,false)
if #stockLines~=1 or stockLines[1]:find(" for 15 Physical",1,true) then fail("installed stock seam leaked native damage") end
C.state.enabled=false
CombatLog_AddEvent(6,"SWING_DAMAGE","Player-self","Brus",0,"Creature-target","Diseased Young Wolf",0,15,0,1,0,0,0,false,false,false)
if nativeCalls~=1 then fail("Chaos OFF did not restore ordinary stock event path") end
C.state.enabled=true
pass("stock Combat Log wording, compact recipient scale, crit, healing, miss, and narrow failsafe")

local Equipment=EchoesUI.ChaosEquipment
local low,high,speed,dps=Equipment:ParseWeaponLines({"12 - 18 Damage","Speed 2.00","(7.5 damage per second)"})
if low~=12 or high~=18 or speed~=2 or dps~=7.5 then fail("weapon tooltip parsing failed") end
local refLow,refHigh,personalScale=Equipment:GetReferenceRange(12,18)
if personalScale~=C:GetScale("player") or refLow~=12*personalScale or refHigh~=18*personalScale then fail("personal reference scale diverged") end
local betterLow,betterHigh=Equipment:GetReferenceRange(16,24)
if betterLow<=refLow or betterHigh<=refHigh or math.abs((betterHigh/refHigh)-(24/18))>0.000001 then fail("gear ordering/ratio invariant failed") end
local display=Equipment:FormatReferenceRange(12,18)
if display~=C:Format(refLow,4).." - "..C:Format(refHigh,4) then fail("equipment formatter diverged") end
local statFrame=CreateFrame("Frame","MockDamageStat",UIParent)
_G.MockDamageStatStatText=statFrame:CreateFontString("MockDamageStatStatText","OVERLAY")
PaperDollFrame_SetDamage(statFrame,"player")
if MockDamageStatStatText:GetText()~=display or not statFrame.tooltip2:find("Native range: 12 %- 18") then fail("paper-doll Chaos damage reference failed") end
C.state.enabled=false
if Equipment:AddWeaponReference(GameTooltip) then fail("Chaos OFF added a tooltip reference") end
PaperDollFrame_SetDamage(statFrame,"player")
if MockDamageStatStatText:GetText()~="12 - 18" then fail("paper-doll Chaos OFF did not restore native range") end
C.state.enabled=true
pass("personal static scale, tooltip parsing, shared formatter, ordering, ratio, and Chaos OFF")

local Tooltip=EchoesUI.ChaosTooltip
local function AssertClass(line,kind,low,high)
    local value=Tooltip:ClassifyLine(line)
    if not value or value.kind~=kind or value.low~=low or value.high~=high then fail("tooltip classification failed: "..line) end
end
AssertClass("Deals 12 to 18 Fire damage.","damage",12,18)
AssertClass("Causes 24 Bleed damage over 12 sec.","periodic_damage",24,24)
AssertClass("Heals a friendly target for 20 to 30.","heal",20,30)
AssertClass("Heals the target for 45 over 15 sec.","periodic_heal",45,45)
AssertClass("Absorbs 35 damage.","absorb",35,35)
if Tooltip:ClassifyLine("Increases damage by 10%.") or Tooltip:ClassifyLine("Increases spell power by 25.") then fail("native percentage/stat input was translated") end

GameTooltip:ClearLines(); GameTooltip:AddLine("Mock Spell"); GameTooltip:AddLine("Deals 12 to 18 Fire damage."); GameTooltip._shown=true
GameTooltip:FireEvent("OnTooltipSetSpell")
local spellCount=0
for _,value in ipairs(GameTooltip._lines) do if tostring(value):find("Chaos Ability Reference",1,true) then spellCount=spellCount+1 end end
if spellCount~=1 then fail("spell tooltip reference was not appended exactly once") end
GameTooltip:FireEvent("OnTooltipSetSpell")
spellCount=0
for _,value in ipairs(GameTooltip._lines) do if tostring(value):find("Chaos Ability Reference",1,true) then spellCount=spellCount+1 end end
if spellCount~=1 then fail("spell tooltip reference duplicated: "..tostring(spellCount)) end

GameTooltip:ClearLines(); GameTooltip:AddLine("Mock Trinket"); GameTooltip:AddLine("Use: Deals 25 Fire damage.")
if not Tooltip:AddProcReference(GameTooltip) then fail("fixed use-effect reference was not appended") end
GameTooltip:ClearLines(); GameTooltip:AddLine("Mock Trinket"); GameTooltip:AddLine("Equip: Increases spell power by 25.")
if Tooltip:AddProcReference(GameTooltip) then fail("formula input proc was translated") end
C.state.enabled=false
GameTooltip:ClearLines(); GameTooltip:AddLine("Mock Spell"); GameTooltip:AddLine("Deals 12 Fire damage.")
if Tooltip:AddSpellReference(GameTooltip) then fail("Chaos OFF added a spell reference") end
C.state.enabled=true
pass("fixed spell, periodic, heal, absorb and proc references; deduplication; native exclusions; Chaos OFF")

target.exists=false
Overlay:Refresh(); if Overlay.frame:IsShown() then fail("overlay showed with no target") end
target.exists=true; target.current=42; target.maximum=42; Overlay:Refresh()
if not Overlay.frame:IsShown() or Overlay.value:GetText()~="42.0K / 42.0K" then fail("early target rendering failed: "..tostring(Overlay.value:GetText())) end
if Overlay.playerValue:GetText()~="101K / 101K" then fail("player curve rendering failed: "..tostring(Overlay.playerValue:GetText())) end
if TargetFrameHealthBarText:GetAlpha()~=0 or PlayerFrameHealthBarText:GetAlpha()~=0 then fail("native health text was not suppressed") end
if FocusFrameHealthBarText:GetAlpha()~=0 or PetFrameHealthBarText:GetAlpha()~=0 or PartyMemberFrame1HealthBarText:GetAlpha()~=0 then fail("auxiliary native health text was not suppressed") end
if PlayerHitIndicator:GetAlpha()~=0 or PetHitIndicator:GetAlpha()~=0 then fail("UNIT_COMBAT native hit indicators were not suppressed") end
target.current=21; Overlay.events:GetScript("OnEvent")(Overlay.events,"UNIT_HEALTH","target")
if Overlay.value:GetText()~="21.0K / 42.0K" then fail("injured target event did not refresh") end
target.current=0; Overlay.events:GetScript("OnEvent")(Overlay.events,"UNIT_HEALTH","target")
if Overlay.value:GetText()~="0 / 42.0K" then fail("target death did not retain the valid zero-health reading") end

target.current=117; target.maximum=117; target.level=4
Overlay.events:GetScript("OnEvent")(Overlay.events,"PLAYER_TARGET_CHANGED")
if Overlay.value:GetText()~=Overlay.playerValue:GetText() or Overlay.value:GetText()~="101K / 101K" then fail("self-target unit consistency failed") end
target.classification="elite"
if C:GetScale("target")~=C:GetScale("player") then fail("classification was double-counted over authoritative native HP") end
target.level=-1; target.classification="worldboss"
if C:GetScale("target")~=100 then fail("skull-level taper failed") end

target.exists=false; Overlay.events:GetScript("OnEvent")(Overlay.events,"PLAYER_TARGET_CHANGED")
if Overlay.frame:IsShown() then fail("overlay remained visible after target loss") end
pass("level/rank curve, target lifecycle, and PlayerFrame self-target consistency")

EchoesUI.StateStore:Ingest({chaos_enabled="0",chaos_power="1000",chaos_magnitude="1",chaos_scale="1000"},2)
if Overlay.frame:IsShown() or Settings.chaos.value:GetText()~="OFF" then fail("Chaos OFF visibility failed") end
if Overlay.playerValue:IsShown() or TargetFrameHealthBarText:GetAlpha()~=0.65 or PlayerFrameHealthBarText:GetAlpha()~=0.8 then fail("Chaos OFF did not exactly restore stock text state") end
if FocusFrameHealthBarText:GetAlpha()~=1 or PetFrameHealthBarText:GetAlpha()~=1 or PartyMemberFrame1HealthBarText:GetAlpha()~=1 then fail("Chaos OFF did not restore auxiliary health text") end
if PlayerHitIndicator:GetAlpha()~=0.9 or PetHitIndicator:GetAlpha()~=0.7 then fail("Chaos OFF did not restore native hit indicators") end
if GetMockCVar("CombatDamage")~="1" or GetMockCVar("CombatHealing")~="1" or GetMockCVar("enableCombatText")~="1" then fail("Chaos OFF did not exactly restore native combat CVars") end
SetMockCVar("CombatDamage","custom"); EchoesUI.StateStore:Ingest({chaos_enabled="1",chaos_power="1000",chaos_magnitude="1",chaos_scale="1000"},3); EchoesUI.StateStore:Ingest({chaos_enabled="0",chaos_power="1000",chaos_magnitude="1",chaos_scale="1000"},4)
if GetMockCVar("CombatDamage")~="custom" then fail("non-default original CVar was not preserved verbatim") end
local hydratedOn={chaos_enabled="1",chaos_power="1000",chaos_magnitude="1",chaos_scale="1000"}
local hydratedOff={chaos_enabled="0",chaos_power="1000",chaos_magnitude="1",chaos_scale="1000"}
C:ApplyAuthoritativeState(hydratedOn,"relog"); C:ApplyAuthoritativeState(hydratedOn,"state_refresh")
if not Combat.active or GetMockCVar("CombatDamage")~="0" or PlayerFrameHealthBarText:GetAlpha()~=0 then fail("repeated ON was not idempotent") end
C:ApplyAuthoritativeState(hydratedOff,"character_swap"); C:ApplyAuthoritativeState(hydratedOff,"state_refresh")
if Combat.active or GetMockCVar("CombatDamage")~="custom" or PlayerFrameHealthBarText:GetAlpha()~=0.8 then fail("repeated OFF did not restore original CVar/alpha baselines") end
C:ApplyAuthoritativeState(hydratedOn,"character_A"); C:ApplyAuthoritativeState(hydratedOff,"character_B"); C:ApplyAuthoritativeState(hydratedOn,"character_A_return")
if not C.state.enabled or not Combat.active or not Overlay.playerValue:IsShown() then fail("A ON -> B OFF -> A ON state projection failed") end
EchoesUI.StateStore:Ingest(hydratedOn,4.5,true)
Combat.events:GetScript("OnEvent")(Combat.events,"PLAYER_LOGOUT")
if Combat.active or GetMockCVar("CombatDamage")~="custom" then fail("logout simulation did not restore native combat presentation") end
local unchanged=EchoesUI.StateStore:Ingest(hydratedOn,5,true)
if unchanged~=false or not Combat.active or GetMockCVar("CombatDamage")~="0" then fail("unchanged authoritative relog snapshot did not reapply Chaos: changed="..tostring(unchanged).." active="..tostring(Combat.active).." cvar="..tostring(GetMockCVar("CombatDamage"))) end
GameTooltip:ClearLines(); GameTooltip:AddLine("Mock Spell"); GameTooltip:AddLine("Deals 12 Fire damage."); GameTooltip._shown=true
GameTooltip:FireEvent("OnTooltipSetSpell"); GameTooltip:FireEvent("OnTooltipSetSpell")
local hydrationSpellCount=0
for _,line in ipairs(GameTooltip._lines) do if tostring(line):find("Chaos Ability Reference",1,true) then hydrationSpellCount=hydrationSpellCount+1 end end
if hydrationSpellCount~=1 then fail("state reapplication duplicated tooltip augmentation") end
pass("relog, reload-style refresh, character swap, idempotence, CVar/alpha baselines, and singular tooltip behavior")
AttunementPlusBridgeDB.c43.reducedMotion=true; EchoesUI.StateStore:Ingest({chaos_enabled="1",chaos_power="1000",chaos_magnitude="1",chaos_scale="1000"},3)
PlayerFrame.unit="vehicle"; Overlay:Refresh()
if Overlay.playerValue:GetText()~=C:Format(500*C:GetScale("vehicle")).." / "..C:Format(1000*C:GetScale("vehicle")) then fail("vehicle-bound PlayerFrame did not use vehicle health") end
PlayerFrame.unit="player"
if Overlay.transition:GetScript("OnUpdate") then fail("Reduced Motion installed a transition animation") end
RunAllTimers(); if Overlay.transition:IsShown() then fail("Reduced Motion notice did not end cleanly") end
pass("conditional visibility and Reduced Motion transition path")
print("ALL CHAOS UI TESTS PASSED")

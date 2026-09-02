-- Behavioral smoke test for the EchoesUI native Dashboard completion layer.
-- This is a WoW 3.3.5a mock host, not a client renderer.

package.path = package.path .. ";./?.lua"

local ADDON_DIR = arg[1]
assert(ADDON_DIR, "usage: lua5.1 smoke_test.lua <addon-dir>")
dofile(arg[2])

local function pass(msg) print("PASS: " .. msg) end
local function fail(msg) print("FAIL: " .. msg); os.exit(1) end

_G.APB = { echoes = { welcomed = false } }
AttunementPlusBridgeDB = { cache = {} }

local function load(rel)
    local chunk, err = loadfile(ADDON_DIR .. "/" .. rel)
    if not chunk then fail("could not load " .. rel .. ": " .. tostring(err)) end
    local ok, runErr = pcall(chunk)
    if not ok then fail("runtime error loading " .. rel .. ": " .. tostring(runErr)) end
    pass("loaded " .. rel)
end

load("EchoesUI/Bootstrap.lua")
load("EchoesUI/Theme.lua")
load("EchoesUI/StateStore.lua")
load("EchoesUI/AnimationController.lua")
load("EchoesUI/Chaos.lua")
load("EchoesUI/ChaosCombatText.lua")
load("EchoesUI/ChaosCombatLog.lua")
load("EchoesUI/ChaosEquipment.lua")
load("EchoesUI/ChaosTooltip.lua")
load("EchoesUI/ScreenManager.lua")
load("EchoesUI/InputManager.lua")
load("EchoesUI/Layout.lua")
load("EchoesUI/Components/IconButton.lua")
load("EchoesUI/Components/Landmark.lua")
load("EchoesUI/Components/CoreWidget.lua")
load("EchoesUI/Components/ResourceDisplay.lua")
load("EchoesUI/Components/ProgressionZone.lua")
load("EchoesUI/Components/ProgressionRow.lua")
load("C43Dashboard.lua")
load("EchoesUI/DashboardGateB.lua")
load("EchoesUI/Screens/ProgressionScreen.lua")
load("EchoesUI/Screens/WorldThreatScreen.lua")
load("EchoesUI/Screens/CrucibleScreen.lua")
load("EchoesUI/Screens/TalentsScreen.lua")
load("EchoesUI/Screens/RackScreen.lua")
load("EchoesUI/Screens/ForgeScreen.lua")
load("EchoesUI/Screens/VisageScreen.lua")

local Gate = EchoesUI.DashboardGateB
local C43 = APB.C43
local Progression = EchoesUI.ProgressionScreen
local WorldThreat = EchoesUI.WorldThreatScreen
local Crucible = EchoesUI.CrucibleScreen
local Talents = EchoesUI.TalentsScreen
local Rack = EchoesUI.RackScreen
local Forge = EchoesUI.ForgeScreen
local Visage = EchoesUI.VisageScreen
local nativeIds = {
    "codex", "search", "talents", "rack", "visage", "core",
    "progression", "threat", "crucible", "forge",
    "accessibility", "settings", "close",
}

local function SubscriberCount()
    local count = 0
    for _ in pairs(EchoesUI.StateStore.subscribers) do count = count + 1 end
    return count
end
local subscriberCountAtConstruction

if EchoesUI.flags.nativeDashboardGateB ~= false then
    fail("native Dashboard must remain default-off")
end
if Gate.active then fail("native Dashboard must be inactive by default") end
pass("native Dashboard completion layer defaults to false")

local seen = nil
EchoesUI.StateStore:Subscribe(function(values, changed) seen = changed end)
local changed = EchoesUI.StateStore:Ingest({ essence="1234", mastery_rank="3" }, 100)
if not changed or EchoesUI.StateStore:Get("essence") ~= 1234 then
    fail("StateStore did not normalize the first state")
end
if not seen or seen.essence ~= 1234 then fail("StateStore subscriber missed essence") end
if Gate.resource.value:GetText() ~= "1,234" then
    fail("native Essence did not consume shared state")
end
local resourceTick = Gate.resource.responseFrame:GetScript("OnUpdate")
if resourceTick then resourceTick(Gate.resource.responseFrame, 0.40) end
local glyphTick = Gate.resource.glyphFrame:GetScript("OnUpdate")
if glyphTick then glyphTick(Gate.resource.glyphFrame, 0.11) end
glyphTick = Gate.resource.glyphFrame:GetScript("OnUpdate")
if glyphTick then glyphTick(Gate.resource.glyphFrame, 0.20) end
if Gate.resource.responseFrame:GetScript("OnUpdate") then
    fail("Essence acknowledgement left an idle OnUpdate")
end
if Gate.resource.glyphFrame:GetScript("OnUpdate") then
    fail("Essence glyph acknowledgement left an idle OnUpdate")
end
RunAllTimers()
pass("StateStore feeds native Essence with bounded acknowledgement")

if EchoesUI.StateStore:Ingest({ essence="1234", mastery_rank="3" }, 101) then
    fail("unchanged state must remain idempotent")
end
subscriberCountAtConstruction = SubscriberCount()
pass("StateStore ingest is idempotent")

EchoesUI.StateStore:Ingest({
    essence="2500", mastery_rank="4", absorb_pct="16.2", mastery_next_cost="1200",
    attuned="12", snapshots="28", absorbed_stats="3.5/1.0/8.2/0/0.5",
    slots="0:80,4:180,15:500",
    threat_level="4", threat_name="Menacing", threat_max="10",
    threat_ceiling_pct="40", threat_momentum_pct="25", threat_effective_pct="10",
    threat_safety_pct="80", threat_debt_kills="3", threat_debt_mult_pct="65",
    threat_attune_loss_pct="10", threat_essence_loss_pct="3", threat_essence_cap="1000",
    threat_penalty_debt_kills="15", threat_penalty_debt_mult_pct="65",
    threat_cap_normal_pct="40", threat_cap_elite_pct="70", threat_cap_boss_pct="85", threat_cap_raid_pct="100",
}, 102)
Progression:Show()
if not Progression.active or not Progression.frame:IsShown() then fail("Progression screen did not open") end
if Progression.rankValue:GetText() ~= "4" or Progression.action.value:GetText() ~= "1,200" then
    fail("Progression Mastery did not consume authoritative state")
end
if not Progression.back.compact or not Progression.home.compact or not Progression.close.compact
    or Progression.back.label:GetText() ~= "‹  BACK"
    or Progression.home.label:GetText() ~= "CORE / HOME"
    or Progression.close.label:GetText() ~= "CLOSE  ×" then
    fail("Progression compact navigation labels regressed or clipped structurally")
end
if Progression.action.meta:GetText():find("authoritative", 1, true)
    or Progression.action.tooltip:find("server", 1, true) then
    fail("Progression exposed developer-facing validation language")
end
if Progression.attunedValue:GetText() ~= "12" or Progression.statValues[1]:GetText() ~= "+3.5" then
    fail("Progression retained aggregate did not consume backend truth")
end
if #Progression.equipped ~= 3 then fail("Current Attunement did not enumerate tracked equipped items") end
Progression:OnAttunement({entry=1001,prog=500,cap=1000})
if Progression.currentRows[1].value:GetText() ~= "50%" then fail("APTIP data did not update Current Attunement") end
Progression:OnAttunement({entry=1001,prog=1000,cap=1000})
if Progression.currentRows[1].value:GetText() ~= "ATTUNED"
    or not Progression.currentRows[1].completeMark:IsShown() then
    fail("completed Current Attunement did not establish its retained marker")
end
if Progression.slotRows[1].value:GetText() ~= "+2.5%" then fail("Slot Specialization derivation is incorrect") end
if Progression.slotScrollPosition:GetText() ~= "1–7 / 17" then
    fail("Slot Specialization scroll affordance did not expose its viewport")
end
Progression.input:SetFocusById("mastery")
Progression.input:HandleKey("RIGHT")
if Progression.input.focusId ~= "history" then fail("Progression zone navigation failed") end
Progression:Leave("back")
if Progression.active then fail("Progression Back did not close the screen") end
pass("functional native Progression state, attunement, slots, navigation, and lifecycle")

local threatAction, threatActionSends
local originalThreatActionRequest=APB.RequestEchoesAction
local originalThreatStateRequest=APB.RequestEchoesState
APB.RequestEchoesAction=function(_,name) threatAction=name; threatActionSends=(threatActionSends or 0)+1; return true end
APB.RequestEchoesState=function() end
local threatNames={"Peaceful","Uneasy","Stirring","Dangerous","Menacing","Hostile","Dire","Cataclysmic","Apocalyptic","Worldbreaker","Ascendant"}
local function IngestThreat(level,momentum,stamp)
    local attuneLoss,essenceLoss,essenceCap,debtKills,debtMult=0,0,0,0,100
    if level<=3 and level>0 then attuneLoss,essenceLoss,essenceCap,debtKills,debtMult=5,1,250,10,80
    elseif level<=6 and level>0 then attuneLoss,essenceLoss,essenceCap,debtKills,debtMult=10,3,1000,15,65
    elseif level<=9 and level>0 then attuneLoss,essenceLoss,essenceCap,debtKills,debtMult=15,5,5000,20,50
    elseif level==10 then attuneLoss,essenceLoss,essenceCap,debtKills,debtMult=20,8,10000,25,40 end
    momentum=momentum or 25
    EchoesUI.StateStore:Ingest({
        essence="2500",mastery_rank="4",absorb_pct="16.2",mastery_next_cost="1200",
        attuned="12",snapshots="28",absorbed_stats="3.5/1.0/8.2/0/0.5",slots="0:80,4:180,15:500",
        threat_level=tostring(level),threat_name=threatNames[level+1],threat_max="10",
        threat_ceiling_pct=tostring(level*10),threat_momentum_pct=tostring(momentum),
        threat_effective_pct=tostring(level*momentum/10),threat_safety_pct=tostring(math.max(50,100-level*5)),
        threat_debt_kills="0",threat_debt_mult_pct="100",threat_attune_loss_pct=tostring(attuneLoss),
        threat_essence_loss_pct=tostring(essenceLoss),threat_essence_cap=tostring(essenceCap),
        threat_penalty_debt_kills=tostring(debtKills),threat_penalty_debt_mult_pct=tostring(debtMult),
        threat_cap_normal_pct="40",threat_cap_elite_pct="70",threat_cap_boss_pct="85",threat_cap_raid_pct="100",
    },stamp)
end
WorldThreat:Show()
if not WorldThreat.active or WorldThreat.stanceName:GetText()~="Menacing"
    or WorldThreat.levelValue:GetText()~="4" or WorldThreat.ceilingValue:GetText()~="+40.0%" then
    fail("World Threat did not consume its authoritative stance snapshot")
end
if WorldThreat.stages[4].mark:GetText()~="CURRENT" or WorldThreat.stages[5].mark:GetText()~="" then
    fail("World Threat discrete pressure rail did not establish current state")
end
WorldThreat.raise:Activate("keyboard")
if threatAction~="threat_increase" or not WorldThreat.actionPending then
    fail("World Threat increase did not use the canonical action seam")
end
WorldThreat:OnAction("ACTION_OK",{action="threat_increase",status="SUCCESS",new_level="5"})
EchoesUI.StateStore:Ingest({
    essence="2500", mastery_rank="4", absorb_pct="16.2", mastery_next_cost="1200",
    attuned="12", snapshots="28", absorbed_stats="3.5/1.0/8.2/0/0.5",
    slots="0:80,4:180,15:500",
    threat_level="5",threat_name="Hostile",threat_max="10",threat_ceiling_pct="50",
    threat_momentum_pct="25",threat_effective_pct="12.5",threat_safety_pct="75",
    threat_debt_kills="3",threat_debt_mult_pct="65",threat_attune_loss_pct="10",
    threat_essence_loss_pct="3",threat_essence_cap="1000",threat_penalty_debt_kills="15",
    threat_penalty_debt_mult_pct="65",threat_cap_normal_pct="40",threat_cap_elite_pct="70",
    threat_cap_boss_pct="85",threat_cap_raid_pct="100",
},103)
RunAllTimers()
if WorldThreat.levelValue:GetText()~="5" or WorldThreat.stanceName:GetText()~="Hostile" then
    fail("World Threat action did not settle through refreshed server state")
end
if WorldThreat.currentSealLeftGap<WorldThreat.protectedReadoutLeft
    or WorldThreat.currentSealRightGap<WorldThreat.protectedReadoutRight
    or WorldThreat.sealLeftWidth>190 or WorldThreat.sealRightWidth>145 then
    fail("World Threat seals entered the protected central reading aperture")
end
if WorldThreat.stanceName._width~=400 then fail("World Threat stance name lacks its protected reading seat") end

-- Reproduce the live failure: a second action before STATE can be rejected by
-- the server action window as ERROR|RATE_LIMITED|message=action. That terminal
-- result must unlock the active plate without graying unrelated mutations.
local sendsBefore=threatActionSends
WorldThreat.raise:Activate("keyboard")
if not WorldThreat.raise.pending or WorldThreat.lower.pending or not WorldThreat.lower.enabled
    or not WorldThreat.reset.enabled or not WorldThreat.back.enabled or not WorldThreat.home.enabled or not WorldThreat.close.enabled then
    fail("World Threat pending state was not local to the activated mutation")
end
if WorldThreat.raise.meta:GetText()~="ADJUSTING…" or WorldThreat.raise.edge:GetAlpha()~=0.74 then
    fail("World Threat pending state is not visually distinct from disabled")
end
WorldThreat.lower:Activate("mouse")
if threatActionSends~=sendsBefore+1 then fail("rapid input queued a second World Threat mutation") end
WorldThreat:OnAction("ERROR",{code="RATE_LIMITED",message="action"})
if WorldThreat.actionPending or not WorldThreat.raise.pending or WorldThreat.settlingAction~="threat_increase"
    or WorldThreat.raise.meta:GetText()~="STABILIZING…" or not WorldThreat.raise.enabled
    or not WorldThreat.lower.enabled or not WorldThreat.reset.enabled then
    fail("rate-limited World Threat action did not enter local settling presentation")
end
RunAllTimers()
if WorldThreat.settlingAction or WorldThreat.raise.pending then
    fail("World Threat local settling presentation did not clear")
end

-- Exercise every authoritative level transition and independent bound state.
IngestThreat(0,0,200)
if not WorldThreat.raise.enabled or WorldThreat.lower.enabled or WorldThreat.reset.enabled then
    fail("World Threat level-zero action availability is incorrect")
end
if WorldThreat.reset.width~=220 or WorldThreat.lower.width~=250 or WorldThreat.raise.width~=250 then
    fail("World Threat baseline reset did not retain its subordinate utility hierarchy")
end
for _,segment in ipairs(WorldThreat.loadSegments) do
    if segment:GetAlpha()~=.06 then fail("Peaceful World Threat rendered active structural load") end
end
for level=0,9 do
    local before=threatActionSends
    WorldThreat.raise:Activate("keyboard")
    if threatActionSends~=before+1 or not WorldThreat.actionPending then fail("World Threat raise sequence did not start") end
    WorldThreat:OnAction("ACTION_OK",{action="threat_increase",status="SUCCESS",old_level=tostring(level),new_level=tostring(level+1)})
    if WorldThreat.actionPending then fail("successful World Threat action did not terminate pending") end
    IngestThreat(level+1,25,201+level)
    RunAllTimers()
end
if WorldThreat.raise.enabled or not WorldThreat.lower.enabled or not WorldThreat.reset.enabled
    or WorldThreat.raise.tooltip~="Maximum world pressure reached." then
    fail("World Threat maximum bound disabled the wrong control family")
end
for _,segment in ipairs(WorldThreat.loadSegments) do
    if segment:GetAlpha()<.50 then fail("maximum World Threat did not express pressure through structure") end
end
if WorldThreat.raise.edge:GetAlpha()~=0.16 or WorldThreat.lower.edge:GetAlpha()==0.16 then
    fail("World Threat disabled bound is not visually distinct from valid actions")
end
WorldThreat.actionPending=true; WorldThreat.pendingAction="threat_increase"; WorldThreat:RefreshState(EchoesUI.StateStore.values)
WorldThreat:OnAction("ACTION_OK",{action="threat_increase",status="MAXIMUM",old_level="10",new_level="10"})
if WorldThreat.actionPending or WorldThreat.raise.enabled or not WorldThreat.lower.enabled or not WorldThreat.reset.enabled then
    fail("canonical maximum result did not recover with correct action bounds")
end
RunAllTimers()

for level=10,8,-1 do
    WorldThreat.lower:Activate("keyboard")
    WorldThreat:OnAction("ACTION_OK",{action="threat_decrease",status="SUCCESS",new_level=tostring(level-1)})
    IngestThreat(level-1,0,220-level)
    RunAllTimers()
end
WorldThreat.reset:Activate("keyboard")
WorldThreat:OnAction("ACTION_OK",{action="threat_reset",status="SUCCESS",new_level="0"})
IngestThreat(0,0,230)
RunAllTimers()
WorldThreat.input:SetFocusById("increase")
local beforeKeyboard=threatActionSends
WorldThreat.input:HandleKey("ENTER")
WorldThreat.input:HandleKey("SPACE")
if threatActionSends~=beforeKeyboard+1 then fail("World Threat keyboard rapid input escaped the in-flight guard") end
WorldThreat:OnAction("ACTION_OK",{action="threat_increase",status="SUCCESS",new_level="1"})
IngestThreat(1,25,231)
RunAllTimers()

WorldThreat.raise:Activate("keyboard")
if not WorldThreat.actionPending then fail("World Threat timeout test did not enter pending") end
RunAllTimers()
if WorldThreat.actionPending or WorldThreat.raise.pending or not WorldThreat.lower.enabled
    or not WorldThreat.reset.enabled or not WorldThreat.back.enabled then
    fail("World Threat timeout did not restore independent controls and navigation")
end
WorldThreat:Leave("back")
RunAllTimers()
APB.RequestEchoesAction=originalThreatActionRequest
APB.RequestEchoesState=originalThreatStateRequest
pass("native World Threat full-range actions, bounds, rejection, timeout, protected readout, and lifecycle")

local crucibleAction, crucibleArgs
local originalCrucibleActionRequest=APB.RequestEchoesAction
local originalCrucibleStateRequest=APB.RequestEchoesState
APB.RequestEchoesAction=function(_,name,category,amount) crucibleAction=name; crucibleArgs={category,amount}; return true end
APB.RequestEchoesState=function() end
EchoesUI.StateStore:Ingest({
    essence="12000",crucible_total_invested="326000",
    crucible="life_leech:250000,fortitude:50000,melee_power:10000,spell_power:0,crit_rating:5000,haste_rating:0,armor_pen:0,execute_power:0,spell_mitigation:1000,dodge_rating:0,parry_rating:0,reflect_chance:0,cooldown_reduction:5000,movement_speed:5000,res_resilience:0,aether_surge:0,attunement_echo:0",
    crucible_status="life_leech:AVAILABLE,fortitude:AVAILABLE,melee_power:AVAILABLE,spell_power:AVAILABLE,crit_rating:AVAILABLE,haste_rating:AVAILABLE,armor_pen:AVAILABLE,execute_power:AVAILABLE,spell_mitigation:AVAILABLE,dodge_rating:AVAILABLE,parry_rating:AVAILABLE,reflect_chance:AVAILABLE,cooldown_reduction:AVAILABLE,movement_speed:AVAILABLE,res_resilience:AVAILABLE,aether_surge:AVAILABLE,attunement_echo:AVAILABLE",
    crucible_effect_pct="life_leech:5.7080,fortitude:6.9646,melee_power:3.9211,spell_power:0,crit_rating:0.2233,haste_rating:0,armor_pen:0,execute_power:0,spell_mitigation:0.0998,dodge_rating:0,parry_rating:0,reflect_chance:0,cooldown_reduction:0.1990,movement_speed:0.2233,res_resilience:0,aether_surge:0,attunement_echo:0",
    crucible_ceiling_pct="life_leech:8.00,fortitude:50.00,melee_power:100.00,spell_power:100.00,crit_rating:15.00,haste_rating:20.00,armor_pen:30.00,execute_power:40.00,spell_mitigation:25.00,dodge_rating:15.00,parry_rating:10.00,reflect_chance:5.00,cooldown_reduction:20.00,movement_speed:15.00,res_resilience:50.00,aether_surge:50.00,attunement_echo:50.00",
},300)
Crucible:Show()
if not Crucible.active or not Crucible.frame:IsShown() or #Crucible.channelOrder~=17 or Crucible.channels.threat_reduction then
    fail("Crucible did not open with exactly seventeen visible backend-active channels")
end
if APB.C43.frame:IsShown() then fail("Crucible did not take visual ownership from the Dashboard") end
if not Crucible.bankFrames.foundation or not Crucible.bankFrames.damage
    or not Crucible.bankFrames.survival or not Crucible.bankFrames.utility then
    fail("Crucible families are not stable machine geography")
end
if Crucible.channels.life_leech.tongue:GetWidth() <= Crucible.channels.spell_power.tongue:GetWidth()
    or Crucible.channels.spell_power.value:GetText() ~= "DORMANT" then
    fail("Crucible channel investment distribution is not structurally legible")
end
if Crucible.investedValue:GetText()~="250,000" or Crucible.effectValue:GetText()~="5.71%" or Crucible.total:GetText():find("326,000",1,true)==nil then
    fail("Crucible did not consume authoritative investment/effect totals")
end
if crucibleAction~="crucible_preview" or crucibleArgs[1]~="life_leech" or crucibleArgs[2]~=1000 then
    fail("Crucible initial selection did not request canonical preview")
end
Crucible:OnAction("ACTION_OK",{action="crucible_preview",status="READY",category="life_leech",amount="1000",current_invested="250000",projected_invested="251000",current_effect_pct="5.7080",projected_effect_pct="5.7194",ceiling_pct="8.00"})
if Crucible.previewProjected:GetText()~="5.72%" or not Crucible.forge.enabled then fail("Crucible preview did not unlock Forge") end
Crucible:SetAmount(50000)
if Crucible.forge.enabled or Crucible.forge.meta:GetText():find("NEED",1,true)==nil then fail("unaffordable Crucible amount was not visibly gated") end
Crucible:SetAmount(5000)
Crucible:OnAction("ACTION_OK",{action="crucible_preview",status="READY",category="life_leech",amount="5000",current_invested="250000",projected_invested="255000",current_effect_pct="5.7080",projected_effect_pct="5.7646",ceiling_pct="8.00"})
Crucible.channels.aether_surge.root:FireEvent("OnEnter")
if not Crucible.channels.aether_surge.hovered then fail("Crucible channel hover did not wake its local mechanism") end
Crucible.channels.aether_surge.root:FireEvent("OnMouseUp","LeftButton")
if Crucible.selected~="aether_surge" then fail("Crucible channel mouse activation did not select across families") end
Crucible.amounts[10000].root:FireEvent("OnEnter")
if not Crucible.amounts[10000].hovered or Crucible.amounts[10000].seat:GetAlpha()<=0.74 then fail("Crucible amount hover was not independently legible") end
Crucible.amounts[10000].root:FireEvent("OnMouseUp","LeftButton")
if Crucible.amount~=10000 then fail("Crucible amount mouse activation did not move the regulator") end
Crucible:SelectCategory("life_leech"); Crucible:SetAmount(5000)
Crucible:OnAction("ACTION_OK",{action="crucible_preview",status="READY",category="life_leech",amount="5000",current_invested="250000",projected_invested="255000",current_effect_pct="5.7080",projected_effect_pct="5.7646",ceiling_pct="8.00"})
Crucible.forge:Activate("keyboard")
if crucibleAction~="crucible_invest" or not Crucible.investPending
    or Crucible.forge.label:GetText()~="FORGING…" or Crucible.forge.meta:GetText()~="THE CHAMBER IS COMMITTING" then
    fail("Crucible Forge did not enter its local pending state")
end
Crucible:OnAction("ACTION_OK",{action="crucible_invest",status="SUCCESS",category="life_leech",amount="5000"})
if Crucible.investPending or Crucible.status:GetText():find("seals the investment",1,true)==nil then fail("Crucible success did not settle through refresh state") end
Crucible.input:SetFocusById("life_leech"); Crucible.input:HandleKey("RIGHT")
if Crucible.input.focusId~="amount10000" then fail("Crucible spatial navigation did not enter amount rail") end
if not Crucible.channels.life_leech.selected then fail("moving focus visually deselected the engaged channel") end
Crucible.input:HandleKey("DOWN")
if Crucible.input.focusId~="forge" then fail("Crucible amount rail did not navigate into Forge") end
SetMockChatActive(true); local crucibleFocus=Crucible.input.focusId; Crucible.input:HandleKey("LEFT"); Crucible.input:HandleKey("ENTER")
if Crucible.input.focusId~=crucibleFocus then fail("Crucible intercepted chat-focused input") end
SetMockChatActive(false)
AttunementPlusBridgeDB.c43.reducedMotion=true; Crucible:WakeCommittedChannel("life_leech")
if Crucible.heat:GetAlpha()~=0.10 or Crucible.selectedJointHeat:GetAlpha()~=0.66 then fail("Crucible reduced-motion commit state did not settle immediately") end
AttunementPlusBridgeDB.c43.reducedMotion=false
Crucible:Leave("back")
APB.RequestEchoesAction=originalCrucibleActionRequest; APB.RequestEchoesState=originalCrucibleStateRequest
pass("native Crucible ownership, machine geography, truth, preview, Forge, accessibility, and navigation")

local talentAction,talentIndex,talentStateRequests
local originalTalentActionRequest=APB.RequestEchoesAction
local originalTalentStateRequest=APB.RequestEchoesState
APB.echoes.welcomed=true
APB.echoes.compatible=1
APB.echoes.caps={talents_state_v1=true,action_talent_preview=true,action_talent_purchase=true}
APB.RequestEchoesAction=function(_,name,index) talentAction=name; talentIndex=index; return true end
APB.RequestEchoesState=function() talentStateRequests=(talentStateRequests or 0)+1; return true end
EchoesUI.StateStore:Ingest({
    essence="5000",talents="0:0,1:0,2:0,3:1,4:0",talent_primary_stat="3",
    talent_role="0:SECONDARY,1:SECONDARY,2:SECONDARY,3:PRIMARY,4:SECONDARY",
    talent_bonus_pct="0:0.0,1:0.0,2:0.0,3:12.0,4:0.0",
    talent_next_rank_cost="0:1000,1:1000,2:1000,3:6000,4:1000",
    talent_next_bonus_pct="0:8.0,1:8.0,2:8.0,3:24.0,4:8.0",
    talent_max_rank="0:2,1:2,2:2,3:3,4:2",talent_distinct_stats="1",talent_distinct_penalty_pct="100.0",
},350)
if not Talents:IsAvailable() then fail("Talents capability gate rejected a complete contract") end
Talents:Show()
if not Talents.active or not Talents.frame:IsShown() or APB.C43.frame:IsShown() then fail("Talents did not take visual ownership") end
for index=0,4 do if not Talents.anchors[index] then fail("missing stable Talent anchor "..index) end end
if Talents.previewTitle:GetText()~="NEXT RANK PREVIEW" or Talents.footer:GetText():find("NO TREE",1,true) then fail("Talents retained player-facing implementation language") end
for index=0,4 do
    local anchor=Talents.anchors[index]
    if not anchor.backing or not anchor.socketFrame or not anchor.arm or not anchor.elbow or not anchor.couplingRib or not anchor.rankTabs or #anchor.rankTabs~=3 then fail("Talent anchor "..index.." is missing articulated brace geometry") end
end
if not Talents.truthBridge or not Talents.actuatorSpine or not Talents.efficiencyTension then fail("Talents central brace does not physically connect preview, Essence, and Invest") end
if not Talents.anchors[3].primary or Talents.anchors[0].primary then fail("authoritative Primary did not control structural dominance") end
if talentAction~="talent_preview" or talentIndex~=0 then fail("initial Talent selection did not request authoritative preview") end
Talents:OnAction("ACTION_OK",{action="talent_preview",status="READY",stat_index="0",cost="1000",affordable="1",current_rank="0",projected_rank="1",current_role="SECONDARY",projected_role="PRIMARY",current_bonus_pct="0.0",projected_bonus_pct="12.0",current_primary_stat="3",projected_primary_stat="0",current_penalty_pct="100.0",projected_penalty_pct="85.0",current_distinct="1",projected_distinct="2"})
if not Talents.invest.enabled or Talents.projectedValue:GetText()~="+12.0%" or not Talents.roleTransition:GetText():find("PRIMARY SHIFTS",1,true) then fail("Talent preview did not expose authoritative Primary transition") end
if Talents.roleTransition:GetText():find("→",1,true) or Talents.efficiency:GetText():find("→",1,true) then fail("Talents used an unsafe client glyph in projected state copy") end
if not Talents.efficiency:GetText():find("85.0%",1,true) then fail("Talent preview omitted projected concentration efficiency") end
Talents.anchors[1].root:FireEvent("OnEnter")
if not Talents.anchors[1].hovered or Talents.anchors[1].wake:GetAlpha()<=.03 then fail("Talent anchor hover did not wake its local joint") end
Talents.input:SetFocusById("talent1")
if Talents.selected~=0 or not Talents.anchors[1].focused or not Talents.anchors[0].selected then fail("Talent focus was conflated with selection") end
Talents.input:HandleKey("ENTER")
if Talents.selected~=1 then fail("keyboard activation did not select the focused Talent anchor") end
Talents:SelectAnchor(0)
Talents:OnAction("ACTION_OK",{action="talent_preview",status="READY",stat_index="0",cost="1000",affordable="1",current_rank="0",projected_rank="1",current_role="SECONDARY",projected_role="PRIMARY",current_bonus_pct="0.0",projected_bonus_pct="12.0",current_primary_stat="3",projected_primary_stat="0",current_penalty_pct="100.0",projected_penalty_pct="85.0",current_distinct="1",projected_distinct="2"})
Talents.invest:Activate("keyboard")
if talentAction~="talent_purchase" or talentIndex~=0 or not Talents.purchasePending or Talents.invest.label:GetText()~="RETAINING..." then fail("Talent commit did not use its canonical guarded action") end
Talents:OnAction("ACTION_OK",{action="talent_purchase",status="SUCCESS",stat_index="0",new_rank="1"})
if Talents.purchasePending or (talentStateRequests or 0)==0 then fail("Talent success did not request authoritative settlement") end
EchoesUI.StateStore:Ingest({
    essence="4000",talents="0:1,1:0,2:0,3:1,4:0",talent_primary_stat="0",
    talent_role="0:PRIMARY,1:SECONDARY,2:SECONDARY,3:SECONDARY,4:SECONDARY",
    talent_bonus_pct="0:12.0,1:0.0,2:0.0,3:8.0,4:0.0",
    talent_next_rank_cost="0:6000,1:1000,2:1000,3:3000,4:1000",
    talent_next_bonus_pct="0:24.0,1:8.0,2:8.0,3:16.0,4:8.0",
    talent_max_rank="0:3,1:2,2:2,3:2,4:2",talent_distinct_stats="2",talent_distinct_penalty_pct="85.0",
},351)
if not Talents.anchors[0].primary or Talents.anchors[3].primary or Talents.anchors[3].roleText:GetText():find("+8.0%",1,true)==nil then fail("post-purchase state did not re-seat the server-selected Primary") end
Talents:SelectAnchor(2)
Talents:OnAction("ACTION_OK",{action="talent_preview",status="READY",stat_index="2",cost="1000",affordable="0",current_rank="0",projected_rank="1",current_role="SECONDARY",projected_role="SECONDARY",current_bonus_pct="0.0",projected_bonus_pct="8.0",current_primary_stat="0",projected_primary_stat="0",current_penalty_pct="85.0",projected_penalty_pct="72.3",current_distinct="2",projected_distinct="3"})
if Talents.invest.enabled or Talents.invest.meta:GetText()~="INSUFFICIENT ESSENCE" then fail("unaffordable Talent preview was not visibly gated") end
AttunementPlusBridgeDB.c43.reducedMotion=true; Talents:WakeAnchor(2)
if Talents.anchors[2].wake:GetAlpha()~=.22 then fail("Talent reduced-motion wake did not settle immediately") end
AttunementPlusBridgeDB.c43.reducedMotion=false
Talents:Leave("back")
if not Gate.active or Gate.input.focusId~="talents" then fail("Talents Back did not restore Dashboard focus") end
APB.RequestEchoesAction=originalTalentActionRequest; APB.RequestEchoesState=originalTalentStateRequest
pass("native Talents five-anchor truth, preview, Primary transition, commit, accessibility, and navigation")

local host = CreateFrame("Frame", "SmokeTestHost", UIParent)
local activated = 0
local button = EchoesUI.IconButton:Create(host, {
    id="smokeButton", tooltip="Smoke", shapedResponse=true, hideIcon=true,
    focusCues={{x=4,y=4,w=9,h=2}},
    onActivate=function() activated=activated+1 end,
})
button.root:FireEvent("OnEnter")
button:SetFocused(true)
button.root:FireEvent("OnMouseDown", "LeftButton")
button.root:FireEvent("OnMouseUp")
button:Activate("mouse")
if activated ~= 1 then fail("IconButton activation path failed") end
button:SetEnabled(false); button:SetEnabled(true)
pass("artifact utility button render paths")

for _, id in ipairs(nativeIds) do
    if not Gate.controls[id] then fail("missing native component " .. id) end
end
if next(Gate.legacyAdapters) then fail("completion layer should not need hybrid adapters") end
if not Gate.controls.core.isCoreWidget then fail("Core/Home must use CoreWidget") end
if not Gate.resource then fail("native Essence display missing") end
if Gate.controls.core.homeCueFrame or Gate.controls.core.homeCue then
    fail("Core still exposes bolted-on HOME text")
end
pass("all thirteen visible controls plus Essence are native")

for _, id in ipairs(nativeIds) do
    local control = Gate.controls[id]
    if id ~= "settings" then
        if control.art then fail(id .. " replaced the Candidate 43 resting body") end
        if not control.responseTextures or #control.responseTextures == 0 then
            fail(id .. " lacks a localized response")
        end
    end
end
if Gate.controls.settings.seatRestAlpha ~= 0 then
    fail("Settings must preserve the Candidate 43 utility body at rest")
end
pass("completion layer uses embedded responses rather than replacement landmarks")

for _, id in ipairs({"progression", "talents", "threat", "crucible", "rack", "visage", "forge", "core"}) do
    local control = Gate.controls[id]
    if not control.materialPieces or #control.materialPieces ~= 3 then
        fail(id .. " lacks its bounded three-part material-state contract")
    end
    if control.focusPieces and #control.focusPieces > 0 then
        fail(id .. " still uses external focus notation")
    end
end
pass("gameplay focus is a bounded material state rather than marker geometry")

Gate:Show("progression")
RunAllTimers()
if not Gate.active or Gate.input.focusId ~= "progression" then
    fail("explicit Dashboard focus did not survive staged reveal")
end
for _, id in ipairs(nativeIds) do
    if not APB.C43.buttons[id].nativeSuppressed then fail("legacy " .. id .. " not suppressed") end
    if APB.C43.buttons[id]._mouseEnabled then fail("suppressed " .. id .. " still owns mouse") end
    if not Gate.controls[id].enabled then
        fail("reveal did not enable " .. id
            .. " (gate=" .. tostring(Gate.active)
            .. ", dashboard=" .. tostring(C43.frame:IsShown())
            .. ", token=" .. tostring(Gate.revealToken) .. ")")
    end
    local revealTick = Gate.controls[id].root:GetScript("OnUpdate")
    if revealTick then revealTick(Gate.controls[id].root, 0.30) end
    if Gate.controls[id].root:GetScript("OnUpdate") then
        fail("staged reveal left idle OnUpdate on " .. id)
    end
end
local essenceRevealTick = Gate.resource.root:GetScript("OnUpdate")
if essenceRevealTick then essenceRevealTick(Gate.resource.root, 0.30) end
if C43.essenceSeat:IsShown() then fail("legacy Essence remained visible in native mode") end
Gate.resource:SetValue(1234567,false)
if Gate.resource.value:GetText()~="1,234,567" then fail("native Essence did not preserve a seven-digit exact value") end
if Gate.resource.label._width~=108 or Gate.resource.value._width~=109 then fail("native Essence fields do not reserve separate text widths") end
if C43.essenceText._width~=109 or C43.essenceValue._width~=109 then fail("legacy Essence fallback does not reserve separate text widths") end
pass("exact full-control suppression and bounded opening choreography")

Gate.controls.core:SetFocused(false)
Gate.controls.core:SetFocused(true)
local coreProof = Gate.controls.core
for _, piece in ipairs(coreProof.materialPieces) do
    local tick = piece.frame:GetScript("OnUpdate")
    if tick then tick(piece.frame, 0.30) end
end
if coreProof.materialPieces[1].frame.__echoesMaterialY ~= 3 then
    fail("Core focus did not settle into its stable material configuration")
end
coreProof.root:FireEvent("OnEnter")
coreProof.root:FireEvent("OnMouseDown", "LeftButton")
for _, piece in ipairs(coreProof.materialPieces) do
    local tick = piece.frame:GetScript("OnUpdate")
    if tick then tick(piece.frame, 0.20) end
end
coreProof.root:FireEvent("OnMouseUp")
for _, piece in ipairs(coreProof.materialPieces) do
    local tick = piece.frame:GetScript("OnUpdate")
    if tick then tick(piece.frame, 0.30) end
end
if not coreProof.focused or coreProof.materialPieces[1].frame.__echoesMaterialY ~= 3 then
    fail("Core press did not return to its focused material configuration")
end
coreProof.root:FireEvent("OnLeave")
pass("Core hover and press layer over persistent material focus")

local originalCoreStateRequest=APB.RequestEchoesState
local coreStateRequests=0
APB.RequestEchoesState=function() coreStateRequests=coreStateRequests+1; return true end
APB.echoes.welcomed=true
C43.stateRequestPending=false
Gate.controls.core:Activate("mouse")
if coreStateRequests~=1 or not C43.coreCommunePending then fail("Core communion did not dispatch authoritative state") end
if C43.status:GetText()~="You reach toward the Worldsoul…" then fail("Core communion lacked immediate semantic acknowledgement") end
APB.echoes.lastState={essence="1234",mastery_rank="4",attuned="12",rack_used="3",rack_cap="10",threat_name="Dangerous",crucible_total_invested="500"}
APB.echoes.lastStateTime=(APB.echoes.lastStateTime or 0)+1
local dashboardTick=C43.frame:GetScript("OnUpdate"); dashboardTick(C43.frame,.21)
local coreReading=C43.status:GetText() or ""
if not coreReading:find("The Worldsoul answers",1,true) or not coreReading:find("Essence 1,234",1,true)
    or not coreReading:find("Rack 3/10",1,true) or not coreReading:find("Threat Dangerous",1,true) then
    fail("Core communion did not present the authoritative Worldsoul reading")
end
if C43.coreCommunePending then fail("Core communion did not reconcile after STATE") end
APB.RequestEchoesState=originalCoreStateRequest
pass("Core communion dispatch, semantic response, and authoritative state summary")

local calibratedIds = {"progression", "talents", "threat", "crucible", "rack", "visage", "core"}
for _, id in ipairs(calibratedIds) do
    local control = Gate.controls[id]
    local hasReadableGeometry = false
    for _, piece in ipairs(control.materialPieces) do
        local spec = piece.spec
        if (spec.focusAlpha or 0) < (spec.hoverAlpha or 0) + 0.12 then
            fail(id .. " focus contrast is not comfortably stronger than hover")
        end
        if math.abs(spec.focusX or 0) >= 2 or math.abs(spec.focusY or 0) >= 2
            or math.abs((spec.focusScale or 1) - 1) >= 0.025 then
            hasReadableGeometry = true
        end
        if (spec.hoverFocusAlpha or 0) < (spec.focusAlpha or 0) then
            fail(id .. " hover erased its focused material strength")
        end
        if (spec.pressedAlpha or 0) < (spec.focusAlpha or 0) then
            fail(id .. " press did not push beyond focus")
        end
    end
    if not hasReadableGeometry then
        fail(id .. " focus still relies on color without a readable geometry delta")
    end
end
local corePeak = Gate.controls.core.materialPieces[3].spec.focusAlpha or 0
for _, id in ipairs({"progression", "talents", "threat", "crucible", "rack", "visage", "forge"}) do
    for _, piece in ipairs(Gate.controls[id].materialPieces) do
        if corePeak <= (piece.spec.focusAlpha or 0) then
            fail("Core does not retain the strongest material-state hierarchy")
        end
    end
end
pass("material calibration preserves hover/focus/press hierarchy and geometric readability")

for _, id in ipairs(nativeIds) do
    local control = Gate.controls[id]
    control.root:FireEvent("OnEnter")
    control:SetFocused(true)
    control.root:FireEvent("OnMouseDown", "LeftButton")
    control.root:FireEvent("OnMouseUp")
    control.root:FireEvent("OnLeave")
    local responseTick = control.responseFrame and control.responseFrame:GetScript("OnUpdate")
    if responseTick then responseTick(control.responseFrame, 0.30) end
    local focusTick = control.focusFrame and control.focusFrame:GetScript("OnUpdate")
    if focusTick then focusTick(control.focusFrame, 0.30) end
    local glowTick = control.glowFrame and control.glowFrame:GetScript("OnUpdate")
    if glowTick then glowTick(control.glowFrame, 0.30) end
    local labelTick = control.labelFrame and control.labelFrame:GetScript("OnUpdate")
    if labelTick then labelTick(control.labelFrame, 0.30) end
    for _, piece in ipairs(control.materialPieces or {}) do
        local materialTick = piece.frame:GetScript("OnUpdate")
        if materialTick then materialTick(piece.frame, 0.30) end
        if piece.frame:GetScript("OnUpdate") then
            fail(id .. " material state left an idle OnUpdate")
        end
    end
    local homeTick = control.homeCueFrame and control.homeCueFrame:GetScript("OnUpdate")
    if homeTick then homeTick(control.homeCueFrame, 0.30) end
    if control.responseFrame and control.responseFrame:GetScript("OnUpdate") then
        fail(id .. " response left an idle OnUpdate")
    end
    if control.focusFrame and control.focusFrame:GetScript("OnUpdate") then
        fail(id .. " focus left an idle OnUpdate")
    end
    if control.glowFrame and control.glowFrame:GetScript("OnUpdate") then
        fail(id .. " glow left an idle OnUpdate")
    end
    if control.labelFrame and control.labelFrame:GetScript("OnUpdate") then
        fail(id .. " label state left an idle OnUpdate")
    end
    if control.homeCueFrame and control.homeCueFrame:GetScript("OnUpdate") then
        fail(id .. " Home cue left an idle OnUpdate")
    end
end
pass("whole-family hover, focus, and press paths")

Gate.input:SetFocusById("progression")
Gate.input:HandleKey("RIGHT")
if Gate.input.focusId ~= "threat" then fail("Progression RIGHT should focus Threat") end
Gate.input:HandleKey("DOWN")
if Gate.input.focusId ~= "crucible" then fail("Threat DOWN should focus Crucible") end
Gate.input:HandleKey("LEFT")
if Gate.input.focusId ~= "core" then fail("Crucible LEFT should focus Core") end
Gate.input:HandleKey("LEFT")
if Gate.input.focusId ~= "rack" then fail("Core LEFT should focus Rack") end
Gate.input:HandleKey("DOWN")
if Gate.input.focusId ~= "visage" then fail("Rack DOWN should focus Visage") end
Gate.input:HandleKey("RIGHT")
if Gate.input.focusId ~= "forge" then fail("Visage RIGHT should focus Forge") end
Gate.input:SetFocusById("codex")
Gate.input:HandleKey("DOWN")
if Gate.input.focusId ~= "search" then fail("Codex DOWN should focus Search") end
Gate.input:SetFocusById("settings")
Gate.input:HandleKey("DOWN")
if Gate.input.focusId ~= "accessibility" then fail("Settings DOWN should focus Accessibility") end
pass("whole-Dashboard spatial navigation graph")

Gate.input:ClearFocus()
Gate.input:HandleKey("RIGHT")
if Gate.input.focusId ~= "crucible" then
    fail("first directional key should resolve through Core/Home")
end
Gate.input:ClearFocus()
Gate.input:HandleKey("TAB")
if Gate.input.focusId ~= "codex" then fail("first Tab should enter at Codex") end
pass("quiet rest state gains keyboard focus predictably")

local routed = { forge=0, core=0, codex=0, search=0, accessibility=0, settings=0 }
for id in pairs(routed) do
    local routeId = id
    APB.C43.buttons[routeId]:HookScript("OnClick", function()
        routed[routeId] = routed[routeId] + 1
    end)
    Gate.input:SetFocusById(routeId)
    Gate.input:HandleKey("ENTER")
    if routed[routeId] ~= 1 then fail("native route failed for " .. routeId) end
end
Gate.input:SetFocusById("progression")
Gate.input:HandleKey("ENTER")
if not Progression.active or EchoesUI.ScreenManager.current ~= "progression" then
    fail("Progression landmark did not enter the native system screen")
end
Progression:Leave("back")
pass("native Progression routing plus legacy Core/Home and utility delegation")

SetMockChatActive(true)
local beforeFocus = Gate.input.focusId
Gate.input:HandleKey("RIGHT")
Gate.input:HandleKey("ENTER")
if Gate.input.focusId ~= beforeFocus then fail("chat-focused key changed Dashboard focus") end
SetMockChatActive(false)
pass("chat-focused keys are ignored")

RunAllTimers()
AttunementPlusBridgeDB.c43.reducedMotion = true
Gate:BeginReveal()
for _, id in ipairs(nativeIds) do
    if Gate.controls[id].root:GetAlpha() ~= 1 or not Gate.controls[id].enabled then
        fail("reduced-motion reveal was not immediate for " .. id)
    end
    if Gate.controls[id].root:GetScript("OnUpdate") then
        fail("reduced-motion reveal installed OnUpdate on " .. id)
    end
end
for _, id in ipairs(calibratedIds) do
    local control = Gate.controls[id]
    control:SetFocused(false)
    control:SetFocused(true)
    for _, piece in ipairs(control.materialPieces) do
        if piece.frame:GetScript("OnUpdate") then
            fail("reduced-motion material focus installed OnUpdate on " .. id)
        end
        if piece.frame.__echoesMaterialX ~= (piece.spec.focusX or 0)
            or piece.frame.__echoesMaterialY ~= (piece.spec.focusY or 0)
            or piece.frame:GetAlpha() ~= (piece.spec.focusAlpha or 0) then
            fail("reduced-motion material focus lost its stable configuration on " .. id)
        end
    end
    control:SetFocused(false)
end
AttunementPlusBridgeDB.c43.reducedMotion = false
pass("reduced-motion completion path is immediate and fully legible")

Gate.controls.close:Activate("keyboard")
if Gate.controls.progression.enabled then fail("close did not suspend native input") end
if APB.C43.motionState ~= "CLOSING" then fail("native Close did not delegate to shell closure") end
if Gate.controls.progression:Activate("keyboard") then
    fail("disabled control accepted input during closure")
end
pass("closing choreography suspends input and strands no focus")

C43:Show()
RunAllTimers()
for _, id in ipairs(nativeIds) do
    if not Gate.controls[id].enabled then
        fail("reversing close did not restore native input for " .. id)
    end
end
if SubscriberCount() ~= subscriberCountAtConstruction then
    fail("repeated opens leaked StateStore subscriptions")
end
pass("reopen during close restarts bounded native reveal")

Gate:BeginClose()

Gate:Hide()
if Gate.active then fail("fallback did not disable native Dashboard") end
for _, id in ipairs(nativeIds) do
    if APB.C43.buttons[id].nativeSuppressed then fail("fallback did not restore " .. id) end
    if not APB.C43.buttons[id]._mouseEnabled then fail("fallback did not restore mouse for " .. id) end
end
if not C43.essenceSeat:IsShown() then fail("fallback did not restore legacy Essence") end
pass("Candidate 43 fallback restores the complete legacy surface")

-- The live bug occurred on Candidate 43's own activation path while the native
-- Dashboard overlay flag was off. Exercise that exact route and its fallback.
C43:Show()
C43.buttons.progression:FireEvent("OnClick")
if not Progression.active or EchoesUI.ScreenManager.current ~= "progression" then
    fail("Candidate 43 Progression activation did not enter the native screen")
end
Progression:Leave("back")
if not Gate.active or Gate.input.focusId ~= "progression" then
    fail("Progression Back did not restore Dashboard focus spatially")
end
Progression:Show()
Progression:Leave("home")
if Gate.input.focusId ~= "core" then fail("Progression Home did not restore Core focus") end
Progression:Show()
Progression.close:Activate("keyboard")
if Progression.active or EchoesUI.ScreenManager.current then fail("Progression Close did not close the Companion") end
EchoesUI.flags.nativeProgression = false
ClearMockChatMessages()
C43:Show()
C43.buttons.progression:FireEvent("OnClick")
local fallbackMessages = GetMockChatMessages()
if #fallbackMessages == 0 or fallbackMessages[#fallbackMessages][1] ~= "ap" then
    fail("unavailable native Progression did not retain gossip fallback")
end
EchoesUI.flags.nativeProgression = true
pass("Candidate 43 live route plus Back, Home, Close, and gossip fallback")

C43:Show()
C43.buttons.threat:FireEvent("OnClick")
if not WorldThreat.active or EchoesUI.ScreenManager.current ~= "threat" then
    fail("Candidate 43 World Threat activation did not enter the native screen")
end
WorldThreat:Leave("back")
if not Gate.active or Gate.input.focusId ~= "threat" then
    fail("World Threat Back did not restore Dashboard focus spatially")
end
WorldThreat:Show()
WorldThreat:Leave("home")
if Gate.input.focusId ~= "core" then fail("World Threat Home did not restore Core focus") end
WorldThreat:Show()
WorldThreat.close:Activate("keyboard")
if WorldThreat.active or EchoesUI.ScreenManager.current then fail("World Threat Close did not close the Companion") end
EchoesUI.flags.nativeWorldThreat = false
ClearMockChatMessages()
C43:Show()
C43.buttons.threat:FireEvent("OnClick")
fallbackMessages = GetMockChatMessages()
if #fallbackMessages == 0 or fallbackMessages[#fallbackMessages][1] ~= "ap" then
    fail("unavailable native World Threat did not retain gossip fallback")
end
EchoesUI.flags.nativeWorldThreat = true
pass("World Threat live route plus Back, Home, Close, and gossip fallback")

C43:Show()
C43.buttons.crucible:FireEvent("OnClick")
if not Crucible.active or EchoesUI.ScreenManager.current ~= "crucible" then
    fail("Candidate 43 Crucible activation did not enter the native screen")
end
Crucible:Leave("back")
if not Gate.active or Gate.input.focusId ~= "crucible" then
    fail("Crucible Back did not restore Dashboard focus spatially")
end
Crucible:Show(); Crucible:Leave("home")
if Gate.input.focusId ~= "core" then fail("Crucible Home did not restore Core focus") end
Crucible:Show(); Crucible.close:Activate("keyboard")
if Crucible.active or EchoesUI.ScreenManager.current then fail("Crucible Close did not close the Companion") end
EchoesUI.flags.nativeCrucible = false
ClearMockChatMessages(); C43:Show(); C43.buttons.crucible:FireEvent("OnClick")
fallbackMessages = GetMockChatMessages()
if #fallbackMessages == 0 or fallbackMessages[#fallbackMessages][1] ~= "ap" then
    fail("unavailable native Crucible did not retain gossip fallback")
end
EchoesUI.flags.nativeCrucible = true
pass("Crucible live route plus Back, Home, Close, and gossip fallback")

C43:Show()
C43.buttons.talents:FireEvent("OnClick")
if not Talents.active or EchoesUI.ScreenManager.current~="talents" then fail("Candidate 43 Talents activation did not enter the capable native screen") end
Talents:Leave("back")
if not Gate.active or Gate.input.focusId~="talents" then fail("Talents route did not restore Dashboard focus") end
EchoesUI.flags.nativeTalents=false
ClearMockChatMessages(); C43:Show(); C43.buttons.talents:FireEvent("OnClick")
fallbackMessages=GetMockChatMessages()
if #fallbackMessages==0 or fallbackMessages[#fallbackMessages][1]~="ap" then fail("disabled native Talents did not retain gossip fallback") end
EchoesUI.flags.nativeTalents=true
APB.echoes.caps.action_talent_purchase=nil
ClearMockChatMessages(); C43:Show(); C43.buttons.talents:FireEvent("OnClick")
fallbackMessages=GetMockChatMessages()
if #fallbackMessages==0 or fallbackMessages[#fallbackMessages][1]~="ap" then fail("incomplete Talents capability set did not retain gossip fallback") end
APB.echoes.caps.action_talent_purchase=true
APB.echoes.compatible=0
ClearMockChatMessages(); C43:Show(); C43.buttons.talents:FireEvent("OnClick")
fallbackMessages=GetMockChatMessages()
if #fallbackMessages==0 or fallbackMessages[#fallbackMessages][1]~="ap" then fail("incompatible Talents protocol did not retain gossip fallback") end
APB.echoes.compatible=1
pass("Talents live route plus capability/flag gossip fallback")

-- Every canonical slot must be keyboard reachable without allowing focus to
-- disappear beyond the seven-row viewport.
Progression:Show()
Progression.input:SetFocusById("slot7")
for _=1,10 do Progression.input:HandleKey("DOWN") end
if Progression.slotOffset ~= 10 or Progression.input.focusId ~= "slot7" then
    fail("keyboard navigation did not scroll through all seventeen slots")
end
Progression.input:SetFocusById("slot1")
for _=1,10 do Progression.input:HandleKey("UP") end
if Progression.slotOffset ~= 0 or Progression.input.focusId ~= "slot1" then
    fail("reverse slot navigation did not retain visible focus")
end
Progression:Leave("back")
pass("seventeen-slot keyboard viewport remains bounded and visible")

-- Duplicate item entries can occupy different equipment positions. One APTIP
-- truth response must populate every matching row, without duplicate requests.
local originalInventory = GetInventoryItemLink
local trackedSlots = {[1]=2001,[5]=2001,[6]=2006,[7]=2007,[8]=2008,[9]=2009,[10]=2010,[15]=2015,[16]=2016,[17]=2017}
GetInventoryItemLink = function(_,slot)
    local entry = trackedSlots[slot]
    return entry and ("|Hitem:"..entry..":0:0:0:0:0:0:0|h[Live Item]|h") or nil
end
Progression:Show()
if #Progression.equipped ~= 10 or #Progression.requestQueue ~= 9 then
    fail("equipped scan did not preserve ten positions with unique APTIP requests")
end
Progression:OnAttunement({entry=2001,prog=25,cap=100})
if Progression.equipped[1].attunement == nil or Progression.equipped[2].attunement == nil then
    fail("duplicate equipped entries did not share authoritative APTIP truth")
end
Progression:Leave("back")
GetInventoryItemLink = originalInventory
pass("Current Attunement handles duplicate equipped entries without request spam")

local originalActionRequest = APB.RequestEchoesAction
local originalStateRequest = APB.RequestEchoesState
local actionSends, stateSends = 0, 0
APB.RequestEchoesAction = function(_,name)
    if name == "mastery_purchase" then actionSends = actionSends + 1 end
    return true
end
APB.RequestEchoesState = function() stateSends = stateSends + 1 end
EchoesUI.StateStore:Ingest({
    essence="2500", mastery_rank="4", absorb_pct="16.2", mastery_next_cost="1200",
    attuned="12", snapshots="28", absorbed_stats="3.5/1.0/8.2/0/0.5",
    slots="0:80,4:180,15:500", residue="0", rack_used="0", rack_cap="0",
    talents="", crucible="",
}, 200)
Progression:Show()
Progression.action:Activate("keyboard")
Progression.action:Activate("keyboard")
if actionSends ~= 1 or not Progression.actionPending then fail("Mastery purchase in-flight gate failed") end
Progression:OnAction("ACTION_OK", {action="mastery_purchase",status="SUCCESS"})
if not Progression.actionPending or stateSends == 0 then fail("successful purchase did not await authoritative refresh") end
EchoesUI.StateStore:Ingest({
    essence="1300", mastery_rank="5", absorb_pct="18.8", mastery_next_cost="1800",
    attuned="12", snapshots="28", absorbed_stats="4.0/1.1/9.0/0/0.6",
    slots="0:80,4:180,15:500", residue="0", rack_used="0", rack_cap="0",
    talents="", crucible="",
}, 201)
if Progression.actionPending or Progression.rankValue:GetText() ~= "5"
    or Progression.essenceValue:GetText() ~= "1,300" then
    fail("authoritative post-purchase state did not replace the live readout")
end
Progression.action:Activate("keyboard")
if actionSends ~= 1 then fail("unaffordable Mastery control sent an action") end
Progression:Hide()
APB.RequestEchoesAction = originalActionRequest
APB.RequestEchoesState = originalStateRequest
pass("Mastery purchase round-trip is gated and refreshed only by authoritative state")

-- Cold-load native-route regression: on a fresh login the Dashboard may be
-- clicked before E2J15 capabilities exist. Once the WELCOME/STATE handshake
-- commits those capabilities, the SAME already-open Dashboard instance must
-- route correctly on the very next click -- no C43:Show()/Gate:Show()
-- reconstruction allowed between the two clicks. This covers the regression
-- where C43Dashboard.lua's legacy click handler had no rack/forge/visage
-- branch at all, so a not-yet-ready click permanently dead-ended instead of
-- re-checking availability on the next click like every other destination.
C43:Show()
for _, id in ipairs({"rack", "forge", "visage"}) do
    ClearMockChatMessages()
    C43.buttons[id]:FireEvent("OnClick")
    local cold = GetMockChatMessages()
    if #cold == 0 or cold[#cold][1] ~= "ap" then
        fail("cold " .. id .. " click before capabilities did not fall back to gossip")
    end
    if EchoesUI.ScreenManager.current == id then
        fail("cold " .. id .. " click opened the native screen before capabilities existed")
    end
end
APB.echoes.caps.rack_state_v1=true; APB.echoes.caps.action_rack_add=true; APB.echoes.caps.action_rack_remove=true; APB.echoes.caps.action_rack_expand=true
APB.echoes.caps.forge_state_v1=true; APB.echoes.caps.action_forge_dissolve=true; APB.echoes.caps.action_forge_purchase_catalyst=true
APB.echoes.caps.visage_state_v1=true; APB.echoes.caps.visage_preview_v1=true; APB.echoes.caps.action_visage_preview=true; APB.echoes.caps.action_visage_apply=true; APB.echoes.caps.action_visage_cancel=true
local originalColdActionRequest, originalColdStateRequest = APB.RequestEchoesAction, APB.RequestEchoesState
APB.RequestEchoesAction = function() return true end
APB.RequestEchoesState = function() return true end
for _, id in ipairs({"rack", "forge", "visage"}) do
    ClearMockChatMessages()
    C43.buttons[id]:FireEvent("OnClick")
    if EchoesUI.ScreenManager.current ~= id then
        fail(id .. " did not become available in place once capabilities committed -- Dashboard reopen should never be required")
    end
    EchoesUI.ScreenManager:Close(id)
end
APB.RequestEchoesAction, APB.RequestEchoesState = originalColdActionRequest, originalColdStateRequest
pass("Rack/Forge/Visage refresh native availability in place after cold-load capabilities commit, with no Dashboard reconstruction")

-- "Not ready yet" (handshake still pending) must not look identical to
-- "genuinely unsupported" (welcomed, but incompatible/missing capability).
-- Before WELCOME, an unavailable click must NOT open real gossip.
local savedWelcomed = APB.echoes.welcomed
APB.echoes.welcomed = false
ClearMockChatMessages()
C43.buttons.codex:FireEvent("OnClick")
local duringHandshake = GetMockChatMessages()
for _, msg in ipairs(duringHandshake) do
    if msg[1] == "ap" then fail("a click during the still-pending E2J15 handshake incorrectly opened real gossip") end
end
if EchoesUI.ScreenManager.current == "codex" then fail("a click during the still-pending handshake incorrectly opened the native screen") end
APB.echoes.welcomed = savedWelcomed

-- Once welcomed, a genuinely unavailable destination still falls back to
-- real gossip exactly as before -- this distinction must not swallow the
-- valid fallback case.
local savedRackCap = APB.echoes.caps.rack_state_v1
APB.echoes.caps.rack_state_v1 = nil
ClearMockChatMessages()
C43.buttons.rack:FireEvent("OnClick")
local genuinelyUnavailable = GetMockChatMessages()
if #genuinelyUnavailable == 0 or genuinelyUnavailable[#genuinelyUnavailable][1] ~= "ap" then
    fail("a genuinely unavailable (welcomed, capability missing) destination lost its real gossip fallback")
end
APB.echoes.caps.rack_state_v1 = savedRackCap
pass("cold-handshake clicks read as connecting, not unsupported; genuine unavailability still falls back to gossip")

-- Final-three submenus consume server lists and keep mutations thin.
-- (capabilities already committed by the cold-load regression test above)
local finalActions={}; APB.RequestEchoesAction=function(_,name,...) finalActions[#finalActions+1]={name,...}; return true end
APB.RequestEchoesState=function() return true end
EchoesUI.StateStore:Ingest({
    rack_used="2",rack_cap="5",rack_entries="1:111:3,3:333:4",rack_candidates="444:2,555:3",rack_next_slots="7",rack_next_essence_cost="2000",rack_next_residue_cost="0",rack_at_max="0",
    forge_eligible="111:3:1000:80000:8,333:4:2500:200000:20",forge_catalyst_status="READY",forge_catalyst_cost="10",forge_catalyst_reward="5000",residue="44",
    visage_primary_theme="worldsoul",visage_primary_enabled="1",visage_primary_tier_selected="1",visage_primary_tier_effective="1",visage_primary_tier_max="2",visage_secondary_theme="ethereal",visage_secondary_enabled="1",visage_secondary_tier_selected="0",visage_secondary_tier_effective="2",visage_secondary_tier_max="2",visage_themes_unlocked="worldsoul,ethereal",visage_flash_enabled="1",visage_chat_flavor_enabled="0",visage_attuned_count="30",visage_crucible_invested="300000",visage_preview_active="0",
},300)
Rack:Show(); Rack.candidates[1]:Activate("keyboard"); if finalActions[#finalActions][1]~="rack_add" or finalActions[#finalActions][2]~=444 then fail("Rack candidate did not route authoritative item entry") end; Rack:OnAction("ACTION_OK",{action="rack_add",status="SUCCESS"}); Rack:Hide()
Forge:Show(); Forge.rows[1]:Activate("keyboard"); local beforeArm=#finalActions; Forge.release:Activate("keyboard"); if #finalActions~=beforeArm or Forge.armedEntry~=111 then fail("Forge first activation did not arm without mutation") end; Forge.release:Activate("keyboard"); if finalActions[#finalActions][1]~="forge_dissolve" or finalActions[#finalActions][2]~=111 then fail("Forge confirmation did not route selected relic") end; Forge:OnAction("ACTION_OK",{action="forge_dissolve",status="SUCCESS",essence_reward="1000",residue_reward="8"}); Forge:Hide()
Visage:Show(); Visage:SetTier("primary",2); if finalActions[#finalActions][1]~="visage_preview" or finalActions[#finalActions][2]~="combined" then fail("Visage selection did not request real combined preview") end; Visage:OnAction("ACTION_OK",{action="visage_preview",status="PREVIEWING"}); Visage.apply:Activate("keyboard"); if finalActions[#finalActions][1]~="visage_apply" then fail("Visage Apply did not commit the server preview") end; Visage:OnAction("ACTION_OK",{action="visage_apply",status="SUCCESS"}); Visage:Hide()
APB.RequestEchoesAction=originalActionRequest; APB.RequestEchoesState=originalStateRequest
pass("Rack, Dissolution, and real Visage preview/apply contracts are functional")

local subscribersBeforeStress = SubscriberCount()
for _=1,20 do
    EchoesUI.ScreenManager:Show("progression")
    Progression:Leave("back")
end
if SubscriberCount() ~= subscribersBeforeStress then fail("repeated Progression navigation leaked subscriptions") end
if Progression.active then fail("navigation stress left Progression active") end
pass("twenty Dashboard/Progression cycles strand no screen or subscription")

-- Route-table parity: C43Dashboard.lua's legacy Activate() and
-- DashboardGateB.lua's RouteThroughCandidate are two independent routing
-- mechanisms that must both route every gameplay destination. This has
-- regressed twice already (the original Final Three gap, and the 1.4.2
-- Phase A+B drop) because a patch touched one without touching the other.
-- Prove BOTH paths open the native screen for every destination that has
-- one registered, so a future patch that silently drops a branch from
-- either path fails this test immediately instead of surfacing as a live
-- "destination interface pending" bug report.
Gate:SetEnabled(true)
local originalParityActionRequest, originalParityStateRequest = APB.RequestEchoesAction, APB.RequestEchoesState
APB.RequestEchoesAction = function() return true end
APB.RequestEchoesState = function() return true end
for _, id in ipairs({"progression", "talents", "threat", "crucible", "rack", "forge", "visage"}) do
    C43:Show(); ClearMockChatMessages()
    C43.buttons[id]:FireEvent("OnClick")
    if EchoesUI.ScreenManager.current ~= id then
        fail(id .. ": legacy Activate() route did not open the native screen (route-table parity)")
    end
    EchoesUI.ScreenManager:Close(id)

    C43:Show(); ClearMockChatMessages()
    Gate.controls[id]:SetEnabled(true) -- routing correctness, not staggered-reveal timing, is under test here
    Gate.controls[id]:Activate("keyboard")
    if EchoesUI.ScreenManager.current ~= id then
        fail(id .. ": DashboardGateB RouteThroughCandidate did not open the native screen (route-table parity)")
    end
    EchoesUI.ScreenManager:Close(id)
end
APB.RequestEchoesAction, APB.RequestEchoesState = originalParityActionRequest, originalParityStateRequest
pass("both Dashboard routing mechanisms open every native gameplay destination (route-table parity)")

print("ALL SMOKE TESTS PASSED")
